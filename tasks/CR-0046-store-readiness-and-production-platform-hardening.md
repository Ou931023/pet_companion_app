# CR-0046 — Store Readiness and Production Platform Hardening

## 1. 任務定位

本任務接續 CR-0033 至 CR-0045。

目前已完成：

- CR-0033：Production Audit
- CR-0034：Production Environment and Config
- CR-0039：Backend Authorization Boundary Part 1
- CR-0040：Resident-Caregiver Authorization Model
- CR-0041：Caregiver Scoped Admin Session Backend
- CR-0042：Caregiver Web Auth UI / Role Header / 401-403 / Empty State
- CR-0043：Caregiver Account and Resident-Caregiver Link Provisioning Backend
- CR-0044：Caregiver Web Provisioning UI
- CR-0045：Care Alert Notify Caller Authentication

授權鏈已在 code 層閉合，P0-1 / P0-2 已解除。

本 CR 目標是轉向正式上架前的平台設定與 production hardening，處理 iOS / Android / web / 文件 / 隱私 / 商店 metadata 的阻擋項。

---

## 2. 本次目標

完成第一輪雙平台上架 readiness 與 production platform hardening。

重點處理：

1. iOS ATS / localhost / arbitrary loads 檢查。
2. Android applicationId / app label / permission 檢查。
3. App display name / brand consistency。
4. App icon / launch screen / adaptive icon 檢查。
5. production API base URL 與 HTTPS 策略。
6. release build config 檢查。
7. Store metadata 草稿。
8. Privacy / data safety 文件草稿。
9. 上架前 blocker 清單。
10. 不改動授權鏈核心邏輯。

---

## 3. 必讀文件

請先閱讀：

- `CLAUDE.md`
- `docs/PRODUCTION_AUDIT_CR0033.md`
- `docs/CHANGE_REVIEW.md`
- `.env.example`
- `docs/ENVIRONMENT_SETUP.md`
- `ios/Runner/Info.plist`
- `ios/Runner.xcodeproj`
- `android/app/build.gradle` 或 `android/app/build.gradle.kts`
- `android/app/src/main/AndroidManifest.xml`
- `lib/config/app_config.dart`
- `caregiver_web/config.example.js`
- `pubspec.yaml`

---

## 4. 先盤點

修改前請先盤點：

1. iOS Bundle ID。
2. iOS display name。
3. iOS ATS 設定。
4. iOS permission descriptions。
5. Android applicationId。
6. Android app label。
7. Android permissions。
8. Android targetSdk / minSdk。
9. Android adaptive icon。
10. Flutter app icon / assets。
11. API base URL 是否仍含 localhost。
12. production 是否允許 http。
13. caregiver_web 是否仍預設 localhost。
14. docs 是否已有 privacy policy / terms / data safety。
15. release build 是否可執行或有哪些 blocker。

---

## 5. iOS 需求

### 5.1 ATS / HTTPS

檢查並處理：

- `NSAllowsArbitraryLoads`
- localhost exception
- http exception
- production 是否強制 HTTPS

要求：

1. production 不可全域允許 arbitrary loads。
2. development 可保留 localhost exception，但需明確隔離。
3. 若目前無法自動依 flavor 切換，請文件化並建立 TODO/blocker。
4. 不可讓正式 App 預設打 localhost。

### 5.2 Permission Description

確認 Info.plist 有清楚、長者友善、App Store 可接受的權限說明。

至少檢查：

- `NSMicrophoneUsageDescription`
- `NSCameraUsageDescription` if used
- `NSPhotoLibraryUsageDescription` if used
- notification usage if applicable

文案不可出現：

- demo
- test
- debug
- mock
- 工程術語

### 5.3 Branding

檢查：

- display name
- bundle id
- app icon
- launch screen

若素材尚未完整，建立明確 blocker，不要用假完成。

---

## 6. Android 需求

### 6.1 applicationId / label

檢查並正式化：

- `applicationId`
- `android:label`
- app name resources

不可保留：

- demo
- test
- default Flutter name
- `com.example.*`

### 6.2 Permissions

檢查：

- RECORD_AUDIO
- INTERNET
- POST_NOTIFICATIONS for Android 13+
- camera/photo permissions if used

要求：

1. 權限需與實際功能一致。
2. 不需要的權限不要保留。
3. 需文件化 Google Play Data Safety 對應。

### 6.3 Release Build

檢查：

- release signing placeholder / 文件
- ProGuard / R8 if applicable
- targetSdk
- adaptive icon
- launcher icon

