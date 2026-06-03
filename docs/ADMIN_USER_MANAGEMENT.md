# 管理者端使用者帳戶管理（CR-0029）

> 本文件說明「管理者端使用者帳戶管理」功能：管理者端如何透過受權限保護的後端 Admin API
> 從 **PostgreSQL** 查詢使用者帳戶，並以安全方式顯示。供開發、Demo 與評審問答使用。

---

## 1. 功能目的

讓管理者（長照人員 / 系統管理者）在 caregiver_web 後台查看「正式的使用者帳戶清單」，
並能向評審清楚證明：

- 帳戶資料**存在 PostgreSQL**，不是本機 JSON 假資料、也不是 hardcoded demo users。
- 管理者端**不直接連資料庫**，只透過後端 Admin API（有權限檢查）。
- API 與畫面**都不會出現** password_hash、token、verification code 等敏感資料。
- Email 一律**遮蔽顯示**（`wang@gmail.com` → `wa***@gmail.com`）。

---

## 2. 正式資料流

```text
管理者端 caregiver_web（使用者管理頁）
        ↓  GET /api/admin/users   (Authorization: Bearer <ADMIN_API_TOKEN>)
後端 requireAdmin 權限檢查（401 / 403 / 放行）
        ↓
PostgreSQL：users 資料表
        ↓
後端只 SELECT 安全欄位（白名單）
        ↓
後端遮蔽 Email、轉成統一 API 格式
        ↓
管理者端顯示使用者清單（Email 已遮蔽，無任何敏感欄位）
```

備援展示（評審想直接看資料庫時）：DBeaver / pgAdmin 執行「安全 SQL」，只查展示必要欄位
（見第 8 節）。

---

## 3. PostgreSQL 作為唯一資料來源

- 使用者帳戶資料表為既有的 `users`（CR-0006 `006_create_users_elders.sql` 建立），本 CR 沿用、
  **未重複建表**。
- 本 CR 新增 migration `008_add_users_last_login_at.sql`：
  - `ALTER TABLE users ADD COLUMN IF NOT EXISTS last_login_at TIMESTAMPTZ;`（冪等）
  - `CREATE INDEX IF NOT EXISTS idx_users_created_at ON users (created_at DESC);`
- 登入流程（`services/auth/sessionService.js`）在 PostgreSQL 路徑會：
  - 新帳號建立時寫入 `last_login_at = NOW()`；
  - 既有帳號再次登入時 `UPDATE last_login_at = NOW()`（失敗不影響登入）。
- **此 API 不使用 JSON fallback**：PG 未啟用 / 查詢失敗 → 回 `500 failed_to_load_users`，
  不會改讀本機 JSON、不會回假資料。

> 啟用 PostgreSQL：`.env` 設 `DATABASE_URL` 並將 `PGVECTOR_ENABLED=true`，
> 然後 `npm run db:migrate`（於 `backend/stt_proxy`）。

`users` 表與本功能相關的欄位：

| 欄位 | 用途 | 是否回傳給前端 |
| --- | --- | --- |
| `id` | 使用者 ID | ✅（id） |
| `display_name` | 顯示名稱 | ✅（displayName） |
| `email` | Email | ⚠️ 僅回傳**遮蔽後**的 emailMasked |
| `auth_provider` | 登入方式 google/apple/email | ✅（authProvider） |
| `email_verified` | Email 是否驗證 | ✅（emailVerified） |
| `created_at` | 註冊時間 | ✅（createdAt） |
| `last_login_at` | 最近登入 | ✅（lastLoginAt） |
| `firebase_uid` / `provider_user_id` | 登入識別 | ❌ 永不回傳 |
| `password_hash` | （目前採 Firebase，無此欄） | ❌ 永不回傳 |

---

## 4. Admin API

### Endpoint

```
GET /api/admin/users
Headers: Authorization: Bearer <ADMIN_API_TOKEN>
```

