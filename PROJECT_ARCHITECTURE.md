# PROJECT_ARCHITECTURE.md

> 本檔是專案架構的**單一真相來源（single source of truth）**。
> 任何觸及 🔒 邊界（Realtime 主流程、`server.js` API 契約、DB schema、Care Alert 共用資料結構、依賴升級）的改動，
> 必須先在此更新並經 `architecture-agent` 核准，才可動程式。
>
> 維護者：`architecture-agent`。其他 agent 只能透過 `docs/CHANGE_REVIEW.md` 提案修改本檔。

---

## 1. 系統概觀

```
  ┌─────────────────────────┐        ┌──────────────────────────┐
  │   Flutter 長者端 (lib/)  │        │  caregiver_web 管理端     │
  │  首頁 / 對話 / 記憶 /     │        │  Care Alert 看板 / 狀態   │
  │  Care Alert / 設定        │        │  (index.html + app.js)    │
  └───────────┬─────────────┘        └─────────────┬────────────┘
              │  WebRTC + HTTPS                      │  HTTPS
              ▼                                      ▼
  ┌───────────────────────────────────────────────────────────────┐
  │            Node 後端  backend/stt_proxy/server.js               │
  │  Realtime SDP 轉送 / Care Alert / 記憶 / 搜尋 / 台語 ASR /       │
  │  Telegram 通知 / Agent Router                                    │
  └───────┬───────────────────────┬───────────────────┬────────────┘
          │                       │                   │
          ▼                       ▼                   ▼
   OpenAI Realtime         PostgreSQL+pgvector    Telegram Bot
   / Responses API        (JSON store 過渡中)      (長照通知)
```

---

## 2. 模組地圖（誰擁有什麼，詳見 `docs/TEAM_AGENTS.md`）

### Flutter 長者端 `lib/`
- `screens/` — 畫面（home / conversation / memory_management / care_alert / settings / onboarding…）→ **frontend-ux-agent**
- `widgets/` — UI 元件 → **frontend-ux-agent**
- `controllers/` — 狀態控制
  - `voice_agent_controller.dart` → **realtime-voice-agent**
  - `conversation_controller.dart` → 共享（transcript 顯示部分屬 realtime-voice）
  - `memory_controller.dart` → **companion-memory-agent**
  - `care_alert_controller.dart`、`pet_controller.dart` 等純前端狀態 → **frontend-ux-agent**
- `services/`
  - `realtime_voice_service.dart`（🔒 獨佔）、`realtime_turn_coordinator.dart`、`realtime_timeout_registry.dart`、`taigi_asr_*`、`language_routing_service.dart`、`*speech_to_text*`、`text_to_speech_service.dart` → **realtime-voice-agent**
  - `companion_*`、`memory_service.dart`、`emotion_services.dart` → **companion-memory-agent**
  - 其餘 UI 取資料用 service → 視情況共享，行為以後端契約為準

### 後端 `backend/`
- `stt_proxy/server.js`（🔒 API 契約）、`stt_proxy/services/`、`stt_proxy/db/`（🔒 schema）、`stt_proxy/repositories/`、`search/`、`agent/` → **backend-agent**
- `companion/`、`memory/` → **companion-memory-agent**
- `stt_proxy/data/*.json` — runtime 資料，**不進 git**

### 管理端
- `caregiver_web/`、`care_mall_website/` → **frontend-ux-agent**

### 文件 / 治理
- `CLAUDE.md`、`PROJECT_ARCHITECTURE.md`、`docs/`、`.claude/agents/` → **architecture-agent**

---

## 3. Realtime WebRTC 主流程（🔒 不可改成 mock）

1. Flutter 取得麥克風音訊。
2. 建立 `RTCPeerConnection`（含 STUN ICE servers）。
3. 建立 offer SDP。
4. 透過後端取得短期 session / 轉送 SDP（見 `/api/realtime/session`、`/api/realtime/call`）。
5. 後端轉送到 OpenAI Realtime Calls API。
6. 後端回傳 answer SDP。
7. Flutter `setRemoteDescription`。
8. 透過 DataChannel 接收 realtime events（partial / final transcript、assistant audio transcript…）。

**共管**：步驟 4–6 的後端端點由 `backend-agent` 實作、`realtime-voice-agent` 定義需求，兩者改動都要 `architecture-agent` 核准。

transcript 規則（沿用 CLAUDE.md）：不可讓 assistant transcript 被誤判成 user；user partial 不可變永久訊息；空白 final 不可產生空訊息。

---

## 4. 後端 API 契約（以 `backend/stt_proxy/server.js` 現況為準）

> 改動任一路由的路徑、方法或 response 形狀 = 🔒，需更新本表並核准。

