# Caregiver Web 身分與授權（前端）

對應 CR-0042（接 CR-0041 後端正餐：identity + middleware + scope）。
後端身分模型見 `docs/AUTHORIZATION_MODEL.md`；本文件只說明 **caregiver_web 前端**
如何選身分、帶 header、處理 401 / 403 / 空狀態，以及正式環境的 token 風險界線。

本文件不放任何真實 token 值；只描述機制與變數名稱。

---

## 1. 支援的身分（authMode）

caregiver_web 在前端維護一個身分狀態：

```js
authState = {
  authMode: 'super_admin' | 'caregiver' | 'none',
  token: string | null,       // 目前模式對應的 token（不印到 console）
  displayName: string | null, // 未在前端驗證，維持 null（不偽造名稱）
  role: string | null,
}
```

| authMode | 可見範圍 | 登入方式 |
| --- | --- | --- |
| `super_admin` | 全部住民（最高權限） | 在登入列選「管理者」並貼上 `ADMIN_API_TOKEN`；或在使用者 / 商品 / 訂單分頁貼上管理者權杖 |
| `caregiver` | 只限被指派住民（`resident_caregiver_links` `status='active'`） | 在登入列選「照護人員」並貼上自己的 Firebase ID Token / 機構提供的 caregiver session 權杖 |
| `none` | 無（尚未登入） | 未登入；不會主動呼叫受保護 API，會提示先登入 |

身分狀態存在瀏覽器 `localStorage`：

- super_admin 權杖：key `caregiver_admin_token`（沿用既有）。
- caregiver 權杖：key `caregiver_login_token`（**獨立 key，絕不與 admin token 共用**）。
- 目前模式：key `caregiver_auth_mode`。

向後相容：舊版只有共享 admin token、無 `caregiver_auth_mode` 時，若偵測到 admin token
即視為 `super_admin`，既有管理者體驗不變。

---

## 2. Header 行為（統一 helper）

所有受驗證請求都透過統一 helper 產生 header，依 `authMode` 帶對的 token：

- `authHeaders()` / `authJsonHeaders()`（caregiver-or-admin 端點用）：
  - `super_admin` → `Authorization: Bearer <ADMIN_API_TOKEN>`
  - `caregiver` → `Authorization: Bearer <Firebase ID Token / caregiver session 權杖>`
  - `none` → 不帶 `Authorization`（且不發送受保護請求）
- `adminAuthHeaders()` / `adminJsonHeaders()`（**僅** super_admin-only 端點用，只帶
  super_admin token：`/admin/users`、`/admin/overview`、marketplace admin）。

界線（紅線）：

- caregiver token **不會**寫入 `caregiver_admin_token`，也不會被命名為 admin token。
- token **不會**被印到 console / log（程式內無任何 `console.*` 印 token）。
- 無 token 時不狂打受保護 API（`ensureCanFetch` 守門）。

端點對應（與 CR-0041 後端一致）：

| 端點 | 角色 | 前端 header |
| --- | --- | --- |
| `GET /api/care-alerts`、`GET /:id`、`PATCH /:id/status` | caregiver-or-admin（scoped） | `authHeaders` / `authJsonHeaders` |
| `GET /api/admin/elders`、`/elders/:id`（physio/emotion/game） | caregiver-or-admin（scoped） | `authHeaders` |
| `GET /api/admin/daily-care-tasks` | caregiver-or-admin（scoped） | `authHeaders` |
| `GET /api/admin/overview` | super_admin-only | caregiver 模式**不打**（避免 403 洗版），整體概況留「—」 |
| `GET /api/admin/users` | super_admin-only | caregiver 模式顯示權限不足、不打 API |
| marketplace admin（products / orders 寫入、訂單列表） | super_admin-only | caregiver 模式隱藏入口 / 顯示權限不足 |

---

## 3. 401 / 403 / 空狀態行為

### 401（登入失效 / 未授權）

- 顯示「登入已失效，請重新登入」。
- 設 `sessionInvalid = true`，停止重複請求，直到使用者重新登入。
- 捲動回登入列，方便重新輸入權杖。
- 不顯示 raw stack、不顯示完整 token、不顯示工程錯誤碼為主文案。

### 403（權限不足）

- 顯示「目前帳號沒有權限查看此資料」。
- **不清除 token**（後端未明示 session invalid，不視為登出）。
- 不重複狂打 API。
- detail / update（跨住民）顯示權限不足；list 視 API 語意顯示權限不足或空狀態。

### 空狀態（caregiver 無授權住民 / API 回空陣列）

- 顯示「目前尚未被指派可查看的住民。請聯絡管理者確認權限設定。」
- 不顯示全部資料、不顯示 stack / undefined、不以假資料填滿畫面。

---

## 4. 正式環境界線（重要）

- `ADMIN_API_TOKEN` 是 **super_admin 共享 token**，持有者可見全部住民、等同最高權限。
- **正式環境不可把 super_admin token 發給一般照護人員。**
  一般照護人員的正確登入方式是以自己的 Firebase ID Token / caregiver session 權杖
  登入（`caregiver` 模式），後端解析為 caregiver 後自動套住民範圍
  （見 `docs/AUTHORIZATION_MODEL.md` §4）。
- caregiver_web 不在前端驗證 token，也不偽造登入成功；token 有效性一律由後端
  回應決定（無效 → 401 → 重新登入）。

---

## 5. 後續（follow-up CR）

- **完整 Firebase popup 登入**（caregiver_web 內嵌 Firebase Web SDK，一鍵 Google / Email
  登入後自動取得 ID Token，免手動貼 token）：列為後續 CR，本 CR 先提供清楚標示的
  token 輸入入口（最小可行 UI）。
- **caregiver 帳號與 `resident_caregiver_links` provisioning 後端**（super_admin-only 端點）：
  **已於 CR-0043 完成**（8 條路由 + 停用閘 + audit）。見 `docs/CAREGIVER_PROVISIONING.md`。
  對應的 caregiver_web 管理 UI（caregiver 管理 + 授權指派，super_admin-only）= **CR-0044**（前端，未做）。
- `/api/care-alerts/notify` caller 驗證（長者 session）：FU-CR。
