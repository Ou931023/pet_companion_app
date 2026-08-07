# RELEASE_SIGNING — iOS / Android 正式簽章準備

> 建立：CR-0058。狀態：**檢查清單 + owner action**；本檔只說明「需要做什麼、放哪裡」，**不含任何金鑰 / 密碼 / 憑證**。
> 🔴 紅線：**禁止**將 keystore / signing key / `.jks` / `.keystore` / `.p12` / Apple `.cer` `.p8` `.mobileprovision` / 任何密碼或 service account 提交進 git。這些一律走部署環境 / secret manager / 各平台後台。

對照：`docs/STORE_RELEASE_CHECKLIST.md`、`docs/ENVIRONMENT_SETUP.md`、`docs/APP_STORE_METADATA.md`。

---

## 1. 現況（CR-0058 盤點）

- Android `android/app/build.gradle.kts`：CR-0096S Batch 4 已改為讀取 `android/key.properties` 的 release signing config。真正跑 release / appbundle 時若缺正式 keystore 設定會 fail-fast，不再用 debug key 假裝可上架。
- iOS：未設定正式 signing（需 Apple Developer 帳號 + 憑證 / provisioning profile，於 Xcode / App Store Connect 設定）。
- 兩者皆 **owner action**（需 Apple Developer 帳號、Google Play Console 帳號、產生 keystore）。

---

## 2. Android keystore（owner action）

1. 產生正式 upload keystore（**本機產生、不進 git**）：
   ```bash
   keytool -genkey -v -keystore <你的安全路徑>/upload-keystore.jks \
     -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
2. 建立 `android/key.properties`（**加入 .gitignore，不提交**），內容只在本機 / CI secret：
   ```
   storePassword=<不入 git>
   keyPassword=<不入 git>
   keyAlias=upload
   storeFile=<keystore 絕對路徑，不入 git>
   ```
3. `build.gradle.kts` 已讀 `key.properties` 動態組 `signingConfigs.release`，`buildTypes.release.signingConfig` 指向它。此程式改動可進 git（**只讀外部檔，不含值**）。
4. **Google Play App Signing**：建議啟用——上傳 upload key 簽的 AAB，Google 用 app signing key 重簽。upload key 遺失可重設，app signing key 由 Google 保管。
5. 產物：`flutter build appbundle --release`（Play 偏好 AAB 而非 APK）。

> ⛔ owner blocker：keystore 產生 + Play Console 帳號 + App Signing 啟用決策。CI 若簽章，金鑰走 CI secret（如 GitHub Actions encrypted secrets / base64），**不進 repo**。

---

## 3. iOS signing（owner action）

1. **Apple Developer Program** 會員資格（年費）。
2. App Store Connect 建立 App record（綁 Bundle ID — 見 `APP_STORE_METADATA §7`，Bundle ID 為 owner blocker）。
3. 憑證 / Provisioning：建議 **Automatically manage signing**（Xcode + Apple ID team），或手動 distribution cert + App Store provisioning profile。
4. 若用第三方登入（Google）→ Apple 規範要求併提供 **Sign in with Apple**（見 `APP_STORE_METADATA §2`）。
5. 產物：Xcode Archive → App Store Connect / TestFlight；CI 走 fastlane match 或 App Store Connect API key（`.p8` **走 secret、不進 git**）。

> ⛔ owner blocker：Apple Developer 帳號 + 憑證 + Bundle ID 拍板。

---

## 4. .gitignore 核對（送審前）

確認下列已被忽略、且歷史未誤提交（CR-0058 未變更 .gitignore，僅提醒核對）：

- `**/key.properties`、`**/*.jks`、`**/*.keystore`、`**/*.p12`、`**/*.p8`、`**/*.cer`、`**/*.mobileprovision`
- `ios/Runner/GoogleService-Info.plist`、`android/app/google-services.json`（Firebase 設定，含專案識別，不進 git）
- `.env*`（既有規範）

> 若任一已誤入版控，需 owner 評估輪替金鑰 + 清理歷史（超出本 CR）。

---

## 5. Owner action 摘要（blocker）

- [ ] Apple Developer Program 帳號 + iOS 憑證 / provisioning。
- [ ] Google Play Console 帳號 + Android upload keystore（本機產生、不進 git）+ App Signing 啟用。
- [ ] Bundle ID / applicationId 正式化（不可逆，見 `APP_STORE_METADATA §7`）。
- [x] `build.gradle.kts` release signingConfig 由 debug key 換成正式 keystore（讀 `key.properties`）。
- [ ] 本機 / CI 提供實際 `android/key.properties` 與 upload keystore（不得提交）。
- [ ] 決定第三方登入策略（含 Sign in with Apple）。