| Method | Path | 用途 | Owner |
|--------|------|------|-------|
| GET | `/health` | 健康檢查 | backend |
| GET | `/api/agent/tools` | 取得可用工具 | backend |
| POST | `/api/agent/route` | Agent Router 工具路由 | backend |
| POST | `/api/care-alerts/notify` | 建立 Care Alert + Telegram 通知 | backend |
| GET | `/api/care-alerts` | Care Alert 列表 | backend |
| GET | `/api/care-alerts/:id` | 單筆 Care Alert | backend |
| PATCH | `/api/care-alerts/:id/status` | 更新狀態 new/acknowledged/resolved | backend |
| POST | `/api/companion/analyze` | 陪伴分析（情緒 / 風險 / 策略） | companion-memory（邏輯）+ backend（端點） |
| POST | `/api/companion/chat` | 正式陪伴聊天回覆（打字 / 非即時文字；取代 MockAiService 罐頭） | companion-memory（persona）+ backend（端點） |
| POST | `/api/stt/transcribe` | 語音轉文字 | backend + realtime |
| GET | `/api/asr/taigi/status` | 台語 ASR 狀態 | backend |
| POST | `/api/asr/taigi/warmup` | 台語 ASR 預熱 | backend |
| POST | `/api/asr/taigi` | 台語 ASR | backend + realtime |
| POST | `/api/memory/extract` `/api/memories/extract` | 記憶抽取 | companion-memory + backend |
| POST | `/api/memory/search` `/api/memories/search` | 記憶語意搜尋 | companion-memory + backend |
| GET | `/api/memory/greeting` `/api/memories/greeting` | 記憶式問候 | companion-memory + backend |
| POST | `/api/memory/forget-recent` | 忘記最近記憶 | companion-memory + backend |
| GET/POST | `/api/memories` | 記憶列表 / 新增 | companion-memory + backend |
| POST | `/api/memories/context` | 記憶脈絡 | companion-memory + backend |
| POST/PATCH | `/api/memories/:id/archive` | 封存記憶 | companion-memory + backend |
| POST | `/api/web/search` `/api/search` | 網路 / 可信來源搜尋 | backend |
| POST | `/api/crawl/refresh` | 重整爬取來源 | backend |
| POST | `/api/realtime/session` | Realtime 短期 session（含 rate limit） | backend + realtime |
| POST | `/api/realtime/call` | Realtime SDP 轉送 | backend + realtime |
| POST | `/api/auth/session` | 登入後建立 / 取回 user+elder（驗 Firebase ID Token，缺金鑰走 demo mock） | backend |
| GET | `/api/admin/overview` | 健康後台 Dashboard 六指標總覽 | backend |
| GET | `/api/admin/elders` | 長者列表（含最近活動 / 風險摘要） | backend |
| GET | `/api/admin/elders/:elderId` | 單一長者完整分析（基本資料 / care alert / 生理 / 心理 / 情緒 / 遊戲） | backend |
| GET | `/api/admin/elders/:elderId/physio` | 生理健康分析序列（demo 資料） | backend |
| GET | `/api/admin/elders/:elderId/emotion` | 情緒分析歷史序列 | backend |
| GET | `/api/admin/elders/:elderId/game-metrics` | 遊戲認知退化指標序列 | backend |

> 註：本表為現況快照；新增 / 修改路由時請同步維護。
> auth / admin 路由為 CR-0006 / CR-0007 新增（見 `docs/CHANGE_REVIEW.md`），契約定義見 §10、§11。

**`POST /api/companion/chat` 契約（CR-0049-B1）**

- Request（JSON）：`{ userText: string（必填）, petName?: string, memoryContextSummary?: string, languageHint?: string, replyLanguage?: string }`。
  - `memoryContextSummary` 由前端傳入既有摘要；本端點**不重查跨住民記憶**，避免跨住民洩漏。
- Response 成功：`{ success: true, reply: string }`（reply = 陪伴語氣自然回覆）。
- Response 失敗：`{ success: false, error: 'invalid_input' | 'openai_unavailable' }`；
  缺 `userText` → `400 invalid_input`；OpenAI 不可用 / 失敗 / 回空 → `503 openai_unavailable`。
- 紅線：**不回 fake/罐頭回覆假裝成功、不回 stack**；OpenAI 金鑰留後端、前端不放 key；log 經 redaction（不輸出完整 `userText` / `reply` / token）。
- persona 重用 Realtime 主流程的 `buildRealtimeInstructions`（同一份陪伴 persona），不自創文案。

---

## 5. Care Alert 共用資料結構（🔒 三方共用）

分析邏輯 owner：`companion-memory-agent`；持久化 / 狀態 / 通知 owner：`backend-agent`；顯示 owner：`frontend-ux-agent`。任何一方都不可單方面改欄位。

以 `backend/stt_proxy/services/careAlertStoreService.js` 與 `data/care_alerts.json` 現況為準：

```jsonc
{
  "id": "uuid",
  "elderId": "uuid | null",         // CR-0008 新增：綁定哪位長者（舊資料/未綁定為 null，向下相容）
  "receivedAt": "ISO8601",          // 後端收到時間
  "status": "new | acknowledged | resolved",  // VALID_STATUSES
  "riskLevel": "low | medium | high | urgent", // 權威分級（見 §5.1）
  "riskLevelLabel": "一般 | 持續觀察 | 需通知 | 緊急", // 顯示用中文（label 可調，level 代碼為權威值）
  "category": "other | ...",
  "categoryLabel": "其他 | ...",
  "triggerSummary": "觸發摘要",
  "transcriptSnippet": "對話片段",
  "createdAt": "ISO8601",
  "source": "companion_analysis",
  "statusUpdatedAt": "ISO8601",     // 狀態變更時間
  "acknowledgedAt": "ISO8601",      // status=acknowledged 時寫入
  "resolvedAt": "ISO8601"           // status=resolved 時寫入
}
```

狀態機（已實作）：`new → acknowledged → resolved`。

**`elderId` 相容規則（CR-0008）**：`elderId` 為 **nullable 新增欄位**——payload 未帶時寫入 `null`，既有 `data/care_alerts.json` 舊資料不改寫、讀取時缺欄位視為 `null`。`GET /api/care-alerts?elderId=` 過濾時：明確帶入才過濾，未帶則回全部（含 `elderId=null` 的舊資料）。前台顯示與 Telegram 推播規則不因此改變。

