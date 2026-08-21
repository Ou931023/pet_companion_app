# Backend Deployment Guide — `backend/stt_proxy` 部署到 Render + Neon

> 對象：要把本系統 Node 後端（`backend/stt_proxy`）部署成正式 HTTPS 服務的人。
> 範圍：**docs-only**。本文件只說明部署步驟與「需要哪些環境變數名稱」，**不含任何真實值、不印 secret**。
> 來源依據（程式真相）：`backend/stt_proxy/config/env.js`（env 契約 + production fail-fast）、`server.js`（PORT/HOST/health）、`db/migrate.js` + `db/pool.js`（migration）、`db/postgres.js`（runtime pool）。
> 對照：`docs/ENVIRONMENT_SETUP.md §3`（三環境語義與 production 必要變數總表）、`docs/PRODUCTION_CONFIG_CHECKLIST.md`、`docs/STORE_RELEASE_CHECKLIST.md`、`docs/RELEASE_HANDOFF.md`。
> 紅線：不要把 `.env` / keystore / Firebase service account / token 進版控；本文件不替任何 secret 給值。
> 推薦上線路線：**Render Web Service + Neon Postgres（pgvector）+ GitHub Pages legal/support site**。

---

## 0. TL;DR（最容易踩雷的四件事）

1. **`HOST` 必須設成 `0.0.0.0`**。程式預設 `HOST=127.0.0.1`（`server.js:165`），在 Render / Railway 上會導致服務「啟動成功卻無法被路由連到」。
2. **`PGVECTOR_ENABLED=true` 必須顯式開啟**。它**不在** fail-fast 必檢清單內，但 runtime Postgres pool（`db/postgres.js:14`）在沒有它時會回傳 `null` → 長期記憶 / Admin Users / care alert 持久化等功能不會用 DB。設了 `DATABASE_URL` 卻忘了這個，會「靜默」少一半功能。
3. **`DATABASE_URL` 的 SSL**。`db/pool.js` / `db/postgres.js` 直接把 `DATABASE_URL` 丟給 `pg`，**沒有**額外設 `ssl` 選項。雲端託管 PG 多半要求 TLS → 若連線報 SSL 錯，請在連線字串尾端加 `?sslmode=require`（自簽憑證用 `?sslmode=no-verify`）。**不需要改程式**，只改連線字串。
4. **Render Free 可用來先跑正式 HTTPS smoke，但會休眠**。語音陪伴 App 正式送審前建議升級到 always-on；否則長者第一次開 App 可能遇到冷啟動等待。

---

## 0.5 最省錢推薦架構

```text
Flutter App / caregiver_web
  -> Render HTTPS Web Service
      -> backend/stt_proxy Node.js Express
      -> Neon Postgres + pgvector
      -> OpenAI Realtime / Firebase Admin / Telegram

GitHub Pages
  -> privacy.html / terms.html / support.html
```

- **法律頁**：維持 GitHub Pages，已是 HTTPS 靜態網站。
- **後端 API**：Render Web Service，Root Directory 指向 `backend/stt_proxy`。
- **資料庫**：Neon Postgres，migration 啟用 `pgcrypto` 與 `vector`。
- **正式 App build**：`API_BASE_URL` 指向 Render 給的 HTTPS URL。
- **正式送審前 No-Go**：若仍使用會休眠的免費 web service，必須在 `docs/E2E_SMOKE_TEST_REPORT.md` 記錄冷啟動行為；若語音首次連線等待太久，應升級 always-on。

---

## 1. 後端啟動行為盤點（程式真相）

| 項目 | 行為 | 來源 |
|---|---|---|
| 啟動指令 | `node server.js`（= `npm start` = `npm run dev`） | `package.json` scripts |
| 進入點 | `server.js`；啟動最前面呼叫 `assertProductionEnvOrExit(process.env, console)` | `server.js:23` |
| PORT | `process.env.PORT || 3001` | `server.js:133` |
| HOST | `process.env.HOST || "127.0.0.1"` ← **PaaS 需設 `0.0.0.0`** | `server.js:165` |
| listen | `app.listen(port, host, …)`，啟動時 log 一份**遮蔽過**的設定摘要（`describeMaskedConfig`，不印完整值） | `server.js:2793-2794` |
| health check | `GET /health` → `{ status:"ok", hasOpenAiKey:<bool>, realtimeModel, time }`（**只回布林，不回 key**） | `server.js:554` |
| Node 版本 | `package.json` 無 `engines` 欄位；建議在平台指定 **Node 20 LTS 以上**（開發機為 v24） | — |

