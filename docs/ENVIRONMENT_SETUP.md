# Environment Setup（環境啟動指南）

> 對象：開發 / 部署本系統的工程人員。
> 範圍：backend（`backend/stt_proxy`）、Flutter 長者 App、caregiver_web 三端，
> 涵蓋 development / staging / production 三環境。
> 治理依據：`PROJECT_ARCHITECTURE.md` §7.1 / §7.1.1 / §5.3.1、CR-0034。
>
> 紅線：不要把 `.env`、任何 token / API key 進版控；本文件只列「變數名稱與用途」，
> 不含任何真實值。production 上線前請對照 `docs/PRODUCTION_CONFIG_CHECKLIST.md`。

三環境語義（`backend/stt_proxy/config/env.js`）：

- 顯式 `APP_ENV` 優先（`development` | `staging` | `production`）。
- 否則 `NODE_ENV=production` → production，其餘 → development。
- `NODE_ENV=test` 永不解析為 production（保護既有測試基線）。

---

## 1. Development（本機開發）

### Backend

```bash
cd backend/stt_proxy
cp .env.example .env        # 首次：複製範本後填入本機值（OPENAI_API_KEY 等）
npm install
npm start                   # 或 node server.js
```

- 預設 `APP_ENV=development`：不觸發 production fail-fast，允許 JSON fallback 與 mock auth。
- 純本機 / 模擬器：`HOST=127.0.0.1` 即可；iPhone 實機 Demo：`HOST=0.0.0.0`，
  讓同一 Wi-Fi 下的 iPhone 連得到後端。
- DB 可選：不設 `DATABASE_URL` 時其他功能走 JSON store；要測 pgvector / Admin Users
  需 `PGVECTOR_ENABLED=true` 且設 `DATABASE_URL`。
- 健康檢查：`GET /health`。

### Flutter（長者 App）

```bash
flutter pub get
flutter run                 # 預設 APP_ENV=development、API_BASE_URL=http://127.0.0.1:3001
```

- iPhone 實機需指向後端電腦的區網位址：

```bash
flutter run --dart-define=API_BASE_URL=http://<後端電腦區網IP>:3001
```

- dart-define 名稱（見 `lib/config/app_config.dart`）：`APP_ENV`、`API_BASE_URL`
  （舊別名 `BACKEND_BASE_URL`）、`ALLOW_MOCK_SERVICES`、`SHOW_DEV_PANELS`、
  `SHOW_DEMO_LOGIN`、`CARE_MALL_URL`。

### caregiver_web（長照管理端）

- 用任意靜態伺服器開啟 `caregiver_web/index.html`（例如 VS Code Live Server）。
- API base 解析順序（`app.js getApiBase`）：頁面「連線設定」手動輸入 →
  `window.APP_CONFIG.apiBaseUrl` → 同源相對路徑 `/api`。
- 本機通常在頁面「連線設定」填入 `http://127.0.0.1:3001/api`，或在
  `config.js`（複製自 `config.example.js`）設 `apiBaseUrl`。

---

## 2. Staging（預備 / 驗收）

與 production 同流程，但旗標較寬鬆（見 §7.1 對照表）：

```bash
cd backend/stt_proxy
APP_ENV=staging node server.js
```

- `ALLOW_MOCK_SERVICES=false`、`REQUIRE_AUTH=true`、`ENABLE_VERBOSE_LOGS=false`。
- `ALLOW_JSON_FALLBACK` 可視需要設定（不像 production 強制 false）。
- `CORS_ALLOWED_ORIGINS` 建議填 staging 網域白名單。
- Flutter：`--dart-define=APP_ENV=staging --dart-define=API_BASE_URL=https://staging.your-domain.com`。
- caregiver_web：`window.APP_CONFIG.apiBaseUrl` 指向 staging 後端。

---

## 3. Production（正式）

### 3.1 必要環境變數（只列名稱，值放部署環境的 `.env` / secret manager）

production fail-fast 必檢（缺任一即 `process.exit(1)`）：

- `DATABASE_URL`
- `OPENAI_API_KEY`
- `CORS_ALLOWED_ORIGINS`（空白單也算缺）
- Firebase 服務帳戶（擇一）：`GOOGLE_APPLICATION_CREDENTIALS`，或
  `FIREBASE_PROJECT_ID` + `FIREBASE_CLIENT_EMAIL` + `FIREBASE_PRIVATE_KEY` 三件組
- `ADMIN_API_TOKEN`

條件必檢（功能啟用才檢）：

- `TELEGRAM_BOT_TOKEN`（設了 `TELEGRAM_CARE_CHAT_ID` 視為啟用 Telegram 通知）
- `PGVECTOR_ENABLED=true` 時須有 `DATABASE_URL`

不安全旗標（顯式設定即拒絕啟動）：

- `ALLOW_JSON_FALLBACK=true`、`ALLOW_MOCK_SERVICES=true`、`REQUIRE_AUTH=false`

> 完整清單與待辦見 `docs/PRODUCTION_CONFIG_CHECKLIST.md`。

### 3.2 Backend production start（含 fail-fast 行為）

```bash
cd backend/stt_proxy
APP_ENV=production node server.js
# 或 NODE_ENV=production node server.js
```

fail-fast 行為（`config/env.js assertProductionEnvOrExit`）：

- 啟動時於掛路由前驗證一次。缺必要變數或設定不安全旗標時，印出
  **只含變數名稱**的訊息（絕不印任何 token / secret 值），然後 `process.exit(1)`。
