# RELEASE_SIGNING — iOS / Android 正式簽章 Runbook

> 建立：CR-0058。更新：CR-0101B release signing runbook 可執行化。狀態：**repo 接線完成 + owner signing action 待完成**；本檔只說明「需要做什麼、放哪裡」，**不含任何金鑰 / 密碼 / 憑證**。
> 🔴 紅線：**禁止**將 keystore / signing key / `.jks` / `.keystore` / `.p12` / Apple `.cer` `.p8` `.mobileprovision` / 任何密碼或 service account 提交進 git。這些一律走部署環境 / secret manager / 各平台後台。

對照：`docs/STORE_SUBMISSION_RUNBOOK.md`、`docs/STORE_RELEASE_CHECKLIST.md`、`docs/ENVIRONMENT_SETUP.md`、`docs/APP_STORE_METADATA.md`。

---

## 1. 現況

- Android `android/app/build.gradle.kts`：CR-0096S Batch 4 已改為讀取 `android/key.properties` 的 release signing config。真正跑 release / appbundle 時若缺正式 keystore 設定會 fail-fast，不再用 debug key 假裝可上架。
- iOS：`project.pbxproj` 已有 `DEVELOPMENT_TEAM` 與 Automatic signing metadata；App Store 送審仍需 Apple Developer 帳號、App Store Connect app record、distribution signing / provisioning 於 Xcode archive 驗證。
- 兩者皆 **owner action**（需 Apple Developer 帳號、Google Play Console 帳號、產生 keystore）。
- 可自動檢查項目：`scripts/check_release_signing_readiness.sh`。

```bash
bash scripts/check_release_signing_readiness.sh
flutter test test/config/android_release_signing_test.dart test/config/store_readiness_test.dart
```

---

## 2. Android upload keystore（owner action）

### 2.1 產生 upload keystore

在 owner 的安全本機位置產生正式 upload keystore（**本機產生、不進 git**）：

   ```bash
   keytool -genkey -v -keystore <你的安全路徑>/upload-keystore.jks \
     -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```

建議：
- `<你的安全路徑>` 放在 repo 外，例如 macOS Keychain 管理的資料夾或團隊 secret storage 匯出的本機檔。
- 密碼使用密碼管理器保存，勿貼在 issue、PR、README、聊天紀錄或 screenshot。
- 啟用 Google Play App Signing；AAB 用 upload key 簽，Google 保管 app signing key。

### 2.2 建立本機 `android/key.properties`

建立 `android/key.properties`（已被 `.gitignore` 忽略，**不提交**），內容只在本機 / CI secret：

   ```
   storePassword=<不入 git>
   keyPassword=<不入 git>
   keyAlias=upload
   storeFile=<keystore 絕對路徑，不入 git>
   ```

`build.gradle.kts` 已讀 `key.properties` 動態組 `signingConfigs.release`，`buildTypes.release.signingConfig` 指向它。此程式改動可進 git（**只讀外部檔，不含值**）。

### 2.3 Android release build

```bash
flutter build appbundle --release \
  --dart-define=APP_ENV=production \
  --dart-define=API_BASE_URL=https://你的正式後端網域 \
  --dart-define=PRIVACY_POLICY_URL=https://ou931023.github.io/pet_companion_app/privacy.html \
  --dart-define=TERMS_OF_SERVICE_URL=https://ou931023.github.io/pet_companion_app/terms.html \
  --dart-define=SUPPORT_URL=https://ou931023.github.io/pet_companion_app/support.html \
  --dart-define=CONTACT_EMAIL=aicompanion.support@gmail.com
```

驗收：
- Build 產出 AAB。
- `API_BASE_URL` 是 production HTTPS，不是 localhost / LAN IP / ngrok。
- 缺 `android/key.properties` 或缺任一 key 時 build fail-fast。
- Play Console 建 app 時啟用 Play App Signing，並保存 upload key 指紋。

> ⛔ owner blocker：keystore 產生 + Play Console 帳號 + App Signing 啟用決策。CI 若簽章，金鑰走 CI secret（如 GitHub Actions encrypted secrets / base64），**不進 repo**。

---

## 3. iOS signing（owner action）

### 3.1 Apple / Xcode 前置

