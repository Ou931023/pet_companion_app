# Store Release Checklist — AI Pet Companion

> 狀態：第一輪上架前 readiness 盤點（CR-0046）。
> 本檔列出 iOS / Android 正式上架前的待辦、已完成項，以及**必須由負責人決策或提供素材的 blocker**。
> 規則：凡標 ⛔ **BLOCKER** 者，未完成前不得送審；不得以假值/假完成充數。

相關文件：`docs/FINAL_STORE_BLOCKER_BOARD.md`（最後 Go / No-Go 入口）、`docs/STORE_SUBMISSION_RUNBOOK.md`（上架前單一 smoke 入口）、`docs/APP_STORE_METADATA.md`、`docs/GOOGLE_PLAY_DATA_SAFETY.md`、`docs/ENVIRONMENT_SETUP.md`、`docs/PRODUCTION_CONFIG_CHECKLIST.md`、`docs/AUTHORIZATION_MODEL.md`。

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
| ATS（App Transport Security） | 🔁 | CR-0096S Batch 3 已收斂為 `NSAllowsArbitraryLoads=false` + `NSAllowsLocalNetworking=true`。仍需 HTTPS 後端就緒 + iOS 實體裝置 Realtime / REST smoke 後才能送審結案 |
| Display name（CFBundleDisplayName） | ✅ （CR-0061） | `AI Companion`（owner 拍板定值），已寫入 `Info.plist` |
| Bundle ID | ✅ （CR-0061） | `tw.edu.ncyu.im.aicompanion`（嘉義大學反向網域，owner 拍板）。已寫入 pbxproj（app + RunnerTests）。後續 Apple 憑證 / Firebase iOS App / Sign in with Apple 須對應此 ID（上架後不可改） |
| App icon（全尺寸） | ✅ | CR-0101A 已輸出正式候選 icon 全尺寸組；送審前仍需實機 / 商店後台預覽確認 |
| Launch screen | ✅ | 已使用正式候選 icon + 品牌底色；送審前仍需實機確認無閃白/裁切 |
| Release build（`flutter build ios --release --no-codesign`） | 🔁 | 見 §7，需在 macOS + CocoaPods 環境嘗試 |

---

## 3. Android

| 項目 | 狀態 | 說明 |
|---|---|---|
| 權限（INTERNET / RECORD_AUDIO / MODIFY_AUDIO_SETTINGS / POST_NOTIFICATIONS / ACCESS_NETWORK_STATE / READ_MEDIA_IMAGES / READ_EXTERNAL_STORAGE≤32） | ✅ | 與實際功能相符；POST_NOTIFICATIONS 供 Android 13+ |
| `usesCleartextTraffic` / network security config | 🔁 | CR-0096S Batch 2 已收斂：release/main 禁明文，debug/profile 保留本機開發 HTTP。仍需 HTTPS 後端 + Android 實體裝置 smoke 後才能送審結案 |
| `applicationId` | ✅ （CR-0061） | `tw.edu.ncyu.im.aicompanion`（對齊 iOS，owner 拍板）。已寫入 `build.gradle.kts`。**上架後不可再改**。namespace 維持 `com.example.pet_companion_app`（owner 指定不動，與 applicationId 獨立） |
| `android:label` | ✅ （CR-0061） | `AI Companion`（owner 拍板定值，與 iOS CFBundleDisplayName 一致），已寫入 `AndroidManifest.xml` |
| Adaptive icon / launcher icon | ✅ | CR-0101A 已輸出 legacy launcher icon + Android adaptive icon XML / foreground / background；送審前仍需真機 mask 預覽 |
| Release signing config | ⛔ **BLOCKER** | 需正式 upload keystore（**禁止提交 keystore / signing key 進版控**） |
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

