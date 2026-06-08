# CR-0040：Resident-Caregiver Authorization Model

## 1. 任務背景

CR-0039 已完成 Backend Authorization Boundary Part 1：

- `/api/admin/*` 讀取路由已掛 `requireAdmin`
- `GET /api/care-alerts`
- `GET /api/care-alerts/:id`
- `PATCH /api/care-alerts/:id/status`
- caregiver_web 已補 auth header

但目前仍有正式版 P0 風險：

> 持有 `ADMIN_API_TOKEN` 的呼叫者仍可能看見全部住民資料，尚未依照「住民－照護人員授權關係」做資料範圍過濾。

本 CR 目標是建立正式版 resident-caregiver authorization model，讓照護人員只能查看與處理自己被授權管理的住民資料。

---

## 2. 本次目標

建立住民與照護人員的授權關聯模型，並將授權範圍套用到 Care Alert 與 admin analytics 相關 API。

本 CR 是修補 P0-2 的第二階段：

- CR-0039：先加驗證擋門
- CR-0040：再加授權範圍過濾

---

## 3. 必讀文件

開始前請先閱讀：

1. `CLAUDE.md`
2. `docs/PRODUCTION_AUDIT_CR0033.md`
3. `docs/CHANGE_REVIEW.md`
4. CR-0039 相關 commit / review 紀錄
5. 目前 backend auth / admin / care-alerts 相關程式碼

---

## 4. 實作範圍

### 4.1 Schema / Data Model

請盤點目前是否已有以下資料結構：

- users
- residents
- caregivers
- resident_caregiver_links
- care_alerts
- admin analytics 相關資料表或 store

若缺少 `resident_caregiver_links`，請提出並實作最小可行 schema / migration。

建議欄位：

```sql
resident_caregiver_links
- id
- resident_id
- caregiver_id
- role
- status
- created_at
- updated_at
- revoked_at
```

`status` 建議至少支援：

- active
- revoked

`role` 可先保守支援：

- primary
- secondary
- viewer

如目前專案 schema 不適合完全照此設計，請以現有架構為準，但必須達成授權範圍過濾。

---

### 4.2 Authorization Service

請建立或補強授權 service / middleware，例如：

```js
getAuthorizedResidentIdsForCaregiver()
assertCanAccessResident()
filterAlertsByAuthorizedResidents()
```

要求：

1. 不可 hardcode resident id。
2. 不可 hardcode caregiver id。
3. 不可把所有 caregiver 都當 super admin。
4. 必須能區分「已驗證」與「有權限」。
5. 無權限時 list API 不可混入資料，detail / update API 必須拒絕跨住民操作。

---

### 4.3 Care Alert API Scope

請將授權範圍套用到：

1. `GET /api/care-alerts`
2. `GET /api/care-alerts/:id`
3. `PATCH /api/care-alerts/:id/status`

要求：

- 未驗證：401
- 已驗證但無權限：403 或 list 中不回傳該資料
- 已驗證且有權限：200
- list API 不可回傳未授權 resident 的 alerts
- detail API 不可讀取未授權 resident 的 alert
- update API 不可修改未授權 resident 的 alert

---

### 4.4 Admin Analytics API Scope

請盤點並套用 resident scope 到 `/api/admin/*` 中涉及住民資料的讀取 API。

至少需檢查：

- 情緒分析
- 生理／生活狀態分析
- 心理健康分析
- 遊戲退化指標
- 使用者／住民相關資料
- Care Alert 統計

要求：

- caregiver 只能看到授權住民資料。
- 若是真正 super admin，必須有明確角色或設定，不可用「持 token 即全看」作為正式行為。
- 若現有權限模型尚無 super admin / caregiver 分層，請先以最小改動建立清楚分界。

---

### 4.5 caregiver_web Integration

後端加上 scope 後，caregiver_web 必須能正常顯示。

要求：

1. caregiver_web 繼續帶 auth header。
2. 無授權住民時顯示空狀態。
3. 不可因 403 / empty list 直接壞版。
4. UI 不可顯示工程錯誤字眼。
5. 不可用假資料填畫面。

---

## 5. 明確不可做

本 CR 不可：

1. 破壞 CR-0039 已建立的 `requireAdmin` 擋門。
2. 破壞 `/api/care-alerts/notify` 長者端建立 Care Alert 流程。
3. 更改 Realtime WebRTC 流程。
4. 更改 Memory API 成功回傳契約。
5. 更改 Care Alert API 既有 200 成功回傳格式。
6. 使用 hardcoded resident/caregiver 作為正式授權。
7. 用 demo seed 假裝正式授權完成。
8. 一次重寫整個 auth 系統。

---

## 6. 測試要求

請補上 backend 與 caregiver_web 必要測試。

至少涵蓋：

### 6.1 Care Alert List

- 未驗證 → 401
- 已驗證但無授權住民 → 200 empty list 或合理空結果
- 已驗證且有授權 → 200，只回傳授權住民 alerts
- list 不可混入未授權 resident alerts

### 6.2 Care Alert Detail

- 未驗證 → 401
- 已驗證但無該 resident 權限 → 403
- 已驗證且有權限 → 200

### 6.3 Care Alert Status Update

- 未驗證 → 401
- 已驗證但無該 resident 權限 → 403
- 已驗證且有權限 → 200，狀態成功更新

### 6.4 Admin Analytics

- 未驗證 → 401
- 有權限 → 只回傳授權住民資料
- 無權限 → 不回傳未授權住民資料

### 6.5 caregiver_web

- auth header 仍存在
- 空狀態不壞版
- 403 有友善提示或安全處理

---

## 7. 建議執行指令

Backend：

```bash
cd backend/stt_proxy
npm run check
npm test
```

Caregiver Web：

```bash
cd caregiver_web
node --test *.test.js
```

若實際專案指令不同，請依現有 package scripts 執行，並在回報中說明。

---

## 8. 驗收標準

本 CR 完成後必須符合：

1. Care Alert 管理 API 已具備 resident scope。
2. admin analytics 涉及住民資料的 API 已具備 resident scope。
3. caregiver_web 不會顯示未授權住民資料。
4. 未授權跨住民讀取／更新會被擋下。
5. `/api/care-alerts/notify` 長者端建立流程未被破壞。
6. 所有新增與既有相關測試通過。
7. `docs/CHANGE_REVIEW.md` 已新增 CR-0040 紀錄。

---

## 9. 完成回報格式

請完成後用以下格式回報：

```md
## CR-0040 完成回報

### 1. 本次目標
-

### 2. 修改檔案
-

### 3. 新增 / 修改的授權模型
-

### 4. 已套用 resident scope 的 API
-

### 5. 測試結果
-

### 6. 正式版風險檢查
- 是否仍可能跨住民讀取：
- 是否仍可能跨住民更新 Care Alert：
- 是否破壞 /notify：
- 是否破壞 caregiver_web：
- 是否使用 hardcoded 授權：

### 7. 殘留風險與下一步
-
```
