# CR-0055 — Apply Transport Security Patch and Run Device Smoke

## 1. 任務定位

本任務接續 CR-0054。

CR-0054 已完成：

- 修復 production CORS allow-all 缺口
- CORS middleware 改用 `resolveCorsOrigins(process.env)`
- production fail-fast 與 CORS middleware 同源
- no-Origin 放行保留，不破壞 Flutter / Realtime broker
- 新增 `docs/TRANSPORT_SECURITY.md`
- 產出 iOS ATS 與 Android cleartext 收斂就緒 patch
- 因缺正式 HTTPS 後端與實體裝置，Batch 2 未盲套

目前 release blocker：

1. iOS 仍全域 `NSAllowsArbitraryLoads=true`
2. Android 仍允許 `usesCleartextTraffic=true`
3. 正式 HTTPS 後端網域尚未用實機驗證
4. iOS / Android Realtime + API + Care Alert 尚未在收斂後跑 smoke

本 CR 目標是在 owner 已準備好正式 HTTPS 後端與實體裝置後，套用 CR-0054 的 transport security patch，並執行 T1–T9 裝置 smoke。

---

## 2. 前置條件

執行本 CR 前，請確認 owner 已提供或完成：

1. 正式 HTTPS backend URL
2. 有效 TLS certificate
3. production/staging env 可連 PostgreSQL / Firebase / OpenAI / Telegram
4. iOS 實體裝置
5. Android 實體裝置或可代表上架環境的測試機
6. Flutter production API base URL 指向 HTTPS
7. caregiver_web production origin / CORS allowlist 已設定
8. 可 rollback 的 git 狀態

若以上未齊，請不要套用 patch，改成更新 blocker 報告。

---

## 3. 必讀文件

請先閱讀：

- `CLAUDE.md`
- `docs/TRANSPORT_SECURITY.md`
- `docs/E2E_SMOKE_TEST_PLAN.md`
- `docs/E2E_SMOKE_TEST_REPORT.md`
- `docs/STORE_RELEASE_CHECKLIST.md`
- `docs/ENVIRONMENT_SETUP.md`
- `docs/CHANGE_REVIEW.md`
- `ios/Runner/Info.plist`
- `android/app/src/main/AndroidManifest.xml`
- Android network security config if exists
- `lib/config/app_config.dart`
- backend CORS/env config

---

## 4. 本次目標

完成 transport security 實際落地：

1. iOS production 關閉全域 arbitrary loads。
2. Android production 關閉 cleartext。
3. development 保留 localhost / LAN 開發能力。
4. production 只走 HTTPS。
5. 真機驗證 Realtime / API / Care Alert。
6. 若 smoke 失敗，依 rollback 設計回復並記錄原因。
7. 不破壞 CR-0039～CR-0054 主流程。

---

## 5. iOS 改動需求

請依 `docs/TRANSPORT_SECURITY.md` 套用 iOS patch。

要求：

1. production 不可保留：
   ```xml
   <key>NSAllowsArbitraryLoads</key>
   <true/>
   ```
2. 若需要 local networking，只限 development 或清楚註明。
3. 不可為 production 全域開 HTTP。
4. 權限文案不可出現 demo/test/mock/debug。
5. 套用後需跑 iOS 真機 smoke。

---

## 6. Android 改動需求

請依 `docs/TRANSPORT_SECURITY.md` 套用 Android patch。

要求：

1. production 不可保留：
   ```xml
   android:usesCleartextTraffic="true"
   ```
2. development/debug 可用 network security config 允許 localhost、10.0.2.2、LAN IP if needed。
3. production network security config 不可 allow all cleartext。
4. 套用後需跑 Android 真機 smoke。

---

## 7. Smoke 測試項目

請至少執行 T1–T9。

### T1 App 啟動
- production flavor
- 無 debug banner
- 無 demo login
- 無 dev panel
- 無 mock STT / mock AI

### T2 Auth
- resident 登入
- Firebase idToken 取得成功
- token 不出現在 log

### T3 Realtime 語音
- `/api/realtime/call` HTTPS 成功
- WebRTC 語音連線成功
- 可聽到 AI 寵物回覆

### T4 Typed chat
- `/api/companion/chat` HTTPS 成功
- 回覆符合陪伴 persona
- 不 fallback mock

### T5 Voice Care Alert medium
- 語音 medium 建立 Care Alert
- 不推 Telegram
- 管理端可看到紀錄