### `package.json` scripts

| script | 內容 | 用途 |
|---|---|---|
| `npm start` / `npm run dev` | `node server.js` | 啟動服務 |
| `npm run db:migrate` | `node db/migrate.js` | 套用 DB 擴充 + migration（見 §6） |
| `npm run check` | 一連串 `node --check`（語法檢查，不連線） | CI / 部署前快速健檢 |
| `npm test` | `node --test …`（495 案，使用 stub / mock pg，不需真環境） | 回歸測試 |

> production 啟動語義（`config/env.js`）：顯式 `APP_ENV=production` 優先；否則 `NODE_ENV=production` → production。`NODE_ENV=test` 永不解析為 production。

---

## 2. Production 必要環境變數清單（只列名稱，**不含值**）

依 `config/env.js validateProductionEnv()`，production 啟動會 fail-fast（缺任一 → 印「只含變數名稱」訊息後 `process.exit(1)`）。

### 2.1 fail-fast 必檢（缺一即拒絕啟動）

| 變數名稱 | 用途 |
|---|---|
| `DATABASE_URL` | PostgreSQL 連線字串（pgvector 長期記憶 / 授權 / care alert 持久化） |
| `OPENAI_API_KEY` | OpenAI Realtime / STT / chat / embedding |
| `CORS_ALLOWED_ORIGINS` | 允許的前端來源（逗號分隔）。相容舊別名 `ALLOWED_ORIGINS`（新名優先） |
| Firebase 服務帳戶（**擇一組**） | 後端驗證 Firebase idToken。① `GOOGLE_APPLICATION_CREDENTIALS`（指向 JSON 檔路徑）**或** ② `FIREBASE_PROJECT_ID` + `FIREBASE_CLIENT_EMAIL` + `FIREBASE_PRIVATE_KEY` 三件組 |
| `ADMIN_API_TOKEN` | caregiver_web / 管理端 API 的管理者權杖 |

### 2.2 條件必檢（啟用該功能才需要）

| 變數名稱 | 用途 |
|---|---|
| `TELEGRAM_CARE_CHAT_ID` | 設了它＝啟用 Telegram 照護通知 |
| `TELEGRAM_BOT_TOKEN` | **一旦設了 `TELEGRAM_CARE_CHAT_ID` 就成為必填**（否則 fail-fast） |

### 2.3 production 嚴禁的旗標（顯式設成下列「不安全值」會被拒絕啟動）

| 變數名稱 | production 必須 |
|---|---|
| `ALLOW_JSON_FALLBACK` | 不可為 `true`（不設或 `false`） |
| `ALLOW_MOCK_SERVICES` | 不可為 `true` |
| `REQUIRE_AUTH` | 不可為 `false`（不設或 `true`） |

### 2.4 不在 fail-fast、但 production 實務上必設

| 變數名稱 | 建議值 | 為什麼 |
|---|---|---|
| `APP_ENV` | `production` | 觸發正式語義與 fail-fast |
| `HOST` | `0.0.0.0` | 否則 PaaS 連不到（見 §0） |
| `PGVECTOR_ENABLED` | `true` | 否則 runtime 不會用 Postgres（見 §0） |
| `PORT` | 由平台自動注入（Render/Railway 會給）→ 程式會讀 | 本機預設 3001 |

### 2.5 選用調校（有預設值，可不設）

`PG_POOL_MAX`（預設 10）、`PG_IDLE_TIMEOUT_MS`（30000）、`PG_CONNECTION_TIMEOUT_MS`（2000）、`REALTIME_MODEL`（`gpt-realtime`）、`TAIGI_ASR_MAX_UPLOAD_BYTES`（10MB）。

> 完整三環境對照見 `docs/ENVIRONMENT_SETUP.md §3`；本表為 Render/Railway 部署精簡版。

---

## 3. 共通前置

1. **Postgres 需支援 `vector` 擴充（pgvector）**。migration 會 `CREATE EXTENSION IF NOT EXISTS vector`（`db/migrate.js:8-11`）；選的 PG 必須能裝 pgvector，否則 migration 失敗。
   - 推薦：Neon Postgres（支援 extension，適合先用免費方案 smoke）。
   - 備案：Render Postgres / Railway Postgres / Supabase Postgres，只要能建立 `vector` extension。
