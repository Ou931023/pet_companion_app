# Production Config Checklist（正式上線前檢查表）

> 對象：負責把本系統推上正式環境 / 上架的人。
> 用途：production 部署前逐項勾選，確保 fail-fast 必要設定齊全、不安全旗標關閉、
> 待辦（hosted URL / migrations / 上架身份）已處理。
> 治理依據：`PROJECT_ARCHITECTURE.md` §7.1 / §7.1.1 / §5.3.1、CR-0034。
>
> 紅線：不要把 `.env` 或任何 token / API key 進版控；本文件只列名稱，不含真實值。
> 啟動 / build 操作步驟見 `docs/ENVIRONMENT_SETUP.md`。正式送審前最後 Go / No-Go 入口見
> `docs/FINAL_STORE_BLOCKER_BOARD.md`，smoke 執行入口見 `docs/STORE_SUBMISSION_RUNBOOK.md`。

---

## 1. 環境 / flag 對照表（dev / staging / prod，引用 §7.1）

| flag | development | staging | production | 備註 |
|---|---|---|---|---|
| `APP_ENV` | development | staging | production | 顯式優先；`NODE_ENV=test` 永不視為 production |
| `ALLOW_MOCK_SERVICES` | true | false | **false（顯式 true → fail-fast）** | 收斂 `AUTH_ALLOW_MOCK` / Flutter mock 注入 |
| `ALLOW_JSON_FALLBACK` | true | 可設 | **false（顯式 true → fail-fast）** | 治理 §5.3.1 各 store |
| `REQUIRE_AUTH` | false | true | **true（顯式 false → fail-fast）** | production 強制驗 token |
| `REQUIRE_CONSENT` | false | true | true | 治理表（後端尚未全面接入） |
| `ENABLE_VERBOSE_LOGS` | true | false | false | production log 不得輸出 secret / 完整個資 |
| `SHOW_DEV_PANELS`（Flutter） | 可開 | false | **false（強制）** | `lib/config/app_config.dart` |
| `SHOW_DEMO_LOGIN`（Flutter） | 可開 | false | **false（強制）** | 同上 |
| `CORS_ALLOWED_ORIGINS`（後端） | 寬鬆 | 白名單 | **必填白名單（空 → fail-fast）** | 相容別名 `ALLOWED_ORIGINS` |
| `PGVECTOR_ENABLED`（後端） | 可選 | 依用 | 記憶向量啟用則必填 | 與環境正交的 feature flag |
| `API_BASE_URL`（Flutter / web） | localhost | staging URL | **正式 https 網域（localhost/空 → 阻擋）** | Flutter 收斂 `BACKEND_BASE_URL` |

---

## 2. production 必要 env（fail-fast 必檢，缺一即 `process.exit(1)`）

- [ ] `DATABASE_URL`
- [ ] `OPENAI_API_KEY`
- [ ] `CORS_ALLOWED_ORIGINS`（正式前端網域白名單，逗號分隔）
- [ ] Firebase 服務帳戶（擇一）：
  - [ ] `GOOGLE_APPLICATION_CREDENTIALS`（service account JSON 路徑），或
  - [ ] `FIREBASE_PROJECT_ID` + `FIREBASE_CLIENT_EMAIL` + `FIREBASE_PRIVATE_KEY` 三件組
- [ ] `ADMIN_API_TOKEN`（caregiver_web 存取 `/api/admin/*`）

條件必檢（功能啟用才需要）：

- [ ] `TELEGRAM_BOT_TOKEN`（若設了 `TELEGRAM_CARE_CHAT_ID` 啟用 Telegram 通知）
- [ ] `PGVECTOR_ENABLED=true` 時須有 `DATABASE_URL`

待 CR-0038（正式 admin / JWT 登入）落地後納入必檢，現況先列：

- [ ] `SESSION_SECRET` / `JWT_SECRET`（目前未使用，現況走 Firebase + `ADMIN_API_TOKEN`）

---

## 3. fail-fast 行為（驗收方式）

- [ ] 故意缺一個必要變數，`APP_ENV=production node server.js` 應退出，
      log **只列缺哪些變數名稱**，且不含任何 token / secret 值。
- [ ] 啟動成功時印出的設定摘要為遮蔽值（`postgres://***`、`sk-***last4`、
      `ou***@example.com`、chat id 僅 `(set)/(unset)`）。
