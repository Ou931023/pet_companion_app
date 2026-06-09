# E2E_SMOKE_TEST_PLAN — Production-like 端到端 Smoke 測試計畫

> 目的：在正式上架前，用**真 Firebase / 真 PostgreSQL / 真 OpenAI key / 真 Telegram Bot / 真裝置**跑一輪最小端到端 smoke，確認系統閉環可用，並產出 release blocker 清單。
> 本文件是「怎麼跑」的 checklist；每次實際執行的結果記在 `docs/E2E_SMOKE_TEST_REPORT.md`（一次一個 Run 區塊）。
> 建立：CR-0053。對照：`docs/ENVIRONMENT_SETUP.md`（§2 staging / §3 production 啟動細節）、`docs/AUTHORIZATION_MODEL.md`、`docs/CAREGIVER_PROVISIONING.md`、`docs/CAREGIVER_WEB_AUTH.md`、`docs/VOICE_CARE_ALERT_FLOW.md`、`docs/TYPED_CHAT_CARE_ALERT_FLOW.md`、`docs/LOGGING_AND_REDACTION.md`、`docs/STORE_RELEASE_CHECKLIST.md`。

> ⚠️ 安全紅線（執行與記錄時都必須遵守，見 CLAUDE.md / CR-0053 §12）：
> - 不讀 / 不貼 `.env`、Firebase service account、signing key / keystore。
> - 報告**不得**出現 token、Telegram chat id、完整對話原文、完整 email、`DATABASE_URL` 值。需要佐證時用遮蔽值（`sk-***1234`、`ou***@domain`、`postgres://***`）或截圖去敏。
> - 不為了通過 smoke 關閉 auth、啟用 mock、或污染正式資料（測試資料須可清理，見 §6）。
> - 不假裝通過：缺環境就走 Plan-only，缺口列 owner blocker。

---

## 0. 模式判定

| 模式 | 條件 | 產出 |
|---|---|---|
| **Plan-only** | 缺真金鑰 / 真網域 / 真 DB / 真裝置其一 | 本計畫 + REPORT 標示未執行原因 + 缺口/owner blocker + 下一步 |
| **Execute** | 環境齊全 | 依 §2–§5 實跑，逐項 pass/fail 記入 REPORT（含時間 / commit / 環境 / 裝置） |

> 同一輪可「部分 Execute」：例如 backend + caregiver_web 能在 staging 跑，但 iOS/Android release 裝置 smoke 仍 Plan-only。逐項標示，不要整輪二分。

---

## 1. 前置準備（Prerequisites）

### 1.1 帳號 / 憑證（只列「需要什麼」，值放部署環境，不進版控）

- Firebase 專案：Auth 已啟用 Email/Password（或實際採用的登入方式）。
- Firebase 測試帳號 ≥ 3：
  - 1 個 **resident（長者）** 帳號 → 對應 `users.elder_id`、`role=resident`、`status=active`。
  - 1 個 **caregiver（照護者）** 帳號 → `role=caregiver`。
  - 1 個 **super_admin** 帳號 → caregiver_web provisioning 用。
- Firebase 服務帳戶（後端驗 idToken 用）：`GOOGLE_APPLICATION_CREDENTIALS` 或
  `FIREBASE_PROJECT_ID` + `FIREBASE_CLIENT_EMAIL` + `FIREBASE_PRIVATE_KEY` 三件組。
- OpenAI API key（Realtime + STT + chat + embedding）。
- Telegram Bot token + 一個**測試用** care chat id（勿用正式照護群組）。
- PostgreSQL（含 pgvector）連線。
- 正式 / staging **HTTPS** 後端網域；caregiver_web 網域（供 CORS 白名單）。
- 真 iOS 裝置 + 真 Android 裝置（Realtime 麥克風 / WebRTC 需實機）。

### 1.2 後端必要環境變數（**只列名稱**；值放部署 secret，勿貼）

production fail-fast 必檢（`config/env.js validateProductionEnv`，缺即 `process.exit(1)`）：

- `DATABASE_URL`
- `OPENAI_API_KEY`
- `CORS_ALLOWED_ORIGINS`（相容別名 `ALLOWED_ORIGINS`；空白也算缺）
- Firebase 服務帳戶（擇一，見 §1.1）
- `ADMIN_API_TOKEN`

條件必檢：`TELEGRAM_BOT_TOKEN`（設了 `TELEGRAM_CARE_CHAT_ID` 即視為啟用）、`PGVECTOR_ENABLED=true` 需 `DATABASE_URL`。

不安全旗標（顯式設 true 即拒絕啟動）：`ALLOW_JSON_FALLBACK` / `ALLOW_MOCK_SERVICES` / `REQUIRE_AUTH=false`。