### 5.1 Care Alert 權威風險分級（architecture-agent 裁決，OI-0001 已結案）

**權威資料層 `riskLevel` 只有四個值：`low` / `medium` / `high` / `urgent`。**
這是 Care Alert「資料層 / API / 持久化 / 跨 agent 溝通」的唯一合法集合。三方共用，任何一方不可單方面新增或改名。

| level（資料層權威值） | 建議中文 label | 意義 | 對應行動 |
|---|---|---|---|
| `low` | 一般 | 一般關心即可 | 前台陪伴語氣互動，不通知 |
| `medium` | 持續觀察 | 需要持續觀察 | 後台留意趨勢，暫不通知 |
| `high` | 需通知 | 建議通知家屬或長照人員 | 觸發 Care Alert，建議通知 |
| `urgent` | 緊急 | 需要立即協助 | 立即通知（Telegram 等） |

說明：
- **level 代碼（左欄）是權威值，不可變動**；label（中文，右欄）僅供顯示，可由 frontend-ux-agent 微調。
- 與 §「Agent Tool 風險」是**兩套不同的分類，互不混用**（見 §5.2）。

#### `attention` / `normal` 的定位（重點）

> **`normal` / `attention` 不是正式資料層 level；它們僅作為 legacy 相容值（讀取），不得作為新的權威 `riskLevel` 寫入或比對。**

現況（CR-0002 已完成，2026-05-31）：程式已全面輸出權威四級 `low/medium/high/urgent`，並保留對舊值的讀取容錯：
- `backend/companion/safety_guard.js` → 直接輸出 `low / medium / high / urgent`（urgent 門檻不變、新增 high/medium、原 normal→low）
- `backend/companion/companion_engine.js` → `RISK_LEVELS = new Set(["low","medium","high","urgent"])`、`normalizeRiskLevel()` 讀取容錯、fallback `low`
- `backend/stt_proxy/services/careAlertStoreService.js` → 寫入正規化 + filter 雙向正規化（`normalizeRiskLevel`）
- `backend/stt_proxy/services/telegramNotifyService.js` → 顯示四級中文 label
- `lib/models/care_alert.dart` → 聯集 `enum { low, medium, high, urgent, normal, attention }`，`fromJson` 兩套皆讀、`toJson` 原樣、`canonical` 對映
- `caregiver_web`（app.js/styles.css/index.html）→ 支援兩套代碼顯示與篩選
- runtime `data/care_alerts.json` 內仍可見 `attention` 等歷史值，**未改寫**，靠各層讀取容錯正常顯示/篩選

權威 ↔ 舊代碼對照（消費端讀到舊值時依此對映；legacy 值僅供「讀取相容」）：

| 舊代碼（legacy） | 對映權威 level |
|---|---|
| `normal` | `low` |
| `attention` | `medium`（若該筆 `needsHumanSupport=true`，視個案可由 companion-memory-agent 升 `high`） |
| `urgent` | `urgent` |

> 治理結論：Care Alert 權威分級為 **`low / medium / high / urgent`**，已於 CR-0002（B3→B2→B1，全部完成）落實到程式。`normal` / `attention` 僅作為 **legacy 讀取相容值**，新寫入與 API 過濾一律使用權威四級。各層目前仍保留 legacy 容錯，未來待四級資料穩定後可另開 CR 移除（見 `docs/CHANGE_REVIEW.md` FU-0001）。

### 5.2 Agent Tool 風險分級（與 Care Alert 不同，勿混用）

工具呼叫（Tool Calling）有**獨立**的風險分級，衡量的是「執行某個工具動作的風險」（例如撥電話、寄信），與長者狀態的 Care Alert 嚴重度**無關**：
- `backend/agent/tool_schemas.js` → `RISK_LEVELS = ["low", "medium", "high"]`
- `lib/models/agent_tool_intent.dart` → `enum AgentToolRiskLevel { low, medium, high }`

這套 `low/medium/high` 屬於 `backend/agent/**` 與 tool intent，**owner 為 backend-agent**，不在 Care Alert OI-0001 範圍內，維持現狀。撰文時請以「Agent Tool 風險」明確區分，避免與 Care Alert 的 `riskLevel` 混淆。

### 5.3 後端 Care Alert 持久化（CR-P2A，DB-優先 + JSON fallback）

> CR-P2A 已將後端 Care Alert 持久化由「JSON 檔當正式資料來源」升級為 **PostgreSQL 優先**，
> 對映 migration `011_create_care_alerts.sql`（`care_alerts` + `care_alert_status_events` 兩表）。

持久化策略 — **DB-優先 + JSON fallback**（與 CR-0036 consent 的 **DB-only** 刻意不同）：

