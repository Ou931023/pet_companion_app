# Backend Deployment Guide — `backend/stt_proxy` 部署到 Render / Railway

> 對象：要把本系統 Node 後端（`backend/stt_proxy`）部署成正式 HTTPS 服務的人。
> 範圍：**docs-only**。本文件只說明部署步驟與「需要哪些環境變數名稱」，**不含任何真實值、不印 secret**。
> 來源依據（程式真相）：`backend/stt_proxy/config/env.js`（env 契約 + production fail-fast）、`server.js`（PORT/HOST/health）、`db/migrate.js` + `db/pool.js`（migration）、`db/postgres.js`（runtime pool）。
> 對照：`docs/ENVIRONMENT_SETUP.md §3`（三環境語義與 production 必要變數總表）、`docs/PRODUCTION_CONFIG_CHECKLIST.md`、`docs/STORE_RELEASE_CHECKLIST.md`、`docs/RELEASE_HANDOFF.md`。
> 紅線：不要把 `.env` / keystore / Firebase service account / token 進版控；本文件不替任何 secret 給值。

---

## 0. TL;DR（最容易踩雷的三件事）

1. **`HOST` 必須設成 `0.0.0.0`**。程式預設 `HOST=127.0.0.1`（`server.js:165`），在 Render / Railway 上會導致服務「啟動成功卻無法被路由連到」。
2. **`PGVECTOR_ENABLED=true` 必須顯式開啟**。它**不在** fail-fast 必檢清單內，但 runtime Postgres pool（`db/postgres.js:14`）在沒有它時會回傳 `null` → 長期記憶 / Admin Users / care alert 持久化等功能不會用 DB。設了 `DATABASE_URL` 卻忘了這個，會「靜默」少一半功能。
3. **`DATABASE_URL` 的 SSL**。`db/pool.js` / `db/postgres.js` 直接把 `DATABASE_URL` 丟給 `pg`，**沒有**額外設 `ssl` 選項。雲端託管 PG 多半要求 TLS → 若連線報 SSL 錯，請在連線字串尾端加 `?sslmode=require`（自簽憑證用 `?sslmode=no-verify`）。**不需要改程式**，只改連線字串。

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

## 3. 共通前置（兩平台都需要）

1. **Postgres 需支援 `vector` 擴充（pgvector）**。migration 會 `CREATE EXTENSION IF NOT EXISTS vector`（`db/migrate.js:8-11`）；選的 PG 必須能裝 pgvector，否則 migration 失敗。
   - Railway：用官方 **pgvector** 模板 / image。
   - Render：用 Render Postgres（近版支援 `CREATE EXTENSION vector`），或自備支援 pgvector 的實例。
2. **Monorepo root**：後端在子目錄 `backend/stt_proxy`，部署時要把 **Root Directory 設成 `backend/stt_proxy`**（否則找不到 `package.json`）。
3. **Firebase 私鑰換行**：用三件組時，`FIREBASE_PRIVATE_KEY` 在環境變數 UI 內常需把實際換行寫成 `\n` 字面字串（後端 firebase-admin 初始化會處理）。若驗證 idToken 失敗，多半是換行被吃掉——**請勿把私鑰貼進程式碼或 git，只放部署環境 secret**。

---

## 4. Render 部署步驟

> 目標：一個 Render **Web Service**（後端）+ 一個 **Postgres**。

1. **建立 Postgres**：Render Dashboard → New → Postgres（選支援 pgvector 的版本）。建立後取得 **Internal Database URL**（同區服務間連線免 SSL 困擾）。
2. **建立 Web Service**：New → Web Service → 連結這個 repo。
   - **Root Directory**：`backend/stt_proxy`
   - **Build Command**：`npm ci`（或 `npm install`）
   - **Start Command**：`node server.js`
   - **Health Check Path**：`/health`
   - Node 版本：在環境變數設 `NODE_VERSION=20`（或更新）以固定 runtime。
