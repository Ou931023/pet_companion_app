# Store Release Checklist — AI Pet Companion

> 狀態：第一輪上架前 readiness 盤點（CR-0046）。
> 本檔列出 iOS / Android 正式上架前的待辦、已完成項，以及**必須由負責人決策或提供素材的 blocker**。
> 規則：凡標 ⛔ **BLOCKER** 者，未完成前不得送審；不得以假值/假完成充數。

相關文件：`docs/APP_STORE_METADATA.md`、`docs/GOOGLE_PLAY_DATA_SAFETY.md`、`docs/ENVIRONMENT_SETUP.md`、`docs/PRODUCTION_CONFIG_CHECKLIST.md`、`docs/AUTHORIZATION_MODEL.md`。

---

## 0. 圖例

- ✅ 已完成（程式/設定層）
- 🟡 進行中 / 部分完成
- ⛔ **BLOCKER** — 需負責人決策或提供正式素材/憑證，未完成不得送審
- 🔁 需在真環境（實機 / 真後端 / 真 Firebase）驗證

---

## 1. 授權與安全（CR-0039–0045，code 層已閉合）

- ✅ 後端 admin / care-alert 讀取 API 擋門（requireAdmin）
- ✅ resident-caregiver 授權範圍過濾
- ✅ caregiver HTTP 身分（Firebase idToken → users.role）
- ✅ caregiver_web 角色化 auth UI / 401 / 403 / empty state
- ✅ caregiver 帳號 + resident-caregiver link provisioning（super_admin-only）
- ✅ `/api/care-alerts/notify` caller 驗證（resident idToken，server 權威 elderId）
- 🔁 ⛔ **部署前對「真 Postgres + 真 Firebase」做端到端驗證**：idToken → users.elder_id → care alert → Telegram；caregiver scope；inactive 即時失效。（目前所有授權測試皆為 mock pg + stub firebaseAdmin）
- ✅ **Production log 去識別化（CR-0047）**：後端高風險 log 點（`server.js logInfo/logError`、`memoryExtractor`、`memory/*`、`search/*`、`embeddingService`）改用 `services/privacy/redaction.js`；production log 不輸出完整對話 / Care Alert summary·reason / email / phone / token / secret / DATABASE_URL / stack。原則與除錯方式見 `docs/LOGGING_AND_REDACTION.md`。

---

## 2. iOS

| 項目 | 狀態 | 說明 |
|---|---|---|
| 麥克風權限文案 `NSMicrophoneUsageDescription` | ✅ | 長者友善、無工程字眼 |
| 相機 / 相簿 / 語音辨識 / 區網權限文案 | ✅ | 皆清楚、無 demo/test/mock |
| ATS（App Transport Security） | ⛔🔁 **BLOCKER** | 目前 `NSAllowsArbitraryLoads=true`（全域允許明文）。收斂方案見 §6，**需區網語音 smoke 驗證後才可套用**，否則回退 |
| Display name（CFBundleDisplayName） | ⛔ **BLOCKER** | 目前 "Pet Companion App"，正式品牌名待負責人定案（見 §5 #1） |
| Bundle ID | ⛔ **BLOCKER** | 目前 `com.Andrew.petCompanionApp`（個人名、非註冊網域）。正式化會綁定 Apple 憑證 / Firebase iOS App / Sign in with Apple，需負責人拍板（見 §5 #2） |
| App icon（全尺寸） | ⛔ **BLOCKER** | 需正式 icon 素材 |
| Launch screen | 🟡 | 需確認正式化、無 debug banner |
| Release build（`flutter build ios --release --no-codesign`） | 🔁 | 見 §7，需在 macOS + CocoaPods 環境嘗試 |

---

## 3. Android

