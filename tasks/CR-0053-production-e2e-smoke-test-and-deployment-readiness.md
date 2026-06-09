# CR-0053 — Production End-to-End Smoke Test and Deployment Readiness

## 1. 任務定位

本任務接續 CR-0052。

目前已完成：

- CR-0039～CR-0045：授權鏈閉合
- CR-0046：Store readiness 第一輪
- CR-0047：Production logging redaction
- CR-0048～CR-0049：mock service production 隔離與 AI/STT 正式化
- CR-0050：companion chat persona 正式化
- CR-0051：typed chat Care Alert integration
- CR-0052：voice medium Care Alert persist gate alignment

目前共同殘留正式版風險：

> 多數驗證仍以 mock pg / stub Firebase / 測試 spy 為主。  
> 正式上架前必須用真 Firebase、真 PostgreSQL、真 OpenAI key、真 Telegram Bot、真裝置跑最小端到端 smoke。

本 CR 目標是建立並執行第一輪 production-like E2E smoke test，確認正式系統閉環可用，並產出 release blocker 報告。

---

## 2. 本次目標

完成真環境端到端 smoke 測試計畫與執行紀錄。

至少覆蓋：

1. Firebase 登入 / idToken。
2. PostgreSQL migration。
3. Realtime 語音連線。
4. 語音 medium → Care Alert persist，不推 Telegram。
5. 語音 high/urgent → Care Alert persist + Telegram。
6. 打字 medium → Care Alert persist。
7. 打字 high/urgent → Care Alert persist + Telegram。
8. caregiver_web super_admin 登入。
9. caregiver 帳號 provisioning。
10. resident-caregiver link provisioning。
11. caregiver scoped dashboard 只看授權住民。
12. /notify caller auth 真 Firebase 驗證。
13. production API base URL / HTTPS / CORS。
14. iOS ATS / Android cleartext smoke gate。
15. 無 mock / demo / dev panel / sensitive logs。

---

## 3. 必讀文件

請先閱讀：

- `CLAUDE.md`
- `docs/CHANGE_REVIEW.md`
- `docs/STORE_RELEASE_CHECKLIST.md`
- `docs/APP_STORE_METADATA.md`
- `docs/GOOGLE_PLAY_DATA_SAFETY.md`
- `docs/ENVIRONMENT_SETUP.md`
- `docs/AUTHORIZATION_MODEL.md`
- `docs/CAREGIVER_WEB_AUTH.md`
- `docs/CAREGIVER_PROVISIONING.md`
- `docs/TYPED_CHAT_CARE_ALERT_FLOW.md`
- `docs/VOICE_CARE_ALERT_FLOW.md`
- `docs/LOGGING_AND_REDACTION.md`
- `backend/stt_proxy/.env.example`
- `caregiver_web/config.example.js`
- Flutter production flavor / AppConfig 文件

---

## 4. 先盤點

修改或執行前請先盤點：

1. 目前真 Firebase 專案設定是否齊。
2. Firebase users 是否有 resident / caregiver / admin 測試帳號。
3. PostgreSQL 是否可連線。
4. migration 013 / 014 是否可在真 DB 冪等執行。
5. OpenAI API key 是否可用於 Realtime / STT / chat。
6. Telegram Bot token / chat id 是否可用。
7. production API base URL 是否為 HTTPS。
8. CORS 是否允許 caregiver_web 正式網域。
9. iOS ATS 是否仍全域 arbitrary loads。
10. Android cleartext 是否仍開啟。
11. Flutter production build 是否可跑。
12. Android release build 是否可跑。
13. iOS release build 是否可跑。
14. log 是否有可觀察但不洩密的輸出。
15. smoke 測試資料是否可清理。

---

## 5. Environment 要求

本 CR 可分成兩種模式：

### 5.1 Plan-only

如果目前缺真金鑰、真網域、真 DB 或真裝置，請不要假裝完成 smoke。

請產出：

- 可執行 smoke test checklist
- 缺口清單
- owner action item
- 阻擋原因
- 下一次執行步驟

### 5.2 Execute

如果環境齊全，請實際執行 smoke，記錄：

- 時間
- 環境
- build type
- device
- backend commit
- app commit
- pass/fail
- failure log 摘要，不含 secret
- 截圖需求 if applicable

---

## 6. Backend Smoke

請確認：

1. `APP_ENV=production` 或 production-like staging。
2. 缺必要 env 會 fail-fast。
3. DATABASE_URL 真連線成功。
4. migrations 可執行。
5. production 不啟用 JSON fallback。
6. production 不啟用 mock auth。
7. `/api/health` 或等價 health check 正常。
8. `/api/realtime/call` 可取得正式 session。
9. `/api/companion/chat` 需 auth 且可回覆。
10. `/api/care-alerts/notify` 需 auth 且可建立 alert。
11. high/urgent Telegram 可送達。
12. medium 不推 Telegram。
13. logs 不含 token / email /完整對話。

---

## 7. Flutter App Smoke

請確認：