其餘：`APP_ENV=production`（或 staging）、`REALTIME_MODEL`、`REALTIME_VOICE`、`REQUIRE_CONSENT`、`PORT`、`HOST`、`RATE_LIMIT_*`、`TAVILY_API_KEY`（web search 啟用才需）。完整名稱見 `backend/stt_proxy/.env.example`、`docs/ENVIRONMENT_SETUP.md §3.1`、`docs/PRODUCTION_CONFIG_CHECKLIST.md`。

### 1.3 commit / build 紀錄（每輪都要記）

- backend commit hash、app commit hash（`git rev-parse --short HEAD`）。
- build type：staging / production；Flutter dart-define 值（不含 secret）。
- 裝置型號 + OS 版本。

---

## 2. Backend Smoke（對應 CR-0053 §6）

> 跑在 `APP_ENV=production`（或 production-like staging）。啟動細節見 `ENVIRONMENT_SETUP §3.2`。

| # | 項目 | 步驟 | 通過判準 |
|---|---|---|---|
| B1 | fail-fast 缺 env | 故意不設 `OPENAI_API_KEY` 啟動 | 印「只含變數名稱」訊息（**無值**）後 `exit(1)` |
| B2 | 正常啟動 | 補齊 §1.2 後 `APP_ENV=production node server.js` | 啟動成功；啟動摘要全遮蔽（`postgres://***`、`sk-***1234`、chat id 僅 `(set)`） |
| B3 | DB 連線 | 啟動 + 查任一 PG-only API（如 `/api/admin/users` 帶 admin token） | 連線成功，非 `failed_to_load_users` |
| B4 | migration 冪等 | `npm run db:migrate`（`node db/migrate.js`）跑兩次 | 第二次無錯、不重建已存在物件（013 resident_caregiver_links / 014 users.status 已有單元測試 `db/migration013/014.test.js`） |
| B5 | health | `GET /health` | `{status:"ok", hasOpenAiKey:true, realtimeModel, time}` |
| B6 | 無 JSON fallback | production 下查 marketplace / dailyCareTask | 被 guard 擋（友善 `feature_unavailable_in_production`），不靜默走 JSON |
| B7 | 無 mock auth | `REQUIRE_AUTH` 未關、`AUTH_ALLOW_MOCK` 未開 | 帶 mock token 被拒 401 |
| B8 | Realtime call | `POST /api/realtime/call`（帶 resident idToken + offer SDP） | 回正式 answer SDP（非 stub）；見 §4 實機驗證 |
| B9 | chat 需 auth + 可回覆 | `POST /api/companion/chat`（帶 resident idToken）送一句中性句 | 200 + `reply` 非空；無 token → 401 |
| B10 | notify 需 auth + 建 alert | `POST /api/care-alerts/notify`（resident idToken，medium body） | 200；`care_alerts` 落一筆 medium；無 token → 401；跨住民 → 403 |
| B11 | high/urgent Telegram | notify 送 high/urgent | Telegram 測試 chat 收到（時間 / 住民識別 / 摘要 / 建議方向）；`notification_logs` 記一列 sent |
| B12 | **medium 不推 Telegram** | notify 送 medium | `care_alerts` 有列、Telegram **無**訊息、`notification_logs` 記 `skipped_low_risk`（或等價）。**此為 CR-0051/0052 對齊核心** |
| B13 | log 去敏 | 觀察 B8–B12 期間 production log | 無 token / email / 完整對話 / `DATABASE_URL`；錯誤只記安全摘要（`docs/LOGGING_AND_REDACTION.md`） |

---

## 3. caregiver_web Smoke（對應 CR-0053 §8）

> 設定見 `ENVIRONMENT_SETUP §3.4`、`docs/CAREGIVER_WEB_AUTH.md`、`docs/CAREGIVER_PROVISIONING.md`。

| # | 項目 | 通過判準 |
|---|---|---|
| W1 | super_admin 登入 | 以 super_admin idToken 進管理端 |
| W2 | 建立 caregiver | provisioning 建 caregiver 帳號成功 |
| W3 | 綁 Firebase uid | caregiver 綁定正確 uid |
| W4 | 建 resident-caregiver link | link 建立成功（`resident_caregiver_links`） |
| W5 | caregiver 登入 | caregiver token 進得了管理端 |
| W6 | scoped 只看授權住民 | caregiver 只看到被 link 的住民 |
| W7 | 看不到未授權住民 | 直接打未授權 resident API → 403 / 空 |
| W8 | caregiver 不能進 provisioning | provisioning UI / API 對 caregiver → 403 |
| W9 | 401/403/empty state | 未登入 401、越權 403、無資料友善空狀態（非工程錯誤） |
| W10 | alert 狀態更新 | new → acknowledged → resolved 可更新並寫 `care_alert_status_events` |
| W11 | daily-care-tasks scoped | 只看授權住民任務 |
| W12 | log 去敏 | 不含 token；email 遮蔽顯示 |