1. 需要 **Apple Developer Program** 會員資格。
2. App Store Connect 建立 App record，Bundle ID 使用 `tw.edu.ncyu.im.aicompanion`。
3. Xcode 開啟 `ios/Runner.xcworkspace`。
4. Runner target → Signing & Capabilities：
   - Team：選正式 Apple Developer team。
   - Bundle Identifier：確認 `tw.edu.ncyu.im.aicompanion`。
   - Signing：建議先用 Automatically manage signing。
5. RunnerTests target 若 Xcode 要求，也保持同 team。

### 3.2 iOS archive / TestFlight

```bash
flutter build ipa --release \
  --dart-define=APP_ENV=production \
  --dart-define=API_BASE_URL=https://你的正式後端網域 \
  --dart-define=PRIVACY_POLICY_URL=https://ou931023.github.io/pet_companion_app/privacy.html \
  --dart-define=TERMS_OF_SERVICE_URL=https://ou931023.github.io/pet_companion_app/terms.html \
  --dart-define=SUPPORT_URL=https://ou931023.github.io/pet_companion_app/support.html \
  --dart-define=CONTACT_EMAIL=aicompanion.support@gmail.com
```

若 CLI archive 卡簽章，改用 Xcode：
1. Product → Archive。
2. Organizer → Distribute App。
3. 選 App Store Connect → Upload。
4. 上傳後到 TestFlight 跑內測 smoke。

驗收：
- Archive 使用 App Store distribution signing / provisioning。
- App Store Connect 看到 build，且 Bundle ID / version / build number 正確。
- TestFlight 安裝後用 production HTTPS 後端，並跑 `docs/STORE_SUBMISSION_RUNBOOK.md` §4–§5。

若用第三方登入（Google）→ Apple 規範要求併提供 **Sign in with Apple**（見 `APP_STORE_METADATA §2`）。本版 production 已隱藏第三方登入，只保留 Email login/register。

> ⛔ owner blocker：Apple Developer 帳號 + App Store Connect app record + iOS distribution signing。

---

## 4. CI secrets 建議命名（不可提交值）

若未來要用 GitHub Actions 或其他 CI 打 release，建議 secret names：

Android：
- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_KEY_ALIAS`

iOS：
- `APP_STORE_CONNECT_API_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_API_KEY_P8`
- `IOS_DISTRIBUTION_CERTIFICATE_BASE64`
- `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD`
- `IOS_PROVISIONING_PROFILE_BASE64`

本 repo 目前不新增 CI release workflow，避免在帳號與 secret 尚未準備好前做出假自動化。

---

## 5. .gitignore 核對（送審前）

確認下列已被忽略、且歷史未誤提交（CR-0058 未變更 .gitignore，僅提醒核對）：

- `**/key.properties`、`**/*.jks`、`**/*.keystore`、`**/*.p12`、`**/*.p8`、`**/*.cer`、`**/*.mobileprovision`
- `ios/Runner/GoogleService-Info.plist`、`android/app/google-services.json`（Firebase 設定，含專案識別，不進 git）
- `.env*`（既有規範）

> 若任一已誤入版控，需 owner 評估輪替金鑰 + 清理歷史（超出本 CR）。

---

## 6. Owner action 摘要（blocker）

- [ ] Apple Developer Program 帳號 + iOS 憑證 / provisioning。
- [ ] Google Play Console 帳號 + Android upload keystore（本機產生、不進 git）+ App Signing 啟用。
- [x] Bundle ID / applicationId 正式化：`tw.edu.ncyu.im.aicompanion`（不可逆，見 `APP_STORE_METADATA §7`）。
- [x] `build.gradle.kts` release signingConfig 由 debug key 換成正式 keystore（讀 `key.properties`）。
- [ ] 本機 / CI 提供實際 `android/key.properties` 與 upload keystore（不得提交）。
- [x] 第三方登入策略：本版 production 隱藏 Google / Apple，只保留 Email login/register；Sign in with Apple 完成前不得開啟第三方登入送審。

---

## 7. No-Go 條件

以下任一項成立，禁止送 App Store / Google Play：

- Android release 使用 debug signing。
- `android/key.properties`、keystore、Apple 憑證、`.p8`、`.mobileprovision` 或密碼進 git。
- `API_BASE_URL` 不是正式 HTTPS。
- App Store Connect / Play Console 裡的 Bundle ID / applicationId 與 repo 不一致。
- TestFlight / Internal testing 未跑 Realtime 語音、Care Alert、usage tracking、管理者 analytics smoke。
