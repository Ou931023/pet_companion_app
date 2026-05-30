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

> 註：本表為現況快照；新增 / 修改路由時請同步維護。

---

## 5. Care Alert 共用資料結構（🔒 三方共用）

分析邏輯 owner：`companion-memory-agent`；持久化 / 狀態 / 通知 owner：`backend-agent`；顯示 owner：`frontend-ux-agent`。任何一方都不可單方面改欄位。

以 `backend/stt_proxy/services/careAlertStoreService.js` 與 `data/care_alerts.json` 現況為準：

```jsonc
{
  "id": "uuid",
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

---

## 6. 資料儲存

- 現況：JSON store（`backend/stt_proxy/data/*.json`），屬 runtime 資料，**不進 git**（見 [[commit_hygiene]] 原則）。
- 目標：PostgreSQL + pgvector；embedding 預設 `text-embedding-3-small`。
- migration：`backend/stt_proxy/db/migrate.js`（🔒 schema 變更需核准）。
- 連線：`backend/stt_proxy/db/pool.js`、`postgres.js`。

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

---

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