2. **Monorepo root**：後端在子目錄 `backend/stt_proxy`，部署時要把 **Root Directory 設成 `backend/stt_proxy`**（否則找不到 `package.json`）。
3. **Firebase 私鑰換行**：用三件組時，`FIREBASE_PRIVATE_KEY` 在環境變數 UI 內常需把實際換行寫成 `\n` 字面字串（後端 firebase-admin 初始化會處理）。若驗證 idToken 失敗，多半是換行被吃掉——**請勿把私鑰貼進程式碼或 git，只放部署環境 secret**。

---

## 4. Neon 建立 PostgreSQL / pgvector

> 目標：拿到一個 production `DATABASE_URL`，並確認 pgvector migration 能跑。

1. Neon Dashboard → New Project。
2. Project name 建議：`ai-companion-production`。
3. Region 儘量選與 Render Web Service 接近的區域，降低 Realtime 工具呼叫與 DB 延遲。
4. 建立 database，例如 `aicompanion`。
5. 到 Connection Details 複製連線字串給 Render 的 `DATABASE_URL` 使用。
   - 只放在 Render Environment。
   - 不寫進 repo、文件、issue、PR、截圖。
   - 若連線或 migration 顯示 SSL 問題，在 connection string 尾端使用平台建議的 SSL 參數，例如 `sslmode=require`。
6. migration 會自動執行：
   - `CREATE EXTENSION IF NOT EXISTS pgcrypto`
   - `CREATE EXTENSION IF NOT EXISTS vector`
   - `db/migrations/*.sql`

> 驗收重點：`npm run db:migrate` 成功印出 `[DB] migrations completed`。這比 `/health` 更重要，因為後台真數據、`app_usage_events`、長期記憶與 Care Alert 都靠 migration。

---

## 5. Render 部署 Web Service

> 目標：一個 Render **Web Service**，提供正式 HTTPS API 給 Flutter App 與 caregiver_web。

1. Render Dashboard → New → Web Service → Connect GitHub repo。
2. Web Service 設定：
   - **Root Directory**：`backend/stt_proxy`
   - **Build Command**：`npm ci`（或 `npm install`）
   - **Start Command**：`node server.js`
   - **Health Check Path**：`/health`
   - Node 版本：在環境變數設 `NODE_VERSION=20`（或更新）以固定 runtime。
3. Plan：
   - Free 可以先跑 production-like smoke。
   - 正式送審前建議改 always-on，避免後端休眠造成 Realtime 首次連線等待。
4. 設定環境變數（Service → Environment）：把 §2 的變數逐一加入。
   - `DATABASE_URL` = Neon connection string。
   - `APP_ENV=production`、`HOST=0.0.0.0`、`PGVECTOR_ENABLED=true`。
   - `PORT` 由 Render 自動注入，**不用手動設**。
   - `CORS_ALLOWED_ORIGINS` 填公開 HTTPS 前端來源，例如 caregiver_web 的 GitHub Pages / Render Static Site / 自訂網域。多個來源用逗號分隔；不要用 `*`。
   - 其餘 secret（`OPENAI_API_KEY` / `ADMIN_API_TOKEN` / Firebase / Telegram）一律用 Environment / Secret，**不進 git**。
5. Deploy。
6. 若 deploy 失敗且 log 只列缺少變數名稱，代表 production fail-fast 正常運作；補齊對應變數後重 deploy。
7. Deploy 成功後，記下 Render HTTPS URL，例如 `https://<service-name>.onrender.com`。這就是 App 的 `API_BASE_URL`。

---

## 6. 執行資料庫 migration

migration 程式：`db/migrate.js`（透過 `db/pool.js` 讀 `DATABASE_URL`）。動作：先 `CREATE EXTENSION pgcrypto / vector`，再依序套用 `db/migrations/001…017`（共 17 個 `.sql`）。其中：

- `015_marketplace_pg_seed.sql`：marketplace 表 id 放寬為 TEXT 並灌入 15 筆 `seed-*` 種子商品。
- `016_create_daily_care_tasks.sql`：建立 `daily_care_tasks` / `daily_care_task_submissions`。
- `017_create_app_usage_events.sql`：建立 `app_usage_events`，管理者 / 照護者 analytics 需要它才看得到真實使用數據。

**指令（在已設好 `DATABASE_URL` 的環境執行）：**

```bash
cd backend/stt_proxy
npm run db:migrate
```

- **Render**：Service → Shell 進入容器後跑上述指令；或建立 one-off Job（同 repo、Root Directory 同設）以 `npm run db:migrate` 為指令。
- **冪等**：migration 用 `CREATE EXTENSION IF NOT EXISTS` 與各 `.sql`；重跑前請確認各 migration 檔本身可安全重入。成功會印 `[DB] migrations completed`；失敗會印 `[DB] migration failed:` 並 `exitCode=1`。
- migration **需要** `DATABASE_URL`；它**不**讀 `PGVECTOR_ENABLED`（那只影響 runtime pool）。但 runtime 要用到資料就仍需 `PGVECTOR_ENABLED=true`。