1. ✅ **正式品牌 display name**（CR-0061 已定值）：iOS CFBundleDisplayName = Android `android:label` = 商店 App 名稱 = `AI Companion`（中文 `AI陪伴`）。發行者：國立嘉義大學資訊管理學系專題第四組。
2. ✅ **App 識別碼正式化**（CR-0061 已定值）：iOS Bundle ID = Android `applicationId` = `tw.edu.ncyu.im.aicompanion`（**一旦上架不可更改**；後續 Apple/Google/Firebase 憑證與 Sign in with Apple 設定須對應此 ID）。
3. ✅ **Hosted 法務/支援 URL** / ✅ **客服信箱**：`privacyPolicyUrl` / `termsOfServiceUrl` / `supportUrl` / `contactEmail` 已支援透過 `--dart-define` 注入；GitHub Pages 已提供公開 HTTPS URL：`https://ou931023.github.io/pet_companion_app/privacy.html`、`https://ou931023.github.io/pet_companion_app/terms.html`、`https://ou931023.github.io/pet_companion_app/support.html`；客服信箱已定為 `aicompanion.support@gmail.com`。
4. ✅ / 🔁 **視覺素材**：App icon（iOS 全尺寸 + Android adaptive/launcher）、Google Play feature graphic、兩平台 store screenshots 與 launch screen 已輸出正式候選；送審前仍需商店後台與實機人工預覽。
5. ⛔ **Release signing**：Android Gradle 已接 `android/key.properties` 並不再使用 debug key；仍需正式 upload keystore / CI secret。iOS 仍需簽章憑證 / provisioning profile（**禁止提交進版控**）。
6. 🟡 **Production 環境**（部分完成）：
   - Firebase：✅ iOS/Android App 已以正式 Bundle ID `tw.edu.ncyu.im.aicompanion` 註冊，`GoogleService-Info.plist`（BUNDLE_ID 對齊）/ `google-services.json`（含對應 client）已落地，**兩檔 gitignored 不進版控**（CR-0062）。🟡 待真機 Firebase Auth smoke。
   - ⛔ 仍待 owner：正式後端 HTTPS 網域、`CORS_ALLOWED_ORIGINS`、OpenAI / Telegram / PostgreSQL 正式憑證（走 env，**不寫死、不進版控**）。
   - 📘 部署步驟與 env 清單見 **`docs/BACKEND_DEPLOYMENT_GUIDE.md`**（CR-0063；Render / Railway、`npm run db:migrate`、`/health`）。

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

- 🔁 ⛔ **上架 smoke 單一 Runbook**：送 TestFlight / Internal testing / App Store / Google Play 前，需依 `docs/STORE_SUBMISSION_RUNBOOK.md` 完整執行並留下 Run 記錄。未跑完不得送審。
- ✅ `flutter analyze`（CR-0046 後）
- ✅ `flutter test`（授權鏈相關測試綠；整包回歸建議於 CI 跑）
- ✅ repo 自動 store readiness test 已建立：`flutter test test/config/store_readiness_test.dart`
- 🔁 ⛔ `flutter build apk --release` — 需在具 Android SDK 環境嘗試；失敗記錄 blocker 與錯誤摘要，不偽造綠燈
- 🔁 ⛔ `flutter build ios --release --no-codesign` — 需 macOS + CocoaPods；失敗記錄 blocker
- 🔁 上架前三大 smoke（真環境）：Auth 登入 / Realtime 語音 / Care Alert → Telegram

---

## 8. 內容合規（送審前掃描）

- ✅ App 內無 demo/test/mock/debug 對使用者可見字樣（dev panel / Demo 登入由 flag 隔離、production 強制關）
- ✅ **CR-0101A 第三方登入上架策略**：Apple Sign in 尚未完成前，production 隱藏 Google / Apple 入口，只保留 Email login / Email register，避免 App Store Sign in with Apple 與 placeholder 風險。
- ✅ **CR-0101A in-app support / account deletion wording**：設定頁有 App 內隱私 / 條款、重新檢視同意、支援說明與帳號刪除流程；刪除確認文案明確說明會刪除伺服器帳號資料與本機寵物 / 記憶 / 提醒 / 使用紀錄。
- ✅ pubspec `description` 已移除 "demo"（CR-0046）
- 🔁 mock service build-flavor 隔離（CR-0048，詳見 `docs/FLUTTER_BUILD_FLAVORS.md`）：
  - ✅ `MockShopService` 已隔離（production 不注入）。
  - ✅ `MockTaigiAsrStrategy` 已隔離（production 不注入；settings 手動 ASR 下拉的台語 mock 選項在正式版隱藏；語音路由 fallback 回 OpenAI Realtime）。
  - ✅ `MockAiService` / `MockSpeechToTextService` 已隔離（**CR-0049**）：兩個 `Provider` 改 `if (mockServicesEnabled)`，production provider 樹零 mock 實例；聊天走後端 `companionChatService`（`AiToolRouter.mockAiService==null`、`useMockChat==false`），STT 走正式 `OpenAiSpeechToTextService`。audit P2-5 mock 隔離完成。