### 管理者權限檢查（requireAdmin）

`backend/stt_proxy/services/admin/requireAdmin.js`（fail-closed）：

- 沒有 Authorization header / 沒有 token → `401 { ok:false, error:"missing_admin_token" }`
- 後端未設定 `ADMIN_API_TOKEN`，或 token 不符 → `403 { ok:false, error:"admin_permission_required" }`
- token 正確 → 放行查詢

> 目前為 Demo 階段的 token 機制。**正式產品應改為管理者登入 + JWT + role-based access
> control**（不可宣稱已完成 RBAC）。

### 回傳格式

```json
{
  "ok": true,
  "users": [
    {
      "id": "0f1f1a6e-2c4a-4f1d-9b4e-123456789abc",
      "displayName": "王小明",
      "emailMasked": "wa***@gmail.com",
      "authProvider": "google",
      "emailVerified": true,
      "createdAt": "2026-06-01T10:20:00.000Z",
      "lastLoginAt": "2026-06-02T09:30:00.000Z"
    }
  ]
}
```

- 只含：`id`、`displayName`、`emailMasked`、`authProvider`、`emailVerified`、`createdAt`、`lastLoginAt`。
- 依 `created_at DESC` 排序，最多 100 筆。
- 查詢失敗：`500 { ok:false, error:"failed_to_load_users" }`（不回傳 stack trace / 原始錯誤）。

### Email 遮蔽

`adminUsersService.maskEmail()`：保留 local part 前兩碼 + `***@` + 原 domain；
空值 / 非 email 一律回空字串（不外漏原值）。

### 敏感欄位保護（雙層）

1. **SQL 白名單**：只 SELECT 安全欄位，根本不查 password_hash / provider_user_id / token。
2. **映射白名單**：`toSafeUser()` 只組裝安全欄位，即使 row 夾帶敏感欄位也不會外漏。

以下欄位**絕不**出現在 response：
`password`、`password_hash`、`provider_user_id`、`apple_user_identifier`、`access_token`、
`refresh_token`、`id_token`、`verification_token`、`verification_token_hash`、
`reset_password_token`、`reset_token`、`otp`、`email_code`、`session_token`、`csrf_token`、`firebase_uid`。

---

## 5. 管理者端畫面

- 入口：caregiver_web 上方分頁新增「使用者管理」（不破壞既有 照護提醒 / 健康分析 / 日常任務）。
- 權杖：頁面內提供「管理者權杖」輸入框，存於瀏覽器 `localStorage`（key：`caregiver_admin_token`），
  **不寫死、不進 Git**。呼叫 API 時自動帶 `Authorization: Bearer <token>`。
- 表格欄位：使用者 ID、姓名、Email（遮蔽）、登入方式、驗證狀態、註冊時間、最近登入。
- 顯示轉換：
  - authProvider：google→Google、apple→Apple、email→Email
  - emailVerified：true→已驗證、false→未驗證
  - lastLoginAt：null→「尚未登入或無紀錄」
- UI 狀態：
  - 載入中：「使用者資料載入中...」
  - 失敗：「使用者資料載入失敗，請確認後端與資料庫是否已啟動。」
  - 未授權（401/403）：「管理者權杖無效或未授權，請確認 Admin Token 是否正確。」
  - 沒有資料：「目前尚無使用者帳戶資料」
  - 成功：顯示使用者表格。

---

## 6. 環境變數

於 `backend/stt_proxy/.env`（範本見 `.env.example`，**勿提交真實值**）：

```
DATABASE_URL=postgres://postgres:password@localhost:5432/love_companion
PGVECTOR_ENABLED=true
ADMIN_API_TOKEN=<請自行產生隨機字串>
```

caregiver_web 的權杖請於畫面輸入框設定（存 localStorage），不要寫進前端原始碼或 commit。

---

## 7. 測試

後端（`backend/stt_proxy`，`npm test`）：