---

## 7. Health check 驗證

```bash
curl https://<你的正式網域>/health
```

預期回應（範例形狀，值依環境）：

```json
{ "status": "ok", "hasOpenAiKey": true, "realtimeModel": "gpt-realtime", "time": "2026-..." }
```

- `hasOpenAiKey` 是**布林**（只表示有沒有設 key，**不洩漏 key**）。
- 把這個路徑填到 Render 的 **Health Check Path** = `/health`，讓平台用它判斷服務存活。
- 啟動 log 會有一行遮蔽過的設定摘要（`[config] effective config (masked)`），可用來確認 `databaseUrl`/`openaiApiKey`/`adminApiToken` 等顯示為已設（遮蔽）而非 `(unset)`，但**不會**印出完整值。

---

## 8. 部署後串接（下游）

- **Flutter**：release build 帶 `--dart-define=API_BASE_URL=https://<Render HTTPS URL>`（否則守門畫面會擋）。見 `ENVIRONMENT_SETUP §3.3`。
- **caregiver_web**：`config.js` 指向正式 API URL；把該 origin 加入後端 `CORS_ALLOWED_ORIGINS`。見 `ENVIRONMENT_SETUP §3.4`。
- **transport 收斂**（CR-0054/0055）：HTTPS 後端就緒後，才可套用 iOS ATS / Android cleartext 收斂 patch 並做實機 smoke。
- **真環境 E2E**（CR-0053 Execute）：HTTPS 後端 + 真 PG/Firebase/OpenAI/Telegram 齊全後，依 `E2E_SMOKE_TEST_PLAN` 執行並寫 Run 報告。

### 8.1 App production build 範例

```bash
flutter build appbundle --release \
  --dart-define=APP_ENV=production \
  --dart-define=API_BASE_URL=https://<Render HTTPS URL> \
  --dart-define=PRIVACY_POLICY_URL=https://ou931023.github.io/pet_companion_app/privacy.html \
  --dart-define=TERMS_OF_SERVICE_URL=https://ou931023.github.io/pet_companion_app/terms.html \
  --dart-define=SUPPORT_URL=https://ou931023.github.io/pet_companion_app/support.html \
  --dart-define=CONTACT_EMAIL=aicompanion.support@gmail.com
```

正式 iOS build 同樣帶相同 dart-define。`API_BASE_URL` 不可使用 localhost、LAN IP、ngrok 或暫時 tunnel。

### 8.2 管理者 / 照護者數據驗收

照護者交付、App 行為數據與 Telegram 正式維運請同步依
`docs/CAREGIVER_OPERATIONS_RUNBOOK.md` 執行。該文件是 production 後台交付的單一
runbook：涵蓋 `app_usage_events` 真實數據、照護人員開通 / 授權指派、Telegram Bot
配置、smoke 驗收與 No-Go 條件。

部署完成後，必跑以下 smoke：

1. App 用 production build 開啟一次，確認後端收到 app/session usage event。
2. 語音互動開始 / 結束一次，確認 `voice_interaction_start` / `voice_interaction_end` 寫入 `app_usage_events`。
3. 打字聊天一次，確認 `typed_chat_sent` 寫入。
4. 觸發一筆 medium Care Alert，確認持久化但不推 Telegram。
5. 觸發一筆 high / urgent 測試 Care Alert，確認持久化並推 Telegram（若已啟用）。
6. caregiver_web / admin analytics 以正式 API 讀取，確認顯示真實彙整，不是空殼或假資料。

---

## 9. 安全紅線（部署時務必遵守）

1. 所有 secret（`OPENAI_API_KEY` / `ADMIN_API_TOKEN` / `FIREBASE_PRIVATE_KEY` / `TELEGRAM_BOT_TOKEN` / `DATABASE_URL`）只放部署環境 secret store，**不進 git、不寫死、不貼進文件**。
2. 不要把 `.env`、Firebase service account JSON、keystore 進版控。
3. production **不可**設 `ALLOW_JSON_FALLBACK=true` / `ALLOW_MOCK_SERVICES=true` / `REQUIRE_AUTH=false`（會被 fail-fast 擋下，也違反正式版原則）。
4. log 不可輸出完整 secret / 個資；後端已有 masked logging（`config/env.js` + redaction），維持。
