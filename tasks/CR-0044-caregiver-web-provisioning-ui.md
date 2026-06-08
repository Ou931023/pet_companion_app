# CR-0044 — Caregiver Web Provisioning UI for Caregiver Accounts and Resident Assignments

## 1. 任務定位

本任務接續：

- CR-0040：Resident-Caregiver Authorization Model
- CR-0041：Caregiver Scoped Admin Session Backend
- CR-0042：Caregiver Web Auth UI / Role Header / 401-403 / Empty State
- CR-0043：Caregiver Account and Resident-Caregiver Link Provisioning Backend

目前後端已具備 super_admin-only provisioning API：

- `GET /api/admin/caregivers`
- `POST /api/admin/caregivers`
- `PATCH /api/admin/caregivers/:id`
- `PATCH /api/admin/caregivers/:id/status`
- `GET /api/admin/resident-caregiver-links`
- `POST /api/admin/resident-caregiver-links`
- `PATCH /api/admin/resident-caregiver-links/:id`
- `DELETE /api/admin/resident-caregiver-links/:id`

本 CR 目標是補齊 caregiver_web 的 super_admin 管理 UI，讓管理者可透過網頁建立照護人員帳號並指派住民授權關聯。

---

## 2. 本次目標

完成 caregiver_web 兩個 super_admin-only 管理頁：

1. 照護人員管理
2. 住民授權指派管理

完成後應達成：

- super_admin 可在 caregiver_web 建立 / 查看 / 編輯 / 停用 caregiver。
- super_admin 可建立 / 查看 / 修改 / 停用 resident-caregiver link。
- caregiver 模式不可看到或操作這些 super_admin-only 功能。
- UI 正確處理 401 / 403 / empty state。
- 不使用假資料。
- 不破壞既有 dashboard、Care Alert、analytics、daily-care-tasks。

---

## 3. 必讀文件

請先閱讀：

- `CLAUDE.md`
- `docs/CHANGE_REVIEW.md`
- `docs/AUTHORIZATION_MODEL.md`
- `docs/CAREGIVER_WEB_AUTH.md`
- `docs/CAREGIVER_PROVISIONING.md` if exists
- `caregiver_web/app.js`
- `caregiver_web/index.html`
- `caregiver_web/styles.css`
- `caregiver_web/README.md`
- CR-0043 新增的 backend endpoint tests
- `backend/stt_proxy/server.js`

---

## 4. 先盤點

修改前請盤點：

1. caregiver_web 目前頁籤 / section 架構。
2. super_admin-only 功能目前如何隱藏。
3. authState / authMode 如何判斷。
4. 目前 API helper：
   - authHeaders()
   - authJsonHeaders()
   - adminAuthHeaders()
   - adminJsonHeaders()
5. 目前 401 / 403 / empty state helper。
6. 是否已有 users 管理頁可共用 UI。
7. 是否已有 elders list API 可拿住民選單。
8. 測試架構與現有 caregiver_web 測試。

---

## 5. UI 需求一：照護人員管理

### 5.1 顯示條件

僅 `authMode === 'super_admin'` 顯示。

caregiver 模式：

- 不顯示入口，或顯示但禁用並提示權限不足。
- 不得發送 caregiver management API request。

### 5.2 列表

顯示：

- 顯示名稱
- Email
- Firebase UID 狀態
- 狀態 active / inactive
- 建立時間
- 更新時間
- 操作按鈕

### 5.3 新增 caregiver

表單欄位：

- displayName
- email
- firebaseUid optional / pending
- status default active

要求：

- email 必填。
- displayName 必填。
- 建立成功後刷新列表。
- 失敗時顯示友善錯誤。
- 不顯示 raw stack。
- 不處理密碼。
- 不產生 fake token。

### 5.4 編輯 caregiver

至少支援：

- displayName
- email
- firebaseUid if backend supports
- status if backend supports

若後端只支援部分欄位，請依 CR-0043 API 實際契約實作，不要憑空假設。

### 5.5 停用 / 啟用 caregiver

支援切換 active / inactive。

提示語需說明：

> 停用後，該照護人員將無法查看被指派住民資料。

---

## 6. UI 需求二：住民授權指派管理

### 6.1 顯示條件

僅 super_admin 顯示。

caregiver 模式不得操作。

### 6.2 列表

顯示：

- 住民名稱
- 照護人員名稱
- role：primary / backup / viewer
- status：active / inactive
- 建立時間
- 更新時間
- 操作按鈕