3. **設定環境變數**（Service → Environment）：把 §2 的變數逐一加入。
   - `DATABASE_URL` = 步驟 1 的 Internal Database URL（跨外網才需 `?sslmode=require`）。
   - `APP_ENV=production`、`HOST=0.0.0.0`、`PGVECTOR_ENABLED=true`。
   - `PORT` 由 Render 自動注入，**不用手動設**。
   - 其餘 secret（`OPENAI_API_KEY` / `ADMIN_API_TOKEN` / Firebase / Telegram）一律用 Environment / Secret，**不進 git**。
4. **跑 migration**：見 §6（Render 用 Shell 或一次性 Job）。
5. **驗證**：見 §7 health check。

---

## 5. Railway 部署步驟

> 目標：一個 Railway **service**（後端）+ 一個 **Postgres (pgvector)** plugin。

1. **建立專案 + Postgres**：New Project → Provision PostgreSQL（選 **pgvector** 模板）。Railway 會自動提供 `DATABASE_URL` 變數，可在後端 service 以 reference 變數引用。
2. **部署後端 service**：Deploy from GitHub repo。
   - **Root Directory**：`backend/stt_proxy`（Settings → Root Directory）。
   - **Start Command**：`node server.js`（Railway 通常自動偵測 `npm start`）。
   - Build：預設 `npm ci` / Nixpacks 自動安裝。
3. **設定環境變數**（service → Variables）：
   - `DATABASE_URL` = 引用 Postgres plugin 的連線字串（必要時加 `?sslmode=require`）。
   - `APP_ENV=production`、`HOST=0.0.0.0`、`PGVECTOR_ENABLED=true`。
   - `PORT`：Railway 會注入；程式讀 `process.env.PORT`，**不用手動固定**。
   - secret 同 §2，放 Variables，**不進 git**。
4. **產生對外網域**：Settings → Networking → Generate Domain（取得 HTTPS URL）。
5. **跑 migration**：見 §6（Railway 用 service shell 或一次性 command）。
6. **驗證**：見 §7。

---

## 6. 執行資料庫 migration

migration 程式：`db/migrate.js`（透過 `db/pool.js` 讀 `DATABASE_URL`）。動作：先 `CREATE EXTENSION pgcrypto / vector`，再依序套用 `db/migrations/001…014`（共 14 個 `.sql`）。

**指令（在已設好 `DATABASE_URL` 的環境執行）：**

```bash
cd backend/stt_proxy
npm run db:migrate
```

- **Render**：Service → Shell 進入容器後跑上述指令；或建一個 one-off Job（同 repo、Root Directory 同設）以 `npm run db:migrate` 為指令。
- **Railway**：service 的 Shell / Run command 跑 `npm run db:migrate`；或臨時把 Start Command 換成 migrate 跑一次再換回。
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

- **Flutter**：release build 帶 `--dart-define=API_BASE_URL=https://<正式網域>`（否則守門畫面會擋）。見 `ENVIRONMENT_SETUP §3.3`。
- **caregiver_web**：`config.js` 指向正式 API URL；把該 origin 加入後端 `CORS_ALLOWED_ORIGINS`。見 `ENVIRONMENT_SETUP §3.4`。
- **transport 收斂**（CR-0054/0055）：HTTPS 後端就緒後，才可套用 iOS ATS / Android cleartext 收斂 patch 並做實機 smoke。
- **真環境 E2E**（CR-0053 Execute）：HTTPS 後端 + 真 PG/Firebase/OpenAI/Telegram 齊全後，依 `E2E_SMOKE_TEST_PLAN` 執行並寫 Run 報告。

---

## 9. 安全紅線（部署時務必遵守）

1. 所有 secret（`OPENAI_API_KEY` / `ADMIN_API_TOKEN` / `FIREBASE_PRIVATE_KEY` / `TELEGRAM_BOT_TOKEN` / `DATABASE_URL`）只放部署環境 secret store，**不進 git、不寫死、不貼進文件**。
2. 不要把 `.env`、Firebase service account JSON、keystore 進版控。
3. production **不可**設 `ALLOW_JSON_FALLBACK=true` / `ALLOW_MOCK_SERVICES=true` / `REQUIRE_AUTH=false`（會被 fail-fast 擋下，也違反正式版原則）。
4. log 不可輸出完整 secret / 個資；後端已有 masked logging（`config/env.js` + redaction），維持。
