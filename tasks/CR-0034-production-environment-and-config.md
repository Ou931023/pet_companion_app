# CR-0034：Production Environment and Config

## 任務名稱

Production Environment and Config 正式環境設定與正式版開關隔離

## 任務背景

本專案正在從畢業專題 Demo 升級為可正式上架 iOS App Store 與 Google Play 的 production-ready 版本。CR-0034 的目標是建立清楚、可維護、可驗證的正式環境設定機制，避免 production build 誤用 demo、mock、fake data、debug panel 或 JSON fallback。

請先閱讀根目錄 `CLAUDE.md`，再執行本任務。

---

## 一、任務目標

請建立 development / staging / production 三種環境的設定治理方式，並確保正式環境具備 fail-fast 驗證能力。

正式版必須符合以下原則：

1. production 不可啟用 demo-only code。
2. production 不可啟用 mock service。
3. production 不可顯示 debug panel。
4. production 不可依賴 JSON fallback 作為主要資料來源。
5. production 缺少必要環境變數時，後端必須啟動失敗並清楚提示缺少哪些設定。
6. 所有敏感資訊只能透過環境變數或安全設定提供，不可寫死於程式碼。
7. Flutter、Node.js backend、caregiver_web 的正式環境設定必須一致且可文件化。

---

## 二、任務範圍

請檢查並修改以下範圍：

1. Flutter App
   - build flavor / dart-define / compile-time config
   - app config
   - dev panel flag
   - mock service flag
   - production UI 行為

2. Node.js Backend
   - environment config loader
   - production required env validation
   - JSON fallback 控制
   - mock/dev routes 控制
   - sensitive log masking

3. Caregiver Web
   - API base URL 設定
   - dev/prod config 分離
   - debug UI 隔離

4. Project Docs
   - `.env.example`
   - environment setup 文件
   - production readiness 文件
   - `docs/CHANGE_REVIEW.md`

---

## 三、正式環境設定需求

### 3.1 環境名稱

請統一支援以下環境名稱：

```text
development
staging
production
```

不得在正式流程中使用模糊環境名稱，例如：

```text
testmode
real_demo
prod_test
temporary
```

若目前已有不同命名，請先盤點，再以相容方式收斂，不要一次造成大量破壞。

---

### 3.2 必要正式版 flag

請建立或統一以下設定：

```text
APP_ENV=development|staging|production
SHOW_DEV_PANELS=false in production
ALLOW_MOCK_SERVICES=false in production
ALLOW_JSON_FALLBACK=false in production
REQUIRE_AUTH=true in production
REQUIRE_CONSENT=true in production
ENABLE_VERBOSE_LOGS=false in production
```

如果 Flutter 與 backend 使用不同命名，請建立對應表並文件化。

---

### 3.3 Backend production fail-fast

當 `APP_ENV=production` 或 `NODE_ENV=production` 時，後端必須檢查必要設定。

至少檢查：

```text
DATABASE_URL
OPENAI_API_KEY
SESSION_SECRET or JWT_SECRET
CORS_ALLOWED_ORIGINS
```

若專案已使用以下功能，請一併檢查：

```text
TELEGRAM_BOT_TOKEN
ADMIN_API_TOKEN
PGVECTOR_ENABLED
PUBLIC_APP_URL
PRIVACY_POLICY_URL
SUPPORT_URL
```

正式環境缺少必要設定時：

1. 不可靜默啟動。
2. 不可自動切回 JSON fallback。
3. 不可自動切到 mock service。
4. 必須輸出安全的錯誤訊息，說明缺少哪些環境變數。
5. 錯誤訊息不可印出 token 或 secret 的值。

---

### 3.4 JSON fallback 控制

正式環境不允許 JSON fallback 作為主要資料來源。

請檢查所有類似以下資料：

```text
data/*.json
local json store
file based fallback
in-memory fallback
mock resident data
mock care alert data
mock memory data
```

要求：

1. development 可保留 JSON fallback。
2. test 可保留 mock / fixture。
3. production 必須停用 JSON fallback。
4. production 若無 DATABASE_URL，必須 fail fast。
5. 若某些舊 service 還沒完全改 PostgreSQL，請先以清楚的 guard 阻止 production 使用，並列入下一個 CR 的 blocker。

