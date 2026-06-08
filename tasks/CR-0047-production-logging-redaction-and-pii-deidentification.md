# CR-0047 — Production Logging Redaction and PII De-identification

## 1. 任務定位

本任務接續 CR-0046。

CR-0046 已完成第一輪 store readiness 文件與平台阻擋項盤點，授權鏈 CR-0039 至 CR-0045 已在 code 層閉合。

目前仍有正式上架與隱私治理風險：

> production log 可能輸出 email、phone、token、完整對話、Care Alert 摘要、Firebase 錯誤細節、Telegram chat id、OpenAI error payload 或其他敏感資訊。

本 CR 目標是建立 production logging redaction 機制，確保正式環境 log 不暴露個資、健康照護訊號、token、完整對話與第三方金鑰。

---

## 2. 本次目標

完成 production logging 去識別化與敏感資料遮蔽。

完成後應達成：

1. backend production log 不輸出完整 token / secret / API key。
2. backend production log 不輸出完整 email / phone。
3. backend production log 不輸出完整對話內容。
4. backend production log 不輸出完整 Care Alert reason / summary。
5. backend production log 不輸出 Firebase / OpenAI / Telegram 原始敏感錯誤 payload。
6. caregiver_web 不在 console 顯示 token 或完整敏感資料。
7. Flutter 不在 debugPrint / print 顯示 token、完整 transcript、完整敏感錯誤。
8. 新增共用 redaction utility 與測試。
9. 更新隱私與資料治理文件。

---

## 3. 必讀文件

請先閱讀：

- `CLAUDE.md`
- `docs/PRODUCTION_AUDIT_CR0033.md`
- `docs/CHANGE_REVIEW.md`
- `docs/GOOGLE_PLAY_DATA_SAFETY.md`
- `docs/STORE_RELEASE_CHECKLIST.md`
- `backend/stt_proxy/config/env.js`
- `backend/stt_proxy/server.js`
- `backend/stt_proxy/services/admin/adminAuthContext.js`
- `backend/stt_proxy/services/admin/authorizationService.js`
- `backend/stt_proxy/services/careAlertStoreService.js` 或相關 care alert service
- `caregiver_web/app.js`
- Flutter 中所有 `debugPrint`, `print`, logger 使用點

---

## 4. 先盤點

修改前請先盤點並列入回報：

1. backend 所有 `console.log`
2. backend 所有 `console.warn`
3. backend 所有 `console.error`
4. backend 所有 logger helper
5. caregiver_web 所有 `console.*`
6. Flutter 所有 `print`
7. Flutter 所有 `debugPrint`
8. 可能輸出以下內容的位置：
   - Authorization header
   - Firebase idToken
   - ADMIN_API_TOKEN
   - OpenAI API key
   - Telegram token
   - Telegram chat id
   - DATABASE_URL
   - email
   - phone
   - resident name
   - caregiver name
   - full transcript
   - full conversation message
   - Care Alert reason / summary
   - memory content
   - stack trace with request body

---

## 5. Backend Redaction Utility

請建立或補齊共用 redaction utility。

建議檔案：

- `backend/stt_proxy/services/privacy/redaction.js`
- 或依現有架構命名

至少提供：

```js
redactToken(value)
redactEmail(value)
redactPhone(value)
redactDatabaseUrl(value)
redactObject(value)
safeErrorMessage(error)
safeLogPayload(payload)
```

要求：

1. token 只保留前後少量字元或完全遮蔽。
2. email 需遮蔽 username 中段。
3. phone 需遮蔽中段。
4. DATABASE_URL 需遮蔽密碼。
5. object redaction 需遞迴處理常見敏感 key。
6. 不可修改原物件。
7. production 預設使用 safe log。
8. development 可保留較詳細 log，但仍不可印 secret。

常見敏感 key：

- token
- accessToken
- idToken
- authorization
- apiKey
- key
- secret
- password
- chatId
- telegramToken
- openaiApiKey
- databaseUrl
- email
- phone
- transcript
- message
- conversation
- memory
- reason
- summary

---

## 6. Backend Log 修正範圍

請修正高風險 log：

1. auth / session
2. adminAuthContext
3. care-alert notify
4. care-alert store
5. Telegram notification
6. OpenAI / Realtime error
7. memory extraction / retrieval
8. database connection
9. production config summary
10. request error handler

原則：

