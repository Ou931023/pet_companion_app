# CR-0042 — Caregiver Web Auth UI, Role Header, 401/403 Handling, and Empty State

## 1. 任務定位

本任務接續：

- CR-0039：Backend Authorization Boundary Part 1
- CR-0040：Resident-Caregiver Authorization Model
- CR-0041：Caregiver Scoped Admin Session Backend

目前後端已具備：

- `ADMIN_API_TOKEN` → `super_admin`
- Firebase idToken → `users.role`
- caregiver → caregiver-scoped auth context
- Care Alert / elders analytics / daily-care-tasks 已可依授權住民過濾
- production fail-closed，不會預設 super_admin

但 caregiver_web 目前仍殘留：

> caregiver_web 仍主要使用共享 admin token，尚未提供正式 caregiver 登入／session UI，也尚未完整處理 caregiver 權限下的 401、403、empty state。

本 CR 目標是補齊 caregiver_web 前端整合，使管理端能用正式角色與授權範圍操作，而不是依賴共享 super_admin token。

---

## 2. 本次目標

完成 caregiver_web 前端授權整合：

1. caregiver_web 支援 super_admin / caregiver 兩種身分模式。
2. caregiver_web 可帶正確 Authorization header。
3. caregiver token 不得被當成 super_admin token。
4. 401 顯示登入失效或需要重新登入。
5. 403 顯示權限不足。
6. 無授權住民時顯示友善空狀態。
7. 不再讓一般照護人員依賴共享 `ADMIN_API_TOKEN`。
8. 文件化 caregiver_web auth 流程。
9. 不破壞既有 dashboard 功能與測試。

---

## 3. 必讀文件

請先閱讀：

- `CLAUDE.md`
- `docs/CHANGE_REVIEW.md`
- `docs/AUTHORIZATION_MODEL.md`
- `caregiver_web/app.js`
- `caregiver_web/index.html`
- `caregiver_web/README.md`
- `caregiver_web/config.example.js`
- `backend/stt_proxy/services/admin/adminAuthContext.js`
- `backend/stt_proxy/services/admin/authorizationService.js`
- `.env.example`

---

## 4. 先盤點

修改前請先盤點：

1. caregiver_web 目前 token 儲存位置。
2. caregiver_web 目前 `adminAuthHeaders()` / `adminJsonHeaders()` 行為。
3. 是否已有登入表單。
4. 是否已有 config.js / config.example.js。
5. 目前 API error handling 是否集中。
6. 哪些 API 會呼叫：
   - `/api/care-alerts`
   - `/api/admin/elders/*`
   - `/api/admin/daily-care-tasks`
   - `/api/admin/users`
   - `/api/admin/overview`
   - marketplace 相關 API
7. 哪些 API 仍必須 super_admin-only。
8. 現有測試如何覆蓋 fetch header / error UI。

---

## 5. caregiver_web 功能需求

### 5.1 Auth Mode

caregiver_web 需清楚區分：

- `super_admin`
- `caregiver`

建議前端狀態：

```js
{
  authMode: 'super_admin' | 'caregiver' | 'none',
  token: string | null,
  displayName: string | null,
  role: string | null
}
```

實作可以配合現有架構簡化，但語意必須清楚。

---

### 5.2 Header 行為

所有需要驗證的 API 都應透過統一 helper 產生 header。

要求：

1. super_admin 模式：
   - `Authorization: Bearer <ADMIN_API_TOKEN>`
2. caregiver 模式：
   - `Authorization: Bearer <Firebase idToken or caregiver session token>`
3. 不可把 caregiver token 寫入 admin token 欄位。
4. 不可把所有 token 都命名為 admin token。
5. 不可把 token 印到 console。
6. 若無 token，不應狂打受保護 API。

---

### 5.3 Login / Token Input UI

若正式 Firebase login 尚未在 caregiver_web 實作，本 CR 可先建立最小可行 UI，但必須清楚、不可 fake production。

可接受方案：

- super_admin：輸入管理者 token。
- caregiver：貼上或登入取得 caregiver session token/idToken。
- 若尚未完成完整 Firebase popup login，UI 與文件需明確標示目前如何取得 caregiver token，並列為後續 CR。

不可接受：

- hardcode caregiver token
- hardcode caregiver id
- fake login success
- 未驗證就進 dashboard
- 把共享 super_admin token 當一般照護人員登入方式

---

### 5.4 401 Handling

遇到 401：

- 顯示「登入已失效，請重新登入」
- 停止重複請求
- 提供回到登入狀態或重新輸入 token 的方式
- 不顯示 raw stack
- 不顯示完整 token
- 不顯示工程錯誤碼作為主要文案

