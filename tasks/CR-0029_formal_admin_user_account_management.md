<!--# CR-0029 — 正式版管理者端使用者帳戶管理

## 任務背景

本專案是長者 AI 寵物陪伴系統，目前已經有長者端 App、後端、Care Alert、Telegram 通知、管理者端 caregiver_web 等功能。

評審老師可能會問：

- 使用者帳戶資料存在哪裡？
- 管理者怎麼查看使用者帳戶資訊？
- 你們是不是用本機 JSON 模擬資料？
- 如果要看資料庫，怎麼證明資料真的存在？
- 管理者端會不會看到密碼或 Token？
- 使用者 Email、登入方式、驗證狀態怎麼顯示？

本次 CR-0029 要完成「正式版管理者端使用者帳戶管理」功能，讓管理者端可以透過後端 Admin API 從 PostgreSQL 查詢使用者帳戶資料，並用安全方式顯示在管理者端。

---

## 核心原則

1. 不准使用本機 JSON fallback。
2. 不准使用 hardcoded demo users。
3. 不准新增假資料偽裝功能。
4. 使用者帳戶資料只能來自 PostgreSQL。
5. 管理者端不能直接連資料庫，只能透過後端 Admin API 查詢。
6. Admin API 必須有管理者權限檢查。
7. API 不可以回傳 password_hash、token、verification code 等敏感資料。
8. 管理者端畫面不可以顯示 password_hash、token、verification code 等敏感資料。
9. Email 必須遮蔽顯示，例如 `wang@gmail.com` 顯示為 `wa***@gmail.com`。
10. 不要破壞現有 Realtime、Care Alert、Telegram、長期記憶、情緒辨識、登入註冊流程。

---

## 一、正式資料流

請完成以下資料流：