- **為何不採 consent 式 DB-only**：consent 是稽核資料，連不到 DB 必須丟例外、不可 JSON 假成功；**Care Alert 是可降級的營運資料**——`/api/care-alerts/notify` 的 high/urgent 通知若因 DB 連不上就整條失敗，會直接漏掉長者異常通知，比暫存 JSON 更糟。故 Care Alert 採可降級路徑，並在此明記差異與理由。
- **讀寫優先序**：`isPostgresAvailable()` 為 true → 走 DB；DB 例外 → `logError`（不含原文 / PII / token）後**降級 JSON**，不丟例外、不讓 `/notify` 失敗。無 `DATABASE_URL`（含所有現有測試與無 DB 的 Demo 機）→ 直接走 JSON，行為與 DB 化前**完全一致**。
- **對外介面零變更**：`careAlertStoreService` 對外 5 函式 `saveAlert / listAlerts / getAlertById / updateAlertStatus / deleteAlertsByElderId` 的簽章與回傳形狀（`{success,alert}` / `{success,alerts}` 等）**完全不變**；§4 路由路徑 / 方法 / response 形狀亦不變。
- **legacy riskLevel 讀取容錯**：DB 寫入沿用 `normalizeRiskLevel`（normal→low、attention→medium、未知→low）收斂為四級；讀取容錯 legacy 值（見 §5.1）。
- **不自動遷移、不雙寫**：既有 `data/care_alerts.json` 舊資料**不自動匯入 DB、不 JSON↔DB 雙寫**（避免重複 alert / id 衝突）；歷史資料留在 JSON 路徑，啟用 DB 後新資料進 DB。一次性匯入如有需要另開 follow-up。
- **狀態軌跡**：`care_alert_status_events` 為 append-only，DB 路徑於 `updateAlertStatus` 同步 append；JSON 路徑僅更新 alert 本體、不寫軌跡表。**暴露軌跡的 GET 路由屬契約改動，須另開 CR 先更新 §4/§5 契約再放行。**

#### 5.3.1 Production JSON fallback 政策（CR-0034 治理裁決）

> CR-0034 §3.4 要求 production 停用 JSON fallback；CR-P2A 又刻意保留 care alert 的 DB-優先 + JSON fallback 以免 `/notify` 漏掉 high/urgent。以下為架構守門人對兩者衝突的**正式裁決**（依環境分流，dev/staging 行為完全不變、不破壞既有 246 後端測試）。

環境旗標：`ALLOW_JSON_FALLBACK`（development 預設 `true`、staging 可設、**production 強制 `false`**；production 顯式設 `true` → 啟動 fail-fast）。

- **care alert（careAlertStoreService，可降級營運資料）**
  - **development / staging（`ALLOW_JSON_FALLBACK=true`）**：維持現狀 — DB-優先，DB 例外 → `logError` 後降級 JSON，`/notify` 不失敗。**行為與本檔 §5.3 完全一致，零變更。**
  - **production（`ALLOW_JSON_FALLBACK=false`）**：改為 **DB-required**。DB 連得上 → 一律走 DB。DB 例外時**禁止**靜默降級 JSON 假成功；正確行為為：
    1. `saveAlert` 回 `{success:false, error:'care_alert_persist_failed'}`（**清楚錯誤、不丟例外讓 server crash、不寫 JSON 當權威**）。
    2. `/api/care-alerts/notify` 必須把「送 Telegram 通知」與「持久化 alert」**解耦**：high/urgent 的通知仍要送出（這是安全關鍵路徑），持久化失敗以 `notification_logs` 的 `outcome=failed`（或 `persist_failed`）**明確記一列**，**絕不靜默漏通知、絕不假成功**。
    3. `/notify` 的 **request / response 形狀不得改變**（解耦是 endpoint 內部順序調整，非 API 契約改動）。
  - 一句話：production 下 care alert 的權威來源是 DB；DB 故障時「通知照送 + 大聲記錄失敗」，而不是「靜默 JSON 假成功」或「整條 notify 失敗」。

- **auth / memory / consent / search（DB-優先 + JSON fallback 類）**
  - development / staging：維持 DB-優先 + JSON fallback。
  - production：DB-required，缺 `DATABASE_URL` 由啟動層 fail-fast（見 §7.1）擋下；runtime DB 例外回清楚錯誤，不降級 JSON 當權威。consent 既為 DB-only（§5.3 既有），維持不變。

- **marketplace / dailyCareTask（JSON-only，無 DB 路徑）**
  - 此兩 service **目前沒有 DB 路徑**，在 production 等同無持久化保證（PROD_AUDIT P1-4）。
  - **裁決（依 CR-0034 §3.4.5）**：production 下以**清楚 guard 阻擋**，對使用者回長者友善訊息（例：「這個功能整備中，晚點再回來看看」），**不得**以 JSON-only 充當正式資料庫。列為 **CR-0042（PG 化）blocker**。
  - 此為「production 暫時不提供 marketplace / daily care task」的**已知且已文件化限制**，需產品確認接受；dev/staging 不受影響。


---

## 6. 資料儲存

- 現況：JSON store（`backend/stt_proxy/data/*.json`），屬 runtime 資料，**不進 git**（見 [[commit_hygiene]] 原則）。
- 目標：PostgreSQL + pgvector；embedding 預設 `text-embedding-3-small`。
- migration：`backend/stt_proxy/db/migrate.js`（🔒 schema 變更需核准）。
- 連線：`backend/stt_proxy/db/pool.js`、`postgres.js`。

### 6.1 核心資料表（對映 `pet_companion_app/CLAUDE.md §3.3`）

> 隨 Phase 2 production 升級，核心營運 / 稽核資料逐步落地 PostgreSQL。以下為已納入治理的稽核相關核心表現況（PROJECT_ARCHITECTURE 先前僅 CLAUDE.md §3.3 列出、本檔未明列，於此補齊）。