- 對外 response 不回 stack trace。
- production log 不印 request body 全文。
- production log 不印 headers。
- production log 不印完整 error object。
- production log 可保留：
  - error code
  - request id if exists
  - route
  - status code
  - safe message
  - redacted id
  - timestamp

---

## 7. Flutter Log 修正範圍

請檢查 Flutter：

1. auth token 取得
2. Realtime WebRTC
3. transcript partial/final
4. Care Alert notify
5. memory
6. voice agent controller
7. API error

要求：

1. release / production 不輸出 token。
2. release / production 不輸出完整 transcript。
3. release / production 不輸出完整 Care Alert summary。
4. 若需要 debug log，需受 `kDebugMode` 或現有 dev flag 控制。
5. 不破壞 Realtime 狀態追蹤。

---

## 8. caregiver_web Log 修正範圍

請檢查：

1. auth token
2. fetch error
3. provisioning API
4. care-alert detail
5. admin analytics

要求：

1. 不 console.log token。
2. 不 console.log 完整 API response 中的敏感資料。
3. 401 / 403 顯示 UI，不輸出 raw sensitive payload。
4. 測試中避免 snapshot 包含 token。

---

## 9. 測試需求

### 9.1 Backend Tests

至少新增：

1. token redaction。
2. email redaction。
3. phone redaction。
4. DATABASE_URL redaction。
5. nested object redaction。
6. original object 不被 mutate。
7. sensitive keys 被遮蔽。
8. safeErrorMessage 不包含 token。
9. Care Alert summary / reason 不在 safe log 中完整出現。
10. production config summary 不輸出 secret。

### 9.2 Flutter Tests

如有合適測試點，至少新增或更新：

1. Care Alert notify 不 log token。
2. Realtime / transcript log 受 debug guard 控制。
3. auth error 不顯示完整 token。

若目前 Flutter 無集中 logger，請至少將明顯高風險 log 改成 debug-only 或 redacted。

### 9.3 caregiver_web Tests

至少新增或更新：

1. auth token 不被 console.log。
2. 401 / 403 不顯示 raw token。
3. provisioning error 不輸出完整敏感 response。

---

## 10. 文件需求

請更新：

- `docs/CHANGE_REVIEW.md`
- `docs/GOOGLE_PLAY_DATA_SAFETY.md`
- `docs/STORE_RELEASE_CHECKLIST.md`

如需要，新增：

- `docs/LOGGING_AND_REDACTION.md`

文件需說明：

1. production log 不保存哪些資料。
2. 哪些 key 會被 redacted。
3. 如何除錯而不暴露個資。
4. Care Alert / memory / transcript 的 logging 原則。
5. 第三方錯誤 payload 的處理原則。

---

## 11. 限制

本 CR 不得：

1. 破壞授權鏈 CR-0039 至 CR-0045。
2. 修改 Realtime WebRTC 主流程。
3. 修改 Memory API 契約。
4. 修改 Care Alert 成功 response 契約。
5. 移除必要錯誤處理。
6. 為了安靜 log 而吞錯。
7. 在測試中硬編真 secret。
8. 讓 production log 印出完整對話、token、email、phone。
9. 大量重寫 unrelated code。
10. 偽造已完成法律文件。

---

## 12. 驗收標準

完成後必須符合：

1. redaction utility 已建立並有測試。
2. backend 高風險 log 已 redacted。
3. Flutter 明顯高風險 log 已 debug-only 或 redacted。
4. caregiver_web 不輸出 token / sensitive payload。
5. production config summary 不洩漏 secret。
6. backend tests 全綠。
7. Flutter analyze / 相關測試通過。
8. caregiver_web tests 通過。
9. CHANGE_REVIEW 已更新。
10. 無 hardcoded secret / fake production log。

---

## 13. 完成回報格式

請用以下格式回報：

```md
## CR-0047 完成回報

### 1. 本次目標
-

### 2. 修改檔案
-

### 3. Log 盤點結果
-

### 4. Redaction utility
-

### 5. Backend log 修正
-

### 6. Flutter log 修正
-

### 7. caregiver_web log 修正
-

### 8. 測試結果
-

### 9. 正式版風險檢查
- production log 是否仍可能輸出 token：
- 是否仍可能輸出完整 email / phone：
- 是否仍可能輸出完整 transcript：
- 是否仍可能輸出完整 Care Alert summary：
- 是否仍可能輸出 secret：
- 是否吞錯：

### 10. 殘留風險
-

### 11. 下一個建議 CR
-
```