---

### 3.5 Flutter production config

請檢查 Flutter 專案是否已有 app config。

需要支援：

```text
--dart-define=APP_ENV=production
--dart-define=API_BASE_URL=https://正式後端網址
--dart-define=SHOW_DEV_PANELS=false
--dart-define=ALLOW_MOCK_SERVICES=false
```

正式版要求：

1. 不顯示 debug banner。
2. 不顯示 dev panel。
3. 不顯示 Demo / Test / Mock 字樣。
4. 不允許 mock service 被使用。
5. API base URL 不可硬編在 UI 頁面中。
6. 權限說明、錯誤訊息不可出現工程字眼。

如果目前尚未有 flavor 架構，請優先建立低風險的 `AppConfig` / `EnvironmentConfig`，不要大幅重構整個 Flutter 專案。

---

### 3.6 Caregiver Web config

請檢查 caregiver_web 是否有正式 API URL 設定。

要求：

1. API base URL 需可依環境切換。
2. 不可硬編 localhost 作為 production 預設。
3. production 不可顯示 debug panel。
4. production 不可使用 fake alert / fake user data。
5. 若目前是純靜態網頁，也需建立清楚的 config loading 策略。

---

### 3.7 Sensitive log masking

請檢查後端與前端 log。

正式環境不得輸出：

```text
OPENAI_API_KEY
TELEGRAM_BOT_TOKEN
DATABASE_URL full value
JWT_SECRET
SESSION_SECRET
ADMIN_API_TOKEN
完整 email
完整 phone
完整原始對話內容
完整 Care Alert 敏感摘要
```

若需要紀錄，請遮蔽，例如：

```text
ou***@example.com
0912***789
sk-***last4
postgres://***
```

---

## 四、建議實作步驟

請依照以下順序執行。

### Step 1：盤點目前設定

請先搜尋並整理：

```text
process.env
NODE_ENV
APP_ENV
DATABASE_URL
OPENAI_API_KEY
TELEGRAM
ADMIN_API_TOKEN
PGVECTOR
SHOW_DEV
MOCK
DEMO
FALLBACK
localhost
127.0.0.1
data/*.json
```

請列出目前設定分散在哪些檔案。

---

### Step 2：建立後端 config validation

建立或修正 backend config 模組。

建議方向：

1. 統一讀取 env。
2. 正規化 APP_ENV。
3. 建立 `isProduction` 判斷。
4. 在 production 啟動時執行 required env check。
5. 對 boolean env 做安全解析。
6. 對敏感資訊提供 masked logging helper。

請避免在多個 service 中各自解析 env，應盡量集中管理。

---

### Step 3：隔離 fallback / mock / dev panel

請把正式版不得使用的功能加上 guard。

例如：

```text
if (config.isProduction && config.allowJsonFallback) throw error
if (config.isProduction && config.allowMockServices) throw error
if (config.isProduction && showDevPanels) force false or fail validation
```

---

### Step 4：整理 Flutter config

建立或修正 Flutter 端設定來源。

至少支援：

```dart
const appEnv = String.fromEnvironment('APP_ENV', defaultValue: 'development');
const apiBaseUrl = String.fromEnvironment('API_BASE_URL');
const showDevPanels = bool.fromEnvironment('SHOW_DEV_PANELS', defaultValue: false);
const allowMockServices = bool.fromEnvironment('ALLOW_MOCK_SERVICES', defaultValue: false);
```

正式環境下：

```text
APP_ENV=production
SHOW_DEV_PANELS=false
ALLOW_MOCK_SERVICES=false
```

若 `APP_ENV=production` 但 `API_BASE_URL` 為 localhost 或空值，需避免正式 build 使用，或在啟動時給出清楚錯誤並阻止進入正式主流程。

---

### Step 5：整理 `.env.example`

請更新 `.env.example`，至少分區：

```text
# Environment
# Server
# Database
# OpenAI
# Auth / Session
# Telegram Notification
# Admin / Caregiver Web
# Privacy / Store Links
# Development-only Flags
```