- `care_alerts` / `care_alert_status_events`（migration 011，CR-P2A）— Care Alert 本體與狀態軌跡，持久化策略見 §5.3。
- `notification_logs`（migration 012，CR-P2B）— **每次 Care Alert 通知必寫一列**（對映 CLAUDE.md §8.7、§8.10「不可靜默失敗」）。涵蓋 `/api/care-alerts/notify` 的**三結局**：`sent` / `failed` / `skipped_*`（`skipped_low_risk`、`skipped_cooldown`）。欄位僅結構化：`alert_id` / `elder_id` / `channel` / `risk_level` / `outcome` / `error_code` / `http_status` / `created_at`。
  - **紅線（§8.8、§9.14）：不存對話原文 / `transcriptSnippet` / chat_id / bot token / URL / email / ip。**
- `audit_logs`（migration 012，CR-P2B）— **敏感操作須寫一列**（對映 CLAUDE.md §9.13）。最小範圍先涵蓋三類：**帳號刪除**（`/api/auth/delete`）、**Care Alert 狀態變更**（`PATCH /api/care-alerts/:id/status`）、**consent 寫入**（CR-0036 ship 後）；登入 session 暫不納入以免洗稽核。欄位：`actor_type` / `actor_id` / `action` / `target_type` / `target_id` / `outcome` / `metadata(JSONB)` / `created_at`。
  - **紅線：`metadata` 僅放結構化非敏感欄位（如 from/to status、刪除計數）；禁放原文 / email / ip / token。**

> 兩表寫入皆為 **best-effort**：寫入失敗只 `logError`，**絕不丟例外拖垮 `/notify` 或主流程**（詳見 `docs/CHANGE_REVIEW.md` CR-P2B 紅線）。

---

## 7. 環境變數（只列**名稱**，數值一律放 `.env`，絕不寫入程式或文件）

後端會讀取的環境變數名稱（需手動於 `.env` 設定）：

- 伺服器：`PORT`、`HOST`、`ALLOWED_ORIGINS`
- OpenAI / Realtime：`OPENAI_API_KEY`、`REALTIME_MODEL`、`REALTIME_VOICE`
- 記憶：`MEMORY_MODEL`、`MEMORY_TOP_K`
- 搜尋：`TAVILY_API_KEY`、`WEB_SEARCH_SUMMARY_MODEL`、`DEFAULT_WEATHER_LOCATION`
- 台語 ASR：`TAIGI_ASR_MAX_UPLOAD_BYTES`
- Telegram 長照通知：`TELEGRAM_BOT_TOKEN`、`TELEGRAM_CARE_CHAT_ID`
- 資料庫：`DATABASE_URL`、`PGVECTOR_ENABLED`、`PG_POOL_MAX`、`PG_CONNECTION_TIMEOUT_MS`、`PG_IDLE_TIMEOUT_MS`
- Rate limit：`RATE_LIMIT_WINDOW_MS`、`RATE_LIMIT_MAX_CALLS`、`REALTIME_RATE_LIMIT_WINDOW_MS`、`REALTIME_RATE_LIMIT_MAX`
- Firebase ID Token 驗證（CR-0006，**全部缺省時走 demo mock 驗證，不 crash、不擋 Demo**）：
  - 服務帳戶（擇一）：`GOOGLE_APPLICATION_CREDENTIALS`（service account JSON 路徑）；或拆欄位 `FIREBASE_PROJECT_ID`、`FIREBASE_CLIENT_EMAIL`、`FIREBASE_PRIVATE_KEY`
  - 驗證 token audience：`FIREBASE_PROJECT_ID`
  - `AUTH_ALLOW_MOCK`（預設 `true`；未設定 Firebase 時允許 mock session，正式上線可設 `false` 強制驗 token）
- 綁定邏輯：`BINDING_DEADLINE_DAYS`（預設 60）

> Flutter 端 Firebase 設定（`google-services.json` / `GoogleService-Info.plist`、Google `REVERSED_CLIENT_ID`、Apple Service ID/Key）屬 client 平台設定檔，**不是後端 env、也不進 feature commit**。

---

### 7.1 環境與 flag 治理（CR-0034，development / staging / production）

統一三環境名稱：`development` / `staging` / `production`（不得用 testmode / real_demo / prod_test 等模糊名）。集中讀取於後端 `backend/stt_proxy/config/env.js`（新模組，B1），各 service 不再各自 `process.env` 解析旗標。

`APP_ENV` 正規化：顯式 `APP_ENV` 優先；否則 `NODE_ENV==='production'` → production、`NODE_ENV==='test'` → 視為 development 語義（**`NODE_ENV=test` 永遠不得解析為 production**，以保 `careAlertCooldown` / `taigiAsr` 等既有 `NODE_ENV==='test'` 行為與 246 測試）。`isProduction = (APP_ENV==='production' || NODE_ENV==='production')`。