---

### 5.5 403 Handling

遇到 403：

- 顯示「目前帳號沒有權限查看此資料」
- 不清除 token，除非後端明確表示 session invalid
- 不重複狂打 API
- 對 detail/update 顯示權限不足
- 對 list 顯示空狀態或權限不足狀態，依 API 語意處理

---

### 5.6 Empty State

當 caregiver 無授權住民或 API 回空陣列時，顯示友善空狀態：

> 目前尚未被指派可查看的住民。請聯絡管理者確認權限設定。

不可：

- 顯示全部資料
- 顯示錯誤 stack
- 顯示 undefined/null
- 用假資料填滿畫面
- 讓畫面看起來像壞掉

---

## 6. API 行為需求

請確認 caregiver_web 對以下 API 的角色處理：

### caregiver 可用且需 scoped

- `GET /api/care-alerts`
- `GET /api/care-alerts/:id`
- `PATCH /api/care-alerts/:id/status`
- `/api/admin/elders/:id/physio`
- `/api/admin/elders/:id/emotion`
- `/api/admin/elders/:id/game-metrics`
- `GET /api/admin/daily-care-tasks`

### super_admin-only

以下 API 若後端仍為 super_admin-only，caregiver_web 應正確顯示權限不足或隱藏入口：

- `/api/admin/users`
- `/api/admin/overview`
- marketplace admin endpoints if still super_admin-only
- system-level settings

不得讓 caregiver UI 嘗試讀取 super_admin-only API 後一直報錯洗版。

---

## 7. 測試需求

請至少新增或更新 caregiver_web 測試：

1. super_admin mode 會帶 `Authorization: Bearer <admin token>`
2. caregiver mode 會帶 `Authorization: Bearer <caregiver token>`
3. 無 token 不應呼叫受保護 API，或會顯示登入提示
4. 401 顯示登入失效
5. 403 顯示權限不足
6. 空 alert list 顯示友善空狀態
7. caregiver mode 不應把 token 存成 admin token
8. caregiver mode 不應顯示 super_admin-only 功能入口，或需顯示權限不足
9. 不會在 console/log 顯示完整 token
10. 既有 dashboard 渲染測試仍通過

如後端測試需調整，請確保 backend tests 仍全綠。

---

## 8. 文件需求

請更新：

- `caregiver_web/README.md`
- `caregiver_web/config.example.js`
- `docs/CHANGE_REVIEW.md`

請新增：

- `docs/CAREGIVER_WEB_AUTH.md`

文件需包含：

1. caregiver_web 支援的角色
2. super_admin token 用途與風險
3. caregiver token/session 用途
4. header 格式
5. 401 / 403 / empty state 行為
6. 正式 production 不應把 super_admin token 給一般照護人員
7. 若 Firebase popup login 尚未完成，列為 follow-up

---

## 9. 限制

本 CR 不得：

1. 修改或破壞 `/api/care-alerts/notify`
2. 修改 Realtime WebRTC
3. 修改 Memory API
4. 使用 hardcoded caregiver id
5. 使用 fake caregiver token
6. 把 caregiver 當 super_admin
7. 把所有 API 都改成 super_admin-only
8. 在 UI 或 console 顯示完整 token
9. 用假資料填補空狀態
10. 為通過測試而放寬後端授權

---

## 10. 驗收標準

完成後必須符合：

1. caregiver_web 可明確區分 super_admin / caregiver。
2. caregiver_web 可帶正確 Authorization header。
3. caregiver mode 會觸發 CR-0041 後端 caregiver-scoped path。
4. 401/403/empty state 有友善 UI。
5. caregiver 不會看到或操作未授權住民資料。
6. super_admin 行為維持可用。
7. caregiver_web tests 全綠。
8. backend tests 若受影響也需全綠。
9. `docs/CHANGE_REVIEW.md` 已更新。
10. `docs/CAREGIVER_WEB_AUTH.md` 已建立。

---

## 11. 完成回報格式

請用以下格式回報：

```md
## CR-0042 完成回報

### 1. 本次目標
-

### 2. 修改檔案
-

### 3. caregiver_web auth 改動
-

### 4. Header / token 行為
-

### 5. 401 / 403 / empty state 行為
-

### 6. 測試結果
-

### 7. 正式版風險檢查
- caregiver 是否仍使用共享 admin token：
- super_admin token 是否仍可能外流：
- caregiver 是否可跨住民：
- 是否有 hardcoded caregiver：
- 是否有 fake token：
- 是否有 sensitive log：

### 8. 殘留風險
-

### 9. 下一個建議 CR
-
```