| 項目 | 狀態 | 說明 |
|---|---|---|
| 權限（INTERNET / RECORD_AUDIO / MODIFY_AUDIO_SETTINGS / POST_NOTIFICATIONS / ACCESS_NETWORK_STATE / READ_MEDIA_IMAGES / READ_EXTERNAL_STORAGE≤32） | ✅ | 與實際功能相符；POST_NOTIFICATIONS 供 Android 13+ |
| `usesCleartextTraffic` / network security config | ⛔🔁 **BLOCKER** | 與 iOS ATS 同源收斂，見 §6，需區網語音 smoke 驗證 |
| `applicationId` | ⛔ **BLOCKER** | 目前 `com.Andrew.petCompanionApp`（個人名）。**正式上架後不可再改**（破壞更新路徑），需負責人拍板（見 §5 #2） |
| `android:label` | ⛔ **BLOCKER** | 目前 dev 名 `pet_companion_app`，待正式品牌名 |
| Adaptive icon / launcher icon | ⛔ **BLOCKER** | 需正式 icon 素材 |
| Release signing config | ⛔ **BLOCKER** | 需正式 keystore（**禁止提交 keystore / signing key 進版控**） |
| targetSdk | 🟡 | 用 flutter 預設，送審前確認符合 Play 當期最低 targetSdk |
| ProGuard / R8 | 🟡 | 視需要啟用，確認不破壞 reflection（Firebase 等） |

---

## 4. Production API / 連線

- ✅ Flutter `AppConfig.isApiBaseUrlProductionSafe`：production 下 `apiBaseUrl` 指向 localhost / 127.0.0.1 / 10.0.2.2 / 空 → 判定不安全（非 silent fallback；見 `docs/ENVIRONMENT_SETUP.md` §3.3 守門畫面）
- ✅ caregiver_web 預設同源 `/api`（非 localhost 預設，CR-0034 B4）
- ⛔ **BLOCKER** production 後端正式 HTTPS 網域（給 `--dart-define=API_BASE_URL=https://...` 與 caregiver_web `config.js`）
- ⛔ **BLOCKER** production `CORS_ALLOWED_ORIGINS` 白名單網域

---

## 5. Owner-decision blockers（必須由負責人決策 / 提供，禁止假完成）

1. ⛔ **正式品牌 display name**（iOS CFBundleDisplayName + Android `android:label` + 商店 App 名稱一致）。
2. ⛔ **App 識別碼正式化**：iOS Bundle ID + Android `applicationId`（**一旦上架不可更改**；會綁定 Apple/Google/Firebase 憑證與 Sign in with Apple 設定）。
3. ⛔ **Hosted 法務/支援 URL + 客服信箱**：`privacyPolicyUrl` / `termsOfServiceUrl` / `supportUrl` / `contactEmail`（目前 `lib/config/legal_config.dart` 為 `TODO_*` 佔位；**禁止偽造已部署 URL**）。需法務校稿同意內文。
4. ⛔ **視覺素材**：App icon（iOS 全尺寸 + Android adaptive/launcher）、launch screen、商店 screenshots、feature graphic。
5. ⛔ **Release signing**：Android keystore、iOS 簽章憑證 / provisioning profile（**禁止提交進版控**）。
6. ⛔ **Production 環境**：正式後端 HTTPS 網域、`CORS_ALLOWED_ORIGINS`、Firebase 正式專案（iOS/Android App + `GoogleService-Info.plist`/`google-services.json`，**不進版控**）、OpenAI / Telegram / PostgreSQL 正式憑證（走 env，**不寫死、不進版控**）。

---

## 6. ⛔🔁 B3 — ATS / cleartext 收斂（備妥，需區網語音 smoke 驗證後才套用）

> 架構裁決（CR-0046）：Realtime 走 WebRTC，媒體為 DTLS-SRTP，**不受 ATS 管制**；ATS/cleartext 只管 SDP 交換與 REST 的明文 http 後端。收斂**不影響語音媒體**，但 dev 若用「區網 IP + http 後端」需保留區網例外。
> **驗證未過或無法驗證前，維持現狀（不套用），列為 blocker，不假完成。**

驗證步驟（需 macOS + 實機/模擬器 + 區網 http 後端 + 真 OpenAI key）：
1. 套用下列 iOS / Android 變更。
2. 跑一次區網語音 smoke：開麥 → SDP 交換 → DataChannel 開 → partial/final transcript 正常 → Care Alert 可建立。
3. 通過 → 結案；失敗 → `git checkout` 回退這兩處，維持全域允許，並回報實際錯誤。