| flag | development | staging | production | 對映 / 收斂的現有命名 |
|---|---|---|---|---|
| `APP_ENV` | development | staging | production | 新增（後端 + Flutter `--dart-define`） |
| `ALLOW_MOCK_SERVICES` | true | false | **false（顯式 true → fail-fast）** | 收斂 `AUTH_ALLOW_MOCK`、Flutter mock 注入 |
| `ALLOW_JSON_FALLBACK` | true | 可設 | **false（顯式 true → fail-fast）** | 新增；治理 §5.3.1 各 store |
| `REQUIRE_AUTH` | false | true | **true（顯式 false → fail-fast）** | 收斂 `AUTH_ALLOW_MOCK`（production 強制驗 token） |
| `REQUIRE_CONSENT` | false | true | true | 新增（對映 consent gate） |
| `ENABLE_VERBOSE_LOGS` | true | false | false | 收斂散落 `console.*` |
| `SHOW_DEV_PANELS`（Flutter） | 可開 | false | **false** | 既有 `lib/config/app_config.dart`，維持 |
| `SHOW_DEMO_LOGIN`（Flutter） | 可開 | false | **false** | 既有，維持 |
| `CORS_ALLOWED_ORIGINS`（後端） | 寬鬆 | 白名單 | **必填白名單（空 → fail-fast）** | 相容別名既有 `ALLOWED_ORIGINS`（修 P1-1） |
| `PGVECTOR_ENABLED`（後端） | 可選 | 依用 | 若記憶向量啟用則必填 | 既有，維持（feature flag，與環境正交） |
| `API_BASE_URL`（Flutter / caregiver_web） | localhost | staging URL | **正式 https 網域（localhost/空 → 阻擋進正式主流程）** | Flutter 收斂 `BACKEND_BASE_URL`；web 收斂 `DEFAULT_API_BASE` |

**相容收斂原則（不一次大破壞）**：舊命名（`AUTH_ALLOW_MOCK`、`ALLOWED_ORIGINS`、`BACKEND_BASE_URL`）保留為**可讀別名**，由 `config/env.js` 統一映射到新語義；production 下新語義（強制安全值）覆蓋舊命名。`mockAllowed()` 在 production 一律回 `false`（修 P0-3），dev/test 行為不變。

#### 7.1.1 Backend production fail-fast（B1）

- **位置**：新模組 `backend/stt_proxy/config/env.js`，提供純函式 `validateProductionEnv(env) → {ok, missing[]}`（可單測，不退出），與薄包裝 `assertProductionEnvOrExit()`（缺 → 印安全訊息 + `process.exit(1)`）。
- **呼叫點**：`server.js` 頂部 `dotenv.config()` 之後、掛路由之前呼叫一次；**`NODE_ENV==='test'` 或非 production 一律 no-op**（保 246 測試與 Demo 機）。🔒 server.js 啟動段改動，需守門人核准（本 CR 已附條件核准，見 CHANGE_REVIEW CR-0034）。
- **production 必檢**：`DATABASE_URL`、`OPENAI_API_KEY`、`CORS_ALLOWED_ORIGINS`（空白單）、auth secret（現況=Firebase 服務帳戶 `GOOGLE_APPLICATION_CREDENTIALS` 或 `FIREBASE_PROJECT_ID`+`FIREBASE_CLIENT_EMAIL`+`FIREBASE_PRIVATE_KEY` 三件組）、`ADMIN_API_TOKEN`（admin 端點存在）。
- **條件必檢**（功能啟用才檢）：`TELEGRAM_BOT_TOKEN`（Telegram 通知啟用時）、`PGVECTOR_ENABLED`（記憶向量啟用時）。`SESSION_SECRET` / `JWT_SECRET`：待 CR-0038 正式 admin/JWT 登入落地後納入必檢（現況 Firebase + ADMIN_API_TOKEN，先列 checklist）。
- **production 額外 fail-fast**：`ALLOW_JSON_FALLBACK=true`、`ALLOW_MOCK_SERVICES=true`、`REQUIRE_AUTH=false`、`CORS_ALLOWED_ORIGINS` 空 → 任一成立即拒絕啟動。
- **紅線**：缺設定**不可靜默啟動、不可自動切 JSON/mock**；錯誤訊息**只列缺哪些變數名稱**，**絕不印 token/secret 值**；提供 mask helper（`postgres://***`、`sk-***last4`、`ou***@example.com`）。fail-fast 是**啟動層**行為，**不改任何 API request/response 契約**。

## 8. 測試入口

- Flutter：`flutter test`（`test/`）
- 後端：`node --test`（`backend/**/*.test.js`）

改功能要補 / 更新對應測試，不可為了過測刪除既有測試。

---

## 9. 🔒 需核准清單（摘要，細節見 `docs/TEAM_AGENTS.md`）

`CLAUDE.md`、`PROJECT_ARCHITECTURE.md`、`lib/services/realtime_voice_service.dart`、
`backend/stt_proxy/server.js`（路由 / response）、`backend/stt_proxy/db/migrate.js` 與 DB schema、
Care Alert 共用資料結構、`pubspec.yaml` / `backend/stt_proxy/package.json` 依賴、
`.claude/agents/*`、以及任何跨兩個以上 agent 範圍的改動。

---

## 10. 身份與綁定模型（CR-0006，🔒 跨前後端契約）

登入導入後，**每位長者都有固定 `userId` 與 `elderId`**；後續對話記憶、Care Alert、情緒分析、遊戲紀錄都綁定 `elderId`。
登入供應商為 Firebase Authentication（Email / Google / Apple）；**Firebase 缺金鑰時走 demo mock 驗證**，登入系統不得阻擋 Demo。

### 10.1 登入流程（不破壞 Realtime / 不擋 Demo）

1. Flutter 透過 Firebase 完成 Email / Google / Apple 登入，取得 `firebaseUid` + `idToken`。
2. Flutter 呼叫 `POST /api/auth/session`（見下）。
3. 後端驗證 ID Token（或 mock）→ upsert `users` / `elders` → 回 `{ userId, elderId, role, bindingStatus, bindingDeadline }`。
4. Flutter 把 `userId` / `elderId` 存進 secure storage，作為記憶 / care alert / 遊戲 / 情緒寫入時的綁定鍵。
5. **未登入或 demo 模式**：fallback `elderId = "default_user"`（保留既有行為），Realtime 語音與既有流程照常運作。
6. **紅線**：`lib/services/realtime_voice_service.dart` 主流程不得因登入而修改；登入只改「上層傳入的 userId / elderId 來源」。

