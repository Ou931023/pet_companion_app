# CR-0041 — Caregiver Web Auth Integration and Scoped Admin Session

## 1. 任務定位

本任務接續 CR-0039 與 CR-0040。

CR-0039 已完成後端 API 擋門：
- `/api/admin/*` 讀取路由已掛 `requireAdmin`
- `/api/care-alerts` 管理路由已掛 `requireAdmin`

CR-0040 已完成授權範圍模型：
- 新增 `resident_caregiver_links`
- 新增 `authorizationService`
- 建立 `super_admin` 與 `caregiver-scoped` 權限概念
- Care Alert 與部分 admin analytics 已能依授權住民過濾

但目前正式風險是：

> caregiver-scoped 程式碼已存在，但 production 尚無真正 per-caregiver 身分可由 HTTP 觸發。  
> 目前共享 `ADMIN_API_TOKEN` 仍等同 `super_admin`，持 token 者可看全部住民。

本任務目標是把 caregiver_web 與後端 session/auth 串起來，讓長照管理端能以真實 caregiver 身分呼叫 API，並觸發 CR-0040 已建立的 scope 過濾。

---

## 2. 本次目標

建立正式版長照管理端身分流程，使 caregiver_web 不再只依賴共享 `ADMIN_API_TOKEN` 作為唯一身分來源。

完成後應達成：

1. caregiver_web 可使用 caregiver/admin 身分登入或帶入正式 session。
2. 後端能從 request 解析出呼叫者角色：
   - `super_admin`
   - `caregiver`
3. caregiver 呼叫 admin/care-alert API 時，只能看到授權住民資料。
4. super_admin 保留全域管理能力。
5. caregiver_web 對無授權住民情境顯示友善空狀態。
6. 不破壞 CR-0039 的 requireAdmin。
7. 不破壞 CR-0040 的 resident scope。
8. 不破壞長者端 `/api/care-alerts/notify` 建立流程。

---

## 3. 必讀文件

執行前請先閱讀：

- `CLAUDE.md`
- `docs/PRODUCTION_AUDIT_CR0033.md`
- `docs/CHANGE_REVIEW.md`
- `backend/stt_proxy/server.js`
- `backend/stt_proxy/services/admin/authorizationService.js`
- `caregiver_web/app.js`
- `caregiver_web/README.md`
- `.env.example`

---

## 4. 必須先盤點

請先盤點目前是否已有：

1. 使用者登入 session service
2. caregiver / admin user table
3. `last_login_at`
4. admin token middleware
5. caregiver_web auth header 注入點
6. token 儲存方式
7. `requireAdmin`
8. `authorizationService.resolveAuthContext`
9. 測試 seam 是否能改成正式 HTTP auth path
10. 現有 caregiver_web 是否仍只靠 localStorage token

盤點後再決定最小改動方案。

---

## 5. 後端需求

### 5.1 Auth Context

請讓後端可從 request 建立正式 auth context。

建議設計：

```js
{
  role: 'super_admin' | 'caregiver',
  userId: string | null,
  caregiverId: string | null,
  scope: 'all' | 'assigned_residents'
}
```

### 5.2 Super Admin

保留既有共享 `ADMIN_API_TOKEN` 行為，但請明確命名為 super admin token。

要求：

- 共享 token 只能代表 `super_admin`
- log 不可印出 token
- 文件需說明這是管理者最高權限，不應給一般照護人員使用

### 5.3 Caregiver Session

若專案已有 session / user auth，請優先沿用。

若尚未完成正式登入系統，請建立最小可行 caregiver session path，但不得使用 hardcoded user。

最低要求：

- 後端可辨識 caregiver 呼叫者
- caregiver 身分必須來自資料庫或正式 session
- 不可使用寫死 caregiver id
- 不可用 fake token 通過 production

### 5.4 Middleware

請檢查並必要時拆分：

- `requireAdmin`
- `requireCaregiverOrAdmin`
- `resolveAdminAuthContext`
- `requireScopedResidentAccess`

不得讓所有 authenticated user 都自動成為 super admin。

### 5.5 Scope 套用

確認以下 API 能依 role 正確 scope：