### iOS（`ios/Runner/Info.plist`）— 以下列取代全域 `NSAllowsArbitraryLoads`
```xml
<key>NSAppTransportSecurity</key>
<dict>
    <!-- 正式網域走 HTTPS，無需例外。以下僅為 dev 區網 http 後端。 -->
    <key>NSAllowsLocalNetworking</key>
    <true/>
    <key>NSExceptionDomains</key>
    <dict>
        <key>localhost</key>
        <dict>
            <key>NSExceptionAllowsInsecureHTTPLoads</key>
            <true/>
        </dict>
    </dict>
</dict>
```

### Android（`android/app/src/main/AndroidManifest.xml` + 新增 `res/xml/network_security_config.xml`）
`AndroidManifest.xml` 的 `<application>` 加：
```xml
android:networkSecurityConfig="@xml/network_security_config"
```
`android/app/src/main/res/xml/network_security_config.xml`：
```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <!-- 預設禁明文（強制 HTTPS）；dev 區網 http 後端用下方例外。 -->
    <base-config cleartextTrafficPermitted="false" />
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="true">localhost</domain>
        <domain includeSubdomains="true">10.0.2.2</domain>
        <!-- 如用實機 + 區網 IP 後端，於此補該網段網域 -->
    </domain-config>
</network-security-config>
```

---

## 7. Build / 測試

- ✅ `flutter analyze`（CR-0046 後）
- ✅ `flutter test`（授權鏈相關測試綠；整包回歸建議於 CI 跑）
- 🔁 ⛔ `flutter build apk --release` — 需在具 Android SDK 環境嘗試；失敗記錄 blocker 與錯誤摘要，不偽造綠燈
- 🔁 ⛔ `flutter build ios --release --no-codesign` — 需 macOS + CocoaPods；失敗記錄 blocker
- 🔁 上架前三大 smoke（真環境）：Auth 登入 / Realtime 語音 / Care Alert → Telegram

---

## 8. 內容合規（送審前掃描）

- ✅ App 內無 demo/test/mock/debug 對使用者可見字樣（dev panel / Demo 登入由 flag 隔離、production 強制關）
- ✅ pubspec `description` 已移除 "demo"（CR-0046）
- 🔁 mock service build-flavor 隔離（CR-0048，詳見 `docs/FLUTTER_BUILD_FLAVORS.md`）：
  - ✅ `MockShopService` 已隔離（production 不注入）。
  - ✅ `MockTaigiAsrStrategy` 已隔離（production 不注入；settings 手動 ASR 下拉的台語 mock 選項在正式版隱藏；語音路由 fallback 回 OpenAI Realtime）。
  - ✅ `MockAiService` / `MockSpeechToTextService` 已隔離（**CR-0049**）：兩個 `Provider` 改 `if (mockServicesEnabled)`，production provider 樹零 mock 實例；聊天走後端 `companionChatService`（`AiToolRouter.mockAiService==null`、`useMockChat==false`），STT 走正式 `OpenAiSpeechToTextService`。audit P2-5 mock 隔離完成。
- ⛔ **BLOCKER** Google Play Data Safety 表單填寫（依 `docs/GOOGLE_PLAY_DATA_SAFETY.md`）
- ⛔ **BLOCKER** App Store 隱私問卷 / metadata（依 `docs/APP_STORE_METADATA.md`）
- ⛔ **BLOCKER** 對外可存取的隱私政策 URL（Apple/Google 皆要求）

---

## 9. 禁止事項（再次提醒）

- 不提交 keystore / signing key / `GoogleService-Info.plist` / `google-services.json` / `.env`。
- 不寫死任何 production secret（OpenAI / Telegram / DB / Firebase private key）。
- 不偽造已部署的隱私政策 URL 或「已完成」的商店後台設定。
- 不為了讓 release build 通過而暫時關閉必要權限或安全檢查。
- 不讓 production 預設連 localhost。
