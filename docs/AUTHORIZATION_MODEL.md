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

### `/api/care-alerts/notify`（resident-caller，CR-0045）

長者端建立 Care Alert 的路由不掛 admin 驗證（長者端不持有 admin token），改掛
`requireResidentCaller`（`services/auth/residentCallerContext.js`）：

- caller = **長者本人**：Firebase idToken bearer → `firebase_uid` → `users` row → `users.elder_id`。
  context 形狀：`{ userId, firebaseUid, elderId, role:'resident', isSuperAdmin:false }`。
- **server 權威推導 elderId** 並蓋寫在 alert（防偽造，並修復既有 elderId=null 缺口）：
  - body 無 elderId → 用 token 推導值；
  - body 有且 == token 推導 → 放行；
  - body 有且 != token 推導 → **403 `forbidden_resident`**；
  - 一律以 token 推導值寫入 alert，client 值僅供一致性檢核。
- fail-closed：無 / 無效 token → **401**；查無 users row（production）/ `users.elder_id` 為 null →
  **403 `resident_not_linked`**；inactive 帳號（CR-0043 閘）→ **403 `resident_inactive`**。
- **三道保險**（同 §6）：production（`mockAllowed()===false`）強制真 idToken + 真 users row +
  非 null elder_id；無 token→401、無權→403。dev/test 允許 mock caller；**明列 dev-only seam**：
  `mockAllowed()` 且查無 DB row 時，由 verified uid 推導 scoping elderId（僅 dev/mock，
  production 恆走真 row）。
- caregiver / super_admin 代建**不納入**（caller 僅長者本人）；通知 persist / cooldown /
  notification-log / `{ success, telegram }` response 形狀不變。
- 重用 adminAuthContext（CR-0041）的 firebaseAdmin verify / `mockAllowed()` 守門 / status 閘 /
  test seam 模式；為避免動到 adminAuthContext 的 `SELECT id, role, status FROM users`
  （CR-0041 byte-identical 回歸守門），residentCallerContext 自帶 `findUserByFirebaseUid`
  （SELECT 多取 `elder_id`），不抽共用、不改 adminAuthContext。

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

## 6.5 Caregiver 帳號停用閘（CR-0043）

`adminAuthContext.findUserByFirebaseUid` 的 SELECT 補 `status`（migration 014 `users.status`）。
身分解析時，於 **role 分派之前**檢查：

- `users.status === 'inactive'` → **403 `admin_permission_required`**（停用即時失效；對 caregiver 與
  DB-admin 皆適用，更安全）。
- `status` 為 NULL / 缺值（舊 row、未跑 migration 014）→ 視為 `active`（向後相容，不放寬既有判定）。
- 共享 super_admin token 路徑不查 DB → 不受此閘影響。

---

## 7. Provisioning（CR-0043，super_admin-only）

caregiver 帳號與 `resident_caregiver_links` 的建立 / 修改 / 停用由 super_admin-only 端點管理
（全部掛 `requireAdmin`，caregiver idToken 也進不來）。詳見 `docs/CAREGIVER_PROVISIONING.md`：

- 8 條路由：`/api/admin/caregivers`（GET/POST/PATCH/PATCH status）、
  `/api/admin/resident-caregiver-links`（GET/POST/PATCH/DELETE soft-disable）。
- caregiver 綁定採**路線 B**（super_admin 顯式設 `firebaseUid`），不做 email 自動認領（FU-CR-0043a）。
- link DB 維持 `active`/`revoked`，API 對外 `active`/`inactive`（service 映射）；`authorizationService.js` 零改動。
- 停用 link → caregiver 立即看不到該住民（`authorizationService` 只查 `status='active'`）。

---

## 8. 殘留（後續 CR）

- **CR-0044**：caregiver_web 兩個 super_admin-only 管理 UI（caregiver 管理 + 授權指派）。
- **FU-CR-0043a**：caregiver 首次登入以 Firebase-verified email 自動認領 pending caregiver。
- **FU**：`requireSuperAdmin`（讓 DB-backed super_admin 也能用管理路由，目前僅共享 token）。
- **FU**：caregiver email 全域唯一 DB unique index（目前為 app-level SELECT 檢查）。
- ~~**FU-CR**：`/api/care-alerts/notify` caller 驗證（長者 session）。~~
  **已收斂於 CR-0045（B1+B2）**：resident-caller 驗證 + server 權威推導 elderId（見 §2
  `/api/care-alerts/notify` 段）。Flutter 端帶 Authorization header 為 CR-0045 B3。
- `/api/admin/overview` 目前為純聚合計數（無 per-resident 識別），維持 super_admin-only；
  若改回 per-resident 需補 scope。