- ✅ 打字聊天陪伴 persona（**CR-0050**）：`POST /api/companion/chat` 改用 `COMPANION_CHAT_PERSONA`（陪伴型、無工具罐頭、不假裝執行 App 動作、記憶/健康界線），不再借用工具化的語音 persona；語音 persona byte-identical。原則見 `docs/COMPANION_PERSONA.md` / `docs/SAFETY_BOUNDARIES.md`。
- ✅ 打字聊天風險分析 + Care Alert（**CR-0051**）：`POST /api/companion/chat` 掛 `requireResidentCaller`（須住民 idToken，與語音/notify 一致；後端 hard-auth + Flutter 送 token 同一 release），回覆後純函式風險側錄，`riskLevel∈{medium,high,urgent}` 經共用 `processCareAlert` 建 Care Alert（`source="companion_chat"`、high/urgent 推 Telegram），回應加 optional `careAlert`（長者端不顯示監控感文案）。流程見 `docs/TYPED_CHAT_CARE_ALERT_FLOW.md`。
- ✅ 語音 Care Alert persist gate 對齊（**CR-0052**）：`voice_agent_controller.dart` persist gate 由 `needsHumanSupport`（high/urgent）改為 canonical-riskLevel-based `shouldPersistCareAlert`（`{medium,high,urgent}`），語音與打字現在都持久化 medium+。Telegram 仍只 high/urgent（後端權威，前端不複製），medium 不洗版。不改後端、不觸 🔒 檔案、不破壞 Realtime / CR-0045 notify auth / CR-0051 typed chat。流程見 `docs/VOICE_CARE_ALERT_FLOW.md`。
- 🔁 **BLOCKER** 真環境端到端 smoke 尚未執行（**CR-0053**）：已建立 `docs/E2E_SMOKE_TEST_PLAN.md`（可執行 checklist）+ `docs/E2E_SMOKE_TEST_REPORT.md`（Run #0 = Plan-only，未連任何真 Firebase/PostgreSQL/OpenAI/Telegram、無實體裝置，誠實標示未執行原因 + owner blocker + 下一步）。上架前必須完成一輪 Execute（至少計畫 §7 最小通過集：fail-fast / migration / health / chat+notify auth / **medium 不推 Telegram** / caregiver scoped / Realtime+語音 medium·high alert / log 去敏）。
- ✅ 後端 CORS allow-all 缺口已修（**CR-0054** Batch 1）：CORS middleware 改經 `resolveCorsOrigins`（新名 `CORS_ALLOWED_ORIGINS` 優先、相容 legacy `ALLOWED_ORIGINS`），與 production fail-fast 同源，修補「只設新名→middleware 空清單→production allow-all」缺口；保留 dev 空清單 allow-all 與無 Origin 放行。backend 473/473。
- 🔁 **BLOCKER** iOS ATS / Android cleartext 傳輸收斂（**CR-0054** Batch 2 PATCH-READY；**CR-0055** 落地嘗試 = BLOCKED）：就緒 patch + smoke checklist + rollback 見 `docs/TRANSPORT_SECURITY.md`。CR-0055 因無正式 HTTPS 後端 + 無實體裝置，依 task §2/§12.2 未套用 patch、未跑 T1–T9（見 `E2E_SMOKE_TEST_REPORT` Run #1）。落地待 owner 備齊 HTTPS 後端 + iOS/Android 實機後重跑，**不可盲套**。
- ✅ Marketplace / DailyCareTask production 策略確定（**CR-0056**）：兩者 = 本版 production 隱藏/停用（A2 / B2），保留 dev/test，PG 化列 post-release。後端本就 fail-closed（不讀 JSON）；本 CR 補 Flutter 入口 `AppConfig.marketplaceVisible`/`dailyCareTasksVisible`（production 完全隱藏）+ caregiver_web `featureFlags`（預設關）。store-facing 文案不得出現商城/購買/下單/照護任務字樣；不申報財務/購買資料。決策見 `docs/MARKETPLACE_PRODUCTION_DECISION.md`、`docs/DAILY_CARE_TASK_PRODUCTION_DECISION.md`。flutter 541/541、caregiver_web 90/90。
- ✅ Marketplace / DailyCareTask 後端 production 停用路徑收斂（**CR-0057**）：production direct API call 由誤映 500 改為乾淨 **501 `not_enabled`**（保留 `ok`/`success:false` discriminator + 友善 message，不回 stack/path、不讀 JSON、不回 demo data）；helper `isFeatureUnavailableError`（env.js）+ `respondFeatureDisabled`（server.js）；daily-care authz-403 優先序保留、無 token 仍 401、reminders 不受影響；store 語意不改、dev/test 位元不變。backend 473→495。
- 🟡 Store metadata / app identity / icon / signing readiness 整理（**CR-0058**）：app identity 現況與 owner blocker 列於 `docs/APP_STORE_METADATA.md §7`（Bundle ID/applicationId `com.Andrew.*` 個人名、不可逆 → owner 拍板正式反向網域）；icon/screenshot/launch 規格與缺口（Android 缺 adaptive icon）列於 `docs/STORE_ASSET_CHECKLIST.md`；簽章準備與紅線（release 仍用 debug key、不可提交 keystore）列於 `docs/RELEASE_SIGNING.md`；legal URL（`legal_config.dart` 4×`TODO_*`，已有 `isPlaceholder` 防護）待 owner 真值。可離線安全修者：android:label 已對齊 iOS interim。store 文案未宣稱停用之 marketplace/daily-care（`APP_STORE_METADATA §6`）。
- 📋 **交接地圖（CR-0059）**：所有剩餘 release blocker（owner decision / infrastructure / device smoke / store console / post-release）、owner action checklist、環境齊後重啟哪個 CR、20-area readiness matrix、不可假完成清單，彙整於 **`docs/RELEASE_HANDOFF.md`**（單一交接來源）。程式面已硬化（backend 495 / flutter 541 / caregiver_web 90 綠）；尚未上架，剩餘全為 owner-gated。
- ⛔ **BLOCKER** Google Play Data Safety 表單填寫（依 `docs/GOOGLE_PLAY_DATA_SAFETY.md`）
- ⛔ **BLOCKER** App Store 隱私問卷 / metadata（依 `docs/APP_STORE_METADATA.md`）
- 🟡 **Hosted legal/support 靜態頁草稿**：`store_legal_site/` 已建立 `privacy.html` / `terms.html` / `support.html`，可部署到 GitHub Pages / Vercel / Netlify / Firebase Hosting。
- ✅ 對外可存取的隱私政策 URL：`https://ou931023.github.io/pet_companion_app/privacy.html`（Apple/Google 皆要求）。
- ✅ 對外可存取的服務條款 URL：`https://ou931023.github.io/pet_companion_app/terms.html`。
- ✅ 對外可存取的支援 URL：`https://ou931023.github.io/pet_companion_app/support.html`；✅ 客服信箱已定為 `aicompanion.support@gmail.com`（store metadata 必填或強烈建議；App 內外部按鈕只有正式值注入後才顯示）
- ✅ **CR-0097 usage tracking in-app disclosure**：同意畫面與 App 內隱私政策已揭露 App 使用時間、語音/打字互動、寵物互動、提醒、任務、照片驗證、小遊戲等使用紀錄；`LegalConfig.consentVersion` 已更新，舊版同意者會被要求重新同意。
- ⛔ **BLOCKER** Hosted 隱私政策 / 商店後台需同步 CR-0097：正式 hosted 隱私政策、Google Play Data Safety、App Store Privacy Nutrition Labels 必須申報 `app_usage_events` 對應的 App 活動 / 使用分析資料，且用途限 App 功能、照護分析、產品改善，不可填成未收集。

---

## 9. 禁止事項（再次提醒）

- 不提交 keystore / signing key / `GoogleService-Info.plist` / `google-services.json` / `.env`。
- 不寫死任何 production secret（OpenAI / Telegram / DB / Firebase private key）。
- 不偽造已部署的隱私政策 URL 或「已完成」的商店後台設定。
- 不為了讓 release build 通過而暫時關閉必要權限或安全檢查。
- 不讓 production 預設連 localhost。