- 訊息範例（節錄，僅列名稱）：

```
[config] 正式環境啟動中止：缺少或設定不安全的必要環境變數（僅列名稱，未含任何值）：
  - DATABASE_URL
  - OPENAI_API_KEY
  - CORS_ALLOWED_ORIGINS
請在部署環境補齊上述設定後重新啟動。
```

- 啟動成功會印一份「一律遮蔽」的設定摘要（`describeMaskedConfig`）：
  `postgres://***`、`sk-***last4`、`ou***@example.com`、chat id 僅 `(set)/(unset)`。

### 3.3 Flutter production build

```bash
# Android
flutter build apk --release \
  --dart-define=APP_ENV=production \
  --dart-define=API_BASE_URL=https://api.your-domain.com \
  --dart-define=SHOW_DEV_PANELS=false \
  --dart-define=SHOW_DEMO_LOGIN=false \
  --dart-define=ALLOW_MOCK_SERVICES=false

# iOS
flutter build ios --release --no-codesign \
  --dart-define=APP_ENV=production \
  --dart-define=API_BASE_URL=https://api.your-domain.com \
  --dart-define=SHOW_DEV_PANELS=false \
  --dart-define=SHOW_DEMO_LOGIN=false \
  --dart-define=ALLOW_MOCK_SERVICES=false
```

- production 下 `AppConfig` 一律強制關閉開發面板、Demo 登入與 mock 注入
  （即使 dart-define 傳 true 也被 `&& !isProduction` 蓋掉）。
- `API_BASE_URL` 必須是正式 https 網域；若為 localhost / 127.0.0.1 / 10.0.2.2 / 空，
  `isApiBaseUrlProductionSafe` 回 false，App 會顯示長者友善的「服務暫時無法使用」守門畫面，
  不進入正式主流程（避免長者連到不存在的本機服務）。

### 3.4 caregiver_web production config

二擇一：

- A. 設 `window.APP_CONFIG.apiBaseUrl = "https://api.your-domain.com/api"`
  （複製 `config.example.js` 為 `config.js` 填值，於 `app.js` 前載入；`config.js` 不進版控）。
- B. 把 caregiver_web 與後端放同網域 / 反向代理，讓 `/api` 同源相對路徑直接可用
  （`apiBaseUrl` 留 `null`）。

不可把 `http://127.0.0.1:3001/api` 當成正式預設。

### 3.5 production 不允許的旗標（重申）

- `ALLOW_JSON_FALLBACK=true` / `ALLOW_MOCK_SERVICES=true` / `REQUIRE_AUTH=false` → 啟動失敗。
- Flutter `SHOW_DEV_PANELS` / `SHOW_DEMO_LOGIN` 即使傳 true 也被強制隱藏。
- marketplace / dailyCareTask（JSON-only）在 production 一律被 guard 阻擋
  （長者友善訊息），屬 **CR-0042 blocker**（見 §5.3.1）。

---

## 4. 常見錯誤與排查

| 現象 | 可能原因 | 處理 |
|---|---|---|
| production backend 啟動即退出，log 列出一串變數名稱 | fail-fast：缺必要 env 或設了不安全旗標 | 對照 §3.1 補齊；移除 `ALLOW_JSON_FALLBACK=true` / `ALLOW_MOCK_SERVICES=true` / `REQUIRE_AUTH=false` |
| Flutter production build 開啟後停在「服務暫時無法使用」守門畫面 | `API_BASE_URL` 為 localhost / 空 → `isApiBaseUrlProductionSafe=false` | build 時帶 `--dart-define=API_BASE_URL=https://正式網域` |
| caregiver_web 抓不到資料 / CORS 被擋 | `apiBaseUrl` 未設或後端 `CORS_ALLOWED_ORIGINS` 未含該網域 | 設 `window.APP_CONFIG.apiBaseUrl`；後端白名單加入該前端網域 |
| `GET /api/admin/users` 回 `failed_to_load_users` | 此 API 只走 PostgreSQL，未開 PG | 設 `PGVECTOR_ENABLED=true` 且 `DATABASE_URL` |
| Care Alert 通知回 `telegram_not_configured` | 缺 `TELEGRAM_BOT_TOKEN` 或 `TELEGRAM_CARE_CHAT_ID` | 補齊兩者（production 設了 chat id 卻缺 token 會 fail-fast） |
| 看不到開發面板 / Demo 登入按鈕 | production 強制隱藏，或未開 `SHOW_DEV_PANELS` / `SHOW_DEMO_LOGIN` | 僅在非 production build 時用 dart-define 開啟 |
| production care alert 持久化失敗 | DB 例外 + production DB-required（不降級 JSON） | 修復 DB；通知仍照送，失敗以 `notification_logs` 記錄（見 §5.3.1） |

---

## 5. 相關文件

- `docs/PRODUCTION_CONFIG_CHECKLIST.md` — production 上線前檢查表。
- `PROJECT_ARCHITECTURE.md` §7.1 / §7.1.1 — 環境 / flag 治理與 fail-fast 規格。
- `PROJECT_ARCHITECTURE.md` §5.3.1 — production JSON fallback 政策。
- `backend/stt_proxy/.env.example` — 後端環境變數分區範本。
- `lib/config/app_config.dart` — Flutter dart-define 與 production 守門邏輯。
- `caregiver_web/config.example.js` — caregiver_web API base URL 設定範本。
