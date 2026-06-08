# CR-0043 — Caregiver Account and Resident-Caregiver Link Provisioning

## 1. 任務定位

本任務接續：

- CR-0040：Resident-Caregiver Authorization Model
- CR-0041：Caregiver Scoped Admin Session Backend
- CR-0042：Caregiver Web Auth UI / Role Header / 401-403 / Empty State

目前系統已具備：

- `resident_caregiver_links` schema
- caregiver-scoped backend authorization
- caregiver_web 可用 caregiver token 呼叫 scoped API
- caregiver_web 可處理 401 / 403 / empty state

但目前殘留問題是：

> caregiver 帳號與 resident-caregiver 授權關聯尚未有正式 provisioning 流程。  
> 也就是說，super_admin 尚無正式管理介面/API 來建立照護人員帳號、指派住民、停用關聯。

本 CR 目標是建立正式的 caregiver account + resident assignment provisioning，使 caregiver scoped auth 能端到端驗證。

---

## 2. 本次目標

建立 super_admin-only 的照護人員與住民授權管理流程。

完成後應達成：

1. super_admin 可建立 / 查看 / 停用 caregiver 帳號。
2. super_admin 可建立 / 查看 / 停用 resident-caregiver 授權關聯。
3. caregiver 登入後只能看到被指派的住民資料。
4. caregiver_web 提供最小可用的授權管理 UI。
5. 所有敏感操作寫入 audit log。
6. 不破壞既有 super_admin、caregiver scoped、Care Alert、Realtime、Memory 流程。

---

## 3. 必讀文件

請先閱讀：

- `CLAUDE.md`
- `docs/CHANGE_REVIEW.md`
- `docs/AUTHORIZATION_MODEL.md`
- `docs/CAREGIVER_WEB_AUTH.md`
- `backend/stt_proxy/server.js`
- `backend/stt_proxy/services/admin/adminAuthContext.js`
- `backend/stt_proxy/services/admin/authorizationService.js`
- `caregiver_web/app.js`
- `caregiver_web/index.html`
- `caregiver_web/README.md`
- migration 013 resident_caregiver_links

---

## 4. 先盤點

修改前請盤點：

1. users table 欄位：
   - id
   - email
   - role
   - firebase_uid
   - display_name / name
   - status
   - last_login_at
2. elders / residents table 實際名稱與欄位。
3. resident_caregiver_links 目前欄位。
4. 是否已有 audit_logs table。
5. 是否已有 admin users API。
6. caregiver_web 是否已有使用者管理頁。
7. super_admin-only API 目前 middleware。
8. 測試資料如何建立 users / elders / links。

---

## 5. 後端 API 需求

### 5.1 Caregiver Accounts

新增或補齊 super_admin-only API：

- `GET /api/admin/caregivers`
- `POST /api/admin/caregivers`
- `PATCH /api/admin/caregivers/:id`
- `PATCH /api/admin/caregivers/:id/status`

最低資料：

```json
{
  "id": "string",
  "email": "masked or full depending role",
  "displayName": "string",
  "role": "caregiver",
  "status": "active | inactive",
  "firebaseUid": "string|null",
  "createdAt": "datetime",
  "updatedAt": "datetime"
}
```

要求：

1. 僅 super_admin 可呼叫。
2. caregiver 不可建立其他 caregiver。
3. email 不可重複。
4. 不可明文處理密碼。
5. 若 firebase_uid 尚未綁定，可建立 pending caregiver record。
6. 回傳不可包含敏感 token。
7. 修改狀態需寫 audit log。

---

### 5.2 Resident-Caregiver Links

新增或補齊 super_admin-only API：

- `GET /api/admin/resident-caregiver-links`
- `POST /api/admin/resident-caregiver-links`
- `PATCH /api/admin/resident-caregiver-links/:id`
- `DELETE /api/admin/resident-caregiver-links/:id` 或 soft disable

最低資料：

```json
{
  "id": "string",
  "residentId": "string",
  "residentName": "string",
  "caregiverId": "string",
  "caregiverName": "string",
  "role": "primary | backup | viewer",
  "status": "active | inactive",
  "createdAt": "datetime",
  "updatedAt": "datetime"
}
```

要求：

1. 僅 super_admin 可管理。
2. caregiver 不可自行指派住民。
3. 建立 link 前需確認 resident 與 caregiver 存在。
4. 重複 active link 應避免。
5. 停用 link 後 caregiver 不可再看到該 resident 的資料。
6. 每次新增 / 停用 / 修改 link 都需寫 audit log。
7. API 需 fail-closed。

---

### 5.3 Scope Refresh

確認 CR-0040 / CR-0041 的 scope 查詢會即時反映：

1. 新增 link 後 caregiver 可看到該住民資料。
2. 停用 link 後 caregiver 不可看到該住民資料。
3. inactive caregiver 不可存取 scoped API。
4. inactive link 不可授權。
5. super_admin 不受 link 限制。

---

## 6. caregiver_web 需求

新增最小可用 UI，限 super_admin 顯示：

### 6.1 Caregiver Management