不得提交實際 keystore。

---

## 7. Production API Base URL

檢查 Flutter 與 caregiver_web 的 API base URL。

要求：

1. production 不可預設 localhost。
2. production 應要求 HTTPS。
3. staging / development 可配置不同 URL。
4. 缺 production URL 時應 fail-fast 或顯示部署 blocker，不可 silent fallback。
5. 文件化設定方式。

---

## 8. Store Metadata 文件

請建立或更新：

- `docs/STORE_RELEASE_CHECKLIST.md`
- `docs/APP_STORE_METADATA.md`
- `docs/GOOGLE_PLAY_DATA_SAFETY.md`

內容至少包含：

### 8.1 App Store Metadata

- App name
- Subtitle
- Short description
- Full description
- Keywords
- Category
- Age rating 建議
- Privacy policy URL placeholder
- Support URL placeholder
- Review notes draft
- Demo/test account strategy if needed

### 8.2 Google Play Data Safety

列出資料類型：

- account info
- contact info if used
- voice/audio
- messages/conversation
- health-related inferred care signals
- app activity
- device identifiers if used
- notifications

並說明：

- collected or not
- shared or not
- purpose
- encrypted in transit
- deletion request support

### 8.3 Release Checklist

包含：

- iOS build
- Android build
- privacy policy
- terms
- support contact
- app icon
- screenshots
- production backend URL
- Firebase config
- PostgreSQL migration
- Telegram token
- OpenAI key
- no demo/mock/debug
- no hardcoded secrets
- auth smoke test
- Realtime smoke test
- Care Alert smoke test

---

## 9. 測試與指令

請盡可能執行：

Flutter：

```bash
flutter analyze
flutter test
flutter build apk --release
flutter build ios --release --no-codesign
```

Backend 若未改可不完整跑，但如有 config 變更，請跑：

```bash
npm run check
npm test
```

caregiver_web 若未改可不完整跑，但如有 config/docs 以外變更，請跑：

```bash
node --test *.test.js
```

如果 release build 失敗，不要假裝通過，請記錄 blocker 與錯誤摘要。

---

## 10. 文件需求

請更新：

- `docs/CHANGE_REVIEW.md`
- `docs/ENVIRONMENT_SETUP.md` if needed
- `.env.example` if needed
- `caregiver_web/README.md` if needed

請新增或更新：

- `docs/STORE_RELEASE_CHECKLIST.md`
- `docs/APP_STORE_METADATA.md`
- `docs/GOOGLE_PLAY_DATA_SAFETY.md`

---

## 11. 限制

本 CR 不得：

1. 破壞 CR-0039 至 CR-0045 的授權鏈。
2. 修改 Realtime WebRTC 主流程。
3. 修改 Memory API。
4. 修改 Care Alert notify auth。
5. 使用 hardcoded production secret。
6. 提交 keystore / signing key。
7. 偽造已部署的 privacy policy URL。
8. 偽造 App Store / Google Play 已完成設定。
9. 讓 production 預設連 localhost。
10. 為了 release build 暫時關掉必要權限或安全檢查。

---

## 12. 驗收標準

完成後必須符合：

1. iOS ATS / permission / branding 已盤點並修正或列 blocker。
2. Android applicationId / permission / icon / label 已盤點並修正或列 blocker。
3. production API base URL 不再 silent fallback 到 localhost。
4. store metadata docs 已建立。
5. data safety docs 已建立。
6. release checklist 已建立。
7. flutter analyze 通過，或明確記錄 blocker。
8. release build 嘗試執行，成功或明確記錄 blocker。
9. CHANGE_REVIEW 已更新。
10. 無 hardcoded secret / fake production setting。

---

## 13. 完成回報格式

請用以下格式回報：

```md
## CR-0046 完成回報

### 1. 本次目標
-

### 2. 修改檔案
-

### 3. iOS 檢查與改動
-

### 4. Android 檢查與改動
-

### 5. Production API / HTTPS 檢查
-

### 6. Store metadata / Data safety 文件
-

### 7. 測試與 build 結果
-

### 8. 正式版風險檢查
- production 是否仍預設 localhost：
- iOS 是否仍全域允許 arbitrary loads：
- Android 是否仍使用 com.example：
- 是否有 demo/test/mock 字樣：
- 是否有 hardcoded secret：
- 是否提交 signing key：
- 是否破壞授權鏈：

### 9. Release blockers
-

### 10. 下一個建議 CR
-
```