- [ ] fail-fast 屬啟動層行為，未改任何 API request / response 形狀。

---

## 4. 不安全旗標必須為安全值（顯式打開即拒絕啟動）

- [ ] `ALLOW_JSON_FALLBACK` 未設或為 false
- [ ] `ALLOW_MOCK_SERVICES` 未設或為 false
- [ ] `REQUIRE_AUTH` 未設或為 true
- [ ] mock auth：production `mockAllowed()` 一律 false（不採信 client `firebaseUid`，
      強制驗 `idToken`）

---

## 5. JSON fallback 政策（§5.3.1）

- [ ] **care alert**：production DB-required。DB 例外時 `saveAlert` 回
      `{success:false,error:'care_alert_persist_failed'}`，不靜默降級 JSON 假成功。
- [ ] `/api/care-alerts/notify` 已解耦通知與持久化：high/urgent 通知照送，
      持久化失敗以 `notification_logs`（`outcome=persist_failed`）明確記一列，
      **絕不靜默漏通知、絕不假成功、不改 request/response 形狀**。
- [ ] **auth / memory / consent / search**：production DB-required，DB 例外回清楚錯誤，
      不降級 JSON 當權威。
- [ ] **marketplace / dailyCareTask（JSON-only）**：production 以清楚 guard 阻擋
      （長者友善訊息），目前 production **暫不可用**，為 **CR-0042（PG 化）blocker**，
      屬已知且文件化限制，需產品確認接受。

---

## 6. Flutter build define（正式 build 時帶入）

- [ ] `--dart-define=APP_ENV=production`
- [ ] `--dart-define=API_BASE_URL=https://正式後端網域`（非 localhost / 非空）
- [ ] `--dart-define=SHOW_DEV_PANELS=false`
- [ ] `--dart-define=SHOW_DEMO_LOGIN=false`
- [ ] `--dart-define=ALLOW_MOCK_SERVICES=false`
- [ ] `--dart-define=SHOW_SOCIAL_SIGN_IN=true`（正式顯示 Google，iOS 同時顯示 Apple；送審前須完成 Firebase / Apple Developer / provisioning 與真機 smoke）
- [ ] 驗收：production build 開啟不會出現開發面板 / Demo 登入；
      若 `API_BASE_URL` 不安全會顯示長者友善守門畫面（不進主流程）。

---

## 7. caregiver_web APP_CONFIG

- [ ] 設 `window.APP_CONFIG.apiBaseUrl = "https://api.正式網域/api"`
      （複製 `config.example.js` 為 `config.js`，`config.js` 不進版控），或
- [ ] 與後端同網域 / 反向代理，使用同源相對路徑 `/api`（`apiBaseUrl` 留 `null`）。
- [ ] 設 `window.APP_CONFIG.firebase`（Firebase Web app config），讓照護人員可用 Email / Google 登入。
- [ ] Firebase Console Authorized domains 已加入 caregiver_web 正式網域。
- [ ] `config.js` 不含 Firebase Admin service account / private key / `ADMIN_API_TOKEN`。
- [ ] 確認未把 `http://127.0.0.1:3001/api` 當成正式預設。
- [ ] 執行 `node scripts/check_caregiver_web_config.js caregiver_web/config.js` 通過。
- [ ] Render Static Site Build Command：`node caregiver_web/build_config_from_env.js`。
- [ ] Render Static Site Publish Directory：`caregiver_web`。
- [ ] Render env 設定 `CAREGIVER_WEB_API_BASE_URL=https://ai-companion-api-1gm7.onrender.com/api`。
- [ ] 若找不到既有 Static Site，使用 repo 根目錄 `render.yaml` 建立 Render Blueprint；
      Firebase Web config 欄位必須以 `sync: false` 在 Render UI 填值，不寫進 git。

---

## 8. 待辦（上架前必須處理）

### 8.1 LegalConfig 4 個 hosted URL / Email（`lib/config/legal_config.dart`，由 dart-define 注入）

- [x] `privacyPolicyUrl`：`https://ou931023.github.io/pet_companion_app/privacy.html`
- [x] `termsOfServiceUrl`：`https://ou931023.github.io/pet_companion_app/terms.html`
- [x] `supportUrl`：`https://ou931023.github.io/pet_companion_app/support.html`
- [x] `contactEmail`（正式客服信箱）：`aicompanion.support@gmail.com`

