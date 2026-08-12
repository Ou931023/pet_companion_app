# RELEASE_BUILD_SIGNING_CHECK — Release Build / 簽章 / Production Flags 檢查

> 建立：**CR-0070**（2026-06-11）。**檢查報告，非功能變更**：不改 Realtime / Auth / Marketplace / Daily Care Tasks 行為，不改簽章 / 傳輸 runtime 設定（只盤點現況 + 指向 how-to 文件）。
> 對照：`docs/RELEASE_SIGNING.md`（簽章 how-to，CR-0058）、`docs/TRANSPORT_SECURITY.md`（ATS / cleartext 收斂 patch，CR-0054）、`docs/STORE_RELEASE_CHECKLIST.md`、`docs/E2E_SMOKE_TEST_REPORT.md`（Run #2 / CR-0069）。
> 🔴 紅線：本檔不含任何 keystore / 憑證 / 密碼 / key 值。

---

## 1. 正式 production build 指令（canonical）

App Store / Google Play 送審 build：

```bash
flutter run --release \
  --dart-define=APP_ENV=production \
  --dart-define=API_BASE_URL=https://正式後端網域 \
  --dart-define=PRIVACY_POLICY_URL=https://正式隱私權政策 \
  --dart-define=TERMS_OF_SERVICE_URL=https://正式服務條款 \
  --dart-define=SUPPORT_URL=https://正式支援頁 \
  --dart-define=CONTACT_EMAIL=support@example.com
```

- `API_BASE_URL` 不含 `/api`（client 自行接路徑），且必須是正式 HTTPS 網域。
- 不要在送審 build 帶 `SHOW_DEMO_LOGIN`、`SHOW_DEV_PANELS`、`ALLOW_MOCK_SERVICES`、`SHOW_SOCIAL_SIGN_IN`、`SHOW_MARKETPLACE` 或 `SHOW_DAILY_CARE_TASKS` 等展示 / 開發旗標。
- marketplace / 今日任務本版 production 入口強制隱藏；第三方登入待 Apple + Google 皆正式完成前，production 只保留 Email 登入 / 註冊。
- 上架打包：iOS `flutter build ipa --release …`（同 dart-define）；Android `flutter build appbundle --release …`（Play 偏好 AAB）。打包前置（簽章）見 §4 / §5。

---

## 2. Production flags 審查（✅ 全數通過；source of truth = `lib/config/app_config.dart`）

| # | 項目 | production 行為 | 程式 | 結果 |
|---|---|---|---|---|
| P1 | API base URL 安全 | production 下 localhost / 127.0.0.1 / 10.0.2.2 / 空 / 無 scheme 一律判不安全，啟動層擋入主流程 | `isApiBaseUrlProductionSafe`（app_config.dart:154-159） | ✅ |
| P2 | 無寫死正式 URL | `app_config.dart` 未寫死任何 `onrender.com`；正式 URL 全由 `--dart-define` 注入 | grep 確認 | ✅ |
| P3 | 無殘留舊 Render URL | `lib/` 執行碼無 `onrender.com` / `http://` 硬編（除 app_config localhost 預設，受 P1 守門） | grep 確認 | ✅ |
| P4 | mock service 關閉 | `mockServicesEnabled = allowMockServices && !isProduction` → production 恆 false | app_config.dart:41 | ✅ |
| P5 | dev panel 關閉 | `devPanelsVisible = showDevPanels && !isProduction` → production 恆 false（長者不會看到工程診斷） | app_config.dart:141 | ✅ |
| P6 | Demo 登入按鈕 | production 強制隱藏，即使誤帶 `SHOW_DEMO_LOGIN=true` 也不顯示 | app_config.dart | ✅ |
| P7 | 第三方登入入口 | Apple Sign in 完成前，production 強制隱藏 Google / Apple，避免未完成入口與 Apple sign-in 規則風險 | app_config.dart / login_screen.dart | ✅ |
| P8 | Marketplace 入口 | production 強制隱藏 | app_config.dart | ✅ |
| P9 | 今日任務入口 | production 強制隱藏 | app_config.dart | ✅ |

> 註：訪客「先進去陪伴」入口、商城、今日任務與第三方登入可在 development / staging 驗證；正式商店送審 build 不開這些入口，避免 App Store 2.x placeholder / 測試感與隱私申報不一致風險。

---

## 3. 版本

| 平台 | 版本來源 | 值 |
|---|---|---|
| pubspec | `version:` | `1.0.0+1`（versionName 1.0.0 / build 1） |
| iOS | `CFBundleShortVersionString=$(FLUTTER_BUILD_NAME)` / `CFBundleVersion=$(FLUTTER_BUILD_NUMBER)` | 動態取自 pubspec |
| Android | `versionName=flutter.versionName` / `versionCode=flutter.versionCode` | 動態取自 pubspec |