### 10.2 `POST /api/auth/session` 契約

Request body：
```jsonc
{
  "firebaseUid": "string",      // 必填
  "idToken": "string",          // 必填（mock 模式可為任意非空字串）
  "email": "string | null",
  "displayName": "string | null",
  "provider": "email | google | apple | mock",
  "photoUrl": "string | null"   // 可選
}
```
Response（200）：
```jsonc
{
  "success": true,
  "userId": "uuid",
  "elderId": "uuid",
  "role": "elder | caregiver | admin",
  "bindingStatus": "pending | bound | expired",
  "bindingDeadline": "ISO8601",
  "isNewUser": true,
  "authMode": "firebase | mock"   // mock 表示後端未設定 Firebase、以 demo 模式採信
}
```
規則：
- 若 `users.firebase_uid` 已存在 → 回既有 `userId` / `elderId`（`isNewUser=false`）。
- 否則建立 `users` + 對應 `elders`，`bindingDeadline = now + BINDING_DEADLINE_DAYS`（預設 60 天）。
- 驗證失敗（Firebase 模式下 token 無效）→ 401 `{ success:false, error:"invalid_id_token" }`，不得 crash。

### 10.3 DB schema（migrations 006 / 007，🔒）

> 沿用既有 `db/migrate.js` 跑 `db/migrations/*.sql` 機制。後端在 DB 不可用時須能 fallback JSON store（沿用 `memoryStore.js` 模式），確保 Demo 不掛。

`users`：`id (uuid pk)`、`firebase_uid (text unique)`、`elder_id (uuid fk elders.id)`、`role (text default 'elder')`、`email (text)`、`email_verified (bool default false)`、`display_name (text)`、`auth_provider (text)`、`provider_user_id (text)`、`binding_status (text default 'pending')`、`binding_deadline (timestamptz)`、`created_at (timestamptz default now())`、`verified_at (timestamptz null)`、`updated_at (timestamptz)`

`elders`：`id (uuid pk)`、`display_name (text)`、`birth_year (int null)`、`gender (text null)`、`created_at (timestamptz default now())`

`emotion_history`：`id (uuid pk)`、`elder_id (uuid fk)`、`emotion (text)`、`score (numeric null)`、`source (text default 'companion_analysis')`、`summary (text)`、`created_at (timestamptz default now())`

`elder_health_metrics`（生理，demo 資料）：`id (uuid pk)`、`elder_id (uuid fk)`、`metric_date (date)`、`daily_interaction_minutes (int)`、`reminder_completion_rate (numeric)`、`medication_completion_rate (numeric)`、`water_completion_rate (numeric)`、`exercise_completion_rate (numeric)`、`sleep_hours (numeric)`、`sleep_quality (text)`、`created_at (timestamptz default now())`

`game_cognitive_metrics`：`id (uuid pk)`、`elder_id (uuid fk)`、`game_type (text)`、`played_at (timestamptz)`、`moves (int)`、`duration_seconds (int)`、`completion_rate (numeric)`、`difficulty (text)`、`cognitive_score (numeric)`、`regression_flag (bool default false)`、`created_at (timestamptz default now())`

### 10.4 知情同意稽核 API 契約（CR-0036，🔒 跨前後端契約）

> 對應 DB migration `db/migrations/010_create_consent_records.sql`（append-only 稽核表，欄位以該檔為準）與前端 `lib/services/consent_service.dart`。
> 後端持久化是「補齊 §3.3 已規劃 `consent_records` 核心表」，非新架構。**只新增 2 條路由，不改任何既有路由形狀。**
> 身份辨識沿用既有 auth 中介（同 `POST /api/auth/delete`）：`authFirebaseAdmin.isConfigured()` → 驗 `idToken` 取權威 `uid`；否則 `authMockAllowed()`（`AUTH_ALLOW_MOCK`，預設 true）→ 採信傳入識別。**不新發明 auth 機制。**

#### `POST /api/consent`（記錄一次同意 / 撤回，寫一列）

Request body：
```jsonc
{
  "firebaseUid": "string | null",   // 辨識用：firebase configured 時搭配 idToken 驗證
  "idToken": "string | null",       // firebase configured 時必須；mock 模式可省略
  "userId": "uuid | null",          // 已知時直接帶；後端據以回填 consent_records.user_id
  "elderId": "uuid | null",         // 已知時直接帶；回填 consent_records.elder_id
  "consentType": "string",          // 必填：privacy_terms | data_collection | microphone | notification
  "consentVersion": "string",       // 必填：對應前端 consent.acceptedVersion
  "action": "granted | withdrawn",  // 可選，預設 granted
  "source": "string | null",        // 可選：elder_app_onboarding | settings | ...
  "appVersion": "string | null",    // 可選，稽核用
  "platform": "string | null",      // 可選：ios | android
  "agreedAt": "ISO8601 | null"      // 可選，省略時後端用 NOW()
}
```
必填：`consentType`、`consentVersion`。其餘皆可選。
辨識規則：firebase configured → 驗 `idToken` 取權威 `uid` → 解析回填 `user_id`/`elder_id`（驗證失敗回 401 `invalid_id_token`）；否則 mock-allowed → 採信傳入 `userId`/`elderId`/`firebaseUid`。`user_id`/`elder_id` 解析不到時仍可寫列（兩欄 nullable，保留稽核軌跡，比照 010 表設計）。
`withdrawn` 時不刪舊列，改寫一列 `action='withdrawn'`、填 `withdrawn_at`（append-only）。

