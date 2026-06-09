# CR-0054 — HTTPS Deployment and ATS / Cleartext Transport Security Hardening

## 1. 任務定位

本任務接續 CR-0053。

CR-0053 已完成：

- 建立 `docs/E2E_SMOKE_TEST_PLAN.md`
- 建立 `docs/E2E_SMOKE_TEST_REPORT.md`
- 明確標示 Run #0 = NOT EXECUTED
- 誠實列出真 Firebase / 真 PostgreSQL / 真 OpenAI / 真 Telegram / 真裝置尚未執行
- 確認 iOS `NSAllowsArbitraryLoads=true` 與 Android `usesCleartextTraffic=true` 仍是正式上架 blocker

目前正式上架 blocker：

> Production App 不應全域允許 iOS arbitrary loads，也不應在 Android production 允許 cleartext traffic。  
> 但收斂前必須先確認正式 HTTPS 後端、Realtime/WebRTC、API、caregiver_web、CORS 都可正常運作，並保留 rollback 路徑。

本 CR 目標是完成 HTTPS deployment readiness 與 ATS / Android cleartext 收斂方案，並在可驗證時套用；若環境不足，需產出可執行的 smoke-gated patch 與 blocker 報告，不可盲套。

---

## 2. 本次目標

完成正式傳輸安全收斂：

1. 確認 production backend 使用 HTTPS 網域。
2. 確認 Flutter production API base URL 指向 HTTPS。
3. 確認 caregiver_web production 使用 HTTPS / 同源 `/api` 或正式 API URL。
4. 收斂 iOS ATS：
   - production 不全域允許 `NSAllowsArbitraryLoads=true`
   - development 可保留 localhost / LAN exception
5. 收斂 Android cleartext：
   - production 不允許 `usesCleartextTraffic=true`
   - development 可保留 LAN / localhost exception
6. 驗證 Realtime / WebRTC / Care Alert / Chat / caregiver_web 在 HTTPS 下正常。
7. 更新 Store Release Checklist 與 E2E Smoke Report。
8. 不破壞 CR-0039～CR-0053 主流程。

---

## 3. 必讀文件

請先閱讀：

- `CLAUDE.md`
- `docs/CHANGE_REVIEW.md`
- `docs/STORE_RELEASE_CHECKLIST.md`
- `docs/E2E_SMOKE_TEST_PLAN.md`
- `docs/E2E_SMOKE_TEST_REPORT.md`
- `docs/ENVIRONMENT_SETUP.md`
- `docs/APP_STORE_METADATA.md`
- `docs/GOOGLE_PLAY_DATA_SAFETY.md`
- `ios/Runner/Info.plist`
- `android/app/src/main/AndroidManifest.xml`
- Android network security config if exists
- `lib/config/app_config.dart`
- `caregiver_web/config.example.js`
- backend CORS/env config

---

## 4. 先盤點

修改前請先盤點：

1. production backend domain 是否存在。
2. production backend 是否有有效 TLS certificate。
3. production API base URL 是否已設定。
4. caregiver_web 正式網域是否存在。
5. backend CORS 是否允許 caregiver_web 正式網域。
6. iOS `Info.plist` 目前 ATS 設定。
7. Android Manifest 目前 `usesCleartextTraffic` 設定。
8. Android network security config 是否存在。
9. Flutter flavor 是否可分 development / production。
10. iOS 是否有 scheme / xcconfig 可分 dev/prod。
11. Android 是否有 productFlavors 可分 dev/prod。
12. 目前本機 / 區網開發是否仍需要 HTTP。
13. Realtime/WebRTC 是否依賴 HTTP-only endpoint。
14. 是否有 rollback patch。

---

## 5. 執行模式

本 CR 允許兩種結果。

### 5.1 Execute Mode

若正式 HTTPS 後端與真機可用：

請套用 ATS / cleartext 收斂，並執行 smoke：

- Flutter production app
- iOS 真機
- Android 真機
- Realtime 語音
- typed chat
- Care Alert medium/high/urgent
- Telegram high/urgent
- caregiver_web scoped dashboard

### 5.2 Patch-ready Plan Mode

若正式 HTTPS 後端或真機不可用：

請不要盲套。

請產出：

- 可套用 patch 設計
- 需要 owner 補的環境項
- smoke checklist
- rollback 步驟
- release blocker 狀態

---

## 6. iOS ATS 需求

### 6.1 Production

production 不應有：

```xml
<key>NSAllowsArbitraryLoads</key>
<true/>
```

要求：

1. production 全域 arbitrary loads 關閉。
2. 若需要特定 domain exception，必須限定正式 domain 並說明理由。
3. 不可為了方便保留全域 allow。
4. 權限文案不得出現 demo/test/mock/debug。

### 6.2 Development

development 可保留：

- localhost
- 127.0.0.1
- LAN IP
- local backend HTTP

