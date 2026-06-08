# Authorization Model（後端管理 / 照護端授權模型）

對應 CR-0041（Audit §12 #5 per-caregiver 登入 / P1-2 RBAC 子集 / CR-0040 §14 daily-care-tasks BLOCKER 收斂）。
身分解析實作於 `backend/stt_proxy/services/admin/adminAuthContext.js`；
住民範圍過濾實作於 `backend/stt_proxy/services/admin/authorizationService.js`。

本文件說明：兩種管理身分（super_admin vs caregiver）的差異、caregiver 如何取得授權住民、
`resident_caregiver_links` 的用途，以及為何 super_admin token 不可發給一般照護人員。

---

## 1. 角色（Roles）

| 角色 | 可見範圍 | 身分來源 |
| --- | --- | --- |
| `super_admin` | 全部住民（full scope） | (a) Bearer 字面 == `ADMIN_API_TOKEN`（共享 super_admin token），或 (b) Firebase 使用者且 `users.role ∈ ('admin','super_admin')` |
| `caregiver` | 只限被授權住民（`resident_caregiver_links` 內 `status='active'`） | Bearer = Firebase ID Token，驗證後 `users.role='caregiver'`，`caregiverId = users.id` |
| （其他：elder / 未知 / 查無 row） | 無 | 驗過身分但無管理權限 → 403 |

`super_admin` 不只是「token 持有者」這個歷史巧合（CR-0040 已將共享 token 明確命名為 super_admin
角色）；它代表最高權限，能讀取全部住民的 Care Alert、健康分析與每日照護任務。

---

## 2. 身分機制（路線 A：Firebase ID Token 當 Bearer）

caregiver-or-admin 路由掛 `resolveAdminAuthContext` 中介層，解析順序如下（fail-closed，
**絕不預設 super_admin**）：

1. 無 `Authorization` bearer → **401 `missing_admin_token`**。
2. bearer 字面 == `ADMIN_API_TOKEN`（且 env 非空）→ `super_admin`（共享 token，行為與 CR-0039 一致）。
3. 否則當作 Firebase ID Token：
   - 後端已設定 Firebase 服務帳戶 → `firebaseAdmin.verifyIdToken`；驗證失敗 → **401 `invalid_session`**。
   - 未設定 Firebase：production 一律拒（`mockAllowed()===false` → 401）；非 production 才允許 dev mock，
     但仍須由（stub）`verifyIdToken` 解析出 uid，且仍須查得真實 `users` row。
   - 取得 `firebase_uid` → 查 `users`：
     - `role='caregiver'` → `caregiver`（`caregiverId = users.id`）。
     - `role ∈ ('admin','super_admin')` → `super_admin`（DB-backed）。
     - 其他（elder / 查無 row / DB 不可用）→ **403 `admin_permission_required`**（fail-closed）。

解析結果掛在 `req.authContext = { role, userId, caregiverId, scope }`，route body 依此套住民範圍。

### super_admin-only 路由（不接受 caregiver）

`/api/admin/users`、`/api/admin/overview`、marketplace admin 路由仍掛 `requireAdmin`
（只接受共享 `ADMIN_API_TOKEN`，非該 token → 403）。caregiver Firebase token 無法進入這些路由。

### `/api/care-alerts/notify`

長者端建立 Care Alert 的路由**刻意不掛任何 admin 驗證**（長者端不持有 admin token）。
本模型不改變此行為；其 caller 驗證屬另案（FU-CR）。

---

## 3. caregiver 如何取得授權住民（`resident_caregiver_links`）

`resident_caregiver_links`（migration 013）是「照護人員 ↔ 住民」的授權關聯表：

```
resident_caregiver_links(
  elder_id      -> elders(id)
  caregiver_id  -> users(id)     -- role='caregiver' 的 user
  status        -- 'active' 才生效
  ...
)
```

caregiver 的可見住民集合 = 對其 `caregiver_id` 查 `status='active'` 的 `elder_id` 集合
（`authorizationService.getAuthorizedResidentIdsForCaregiver`）。

授權套用規則（route body）：

- list 類（care-alerts、elders、daily-care-tasks）：只回 `elderId` 在授權集合內的資料；
  無授權 → **空陣列**（不是 403、也不是「看全部」）。
- 單筆 / 帶 `elderId` 類（care-alerts/:id、elders/:elderId、daily-care-tasks?elderId=...、
  PATCH care-alerts/:id/status）：跨住民 → **403 `forbidden`**。

fail-closed：`caregiverId` 缺、DB 不可用、查無授權 → 一律視為「無任何授權」（空集合），
**絕不退化成看全部**。不 hardcode 任何 elder / caregiver id。

---

## 4. 為何 super_admin token 不可發給一般照護人員

- `ADMIN_API_TOKEN` 是 **super_admin token**，持有者可見**全部住民**，等同最高權限。
- 一般照護人員只應看到「自己被授權」的住民；發共享 token 給他們等於繞過 `resident_caregiver_links`，
  違反 CLAUDE.md §6#8（不可跨住民洩漏記憶）與 §9#11（照護人員只能查看授權住民）。
- 一般照護人員的正確登入方式：caregiver_web 走 Firebase 登入（CR-0042），
  以 Firebase ID Token 呼叫後端 → 解析為 `caregiver` → 自動套住民範圍。

---

## 5. 環境變數（只列名稱，不放真值）

- `ADMIN_API_TOKEN`：super_admin 共享 token（production 必填）。
- Firebase 服務帳戶（caregiver / DB-admin idToken 驗證所需，與長者 auth 共用，擇一）：
  `GOOGLE_APPLICATION_CREDENTIALS`，或 `FIREBASE_PROJECT_ID` + `FIREBASE_CLIENT_EMAIL` + `FIREBASE_PRIVATE_KEY`。
- `AUTH_ALLOW_MOCK` / `APP_ENV` / `NODE_ENV`：production 守門（production 關 mock，強制驗 idToken）。
- **無新增後端 secret**（路線 A 不需 `JWT_SECRET` / `SESSION_SECRET`）。

---

## 6. 三道保險（防 dev/mock 成為 production 漏洞）

1. **production 一律關 mock**：重用 CR-0034 B2 `mockAllowed()`（production 恆 false）。
2. **fail-closed，絕不預設 super_admin**：唯一 super_admin 來源 = bearer 字面 == `ADMIN_API_TOKEN`，
   或 DB `role ∈ ('admin','super_admin')`。
3. **即使 dev mock 也須查得真實 `users` row**：不 hardcode caregiver id、不 demo seed 進 production、
   不可 fake token 過 production。

---

## 7. 殘留（後續 CR）

- **CR-0042**：caregiver_web Firebase 登入 + per-role auth header + 401/403/empty-state（P1-6）。
- **CR-0043**：caregiver 帳號與 `resident_caregiver_links` provisioning（super_admin-only 端點）。
  目前 `createUserPostgres` 寫死 `role='elder'`，dev 以 SQL / seed 提供 caregiver 帳號與授權關聯。
- **FU-CR**：`/api/care-alerts/notify` caller 驗證（長者 session）。
- `/api/admin/overview` 目前為純聚合計數（無 per-resident 識別），維持 super_admin-only；
  若改回 per-resident 需補 scope。