> 在填入正式值前，UI 以 `LegalConfig.isPlaceholder` 判斷不顯示外部連結入口

靜態頁已在 `store_legal_site/`，並透過 GitHub Pages 提供公開 HTTPS：

- `store_legal_site/privacy.html`
- `store_legal_site/terms.html`
- `store_legal_site/support.html`
- GitHub Pages workflow：`.github/workflows/legal-site-pages.yml`

- `https://ou931023.github.io/pet_companion_app/privacy.html`
- `https://ou931023.github.io/pet_companion_app/terms.html`
- `https://ou931023.github.io/pet_companion_app/support.html`

Production build 應帶：

```bash
--dart-define=PRIVACY_POLICY_URL=https://ou931023.github.io/pet_companion_app/privacy.html
--dart-define=TERMS_OF_SERVICE_URL=https://ou931023.github.io/pet_companion_app/terms.html
--dart-define=SUPPORT_URL=https://ou931023.github.io/pet_companion_app/support.html
--dart-define=CONTACT_EMAIL=aicompanion.support@gmail.com
```
> （避免長者點到不存在的頁面）。

驗收：

- [ ] App 內設定頁顯示支援說明，且不顯示 `TODO_*` / placeholder 字樣。
- [ ] 注入 `SUPPORT_URL` 後，設定頁顯示「聯絡支援」入口。
- [ ] 注入 `CONTACT_EMAIL` 後，設定頁顯示「寫信給客服」入口。
- [ ] App Store Connect / Google Play Console 的 support URL / email 與 dart-define 一致。

### 8.2 Migrations 實跑（`backend/stt_proxy/db/migrations/`）

- [ ] `010_create_consent_records.sql`
- [ ] `011_create_care_alerts.sql`（`care_alerts` / `care_alert_status_events`）
- [ ] `012_create_notification_audit_logs.sql`（`notification_logs` / `audit_logs`）
- [ ] `017_create_app_usage_events.sql`（CR-0097；App 使用時間、語音/打字互動、寵物互動、提醒/任務、照片驗證、小遊戲事件）

> production 啟用 PG 後需於正式 DB 實跑（`db/migrate.js`），確認上述表存在。

### 8.3 Usage tracking privacy disclosure（CR-0097）

- [x] App 內同意畫面 / 隱私政策已揭露 `app_usage_events` 對應的使用紀錄。
- [ ] Hosted 隱私政策正式頁面同步 App 內文。
- [ ] Google Play Data Safety 申報 App 活動 / 使用分析資料。
- [ ] App Store Privacy Nutrition Labels 申報 App 活動 / 使用分析資料。
- [ ] 後台 / 管理端只顯示彙整後使用狀況，不顯示不必要的完整對話或敏感原文。

### 8.4 iOS / Android 上架身份正式化

- [x] iOS Bundle ID：✅ `tw.edu.ncyu.im.aicompanion`（CR-0061 owner 拍板）
- [x] Android applicationId：✅ `tw.edu.ncyu.im.aicompanion`（CR-0061，對齊 iOS）
      （namespace 維持 `com.example.pet_companion_app`，owner 指定不動）
- [x] App 顯示名稱：✅ iOS `CFBundleDisplayName` / Android `android:label` = `AI陪伴`
      （英文品牌 `AI Companion` 可放商店描述 / 關鍵字，CR-0101B）
- [x] App icon / launch screen / 權限文案（麥克風、通知）正式化
- [x] repo 自動檢查確保 production 無 debug banner、無「Demo / 測試 / 開發中」使用者可見入口

---

## 9. 相關文件

- `docs/STORE_SUBMISSION_RUNBOOK.md` — App Store / Google Play 送審前單一 smoke Runbook。
- `docs/FINAL_STORE_BLOCKER_BOARD.md` — 最後上架 Go / No-Go 作戰表。
- `docs/ENVIRONMENT_SETUP.md` — 三環境啟動步驟與排查。
- `PROJECT_ARCHITECTURE.md` §7.1 / §7.1.1 / §5.3.1。
- `backend/stt_proxy/.env.example` — 後端環境變數分區範本。
- `backend/stt_proxy/config/env.js` — fail-fast 與 mask helper 實作。