```text
管理者端 caregiver_web
        ↓
GET /api/admin/users
        ↓
後端檢查管理者權限
        ↓
PostgreSQL users / accounts / auth users 資料表
        ↓
後端只取安全欄位
        ↓
後端遮蔽 Email
        ↓
管理者端顯示使用者清單
二、請先盤點現有架構
修改前請先檢查目前專案架構，不要直接硬加新表造成衝突。
2.1 後端入口
請確認 Express 後端入口檔案，例如：
backend/stt_proxy/server.js
backend/server.js
其他目前實際啟動的 Express app
請確認目前 API 路由如何註冊。
2.2 PostgreSQL 連線
請確認目前 PostgreSQL 連線方式，例如：
DATABASE_URL
pg Pool
db.query
migration 檔案
schema 初始化檔
是否有 dev fallback
本 CR-0029 的 Admin Users API 不可以使用 JSON fallback。
2.3 使用者資料表
請檢查是否已有正式帳戶資料表，例如：
users
user_profiles
accounts
auth_users
user_auth_identities
admin_users
其他登入註冊相關資料表
請優先沿用現有資料表，不要重複建立衝突的 users 表。
2.4 登入 / 註冊流程
請確認目前登入 / 註冊 API 是否已經寫入 PostgreSQL。
如果目前登入註冊尚未完全落到 PostgreSQL，請誠實回報現況，並以最小改動補齊正式帳戶資料寫入流程。
2.5 管理者端
請檢查目前管理者端檔案，例如：
caregiver_web/index.html
caregiver_web/app.js
caregiver_web/styles.css
caregiver_web/*
請確認目前 Care Alert 頁面結構，新增使用者管理入口時不要破壞原頁面。
三、資料庫要求
3.1 優先沿用現有 users / accounts 表
如果專案已經有使用者帳戶資料表，請沿用現有結構。
請找出最適合作為管理者端使用者清單資料來源的資料表，至少能取得：
使用者 ID
顯示名稱
Email
登入方式
Email 是否驗證
註冊時間
最近登入時間
如果欄位名稱不同，請在後端查詢時轉換為統一 API 回傳格式。
3.2 如果沒有正式 users 表，才新增 migration
如果目前真的沒有正式帳戶資料表，請新增 PostgreSQL migration 建立 users 表。
建議欄位如下：
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  display_name TEXT,
  email TEXT UNIQUE NOT NULL,

  auth_provider TEXT NOT NULL CHECK (auth_provider IN ('google', 'apple', 'email')),
  provider_user_id TEXT,

  email_verified BOOLEAN NOT NULL DEFAULT FALSE,

  password_hash TEXT,

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_login_at TIMESTAMPTZ
);
注意：
password_hash 可以存在資料庫，但絕對不能從 Admin API 回傳。
provider_user_id 屬於登入識別資料，不要回傳到管理者端。
如果有 email verification token，正式版應存 hash，不要存明文 token。
不要建立 demo_users.json。
不要新增 JSON fallback。
不要 hardcode demo accounts。
3.3 Email 驗證資料
如果目前有 Email 驗證流程，可沿用既有資料表。
如果需要新增 Email 驗證表，建議使用：
CREATE TABLE IF NOT EXISTS email_verifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

  verification_token_hash TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  verified_at TIMESTAMPTZ,

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
注意：
不要存明文 verification token。
Admin API 不要回傳 verification_token_hash。
管理者端只需要知道 emailVerified: true / false。
四、後端 Admin API
請新增正式 API：
GET /api/admin/users
用途：管理者端查詢使用者帳戶清單。
4.1 管理者權限檢查
此 API 必須有管理者權限檢查。
Demo 階段可以先使用環境變數：
ADMIN_API_TOKEN=change-this-admin-token
前端呼叫時帶：
Authorization: Bearer <ADMIN_API_TOKEN>
後端規則：
沒有 Authorization header：回傳 401。
Token 錯誤：回傳 403。
Token 正確：才可以查 PostgreSQL。
可實作 middleware：
function requireAdmin(req, res, next) {
  const authHeader = req.headers.authorization || '';
  const token = authHeader.replace('Bearer ', '');

  if (!token) {
    return res.status(401).json({
      ok: false,
      error: 'missing_admin_token',
    });
  }

  if (token !== process.env.ADMIN_API_TOKEN) {
    return res.status(403).json({
      ok: false,
      error: 'admin_permission_required',
    });
  }

  next();
}
如果專案已經有正式 admin JWT / role-based access control，請優先沿用現有權限機制，不要重複實作。
4.2 API 查詢欄位
API 只能從 PostgreSQL 查詢正式帳戶資料。
查詢資料來源請依現有資料表決定，但回傳給前端的格式必須統一為：
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
回傳欄位只能包含：
id
displayName
emailMasked
authProvider
emailVerified
createdAt
lastLoginAt
查詢結果依 created_at DESC 排序，最多回傳 100 筆。
4.3 範例 Express 寫法
請依專案現有 db / pool 寫法調整，不要硬套導致壞掉。
app.get('/api/admin/users', requireAdmin, async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT
        id,
        display_name,
        email,
        auth_provider,
        email_verified,
        created_at,
        last_login_at
      FROM users
      ORDER BY created_at DESC
      LIMIT 100
    `);

    const users = result.rows.map((row) => ({
      id: row.id,
      displayName: row.display_name,
      emailMasked: maskEmail(row.email),
      authProvider: row.auth_provider,
      emailVerified: row.email_verified,
      createdAt: row.created_at,
      lastLoginAt: row.last_login_at,
    }));

    res.json({
      ok: true,
      users,
    });
  } catch (error) {
    console.error('[admin/users] failed:', error);

    res.status(500).json({
      ok: false,
      error: 'failed_to_load_users',
    });
  }
});
Email 遮蔽函式：
function maskEmail(email) {
  if (!email || !email.includes('@')) return '';

  const [name, domain] = email.split('@');
  const visiblePart = name.slice(0, 2);

  return `${visiblePart}***@${domain}`;
}
請注意：
以上只是參考，實作時要配合現有資料表與欄位。
不要回傳原始 email。
不要回傳 provider_user_id。
不要回傳 password_hash。
不要把資料庫錯誤 stack trace 回傳給前端。
五、禁止回傳敏感欄位
Admin API 不可以回傳以下欄位：
password
password_hash
provider_user_id
apple_user_identifier
access_token
refresh_token
id_token
verification_token
verification_token_hash
reset_password_token
reset_token
otp
email_code
session_token
csrf_token
即使資料庫中存在這些欄位，也不能出現在 response body。
請新增測試確認 response JSON 不包含以上字串。
六、管理者端網頁
請在 caregiver_web 或目前管理者端新增「使用者管理」頁面或區塊。
6.1 頁面入口
請新增一個入口，例如：
側邊欄：「使用者管理」
上方 tab：「使用者管理」
首頁卡片：「使用者帳戶」
若現有管理者端很簡單，可在 Care Alert 頁面上方新增 tab
不要破壞現有 Care Alert 頁面。
6.2 API 呼叫
管理者端呼叫：
GET /api/admin/users
並帶上：
Authorization: Bearer <ADMIN_API_TOKEN>
如果目前 caregiver_web 是純靜態頁，請依現有設定方式處理 API base URL 與 admin token。
注意：
不要把正式 token commit 到 Git。
可以在 .env.example 或文件中說明 Demo 如何設定 token。
若目前靜態頁無法讀 .env，請使用現有專案可接受的 demo config 方式，但不可寫入正式 token。
6.3 表格欄位
使用者管理表格需包含：
使用者 ID
姓名
Email
登入方式
驗證狀態
註冊時間
最近登入
顯示格式：
authProvider = google → Google
authProvider = apple → Apple
authProvider = email → Email
emailVerified = true → 已驗證
emailVerified = false → 未驗證
lastLoginAt = null → 尚未登入或無紀錄
6.4 UI 狀態
請處理以下狀態：
載入中
使用者資料載入中...
失敗
使用者資料載入失敗，請確認後端與資料庫是否已啟動
沒有資料
目前尚無使用者帳戶資料
成功
顯示使用者表格。
七、環境變數
請更新 .env.example，加入：
DATABASE_URL=postgres://postgres:password@localhost:5432/pet_companion
ADMIN_API_TOKEN=change-this-admin-token
注意：
不要 commit 真正的 .env。
不要 commit 真正的 token。
不要把 token 寫死在正式前端檔案。
文件中需說明正式產品應改為 admin login + JWT + role-based access control。
八、正式展示用 SQL
請新增文件說明，如果評審老師想看 PostgreSQL 原始資料，可以用 DBeaver 或 pgAdmin 執行以下安全 SQL。
不要直接打開完整 users 表。
展示 SQL：
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
如果現有資料表不是 users，請在文件中改成實際資料表與欄位。
文件中需說明：
這段 SQL 只查詢展示必要欄位。
Email 會遮蔽。
不查 password_hash。
不查 token。
不查 verification code。
管理者端正式使用時不會直接操作資料庫，而是透過 Admin API。
九、測試要求
請新增或更新後端測試。
至少包含：
GET /api/admin/users 沒有 token 時回傳 401。
token 錯誤時回傳 403。
token 正確時回傳 200。
token 正確時會從 PostgreSQL 查詢資料。
response 包含：
id
displayName
emailMasked
authProvider
emailVerified
createdAt
lastLoginAt
response 不包含：
password
password_hash
provider_user_id
apple_user_identifier
access_token
refresh_token
id_token
verification_token
verification_token_hash
reset_password_token
reset_token
otp
email_code
session_token
emailMasked 必須遮蔽 Email。
查詢失敗時回傳：
ok: false
error: failed_to_load_users
不允許因測試方便改成本機 JSON fallback。
測試資料請使用測試資料庫或 mock PostgreSQL query，不要新增 demo JSON。
如有 caregiver_web 測試，也請補上：
使用者管理入口存在。
載入成功時表格顯示使用者。
API 失敗時顯示錯誤訊息。
沒有資料時顯示空狀態。
表格不顯示敏感欄位。
十、文件更新
請新增或更新以下文件：
建議新增：
docs/ADMIN_USER_MANAGEMENT.md
並更新：
docs/CHANGE_REVIEW.md
如有需要也更新：
README.md
docs/DEMO_FLOW.md
docs/PROJECT_ARCHITECTURE.md
10.1 docs/ADMIN_USER_MANAGEMENT.md 需包含
功能目的。
正式資料流。
PostgreSQL 作為唯一資料來源。
Admin API endpoint。
管理者權限檢查方式。
API 回傳欄位。
敏感欄位保護。
管理者端畫面說明。
DBeaver / pgAdmin 備用 SQL 展示方式。
評審問答範例。
10.2 評審問答範例
請在文件中加入以下 Q&A。
Q1：使用者帳戶資料存在哪裡？
建議回答：
使用者帳戶資料正式存在 PostgreSQL，不是存在本機 JSON。管理者端會透過後端 Admin API 查詢 PostgreSQL 中的使用者資料。
Q2：管理者怎麼查看使用者帳戶資訊？
建議回答：
管理者端有一個「使用者管理」頁面，會呼叫後端的 /api/admin/users。後端會先檢查管理者權限，確認通過後才會查詢 PostgreSQL，並回傳安全欄位給前端顯示。
Q3：會不會看到使用者密碼？
建議回答：
不會。正式系統不會儲存明文密碼，只會儲存密碼雜湊。而且 Admin API 不會回傳 password_hash，管理者端也不會顯示密碼、Token 或驗證碼。
Q4：Email 會完整顯示嗎？
建議回答：
管理者端預設只顯示遮蔽後的 Email，例如 wa***@gmail.com，避免不必要的個資暴露。
Q5：如果老師想看資料庫本身怎麼辦？
建議回答：
我們可以用 DBeaver 或 pgAdmin 連到 PostgreSQL，執行安全 SQL 查詢，只查詢 id、名稱、遮蔽後 Email、登入方式、驗證狀態、註冊時間與最近登入時間，不會直接打開完整資料表，也不會查詢 password_hash 或 token。
十一、CHANGE_REVIEW 登記
請在 docs/CHANGE_REVIEW.md 新增 CR-0029 紀錄。
格式請沿用目前專案既有 CR 格式。
內容至少包含：
CR 編號：CR-0029
標題：正式版管理者端使用者帳戶管理
修改檔案
新增檔案
資料庫變更
Admin API endpoint
管理者端入口
測試結果
是否有動到 Realtime：否，除非實際有動到
是否有動到 Care Alert：否，除非只是新增管理入口
是否有動到 Telegram：否
是否有動到長期記憶：否
是否有動到情緒辨識：否
是否有動到登入註冊：如有請說明
是否使用 JSON fallback：否
是否 hardcode demo users：否
是否回傳敏感欄位：否
風險與後續建議
十二、驗收標準
完成後請確認：
後端啟動時可以連 PostgreSQL。
使用者帳戶資料來源為 PostgreSQL。
沒有使用 JSON fallback。
沒有 hardcoded demo users。
沒有新增 fake account data。
沒有 ADMIN_API_TOKEN 時無法查詢。
token 錯誤時無法查詢。
token 正確時可以查詢。
管理者端可以看到使用者清單。
Email 已遮蔽。
API response 不包含 password / password_hash。
API response 不包含 provider_user_id。
API response 不包含 access_token / refresh_token / id_token。
API response 不包含 verification token / reset token / otp。
管理者端不顯示任何敏感欄位。
API 查詢失敗時有安全錯誤訊息。
管理者端 API 失敗時有錯誤提示。
管理者端沒有資料時有空狀態。
現有 Realtime 語音功能不受影響。
現有 Care Alert 功能不受影響。
現有 Telegram 推播不受影響。
現有長期記憶功能不受影響。
現有情緒辨識功能不受影響。
測試全數通過，或誠實記錄無法執行原因。
docs/CHANGE_REVIEW.md 已更新 CR-0029。
docs/ADMIN_USER_MANAGEMENT.md 已新增或更新。
十三、請避免的錯誤
請特別避免：
為了展示新增 demo users JSON。
為了方便讓管理者端直接讀資料庫。
把 PostgreSQL 查詢失敗時改走 fallback。
把 password_hash 回傳到前端。
把完整 Email 回傳到前端。
把 Token 寫死在前端並 commit。
為了測試方便把 requireAdmin 關掉。
破壞 Care Alert 頁面。
破壞 Realtime WebRTC 流程。
破壞登入註冊流程。
重複建立和現有 users 表衝突的新資料表。
宣稱已完成 role-based access control，但實際只有 demo token。
十四、建議實作順序
請依照以下順序進行：
盤點現有後端入口、PostgreSQL 連線與帳戶資料表。
確認使用者資料來源表與欄位。
若沒有正式 users 表，新增 migration。
確認登入 / 註冊流程會寫入 PostgreSQL。
新增或沿用 requireAdmin 權限檢查。
新增 GET /api/admin/users。
實作 Email 遮蔽。
確認 API 不回傳敏感欄位。
新增管理者端「使用者管理」入口。
新增使用者管理表格。
補齊載入中、錯誤、空狀態。
新增或更新測試。
新增 docs/ADMIN_USER_MANAGEMENT.md。
更新 docs/CHANGE_REVIEW.md。
執行測試並回報。
十五、完成後回報格式
完成後請用以下格式回報：
CR-0029 完成回報

一、完成內容
- ...

二、修改檔案
- ...

三、新增檔案
- ...

四、資料庫變更
- 使用資料表：
- 是否新增 migration：
- 使用者資料來源：
- 是否使用 JSON fallback：否

五、Admin API
- Endpoint：
- 權限方式：
- 查詢來源：
- 回傳欄位：
- Email 遮蔽：
- 敏感欄位保護：

六、管理者端畫面
- 入口位置：
- 顯示欄位：
- 載入狀態：
- 錯誤處理：
- 空狀態：

七、測試結果
- 後端測試：
- caregiver_web 測試：
- flutter analyze：
- flutter test：
- npm test：

八、確認未影響功能
- Realtime：
- Care Alert：
- Telegram：
- 長期記憶：
- 情緒辨識：
- 登入註冊：

九、文件更新
- docs/ADMIN_USER_MANAGEMENT.md：
- docs/CHANGE_REVIEW.md：
- README / DEMO_FLOW：

十、評審問答說明
- 使用者資料存在哪裡：
- 管理者怎麼查看：
- 是否使用 JSON 模擬：
- 是否顯示敏感欄位：
- 如何用 DBeaver / pgAdmin 備用展示：

十一、風險與後續建議
-...-->