### 6.3 建立 link

表單欄位：

- resident select
- caregiver select
- role select：primary / backup / viewer
- status default active

要求：

- resident 與 caregiver 必填。
- 只能列出可用住民與 caregiver。
- 建立成功後刷新列表。
- 重複 active link 錯誤需友善顯示。
- 不用假資料填 select。

### 6.4 修改 link

至少支援：

- role
- status

### 6.5 停用 link

停用後應提示：

> 停用後，該照護人員將不能再查看此住民的資料。

---

## 7. 401 / 403 / Empty State

沿用 CR-0042 行為。

要求：

1. 401：顯示登入已失效，請重新登入。
2. 403：顯示目前帳號沒有權限查看此資料。
3. 空 caregiver list：顯示目前尚無照護人員。
4. 空 assignment list：顯示目前尚無住民授權指派。
5. resident/caregiver select 無資料時，清楚提示需先建立資料。
6. 不顯示 undefined / null / raw stack。
7. 不用假資料補畫面。

---

## 8. API Helper 要求

super_admin-only provisioning API 必須使用：

- `adminAuthHeaders()`
- `adminJsonHeaders()`

不得使用 caregiver scoped helper。

原因：這些 API 只允許 super_admin 呼叫。

---

## 9. 測試需求

請至少新增或更新 caregiver_web 測試：

1. super_admin mode 顯示照護人員管理入口。
2. caregiver mode 不顯示照護人員管理入口。
3. super_admin mode 顯示住民授權指派入口。
4. caregiver mode 不顯示住民授權指派入口。
5. 建立 caregiver 時使用 admin auth header。
6. 建立 assignment 時使用 admin auth header。
7. 401 顯示登入失效。
8. 403 顯示權限不足。
9. 空 caregiver list 顯示空狀態。
10. 空 assignment list 顯示空狀態。
11. 成功建立 caregiver 後刷新列表。
12. 成功建立 assignment 後刷新列表。
13. 不使用 fake data。
14. 不在 console 顯示 token。

如後端未改，backend tests 可不跑；若有任何後端改動，backend tests 必須全綠。

---

## 10. 文件需求

請更新：

- `docs/CHANGE_REVIEW.md`
- `docs/CAREGIVER_WEB_AUTH.md`
- `docs/CAREGIVER_PROVISIONING.md` if exists
- `caregiver_web/README.md`

文件需說明：

1. super_admin 如何進入照護人員管理。
2. 如何新增 caregiver。
3. 如何綁定 Firebase UID。
4. 如何建立 resident-caregiver link。
5. 停用 caregiver / link 的效果。
6. caregiver 模式不能操作 provisioning。
7. production 不應將 super_admin token 發給一般照護人員。

---

## 11. 限制

本 CR 不得：

1. 修改或破壞 `/api/care-alerts/notify`
2. 修改 Realtime WebRTC
3. 修改 Memory API
4. 修改後端授權規則，除非發現明確 bug 並先說明
5. 讓 caregiver 模式看到 super_admin-only 管理功能
6. 使用 hardcoded caregiver id
7. 使用 fake caregiver token
8. 使用假住民 / 假照護人員資料填 UI
9. 在 UI 或 console 顯示完整 token
10. 為了通過測試而放寬後端授權

---

## 12. 驗收標準

完成後必須符合：

1. super_admin 可從 caregiver_web 管理 caregiver。
2. super_admin 可從 caregiver_web 管理 resident-caregiver links。
3. caregiver 模式看不到或不能操作 provisioning UI。
4. 空狀態、401、403 處理正確。
5. 不使用假資料。
6. caregiver_web tests 全綠。
7. 若後端有改動，backend tests 全綠。
8. CHANGE_REVIEW 已更新。
9. 無 hardcoded auth / fake token / sensitive log。

---

## 13. 完成回報格式

請用以下格式回報：

```md
## CR-0044 完成回報

### 1. 本次目標
-

### 2. 修改檔案
-

### 3. caregiver_web UI 改動
-

### 4. API helper / header 行為
-

### 5. 401 / 403 / empty state 行為
-

### 6. 測試結果
-

### 7. 正式版風險檢查
- caregiver 是否可看到 provisioning UI：
- provisioning API 是否使用 admin header：
- 是否有 hardcoded caregiver：
- 是否有 fake data：
- 是否有 sensitive log：
- 是否改動 backend：

### 8. 殘留風險
-

### 9. 下一個建議 CR
-
```