1. production flavor 啟動。
2. 無 debug banner。
3. 無 demo login。
4. 無 dev panel。
5. 無 mock STT / mock AI。
6. 登入成功。
7. 取得 Firebase idToken。
8. Realtime 語音連線成功。
9. 語音 medium 可建立 Care Alert。
10. 語音 high/urgent 可通知。
11. 打字 medium 可建立 Care Alert。
12. 打字 high/urgent 可通知。
13. chat 失敗時白話錯誤，不 fallback mock。
14. 設定頁登出正常。
15. 記憶管理不跨帳號。
16. release log 不含 token /完整 transcript。

---

## 8. caregiver_web Smoke

請確認：

1. super_admin 登入。
2. 建立 caregiver。
3. 綁定 Firebase uid。
4. 建立 resident-caregiver link。
5. caregiver token 登入。
6. caregiver 只看到授權住民。
7. caregiver 看不到未授權住民。
8. caregiver 不能進 provisioning UI。
9. 401 / 403 / empty state 正常。
10. alert 狀態更新正常。
11. daily-care-tasks scoped 正常。
12. logs 不含 token。

---

## 9. ATS / Cleartext Smoke Gate

此段對應 CR-0046 B3。

請在真裝置確認：

1. iOS 若收斂 `NSAllowsArbitraryLoads=false`，Realtime / API / WebRTC 是否仍正常。
2. iOS 是否仍需 localhost 或區網 http exception。
3. Android 若收斂 cleartext，Realtime / API 是否正常。
4. 若正式 backend 已 HTTPS，應收斂所有 production cleartext。
5. 若尚未 HTTPS，列為 release blocker，不可假裝合規。

若套用 ATS / cleartext 改動，必須能 rollback。

---

## 10. Test Data Cleanup

請建立 smoke 測試資料清理策略：

1. 測試 resident。
2. 測試 caregiver。
3. resident-caregiver links。
4. Care Alerts。
5. memories。
6. notification logs。
7. Telegram 測試訊息。
8. audit logs 是否保留或標記。

不可直接刪除正式使用者資料。

---

## 11. 文件需求

請新增：

- `docs/E2E_SMOKE_TEST_PLAN.md`
- `docs/E2E_SMOKE_TEST_REPORT.md`

請更新：

- `docs/CHANGE_REVIEW.md`
- `docs/STORE_RELEASE_CHECKLIST.md`
- `docs/ENVIRONMENT_SETUP.md`
- `docs/GOOGLE_PLAY_DATA_SAFETY.md` if findings affect data safety

Smoke report 至少包含：

1. 測試日期。
2. 測試 commit。
3. 測試環境。
4. 測試帳號類型。
5. 測試裝置。
6. 測試項目 pass/fail。
7. 失敗摘要。
8. release blockers。
9. next action。
10. 不含 secret 的 log 摘要。

---

## 12. 限制

本 CR 不得：

1. 假裝已跑真環境 smoke。
2. 在文件寫假 URL / 假金鑰 / 假通過。
3. 提交 `.env`。
4. 提交 Firebase service account。
5. 提交 signing key / keystore。
6. 在報告中貼 token、chat id、完整對話、完整 email。
7. 為了通過 smoke 關閉 auth。
8. 為了通過 smoke 啟用 mock。
9. 破壞 CR-0039～CR-0052 主流程。
10. 對正式資料庫做不可逆測試資料污染。

---

## 13. 驗收標準

完成後必須符合以下其中一種：

### 13.1 Plan-only 完成

若環境不足：

1. E2E_SMOKE_TEST_PLAN 已建立。
2. E2E_SMOKE_TEST_REPORT 明確標示未執行原因。
3. 所有缺口列 owner blocker。
4. 下一次執行步驟具體。
5. 未假裝通過。

### 13.2 Execute 完成

若環境齊全：

1. Firebase idToken 真驗證通過。
2. PostgreSQL 真連線與 migration 通過。
3. Realtime 語音 smoke 通過。
4. typed chat Care Alert smoke 通過。
5. voice Care Alert smoke 通過。
6. Telegram high/urgent smoke 通過。
7. caregiver scoped dashboard smoke 通過。
8. medium 不推播已確認。
9. logs 無敏感資訊。
10. release blockers 已列出。
11. CHANGE_REVIEW 已更新。

---

## 14. 完成回報格式

請用以下格式回報：

```md
## CR-0053 完成回報

### 1. 本次目標
-

### 2. 執行模式
- Plan-only / Execute

### 3. 修改檔案
-

### 4. 環境盤點
-

### 5. Backend smoke 結果
-

### 6. Flutter app smoke 結果
-

### 7. caregiver_web smoke 結果
-

### 8. ATS / cleartext gate 結果
-

### 9. Test data cleanup
-

### 10. 測試與 build 結果
-

### 11. 正式版風險檢查
- 是否真 Firebase：
- 是否真 PostgreSQL：
- 是否真 OpenAI：
- 是否真 Telegram：
- 是否仍啟用 mock：
- 是否有 sensitive log：
- 是否有 release blocker：

### 12. Release blockers
-

### 13. 下一個建議 CR
-
```