- `GET /api/care-alerts`
- `GET /api/care-alerts/:id`
- `PATCH /api/care-alerts/:id/status`
- `/api/admin/elders/:id/physio`
- `/api/admin/elders/:id/emotion`
- `/api/admin/elders/:id/game-metrics`
- `GET /api/admin/daily-care-tasks`  
  這是 CR-0040 殘留硬 blocker，必須本次處理或明確拆出且 fail-closed。

---

## 6. caregiver_web 需求

### 6.1 Auth Header

caregiver_web 必須能依登入身分帶正確 header：

- super_admin：使用管理者 token
- caregiver：使用 caregiver session token

不得所有請求都固定帶共享 admin token。

### 6.2 Empty State

若 caregiver 沒有授權住民，畫面應顯示友善空狀態，例如：

> 目前尚未被指派可查看的住民。請聯絡管理者確認權限設定。

不可：
- 顯示全部資料
- 顯示 crash
- 顯示 raw 403 stack
- 顯示工程錯誤

### 6.3 403 Handling

caregiver_web 遇到 403 時：

- 顯示權限不足提示
- 不重複狂打 API
- 不清空登入狀態，除非 session 真的失效
- 不顯示敏感 technical message

---

## 7. 測試需求

請至少補以下測試：

### 7.1 後端測試

1. 未帶任何 auth → 401
2. 帶 super_admin token → 可看全部授權範圍
3. caregiver A → 只能看到 A 授權住民
4. caregiver A → 不可讀 caregiver B 的住民 alert detail
5. caregiver A → 不可 PATCH caregiver B 的住民 alert
6. caregiver 無授權住民 → list 回空陣列，不是全部資料
7. `GET /api/admin/daily-care-tasks` 不可跨住民洩漏
8. production 不接受 fake caregiver token
9. invalid session → 401
10. valid session but no resident scope → 200 empty list or 403 detail, 視 API 語意而定

### 7.2 caregiver_web 測試

1. API request 會帶正確 auth header
2. 401 顯示登入失效
3. 403 顯示權限不足
4. 空資料顯示空狀態
5. 不再預設假設所有 token 都是 super_admin

---

## 8. 文件需求

請更新：

- `docs/CHANGE_REVIEW.md`
- `caregiver_web/README.md`
- `.env.example`
- 如有必要，新增或更新：
  - `docs/AUTHORIZATION_MODEL.md`
  - `docs/CAREGIVER_WEB_AUTH.md`

文件需說明：

1. super_admin 與 caregiver 的差異
2. caregiver 如何取得授權住民
3. resident_caregiver_links 的用途
4. caregiver_web 如何帶 auth
5. production 不應把 super_admin token 發給一般照護人員

---

## 9. 限制

本 CR 不得：

1. 破壞 `/api/care-alerts/notify`
2. 破壞 Realtime WebRTC
3. 破壞 Memory API
4. 把所有登入者視為 super_admin
5. 使用 hardcoded caregiver id
6. 使用 fake token 作為 production auth
7. 讓 caregiver_web 無條件讀取全部住民
8. 在 production log 印出 token、email、完整對話或敏感資料
9. 移除 CR-0039 / CR-0040 的測試
10. 為了通過測試而放寬授權

---

## 10. 驗收標準

完成後必須達成：

1. super_admin 行為維持可用。
2. caregiver-scoped 身分可經正式 HTTP request 觸發。
3. caregiver 只能看到授權住民資料。
4. 未授權 detail / update 不能成功。
5. caregiver_web 能處理 401 / 403 / empty state。
6. `GET /api/admin/daily-care-tasks` 不再是跨住民資料外洩 blocker。
7. backend tests 全綠。
8. caregiver_web tests 全綠。
9. `docs/CHANGE_REVIEW.md` 已更新。
10. 回報殘留風險與下一個 CR。

---

## 11. 完成回報格式

請用以下格式回報：

```md
## CR-0041 完成回報

### 1. 本次目標
-

### 2. 修改檔案
-

### 3. 後端授權改動
-

### 4. caregiver_web 改動
-

### 5. API scope 套用結果
-

### 6. 測試結果
-

### 7. 正式版風險檢查
- 是否仍有共享 super_admin token：
- caregiver 是否可跨住民：
- daily-care-tasks 是否已 scope：
- /notify 是否未被破壞：
- 是否有 hardcoded auth：
- 是否有 sensitive log：

### 8. 殘留風險
-

### 9. 下一個建議 CR
-
```