功能：

1. 照護人員列表。
2. 新增照護人員。
3. 編輯名稱 / email / firebase_uid if applicable。
4. 啟用 / 停用照護人員。
5. 顯示狀態。
6. caregiver 模式不可看到此頁，或顯示權限不足。

### 6.2 Resident Assignment Management

功能：

1. 顯示住民-照護人員授權列表。
2. 建立授權關聯。
3. 修改 role。
4. 啟用 / 停用授權關聯。
5. 顯示目前 active/inactive。
6. 建立後可提示「此照護人員登入後將只能查看被指派住民」。

### 6.3 UX

要求：

1. 不顯示 raw error。
2. 401 / 403 沿用 CR-0042 行為。
3. 操作成功有明確提示。
4. 操作失敗顯示友善錯誤。
5. 空列表顯示空狀態。
6. 不使用假資料填 UI。

---

## 7. Audit Log 需求

若已有 audit log，請使用既有機制。若尚未完整，請建立最小可用紀錄。

需記錄：

1. 建立 caregiver。
2. 停用 caregiver。
3. 修改 caregiver。
4. 建立 resident-caregiver link。
5. 修改 link。
6. 停用 link。

最低欄位：

```json
{
  "actorId": "string|null",
  "actorRole": "super_admin",
  "action": "string",
  "targetType": "caregiver | resident_caregiver_link",
  "targetId": "string",
  "createdAt": "datetime"
}
```

不可在 audit log 寫入 token。

---

## 8. 測試需求

### 8.1 Backend Tests

至少測：

1. caregiver 呼叫 caregiver management API → 403。
2. 無 token → 401。
3. super_admin 建立 caregiver → 201/200。
4. 重複 email → 409 或明確錯誤。
5. super_admin 建立 resident-caregiver link → 201/200。
6. 重複 active link 不會建立第二筆 active link。
7. 停用 link 後 caregiver 無法看該 resident alert。
8. inactive caregiver 無法讀 scoped API。
9. super_admin 可看到全部。
10. audit log 有寫入。
11. API 不回傳 token。
12. invalid resident/caregiver id → 400/404。

### 8.2 caregiver_web Tests

至少測：

1. super_admin mode 顯示 caregiver management。
2. caregiver mode 不顯示 super_admin-only 管理頁。
3. 建立 caregiver request header 正確。
4. 建立 link request header 正確。
5. 401 顯示登入失效。
6. 403 顯示權限不足。
7. 空列表顯示空狀態。
8. 成功操作顯示提示。
9. 不將 caregiver token 當 admin token。
10. 不顯示完整敏感資料。

---

## 9. 文件需求

請更新：

- `docs/CHANGE_REVIEW.md`
- `docs/AUTHORIZATION_MODEL.md`
- `docs/CAREGIVER_WEB_AUTH.md`
- `caregiver_web/README.md`

如需要，新增：

- `docs/CAREGIVER_PROVISIONING.md`

文件需說明：

1. super_admin 如何建立 caregiver。
2. caregiver 如何綁定 Firebase uid / session 身分。
3. 如何指派 resident-caregiver link。
4. link role/status 語意。
5. 停用 caregiver / link 的效果。
6. production 不可把 super_admin token 發給一般照護人員。

---

## 10. 限制

本 CR 不得：

1. 修改或破壞 `/api/care-alerts/notify`
2. 修改 Realtime WebRTC
3. 修改 Memory API
4. 使用 hardcoded caregiver id
5. 使用 fake caregiver token
6. 讓 caregiver 自行指派住民
7. 讓 caregiver 管理其他 caregiver
8. 把 inactive link 當 active 授權
9. 在 log / UI 顯示完整 token
10. 用假資料填補管理畫面
11. 放寬 CR-0039 / CR-0040 / CR-0041 的授權限制

---

## 11. 驗收標準

完成後必須符合：

1. super_admin 可建立 caregiver。
2. super_admin 可建立 resident-caregiver link。
3. caregiver 登入後可看到被指派住民。
4. caregiver 不可看到未指派住民。
5. 停用 link 後權限立即失效。
6. inactive caregiver 不可存取 scoped API。
7. caregiver_web 有最小可用管理 UI。
8. backend tests 全綠。
9. caregiver_web tests 全綠。
10. CHANGE_REVIEW 已更新。
11. 無 hardcoded auth / fake token / sensitive log。

---

## 12. 完成回報格式

請用以下格式回報：

```md
## CR-0043 完成回報

### 1. 本次目標
-

### 2. 修改檔案
-

### 3. 後端 API 改動
-

### 4. caregiver_web 改動
-

### 5. resident-caregiver provisioning 行為
-

### 6. Audit log
-

### 7. 測試結果
-

### 8. 正式版風險檢查
- caregiver 是否可自我授權：
- inactive link 是否仍可存取：
- inactive caregiver 是否仍可存取：
- 是否有 hardcoded caregiver：
- 是否有 fake token：
- 是否有 sensitive log：

### 9. 殘留風險
-

### 10. 下一個建議 CR
-
```