- `services/admin/requireAdmin` + endpoint：無 token→401、token 錯→403、token 對→200、查詢失敗→500。
- 200 時從（mock 的）PostgreSQL 取資料、Email 遮蔽、過濾所有敏感欄位。
- `adminUsersService`：maskEmail、toSafeUser 欄位白名單、SQL 只選安全欄位且 `ORDER BY created_at DESC LIMIT 100`。
- 測試以 mock 取代 `postgres.query`，**不連真 DB、不走 JSON fallback、不新增 demo JSON**。

caregiver_web（`node --test caregiver_web/admin_users.test.js`）：

- 使用者管理入口存在、呼叫 `/admin/users` 並帶 Bearer、token 不寫死。
- 登入方式 / 驗證狀態中文標籤、載入 / 失敗 / 空狀態文字齊全。
- 前端不引用任何敏感欄位、顯示遮蔽後 emailMasked。

---

## 8. DBeaver / pgAdmin 備用展示 SQL

若評審想直接看 PostgreSQL，**不要打開完整 users 表**，請執行只查展示必要欄位的安全 SQL：

```sql
SELECT
  id,
  display_name,
  CONCAT(SUBSTRING(email FROM 1 FOR 2), '***@', SPLIT_PART(email, '@', 2)) AS masked_email,
  auth_provider,
  email_verified,
  created_at,
  last_login_at
FROM users
ORDER BY created_at DESC
LIMIT 20;
```

說明：

- 只查展示必要欄位；Email 在 SQL 層就遮蔽。
- 不查 `password_hash`、不查 token、不查 verification code。
- 管理者端正式使用時不直接操作資料庫，而是透過 Admin API。

---

## 9. 評審問答

**Q1：使用者帳戶資料存在哪裡？**
使用者帳戶資料正式存在 PostgreSQL，不是存在本機 JSON。管理者端會透過後端 Admin API
查詢 PostgreSQL 中的使用者資料。

**Q2：管理者怎麼查看使用者帳戶資訊？**
管理者端有一個「使用者管理」頁面，會呼叫後端 `/api/admin/users`。後端會先檢查管理者權限，
確認通過後才查詢 PostgreSQL，並回傳安全欄位給前端顯示。

**Q3：會不會看到使用者密碼？**
不會。正式系統不會儲存明文密碼，只會儲存密碼雜湊（本專案登入採 Firebase，後端不存密碼）。
而且 Admin API 不會回傳 password_hash，管理者端也不會顯示密碼、Token 或驗證碼。

**Q4：Email 會完整顯示嗎？**
管理者端預設只顯示遮蔽後的 Email，例如 `wa***@gmail.com`，避免不必要的個資暴露。

**Q5：如果老師想看資料庫本身怎麼辦？**
可以用 DBeaver 或 pgAdmin 連到 PostgreSQL，執行第 8 節的安全 SQL，只查詢 id、名稱、
遮蔽後 Email、登入方式、驗證狀態、註冊時間與最近登入時間，不會直接打開完整資料表，
也不會查詢 password_hash 或 token。

---

## 相關檔案

| 用途 | 檔案 |
| --- | --- |
| 權限中介層 | `backend/stt_proxy/services/admin/requireAdmin.js` |
| 使用者清單服務（PG-only、遮蔽、白名單） | `backend/stt_proxy/services/admin/adminUsersService.js` |
| API 路由 | `backend/stt_proxy/server.js`（`GET /api/admin/users`） |
| Migration | `backend/stt_proxy/db/migrations/008_add_users_last_login_at.sql` |
| 登入寫入 last_login_at | `backend/stt_proxy/services/auth/sessionService.js` |
| 管理者端畫面 | `caregiver_web/index.html`、`caregiver_web/app.js` |
| 後端測試 | `services/admin/adminUsersService.test.js`、`services/admin/adminUsersEndpoint.test.js` |
| 前端測試 | `caregiver_web/admin_users.test.js` |
