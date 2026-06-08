# CR-0045 — Care Alert Notify Caller Authentication

## 1. 任務定位

本任務接續 CR-0039 至 CR-0044 的授權鏈。

目前已完成：

- admin / care-alert 管理 API 擋門
- resident-caregiver scope
- caregiver HTTP auth context
- caregiver_web role header / 401 / 403 / empty state
- caregiver 帳號與住民授權 provisioning
- caregiver_web provisioning UI

目前正式上架 blocker：

> `POST /api/care-alerts/notify` 是長者端 App 建立 Care Alert 的核心路徑，但目前仍未驗證 caller。  
> 雖然有 globalLimiter + cooldown 緩解洗版，但正式版不能允許未驗證端任意 POST 建立警示或觸發通知。

本 CR 目標是為 `/api/care-alerts/notify` 補上長者端 caller 驗證，同時不破壞長者端建立 Care Alert 的核心流程。

---

## 2. 本次目標

完成 `/api/care-alerts/notify` caller 驗證與最小授權檢查。

完成後應達成：

1. 長者端 App 必須帶有效 session / idToken 才能呼叫 `/notify`。
2. caller 只能為自己或被授權的 resident 建立 Care Alert。
3. 未驗證 caller 不可建立 alert，不可觸發 Telegram。
4. invalid token 回 401。
5. token 有效但 resident 不符回 403。
6. 不破壞 Realtime / Memory / Care Alert 既有成功路徑。
7. high / urgent 通知規則與 cooldown 保持。
8. 補測試覆蓋未驗證、錯誤授權、正確授權、通知不被未授權觸發。

---

## 3. 必讀文件

請先閱讀：

- `CLAUDE.md`
- `docs/CHANGE_REVIEW.md`
- `docs/PRODUCTION_AUDIT_CR0033.md`
- `docs/AUTHORIZATION_MODEL.md`
- `backend/stt_proxy/server.js`
- `backend/stt_proxy/services/admin/adminAuthContext.js`
- `backend/stt_proxy/services/admin/authorizationService.js`
- `backend/stt_proxy/services/careAlertStoreService.js` 或相關 Care Alert store
- Flutter 長者端呼叫 `/api/care-alerts/notify` 的 service
- 相關 Care Alert 測試

---

## 4. 先盤點

修改前請盤點：

1. Flutter 長者端目前如何登入。
2. Flutter 長者端是否已有 Firebase idToken / session token 可取。
3. `/api/care-alerts/notify` 目前 request body。
4. request body 是否包含 elderId / residentId。
5. users 與 elders / residents 如何關聯。
6. backend 目前是否有可重用的 user session verifier。
7. adminAuthContext 是否可拆出共用 Firebase token verify。
8. Care Alert 建立後如何觸發 Telegram。
9. cooldown / rate limiter 目前位置。
10. 測試如何 mock idToken / users row / residents row。

---

## 5. 後端需求

### 5.1 Caller Auth Middleware

新增或重用 middleware：

- `resolveResidentCallerContext`
- `requireResidentCaller`
- 或符合現有命名風格的等價實作

caller context 建議包含：

```js
{
  userId: "string",
  firebaseUid: "string|null",
  residentId: "string|null",
  role: "resident" | "elder" | "caregiver" | "super_admin",
  isSuperAdmin: false
}
```

實際欄位請依現有 schema 調整，不要憑空假設。

### 5.2 Token 驗證

要求：

1. production 不可接受 fake token。
2. invalid token → 401。
3. 無 token → 401。
4. mock auth 僅限 development / test 且需受 env guard 控制。
5. 不可把 token 印到 log。

### 5.3 Resident Ownership / Authorization

`/notify` 必須驗證：

1. request body 的 residentId / elderId 屬於 caller。
2. 或 caller 具備合法建立該 resident alert 的授權。
3. super_admin 是否可建立 notify 需由架構裁決；若允許，必須明確測試。
4. caregiver 是否可代建 notify 需由架構裁決；若允許，必須走 resident_caregiver_links 檢查。
5. 未授權跨 resident → 403。

### 5.4 不破壞既有通知規則

保留：