### T6 Voice Care Alert high/urgent
- 語音 high/urgent 建立 Care Alert
- Telegram 收到通知
- 管理端可看到紀錄

### T7 Typed Care Alert
- 打字 medium 建立 Care Alert，不推 Telegram
- 打字 high/urgent 建立 Care Alert，推 Telegram

### T8 caregiver_web
- super_admin 登入
- caregiver provisioning
- resident-caregiver link
- caregiver scoped login
- 只看到授權住民
- 401/403/empty state 正常

### T9 Logs
- backend log 不含 token / email / 完整對話
- Flutter release log 不含 token / transcript
- caregiver_web console 不含 token

---

## 8. Rollback 規則

若以下任一項失敗，請 rollback platform patch，保留 CR-0054 CORS 修正：

1. iOS 無法連 HTTPS API
2. iOS Realtime/WebRTC 壞掉
3. Android 無法連 HTTPS API
4. Android Realtime/WebRTC 壞掉
5. Care Alert 不建立
6. Telegram high/urgent 不推
7. production 只能靠 HTTP 才能運作

Rollback 後需記錄：

- 哪一平台失敗
- 哪個測試項失敗
- 錯誤摘要，不含 secret
- 下一步 owner action

---

## 9. 測試與指令

請盡可能執行：

```bash
flutter analyze
flutter test
flutter build apk --release
flutter build ios --release --no-codesign
```

Backend 若有任何 config 或 env 文件以外改動：

```bash
npm run check
npm test
```

caregiver_web 若有改動：

```bash
node --test *.test.js
```

如果 build 或 smoke 無法執行，請明確記錄原因，不可假裝通過。

---

## 10. 文件需求

請更新：

- `docs/CHANGE_REVIEW.md`
- `docs/TRANSPORT_SECURITY.md`
- `docs/E2E_SMOKE_TEST_REPORT.md`
- `docs/STORE_RELEASE_CHECKLIST.md`
- `docs/ENVIRONMENT_SETUP.md`

Smoke report 需包含：

1. 測試日期
2. 測試 commit
3. backend URL 是否 HTTPS
4. iOS 裝置與版本
5. Android 裝置與版本
6. T1–T9 pass/fail
7. rollback 是否啟用
8. release blockers
9. 不含 secret 的 log 摘要

---

## 11. 限制

本 CR 不得：

1. 未有 HTTPS 後端就硬關所有 HTTP 並假裝成功。
2. 假裝 smoke 通過。
3. 為通過 smoke 關閉 auth。
4. 為通過 smoke 啟用 mock。
5. 提交 `.env`。
6. 提交 Firebase service account。
7. 提交 signing key / keystore。
8. 在文件貼 token、chat id、完整 email、完整對話。
9. 破壞 Realtime WebRTC。
10. 破壞 Care Alert / Telegram。
11. 讓 production fallback localhost。
12. 讓 production CORS allow-all。

---

## 12. 驗收標準

### 12.1 成功落地

完成後必須符合：

1. iOS production 不全域允許 arbitrary loads。
2. Android production 不允許 cleartext。
3. iOS T1–T9 smoke 通過或清楚列出非阻擋項。
4. Android T1–T9 smoke 通過或清楚列出非阻擋項。
5. Realtime 在 HTTPS 下正常。
6. Care Alert medium/high/urgent 行為正確。
7. caregiver_web scoped 行為正確。
8. logs 無敏感資訊。
9. rollback 不需啟用。
10. release checklist 更新。

### 12.2 未能落地

若環境仍不足：

1. 不套用 patch。
2. E2E report 明確標示未執行原因。
3. blocker 與 owner action 清楚。
4. 未假裝通過。

---

## 13. 完成回報格式

請用以下格式回報：

```md
## CR-0055 完成回報

### 1. 本次目標
-

### 2. 執行模式
- Execute / Blocked / Rollback

### 3. 修改檔案
-

### 4. iOS ATS 改動與結果
-

### 5. Android cleartext 改動與結果
-

### 6. T1–T9 smoke 結果
-

### 7. Rollback 結果
-

### 8. 測試與 build 結果
-

### 9. 文件更新
-

### 10. 正式版風險檢查
- iOS production 是否仍 arbitrary loads：
- Android production 是否仍 cleartext：
- production 是否仍可能連 localhost：
- CORS 是否仍 allow-all：
- Realtime 是否正常：
- Care Alert 是否正常：
- 是否啟用 mock：
- 是否有 sensitive log：
- 是否假裝通過：

### 11. Release blockers
-

### 12. 下一個建議 CR
-
```