但需明確與 production 隔離。

### 6.3 Rollback

若收斂後 Realtime / API 壞掉，需能 rollback，並記錄原因。

---

## 7. Android Cleartext 需求

### 7.1 Production

production 不應有：

```xml
android:usesCleartextTraffic="true"
```

要求：

1. production 禁止 cleartext。
2. network security config 不應允許所有 domain cleartext。
3. 若 development 需要 HTTP，請透過 dev flavor / debug manifest 控制。
4. 不可提交 keystore。

### 7.2 Development

development 可允許：

- localhost
- 10.0.2.2
- LAN IP

但不得影響 production。

---

## 8. Backend / CORS / HTTPS 需求

請確認：

1. production backend 使用 HTTPS。
2. CORS 僅允許正式 caregiver_web domain / app 必要 origin。
3. 不可 allow-all。
4. production env 缺 `CORS_ALLOWED_ORIGINS` 需 fail-fast。
5. `/api/realtime/call` 在 HTTPS 下正常。
6. `/api/companion/chat` 在 HTTPS 下正常。
7. `/api/care-alerts/notify` 在 HTTPS 下正常。
8. caregiver_web 在正式 origin 下可呼叫 API。

---

## 9. Smoke 測試需求

若 Execute Mode，至少測：

### 9.1 iOS

1. App launch。
2. Login。
3. Realtime 語音。
4. typed chat。
5. voice medium Care Alert persist。
6. voice high/urgent Telegram。
7. typed medium Care Alert persist。
8. typed high/urgent Telegram。
9. logout。
10. logs 無 sensitive data。

### 9.2 Android

同 iOS。

### 9.3 caregiver_web

1. super_admin login。
2. caregiver provisioning。
3. resident link。
4. caregiver scoped login。
5. alert list / detail / status update。
6. 401 / 403 / empty state。

---

## 10. 文件需求

請更新：

- `docs/CHANGE_REVIEW.md`
- `docs/STORE_RELEASE_CHECKLIST.md`
- `docs/E2E_SMOKE_TEST_REPORT.md`
- `docs/ENVIRONMENT_SETUP.md`
- `docs/APP_STORE_METADATA.md` if needed
- `docs/GOOGLE_PLAY_DATA_SAFETY.md` if needed

如需要，新增：

- `docs/TRANSPORT_SECURITY.md`

文件需說明：

1. production HTTPS requirement。
2. iOS ATS policy。
3. Android cleartext policy。
4. dev/prod 差異。
5. smoke checklist。
6. rollback steps。
7. release blocker 狀態。

---

## 11. 限制

本 CR 不得：

1. 盲目關閉 ATS / cleartext 而不驗證。
2. 假裝 smoke 通過。
3. 為了通過 smoke 關閉 auth。
4. 為了通過 smoke 啟用 mock。
5. 提交 `.env`。
6. 提交 signing key / keystore。
7. 提交 Firebase service account。
8. 在文件中貼 secret / token / chat id。
9. 破壞 Realtime WebRTC。
10. 破壞 Care Alert / Telegram。
11. 讓 production fallback localhost。
12. 讓 production CORS allow-all。

---

## 12. 驗收標準

完成後需符合以下其中一種。

### 12.1 Execute Mode 完成

1. iOS production ATS 已收斂。
2. Android production cleartext 已收斂。
3. production HTTPS backend smoke 通過。
4. iOS Realtime smoke 通過。
5. Android Realtime smoke 通過。
6. Care Alert medium/high/urgent smoke 通過。
7. caregiver_web scoped smoke 通過。
8. logs 無 sensitive data。
9. rollback 不需啟用。
10. CHANGE_REVIEW / STORE_RELEASE_CHECKLIST 已更新。

### 12.2 Patch-ready Plan Mode 完成

1. 明確列出不能套用原因。
2. 提供可套用 patch 方案。
3. 提供 smoke checklist。
4. 提供 rollback 步驟。
5. release blocker 清楚標示。
6. 未假裝通過。

---

## 13. 完成回報格式

請用以下格式回報：

```md
## CR-0054 完成回報

### 1. 本次目標
-

### 2. 執行模式
- Execute / Patch-ready Plan

### 3. 修改檔案
-

### 4. HTTPS / CORS 盤點
-

### 5. iOS ATS 結果
-

### 6. Android cleartext 結果
-

### 7. Smoke 結果
-

### 8. Rollback 設計
-

### 9. 文件更新
-

### 10. 正式版風險檢查
- production 是否仍允許 arbitrary loads：
- production 是否仍允許 cleartext：
- production 是否仍指向 localhost：
- CORS 是否仍 allow-all：
- 是否破壞 Realtime：
- 是否破壞 Care Alert：
- 是否假裝通過：

### 11. Release blockers
-

### 12. 下一個建議 CR
-
```