- low 預設不推播或依現有規則
- medium 依現有規則
- high / urgent 通知
- cooldown
- notification log
- Care Alert store 契約

### 5.5 Error Response

錯誤回應不可暴露：

- token
- Firebase error detail
- stack trace
- 完整敏感對話
- Telegram token / chat id

---

## 6. Flutter 長者端需求

如果目前 Flutter 已有 token/session：

1. 呼叫 `/api/care-alerts/notify` 時帶 Authorization header。
2. token 取得失敗時，顯示長者友善錯誤。
3. 不在 log 顯示 token。
4. 不因 notify 失敗阻斷 Realtime 對話本身，但需記錄/提示合理狀態。
5. 未登入/未同意不可建立 Care Alert。

如果 Flutter 尚未有正式 token：

- 不要假裝已完成。
- 建立最小可行正式路徑或將 Flutter 部分標示為 blocker。
- production 不得用 hardcoded token。

---

## 7. 測試需求

### 7.1 Backend Tests

至少新增：

1. 無 Authorization header → 401。
2. invalid token → 401。
3. valid token 但無 users row → 401 或 403，依現有 auth 語意。
4. valid resident token 建立自己的 alert → 200。
5. resident A token 建立 resident B alert → 403。
6. 未授權請求不建立 Care Alert。
7. 未授權請求不觸發 Telegram。
8. high / urgent 授權請求仍觸發通知。
9. cooldown 仍生效。
10. low risk 授權請求仍依原規則不推播。
11. production 不接受 fake token。
12. response 不包含 token / sensitive error。

### 7.2 Flutter Tests

如有對應測試架構，至少新增或更新：

1. notify request 會帶 Authorization header。
2. token 取得失敗時不送出 notify。
3. notify 401 / 403 有可接受處理。
4. 不在 log 顯示 token。

---

## 8. 文件需求

請更新：

- `docs/CHANGE_REVIEW.md`
- `docs/AUTHORIZATION_MODEL.md`
- `.env.example`

如需要，新增：

- `docs/CARE_ALERT_NOTIFY_AUTH.md`

文件需說明：

1. `/notify` caller 驗證流程。
2. resident token 如何對應 resident。
3. caregiver / super_admin 是否可代建 alert。
4. 未授權時不建立 alert、不通知。
5. production 不接受 fake token。
6. Flutter 端需帶 Authorization header。

---

## 9. 限制

本 CR 不得：

1. 破壞長者端建立 Care Alert 的成功路徑。
2. 破壞 Realtime WebRTC。
3. 破壞 Memory API。
4. 移除 cooldown。
5. 讓未驗證 caller 建立 alert。
6. 用 hardcoded resident id。
7. 用 fake token 通過 production。
8. 在 log 顯示完整 token。
9. 把所有 authenticated user 都當成可為任意 resident 建立 alert。
10. 為通過測試而關閉通知。

---

## 10. 驗收標準

完成後必須符合：

1. `/api/care-alerts/notify` 無 token → 401。
2. invalid token → 401。
3. token 有效但 resident 不符 → 403。
4. token 有效且 resident 符合 → 原成功契約維持。
5. 未授權請求不建立 Care Alert。
6. 未授權請求不觸發 Telegram。
7. high / urgent 授權請求通知仍正常。
8. cooldown 仍正常。
9. backend tests 全綠。
10. Flutter tests 若改動則全綠。
11. CHANGE_REVIEW 已更新。
12. 無 hardcoded auth / fake token / sensitive log。

---

## 11. 完成回報格式

請用以下格式回報：

```md
## CR-0045 完成回報

### 1. 本次目標
-

### 2. 修改檔案
-

### 3. 後端 /notify auth 改動
-

### 4. Flutter 長者端改動
-

### 5. 通知與 cooldown 保持結果
-

### 6. 測試結果
-

### 7. 正式版風險檢查
- 無 token 是否仍可建立 alert：
- invalid token 是否仍可建立 alert：
- 跨 resident 是否被擋：
- 未授權是否會觸發 Telegram：
- 是否有 hardcoded resident：
- 是否有 fake token：
- 是否有 sensitive log：

### 8. 殘留風險
-

### 9. 下一個建議 CR
-
```