---

## 4. Flutter App Smoke（真裝置，對應 CR-0053 §7）

> production build 見 `ENVIRONMENT_SETUP §3.3`。`API_BASE_URL` 必須正式 https，否則 App 停在「服務暫時無法使用」守門畫面。

| # | 項目 | 通過判準 |
|---|---|---|
| F1 | production flavor 啟動 | 以 `--dart-define=APP_ENV=production --dart-define=API_BASE_URL=https://...` build 後可啟動 |
| F2 | 無 debug banner | release 無 debug banner |
| F3 | 無 demo login | `demoLoginVisible` 強制 false |
| F4 | 無 dev panel | `devPanelsVisible` 強制 false |
| F5 | 無 mock STT / AI | production `mockServicesEnabled=false`；STT 走 OpenAI、chat 走後端 |
| F6 | 登入成功 | Firebase 登入 → 取得 idToken |
| F7 | Realtime 連線 | 開麥 → 連線成功 → 狀態流轉 idle/listening/thinking/speaking 正常，UI 無 SDP/ICE/token 工程字 |
| F8 | 語音 medium → alert | 說「最近都睡不好、有點孤單」→ 後端 `care_alerts` 落 medium（`source=companion_analysis`）、**Telegram 不推**；長者端**無**監控感文案 |
| F9 | 語音 high/urgent → 通知 | 說高風險句 → `care_alerts` + Telegram 推；長者端仍是陪伴語氣 |
| F10 | 打字 medium → alert | 打字 medium → `care_alerts` 落 medium（`source=companion_chat`）、Telegram 不推 |
| F11 | 打字 high/urgent → 通知 | 打字高風險 → `care_alerts` + Telegram |
| F12 | chat 失敗白話 | 後端不可用時 → 白話錯誤、**不 fallback mock**、不假成功 |
| F13 | 登出 | 設定頁登出正常、清 session |
| F14 | 記憶不跨帳號 | 換帳號看不到他人記憶 |
| F15 | release log 去敏 | 裝置 log 無 token / 完整 transcript |

---

## 5. ATS / Cleartext Smoke Gate（對應 CR-0053 §9 / CR-0046 B3）

> 現況（CR-0053 盤點）：**iOS `NSAllowsArbitraryLoads=true`（全域允許明文）、Android `usesCleartextTraffic="true"`**——皆未收斂，列為 **release BLOCKER**。
> 架構裁決（CR-0046）：Realtime 媒體走 WebRTC DTLS-SRTP，**不受 ATS 管制**；ATS/cleartext 只管 SDP 交換與 REST 明文 http。收斂不影響語音媒體，但 dev 若用「區網 IP + http 後端」需保留例外。收斂改動必須能 rollback。

| # | 項目 | 通過判準 |
|---|---|---|
| A1 | 正式後端 HTTPS 就緒？ | 若是 → 收斂全部 production cleartext；若否 → **BLOCKER**，不可假裝合規 |
| A2 | iOS 收斂 `NSAllowsArbitraryLoads=false` | 真機 Realtime / API / WebRTC 仍正常 |
| A3 | iOS 區網例外 | 確認是否仍需 localhost / 區網 http exception（dev only） |
| A4 | Android 收斂 cleartext | 真機 Realtime / API 仍正常 |
| A5 | rollback 驗證 | 收斂改動可一鍵回退 |

---

## 6. Test Data Cleanup（對應 CR-0053 §10）

> 原則：smoke 一律用**測試專用** resident / caregiver / chat id；**不得**碰正式使用者資料。

清理對象與方式（執行前先確認 SQL 只刪測試 id 範圍）：

1. 測試 resident / caregiver `users` 列。
2. `resident_caregiver_links`（測試 link）。
3. `care_alerts` + `care_alert_status_events`（測試住民）。
4. `memories` + `memory_vectors`（測試住民）。
5. `notification_logs`（測試 source / chat）。
6. Telegram 測試訊息（手動於測試 chat 刪除）。
7. `audit_logs`：**保留**（治理需求），但標記為 smoke 來源以便辨識；不刪。
8. `consent_records`（測試帳號）。

> 建議：以固定前綴 / 專用 elder_id 區隔測試資料，清理腳本只針對該範圍，降低誤刪風險。清理腳本若新增，放 `backend/stt_proxy/scripts/` 並於 REPORT 註明（勿提交真連線字串）。

---

## 7. 一輪 Smoke 的最小通過集（Definition of Done）

Execute 模式下，一輪算「核心通過」需至少：B2 / B4 / B5 / B9 / B10 / B11 / **B12** / W1 / W5 / W6 / W7 / F6 / F7 / F8 / F9 + log 去敏（B13 / F15）。ATS（§5）可分開列為 BLOCKER 追蹤，不阻擋本輪其餘項目記錄。