每個變數需說明用途，但不可放真實 secret。

---

### Step 6：建立文件

請建立或更新：

```text
docs/ENVIRONMENT_SETUP.md
docs/PRODUCTION_CONFIG_CHECKLIST.md
docs/CHANGE_REVIEW.md
```

文件至少說明：

1. development 如何啟動。
2. staging 如何啟動。
3. production 必要環境變數。
4. Flutter production build 範例。
5. Backend production start 範例。
6. caregiver_web production config。
7. production 不允許的 flag。
8. 常見錯誤與排查方式。

---

## 五、測試要求

請執行可用的測試。

### Backend

```bash
npm test
npm run check
npm run lint
```

若某些指令不存在，請明確回報，不要假裝已執行。

請至少新增或確認測試涵蓋：

1. production 缺 DATABASE_URL 時 fail fast。
2. production 缺 OPENAI_API_KEY 時 fail fast。
3. production 不允許 ALLOW_JSON_FALLBACK=true。
4. production 不允許 ALLOW_MOCK_SERVICES=true。
5. sensitive value 不會完整出現在 masked log helper 輸出。

### Flutter

```bash
flutter analyze
flutter test
```

若時間或環境限制無法跑完整 build，請至少跑 analyze 與相關 unit tests。

### Optional release build check

若環境允許，請執行：

```bash
flutter build apk --release --dart-define=APP_ENV=production --dart-define=SHOW_DEV_PANELS=false --dart-define=ALLOW_MOCK_SERVICES=false
flutter build ios --release --no-codesign --dart-define=APP_ENV=production --dart-define=SHOW_DEV_PANELS=false --dart-define=ALLOW_MOCK_SERVICES=false
```

如果失敗，請記錄失敗原因與下一步，不要硬修無關問題。

---

## 六、驗收標準

本 CR 完成時必須符合：

1. 有明確 development / staging / production 環境設定策略。
2. production 缺必要 env 時，後端會 fail fast。
3. production 不會自動使用 JSON fallback。
4. production 不會啟用 mock service。
5. production 不會顯示 debug panel。
6. Flutter 有正式版 config 來源。
7. caregiver_web 有正式 API URL 設定策略。
8. `.env.example` 已更新。
9. `docs/ENVIRONMENT_SETUP.md` 已建立或更新。
10. `docs/PRODUCTION_CONFIG_CHECKLIST.md` 已建立或更新。
11. `docs/CHANGE_REVIEW.md` 已新增 CR-0034 紀錄。
12. 測試已執行，或清楚說明無法執行的原因。

---

## 七、禁止事項

本任務禁止：

1. 不可把真實 API key 寫進任何檔案。
2. 不可提交 `.env`。
3. 不可移除 Realtime WebRTC 主流程。
4. 不可移除 Care Alert。
5. 不可移除長期記憶。
6. 不可將 production 缺設定時自動切到 mock。
7. 不可為了通過測試硬編假資料。
8. 不可把 JSON fallback 當作正式資料庫。
9. 不可大規模重寫架構導致主流程壞掉。
10. 不可假裝已完成 App Store / Google Play 後台設定。

---

## 八、回報格式

完成後請用以下格式回報：

```md
## CR-0034 完成回報

### 1. 本次目標
- 

### 2. 修改檔案
- 

### 3. 主要修改
- 

### 4. Production config 驗證結果
- APP_ENV：
- production required env check：
- JSON fallback guard：
- mock service guard：
- dev panel guard：
- sensitive log masking：

### 5. 測試結果
- backend：
- Flutter：
- caregiver_web：
- build check：

### 6. 正式版風險檢查
- 是否仍有 production 可用 mock：
- 是否仍有 production 可用 JSON fallback：
- 是否仍有 hardcoded secret：
- 是否仍有 localhost production 預設：
- 是否影響 Realtime：
- 是否影響 Memory：
- 是否影響 Care Alert：

### 7. 尚未完成與下一步
- 
```

---

## 九、建議提交訊息

```text
CR-0034 production environment config hardening
```