> 每次送審記得 bump `pubspec.yaml` 的 build 號（`+N`），否則商店會擋重複版本。

---

## 4. iOS release / 簽章 / 傳輸現況

| 項目 | 值 / 狀態 | 位置 |
|---|---|---|
| Bundle ID | ✅ `tw.edu.ncyu.im.aicompanion`（非預設、CR-0061 定值） | `project.pbxproj` |
| Display name | ✅ `AI陪伴` | `Info.plist:10` |
| DEVELOPMENT_TEAM | ✅ 已設（`WAH25TW6U4`）、CODE_SIGN_STYLE Automatic | `project.pbxproj` |
| CODE_SIGN_IDENTITY | `iPhone Developer`（開發憑證）→ 實機展示可；**App Store 送審需 Apple Distribution / App Store provisioning profile**（Xcode 自動或 App Store Connect） | `project.pbxproj` |
| Google URL scheme | ✅ 與 `GoogleService-Info.plist` REVERSED_CLIENT_ID 對齊（CR-0056 修正） | `Info.plist:30` |
| 權限 usage description | ✅ 相機 / 麥克風 / 相簿(2) / 本地網路 / 語音辨識皆齊全 | `Info.plist:48-59` |
| GoogleService-Info.plist | ✅ 存在 | `ios/Runner/` |
| Podfile platform | iOS 15.0 | `ios/Podfile:2` |
| 🔁 ATS | `NSAllowsArbitraryLoads=false` + `NSAllowsLocalNetworking=true`（CR-0096S Batch 3 已收斂；待 iOS 實機 smoke） | `Info.plist` |

---

## 5. Android release / 簽章 / 傳輸現況

| 項目 | 值 / 狀態 | 位置 |
|---|---|---|
| applicationId | ✅ `tw.edu.ncyu.im.aicompanion`（非預設、CR-0061 定值） | `build.gradle.kts:30` |
| namespace | `com.example.pet_companion_app`（僅 R class 套件，非使用者可見；不影響上架，建議日後對齊） | `build.gradle.kts:11` |
| label | ✅ `AI陪伴` | `AndroidManifest.xml:11` |
| minSdk | ✅ `max(flutter.minSdk, 23)`（Firebase / Google Sign-In 需 23+） | `build.gradle.kts:35` |
| 權限 | ✅ INTERNET / RECORD_AUDIO / MODIFY_AUDIO_SETTINGS / POST_NOTIFICATIONS / ACCESS_NETWORK_STATE / READ_MEDIA_IMAGES | `AndroidManifest.xml` |
| google-services.json | ✅ 存在 | `android/app/` |
| 🔁 **release 簽章** | CR-0096S Batch 4 已接 `android/key.properties`；缺正式 keystore 時 release / appbundle fail-fast，不再用 debug key | `build.gradle.kts` |
| 🔁 cleartext | release/main `network_security_config` 禁明文；debug/profile 保留本機開發 HTTP（CR-0096S Batch 2；待 Android 實機 smoke） | `AndroidManifest.xml` / `res/xml/network_security_config.xml` |

---

## 6. Store readiness 結論

**✅ 已就緒（本 CR 確認）**
- Production flags（P1–P9）全數正確：正式 build 不會用 localhost / 舊 URL / dev panel / mock / demo fallback；marketplace / 今日任務 / 未完成第三方登入入口皆強制隱藏。
- iOS / Android 的 bundle id / applicationId / display name / 版本來源 / 權限 / Firebase 設定檔皆就緒。
- 後端 / caregiver_web 正式 URL 在線（見 CR-0069 A1–A7）。

**⛔ 上架前 owner blockers（非本 CR 範圍，how-to 已在既有文件）**
1. **Android release keystore 尚待 owner / CI 提供** → `build.gradle.kts` 已接 `android/key.properties` 並 fail-fast；仍需產生正式 upload keystore + `key.properties`（**`docs/RELEASE_SIGNING.md §2`**）。⚠️ keystore / key.properties 不可提交。
2. **iOS 無正式 distribution 簽章** → 需 Apple Developer 帳號 + App Store provisioning（**`docs/RELEASE_SIGNING.md §3`**）。實機展示用現行 dev 簽章可。
3. **傳輸安全實機 smoke 未結案**：iOS ATS / Android cleartext runtime 設定已於 CR-0096S Batch 2–3 收斂；仍需正式 HTTPS 後端 + iOS/Android 實機跑 Realtime / REST smoke 後，才能從送審 blocker 移除。
4. 實機 E2E（S1–S9 / M1–M4 / D1–D5）仍 PENDING（**`docs/E2E_SMOKE_TEST_REPORT.md` Run #2 / CR-0069**）。

> 本檢查未修改任何 build / 簽章 / 傳輸 runtime 設定；上述 ⛔ 項皆為既有 owner action，how-to 在所引文件，落地後各自更新對應 CR。