**PII 紅線**：`ip` 與 `user_agent` 由後端從 request（`req.ip` / `req.headers['user-agent']`）自行擷取，**僅落 DB 供稽核**；request body 不接受、**response 與 server log 一律不得回顯**。

Response（200）：
```jsonc
{
  "success": true,
  "record": {
    "id": "uuid",
    "consentType": "privacy_terms",
    "consentVersion": "1.0.0",
    "action": "granted",
    "agreedAt": "ISO8601"
    // 絕不含 ip / userAgent
  }
}
```
錯誤碼（沿用既有 `{success:false,error}` 形狀，**絕不回 stack trace**）：
- 缺 `consentType` 或 `consentVersion` → `400 { success:false, error:"invalid_payload" }`
- firebase configured 且 `idToken` 驗證失敗 → `401 { success:false, error:"invalid_id_token" }`
- 例外（DB 寫入失敗等）→ `500 { success:false, error:"consent_failed" }`（細節只進 `logError`，不回前端）

#### `GET /api/consent`（查詢某使用者目前同意狀態）

Query：`?userId=<uuid>`（或 `?firebaseUid=<uid>`；firebase configured 時可搭 `idToken` 驗證）。
語義：回該使用者**每個 `consent_type` 的最新一筆**（依 `created_at` desc 取首列 per type）為「目前同意狀態」，外加可選 `history` 全列表供稽核。未帶可辨識識別 → `400 invalid_payload`。

Response（200）：
```jsonc
{
  "success": true,
  "current": [
    { "consentType": "privacy_terms", "consentVersion": "1.0.0",
      "action": "granted", "agreedAt": "ISO8601" }
  ],
  "history": [
    { "id": "uuid", "consentType": "...", "consentVersion": "...",
      "action": "granted | withdrawn", "agreedAt": "ISO8601",
      "withdrawnAt": "ISO8601 | null" }
    // 同樣遮蔽 PII：絕不含 ip / userAgent
  ]
}
```
錯誤碼：缺可辨識識別 → `400 invalid_payload`；firebase 驗證失敗 → `401 invalid_id_token`；例外 → `500 consent_failed`。

#### 與前端 `ConsentService` 對接（B3，frontend-ux-agent 後續排程）

- 呼叫時機：`recordConsent(version)` 成功寫入本機（shared_preferences）**之後**，best-effort `POST /api/consent`（`consentType` 先固定 `privacy_terms` 對應目前單一 gate）。
- 帶入：當前 `AuthController` 的 `firebaseUid` / `idToken` / `userId` / `elderId`。
- 失敗行為：**非阻塞** — 後端失敗（離線 / 5xx / timeout）**不得影響本機已同意狀態**，使用者照常進入 App（比照 `deleteAccount` best-effort）；可在下次啟動 / 設定頁重試補送。本機 `consent.acceptedVersion` 仍是 App 內判斷是否需重新同意的唯一來源。

#### 環境變數

無新增。沿用既有 `AUTH_ALLOW_MOCK`（預設 true，控制 mock 採信）與既有 Firebase Admin 設定；資料庫沿用既有 PG 連線設定。

---

## 11. 健康後台 Admin API 契約（CR-0007，🔒）

> demo 階段資料可由 JSON store / 確定性 demo 產生器供給（**不串智慧手環**），但 response 形狀須接近正式版；使用者/管理者可見處不得出現 demo / fake / debug 字樣。

`GET /api/admin/overview` → Dashboard 六指標：
```jsonc
{
  "totalElders": 0,            // 長者總人數
  "activeToday": 0,           // 今日互動長者數
  "careAlertsToday": 0,       // 今日 Care Alert 數量
  "highRiskElders": 0,        // 高風險長者數（high/urgent）
  "emotionAbnormalElders": 0, // 情緒異常長者數
  "cognitiveDeclineElders": 0 // 遊戲退化指標異常人數
}
```

`GET /api/admin/elders` → `[{ elderId, displayName, lastActiveAt, latestRiskLevel, emotionAbnormal, cognitiveDecline }]`

`GET /api/admin/elders/:elderId` → 個人完整分析：
```jsonc
{
  "profile": { "elderId", "displayName", "birthYear", "gender", "bindingStatus" },
  "careAlerts": [ /* §5 Care Alert 形狀，依 elderId 過濾 */ ],
  "physio": { /* 同 /physio summary */ },
  "psych": { "summary": "白話心理摘要", "dominantEmotion": "...", "abnormal": false },
  "emotionHistory": [ /* 同 /emotion */ ],
  "gameMetrics": { /* 同 /game-metrics summary */ }
}
```

`GET /api/admin/elders/:elderId/physio` → `{ series: [{ date, dailyInteractionMinutes, reminderCompletionRate, medicationCompletionRate, waterCompletionRate, exerciseCompletionRate, sleepHours, sleepQuality }], summary: {...} }`

`GET /api/admin/elders/:elderId/emotion` → `{ series: [{ date, emotion, score, summary }], dominantEmotion, abnormal }`

`GET /api/admin/elders/:elderId/game-metrics` → `{ series: [{ date, gameType, cognitiveScore, completionRate, durationSeconds, regressionFlag }], trend: "stable | declining", abnormal }`

未知 `elderId` → 404 `{ success:false, error:"elder_not_found" }`。
