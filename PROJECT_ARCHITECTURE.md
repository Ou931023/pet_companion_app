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
| POST | `/api/companion/chat` | 正式陪伴聊天回覆（打字 / 非即時文字；取代 MockAiService 罐頭）。CR-0050 用獨立 `buildCompanionChatInstructions` / `COMPANION_CHAT_PERSONA` seam（見 `docs/COMPANION_PERSONA.md`）。**CR-0051**：掛 `requireResidentCaller`（須住民 idToken；無/無效→401、跨住民→403）；回覆後做純函式風險側錄，`riskLevel∈{medium,high,urgent}` 經共用 `processCareAlert` 建 Care Alert（`source="companion_chat"`）；回應加 optional `careAlert:{created,riskLevel,id}`（low/中性省略）。見 `docs/TYPED_CHAT_CARE_ALERT_FLOW.md`。**CR-0072**：request 新增**選用** `history`（最近對話歷史 user/assistant 陣列）→ 組 messages `[system, ...history, user]` 給模型短期脈絡；無 history 行為不變、response 形狀不變（純 additive，後端 `sanitizeHistory` 清洗 role/長度/則數）。 | companion-memory（persona/分級）+ backend（端點/管線） |
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

> **CR-0075**：上列所有記憶端點（`/api/memory/*`、`/api/memories/*`）已掛 `requireResidentCaller`（須住民 Firebase idToken；無→401、無效/未綁→401/403）。記憶 key 改取 **server 權威 `req.residentCaller.elderId`**（= `users.elder_id`，與 Flutter `currentElderId` 一致）；client 帶與其不符的 `userId`（body/query）→ 403 `forbidden_resident`。成功 response 形狀不變。

| POST | `/api/web/search` `/api/search` | 網路 / 可信來源搜尋 | backend |
| POST | `/api/crawl/refresh` | 非 production 資料建置工具；production 固定 404，不公開爬取入口 | backend |
| POST | `/api/realtime/session` | Realtime 短期 session（含 rate limit） | backend + realtime |
| POST | `/api/realtime/call` | Realtime SDP 轉送 | backend + realtime |
| POST | `/api/auth/session` | 登入後建立 / 取回 user+elder；production 必須驗 Firebase ID Token，mock seam 僅限非 production 測試 | backend |
| GET | `/api/admin/overview` | 健康後台 Dashboard 六指標總覽 | backend |
| GET | `/api/admin/elders` | 長者列表（含最近活動 / 風險摘要） | backend |
| GET | `/api/admin/elders/:elderId` | 單一長者完整分析（基本資料 / care alert / 生理 / 心理 / 情緒 / 遊戲） | backend |
| GET | `/api/admin/elders/:elderId/physio` | 生理健康分析序列（demo 資料） | backend |
| GET | `/api/admin/elders/:elderId/emotion` | 情緒分析歷史序列 | backend |
| GET | `/api/admin/elders/:elderId/game-metrics` | 遊戲認知退化指標序列 | backend |
| GET | `/api/marketplace/products` `/api/marketplace/products/:id` | 長照商城商品列表 / 詳情（長者端，公開讀）CR-0032 | backend |
| POST | `/api/marketplace/orders` | 長者端建立訂單（扣庫存）CR-0032 | backend |
| GET | `/api/admin/marketplace/orders` `/api/admin/marketplace/orders/:id` | 管理端訂單列表 / 詳情（requireAdmin）CR-0032 | backend |
| PATCH | `/api/admin/marketplace/orders/:id/status` | 管理端更新訂單狀態 / 配送備註（requireAdmin）CR-0032 | backend |
| DELETE | `/api/admin/marketplace/orders/:id` | 管理端刪除訂單並還原庫存（requireAdmin）**CR-0067** | backend |
| GET | `/api/daily-care-tasks` | 長者端今日任務列表（Firebase resident token；server 權威 elderId；選用 `?status`）CR-0025/CR-0104 | backend |
| POST | `/api/daily-care-tasks` | 長者建立自己的任務（Firebase resident token；request elderId 不具授權效力）CR-0025/CR-0104 | backend |
| POST | `/api/daily-care-tasks/:id/submit` | 長者上傳完成照片（multipart `photo`）+ AI Vision 驗證 + PostgreSQL submission CR-0025/CR-0104 | backend |
| PATCH | `/api/daily-care-tasks/:id/status` | super_admin 或 active `primary` / `secondary` caregiver 人工更新任務狀態；`viewer` 固定唯讀 CR-0025/CR-0104 | backend |
| GET | `/api/daily-care-tasks/proof/:submissionId` | super_admin 或任何 active 已指派 caregiver（含 `viewer`）讀取證明圖片；private/no-store CR-0025/CR-0104 | backend |
| GET | `/api/admin/daily-care-tasks` | 管理端任務 + 最新 submission；caregiver 僅限已指派住民 CR-0025/CR-0104 | backend |

> 註：daily-care-tasks 已於 **CR-0068** 由 JSON 平移到 PostgreSQL（migration 016：`daily_care_tasks` / `daily_care_task_submissions` 兩表）。**CR-0104 / migration 018** 新增 nullable `proof_image_bytes BYTEA` 與 `proof_mime_type TEXT`：production 新照片以 DB bytes 為唯一正式來源，不依賴 Render ephemeral disk；`proof_image_path` 只保留舊資料相容讀取。JSON + uploads fallback 僅允許非 production 開發／測試環境。
>
> Daily-care JSON response 統一使用 `{ success: boolean, ... }`；認證、授權與業務錯誤亦回 `{ success:false, error }`。所有 task/submission JSON 均不得包含 `proofImagePath` 或 `proofImageBytes`；只可回 `hasProofImage`、`proofMimeType`。照片只能透過上列受保護 proof endpoint 讀取。
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

### 4.1 CR-0108 心情日記契約（2026-09-21 核准，待實作）

以下為 architecture-agent 已核准的 additive 契約，可由指定 owner 直接實作，非既有功能已完成的宣稱。

| Method | Path | 成功回應 / 權限 |
|---|---|---|
| GET | `/api/mood-diary` | 200 `{success:true,entries:[entry]}`；requireResidentCaller，僅本人 |
| POST | `/api/mood-diary` | 201 `{success:true,entry}`；requireResidentCaller，僅本人 |
| PATCH | `/api/mood-diary/:id` | 200 `{success:true,entry}`；requireResidentCaller，僅本人，僅改分享 |
| DELETE | `/api/mood-diary/:id` | 200 `{success:true}`；requireResidentCaller，僅本人 |
| GET | `/api/admin/residents/:residentId/mood-diary` | 200 `{success:true,entries:[entry]}`；既有 staff auth，active 已指派 caregiver（含 viewer）或 super_admin，僅分享資料 |

- `entry = {id,mood,content,createdAt,sharedWithCaregiver}`；id 為 server UUID，createdAt 為 server ISO8601；mood 限 `happy/okay/low/worried`；content trim 後非空、最多 1000 Unicode code points；sharedWithCaregiver 為 boolean，預設 false。
- POST 僅接受 `{mood,content,sharedWithCaregiver?}`；PATCH 僅接受 `{sharedWithCaregiver:boolean}`。拒絕未知欄位（包含 userId、elderId、逐字稿）；所有 resident 身分取 `req.residentCaller` 的 userId / elderId。staff residentId 依既有住民解析方式映射 elderId，再檢查 active assignment，不採信前端授權。
- GET 支援選用 `limit`，整數 1..100、預設 50；依 createdAt DESC、id DESC 排序。staff 查詢必須在 SQL 限 `shared_with_caregiver=true`，super_admin 亦不得讀未分享日記。無分享資料回空列表；非授權住民回 403。
- 錯誤一律 `{success:false,error}`：400 `invalid_payload`、401 沿用 auth error code、403 `forbidden`（既有 middleware code 保持相容）、本人 scope 內找不到 mutation target 為 404 `not_found`、DB 不可用 503 `diary_unavailable`。回應 `Cache-Control: private, no-store`；不記錄內容到 log / analytics。
- 儲存按鈕不等於分享同意：另設未預勾分享 checkbox，清楚指出對已授權照護者 / 管理員可見；撤回分享立即影響後續讀取。無 AI 自動寫入、無私人聊天回填；日記不自動進入長期記憶。保留既有記憶管理與刪除入口。
- 核准 PostgreSQL-only migration `019`（若編號已被並行變更占用，只改用下一個空號，勿覆寫）：`mood_diary_entries`，`id UUID PRIMARY KEY`、`user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE`、`elder_id UUID NOT NULL REFERENCES elders(id) ON DELETE CASCADE`、`mood TEXT NOT NULL CHECK` 四值、`content TEXT NOT NULL CHECK(char_length(content) BETWEEN 1 AND 1000)`、`shared_with_caregiver BOOLEAN NOT NULL DEFAULT FALSE`、`created_at TIMESTAMPTZ NOT NULL DEFAULT now()`。索引為住民時間排序及 shared=true 的住民時間 partial index；user / elder 配對由 server 權威身分寫入，不接受 client 指定。
- 帳號刪除在既有同一 transaction 刪除日記 rows，FK cascade 作防護；核准 `services/auth/sessionService.js` 最小接線及對應測試。不可用 JSON fallback 假成功。無新依賴、無 Care Alert schema 改動。
- 新日記與 resident 任務編輯端點另以 DB 驗證 `users.role='elder'` 及 userId / elderId 配對，不改共享 requireResidentCaller。entry 不新增 elderId / userId，維持上述使用者指定形狀；UI 以請求帳號 generation 隔離回應。v1 不新增 requestId / ledger，UI 防連點，未知 POST 結果先重讀、不自動重送；不得宣稱 POST 冪等。

### 4.2 CR-0108 任務編輯契約（2026-09-21 核准，待實作）

- `PATCH /api/daily-care-tasks/:taskId`：requireResidentCaller，只能本人任務；`PATCH /api/admin/daily-care-tasks/:taskId`：既有 admin auth + assertCanManageResident，super_admin 或 active primary / secondary，viewer 禁寫。
- payload 是非空子集合 `{title?,description?,scheduledTime?}`，拒絕其餘欄位；title trim 後 1..200 code points，description trim 後 0..1000，scheduledTime 為嚴格 `HH:mm`（00:00..23:59），沿用 Asia/Taipei 本地每日時間。不允許改住民、type、status、dueAt、submission 或 proof。
- 成功 200 `{success:true,task}` 沿用現有 task shape；400 `invalid_payload`，auth 錯誤沿用既有中介，scope 內不存在 404 `not_found`，完成任務拒絕 409 `task_not_editable`。dueAt 非 null 時更改 scheduledTime 拒絕 409 `task_schedule_conflict`，內容仍可改，不默默製造不一致時間。
- 核准既有 `dailyCareTaskStore.js` 的 scoped edit 與測試、server 最小路由接線。只更新 payload 指定欄位，以 transaction / row lock 驗證當前可編輯狀態，保存 status / proof。此版不新增 revision 欄位：同欄位並行編輯採最後成功提交者生效，不同欄位不得被整筆覆寫；此規則取代 CR-0108 初稿強制版本衝突要求。UI 保存後重讀，排程只在成功後替換舊提醒。
- 可編輯狀態限定 pending 且無 submission；否則 409 `task_not_editable`。新 PATCH 採 DB-only，故障回 503 `{success:false,error:'task_unavailable'}`，不改其他既有路由 fallback。v1 不要求 If-Match / 428，維持上述欄位級最後提交規則；dueAt 非 null 時更改時間維持 409，不推算另一日期。舊提醒取消 / 重設是 Flutter owner 責任，不宣稱後端已取消本機通知。

### 4.3 CR-0108 語音商店與 Realtime 範圍核准

- 語音購買指**既有本機金幣錢包的虛擬寵物商店**，不是 `/api/marketplace/orders` 外部 commerce。不新增付款、物流或訂單 API。Hegel 診斷後沿用現有商品 / gold / inventory 購買路徑：先顯示品項與金幣成本、明確確認，再檢查餘額 / 持有狀態並扣款發放；同一確認不可重複扣金幣，取消 / 換帳號使確認失效。不得聲稱伺服器級交易保障或真實付款。
- realtime-voice-agent 可改 `realtime_voice_service.dart`：context / tool response instructions 保留明確 reply language；依 user turn + tool call identity 去重，不把同輪不同工具結果互相吞掉；新輸入 / stop 使舊 queued outcome 失效；生成中或音訊播放中先排隊，flush 時重新檢查 generation / turn，播放結束亦不可自動創造無請求續講。
- `voice_agent_controller.dart` 的 start / reconnect / warm input 尊重 profile 明確台語（taigiRealtime、taigiPreferred、manual taigi），輸出為 taigi 而非強制 mixed；reconnect 保留 mode，async tool callback 檢查 generation / turn。profile 持久化 / 帳號隔離由 frontend owner 負責。
- 不改 SDP / ICE / DataChannel 傳輸、VAD 設定或手動 commit / VAD race；後者另 checkpoint。僅新增 / 更新 voice owner 的 regression tests；本次不執行 Flutter tests / build，實機與測試結果不得宣稱通過。

### 4.4 CR-0109 語言同步、通知通道與設備基礎（2026-09-22 核准，待實作）

本節是限定實作核准，不是功能已完成或 production 啟用核准。無 MQTT 硬體 / broker；「小黑豆」僅是候選 IR blaster，型號、協定、設備回報能力均未確認，不假定支援 MQTT。

**最新範圍裁決（2026-09-22，優先於本節下方原核准）：** 兩位 owner 已完成唯讀。A 語言批立即放行，包含 voice owner 的 ai_tool_router 語言區塊及最小 Realtime 同步；不必等待 backend。backend 已確認缺機構收件映射與 consent gate，因此 B 本批只准隔離、預設停用的 LINE adapter、dispatcher、policy resolver interface 與注入式單測；**不接 processCareAlert，不修改 server.js、既有 Telegram sender / cooldown / notification log、catalog / intent policy，也不掛啟動或 live voice 路徑**。下方 B 的正式派送接線、安全 gate、結果與去重要求保留為後續契約，不是本批接線許可；可信授權來源完成並另經審查才放行整合。C 本批縮限為文件 / 契約，不新增可執行 MQTT adapter、device policy、broker client 或連線測試，不宣稱設備可用。下方 C 的程式檔案與驗收設計僅供後續提案，不再構成本批實作許可。

#### A. 國語 / 台語切換

- realtime-voice-agent 主導 `voice_agent_controller.dart`、`language_routing_service.dart` 與 owned tests；特別核准其修改 `ai_tool_router.dart` 的語言命令辨識 / 呼叫區塊（不改其他工具）。frontend-ux-agent 僅修改 profile、設定 UI 與最小 provider 接線。兩種入口走同一語言變更流程，不各自重建 session。
- 明確選擇優先於自動偵測，國語與台語雙向對稱；辨識的是要求切換的命令，而非出現「台語」就切換。否定、引述、歌曲 / 新聞主題、能力詢問、同句衝突目標不切換，必要時澄清。只接受 user final transcript / 主動手動選擇，partial 與 assistant transcript 不觸發。
- 分離 desired preference 與 session applied state；profile 按帳號保存，語言 revision + session / account generation 防止較舊 async 結果蓋回。重連採最新偏好；登出 / stop 清掉舊待套用工作。切換不清除正式對話或重送工具，不因 profile 其他欄位變更重複更新。
- 核准 `realtime_voice_service.dart` 最小語言 instructions 同步及更新成功 / 失敗回報；沿用既有 session.update，送出不等於服務端已套用，失敗保留待同步狀態，不先報成功。已在播放的句子不要求中途換語言，下一個回覆 / 工具結果使用最新已套用偏好；不自動新增無請求 response。
- 不改 SDK、模型、依賴、SDP / ICE / DataChannel 傳輸、VAD / commit 或 ASR 架構；不保證未實機驗證的台語發音品質。

#### B. 機構選擇 Telegram / LINE

- backend-agent（Feynman）核准新增 `services/caregiverNotificationDispatcher.js`、`lineNotifyService.js`、`facilityNotificationPolicy.js` 與對應單測；可小範圍修改既有 Telegram service、notification log / cooldown 及 `server.js` 的 processCareAlert 接線。不改既有 Telegram export / 呼叫簽章與 `/api/care-alerts/notify` request / response 形狀；舊 `telegram` 欄位僅描述 Telegram，不得以 LINE 成功冒充。LINE 結果先留內部通道結果 / 稽核，對外新欄位與管理 UI API 另審。
- 內部可信設定契約：`resolvePolicy(serverElderId) -> { facilityId, channels, recipientBindingRefs, policyVersion } | null`，channels 為 `[]`、`['telegram']`、`['line']` 或兩者，無隱含跨通道 fallback。機構選擇不等於住民同意。facilityId 與收件人由 server 授權關係及受控設定解析，不接受 body、LLM 或工具參數指定 chatId、LINE recipient、URL 或 facilityId。
- 每次派送及重試前檢查當前有效的「住民 + 機構 + 通道 + 收件綁定 + 告知範圍」同意與 active caregiver assignment；一般 privacy_terms、OS 推播許可或模型的 confirmed 不是這項授權。自動 high / urgent alert 需預先明確 opt-in；手動 notify_caregiver 仍需當次內容 / 對象確認，不能冒充 urgent 來繞過規則。撤回、未綁定、查詢失敗一律不送；不得自行新增緊急例外。
- v1 允許以注入的可信 policy / consent / recipient resolver 建立可測試接線；缺少正式權威來源時回 skipped，禁止以 local preference、環境開關或 stub=true 代替同意。此案不核准新 DB schema、同意 / 綁定 API 或 production provisioning；若既有來源不足，先完成 adapter 並保持停用，另提精確契約。
- LINE 預設停用，可用設定名稱 `LINE_NOTIFICATIONS_ENABLED`、`LINE_CHANNEL_ACCESS_TOKEN`（只記名稱，不讀值）；各機構 recipient binding 是可信設定參照，不以全域 recipient 取代住民授權。Telegram 舊全域設定不得自動成為所有機構收件者。保留 Telegram 介面不等於保留未經同意的送出旁路；兩通道共用派送 gate，既有直接 sender 呼叫須納入測試。
- 新通道內容僅含風險四級、時間、受控照護代稱 / alert reference 及固定的關心提示；不含逐字稿、自由文字 triggerSummary、日記、記憶、姓名、電話、住址或任意 URL。Telegram 保留介面但 dispatcher 傳入同樣最小化資料。Care Alert 儲存 / 分析與送訊息分離，通知被拒不刪 alert；不改風險規則或共用 alert shape。
- 內部結果固定 `{channel,status,errorCode?}`，status 限 `accepted/failed/unknown/skipped_disabled/skipped_consent/skipped_binding/skipped_low_risk/skipped_duplicate`；accepted 只表示供應商接受，不等於已送達 / 已讀。每通道獨立結果，一通道失敗不重送已接受的另一通道。timeout 結果可能 unknown，不可直接聲稱沒送出。
- 去重鍵至少包含 facility / elder / event identity / recipient binding / channel；風險升級是新事件。不得沿用僅 source+riskLevel 的全域 cooldown 抑制其他住民。v1 不新增 durable queue / 自動重試 worker；僅 in-process 去重不得宣稱跨重啟 exactly-once。稽核只存 ID、通道、結果與錯誤碼，不存 recipient 值、原文、憑證或 HTTP headers。
- LINE 使用 Messaging API push，非已終止的 LINE Notify；使用既有 fetch，不新增 SDK。首次即使用穩定 UUID retry key，若後續另行核准重試，須遵守供應商有效期限；接受不代表送達。來源：[Messaging API](https://developers.line.biz/en/reference/messaging-api/#send-push-message)、[retry semantics](https://developers.line.biz/en/docs/messaging-api/retrying-api-request/)、[LINE Notify 終止公告](https://developers.line.biz/en/news/2025/04/01/line-notify/)。

#### C. MQTT / IR 僅基礎，不啟用設備

- Feynman 核准新增 `backend/agent/device_control_policy.js`、`backend/stt_proxy/services/facilityMqttAdapter.js` 與 isolated tests。只建立驗證 / adapter interface / disabled result；不裝 MQTT 套件、不建立真 broker connection、不 publish，不接 server 啟動副作用。
- 設定契約為可信注入 `{enabled:false, brokerRef:null, facilityBindings:[]}`；binding 草案為 `{facilityId,deviceId,kind,allowedActions,commandTopicRef,stateTopicRef}`，kind 限 light / ac；本批 enabled=true 必須拒絕為 `not_commissioned`，缺設定回 `disabled`。broker / topic 參照不是允許 client 提供 URL、topic 或 credentials；不得填入猜測的小黑豆協定。
- 內部草案命令 `{commandId,deviceId,action,parameters,expiresAt}` 必須經 server 身分、機構設備綁定、能力白名單與參數驗證；只允許絕對狀態，不接受 toggle、任意 raw IR、任意 topic / payload。AC 溫度界限須待設備及機構政策確認，現在不硬編一組值當正式安全界限。
- `backend/agent/tool_schemas.js` / policy / intent builder 僅核准相容性測試與既有 notify_caregiver 確認規則補強；**不得新增可列出 / 可路由 / 可執行的 MQTT 工具**，不改 live voice catalog，不給 LLM publish 能力。語言切換仍為本機控制，不新增後端語言 endpoint。
- 日後另案確認硬體 / IR 協定、broker TLS / ACL、身分到 facility / device 綁定、當次確認綁 command / expiry、kill switch、retain=false、過期 / 重連不重播、去重及狀態驗證後才可啟用。publish / broker ACK / IR 發送均不是設備實際狀態，無回讀不可說「冷氣已開」。本批測試 fake transport 只限測試，不當成產品成功 fallback。

#### D. 驗收與發布界線

- 語言：手動 / 語音雙向切換、否定 / 引述 / 台語歌曲不誤觸、混合語輸入不覆蓋偏好、連續切換 / 重連 / 換帳號 / update 失敗、工具結果語言與不重複發話。
- 通知：機構選擇矩陣、無 / 撤回同意零 outbound、跨機構 / 未綁定零 outbound、最小化內容、Telegram 相容、雙通道部分失敗、住民隔離去重、timeout 與 redaction。MQTT：disabled / not_commissioned、無 connection / publish、catalog 無設備工具、錯誤 action / scope / expiry 拒絕。
- 所有單測須注入 fake HTTP / policy / transport，禁止讀 env 檔或 runtime data、發真通知 / 操作硬體。正式通知啟用需可信綁定和同意來源驗證；設備啟用另案。不得以本核准宣稱測試通過、台語品質或設備支援。

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

- **marketplace / dailyCareTask（已 PostgreSQL 化）**
  - marketplace 已由 migration 015 與 `marketplaceStore` 提供 PostgreSQL production 路徑；daily care 已由 migrations 016、018 提供任務、submission 與照片 bytes 的 PostgreSQL production 路徑。
  - production 一律 DB-required，資料庫不可用時回清楚錯誤，不得降級 JSON 或 Render ephemeral disk 假成功。
  - development / test 可保留 JSON fallback 供隔離測試；該 fallback 不具 production 權威性。
  - `FeatureUnavailableInProductionError` / `respondFeatureDisabled` 僅保留舊版與防禦性相容，不代表這兩項正式功能目前停用。


---

## 6. 資料儲存

- production 現況：PostgreSQL + pgvector 為 auth、memory、Care Alert、marketplace、daily care、usage analytics 等正式權威來源；embedding 預設 `text-embedding-3-small`。
- development / test：部分 service 可使用 `backend/stt_proxy/data/*.json` fallback；這些 runtime 資料**不進 git**，也不得在 production 啟用。
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
- Firebase ID Token 驗證（CR-0006 / CR-0034，**production 必須設定並驗證；缺少服務帳戶時 fail-fast**）：
  - 服務帳戶（擇一）：`GOOGLE_APPLICATION_CREDENTIALS`（service account JSON 路徑）；或拆欄位 `FIREBASE_PROJECT_ID`、`FIREBASE_CLIENT_EMAIL`、`FIREBASE_PRIVATE_KEY`
  - 驗證 token audience：`FIREBASE_PROJECT_ID`
  - `AUTH_ALLOW_MOCK`（僅非 production 開發 / 測試可用；production 無條件為 false）
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
| `CORS_ALLOWED_ORIGINS`（後端） | 寬鬆 | 白名單 | **必填白名單（空 → fail-fast）** | 相容別名既有 `ALLOWED_ORIGINS`（修 P1-1）。**CR-0054**：CORS middleware 改經 `config/env.js resolveCorsOrigins`（新名優先、相容 legacy）取白名單，與 fail-fast 同源——修補「只設新名時 middleware 仍空→production allow-all」缺口。dev 空清單維持 allow-all、無 Origin 請求（Flutter/Realtime broker 不帶 Origin）一律放行 |
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
正式上架登入供應商為 Firebase Authentication Email、Google 與 Apple。Google / Apple 登入都必須取得 Firebase ID Token，並走同一個 production session API；不得只在前端建立假 session。production 缺 Firebase Admin 設定時後端拒絕啟動，不得走 mock；mock 只保留給 development / test。

### 10.1 登入流程（不破壞 Realtime / 不擋 Demo）

1. Flutter 透過 Firebase Email、Google 或 Apple 登入取得 `firebaseUid` + `idToken`；iOS 提供 Google / Apple，Android 提供 Google，Email 為兩平台共同備援。
2. Flutter 呼叫 `POST /api/auth/session`（見下）。
3. 後端在 production 驗證 ID Token → upsert `users` / `elders` → 回 `{ userId, elderId, role, bindingStatus, bindingDeadline }`；mock 驗證僅限非 production。
4. Flutter 把 `userId` / `elderId` 存進 secure storage，作為記憶 / care alert / 遊戲 / 情緒寫入時的綁定鍵。
5. **未登入**：由 Auth Gate 阻擋正式主流程；`default_user` 僅保留給 development / test 的 mock 路徑與舊資料相容，不是 production 身分備援。

### 10.1.1 帳號刪除順序（production 隱私契約）

1. 使用者先依原登入方式以 Firebase 重新驗證並取得最新 ID Token（Email 密碼、Google 或 Apple）；Apple 重新驗證同時取得只留在記憶體中的 authorization code。
2. App 呼叫 `POST /api/auth/delete`；後端以驗證後的 Firebase UID 為權威，刪除 user / elder / memory / Care Alert 等伺服器資料。
3. **只有後端明確回傳成功後**，Apple 帳號才以 authorization code 呼叫 `revokeTokenWithAuthorizationCode` 撤銷 Apple token；接著刪除 Firebase 帳號與本機 session。Email / Google 帳號直接進入 Firebase 刪除步驟。
4. 後端不可達或刪除失敗時，App 不得撤銷 Apple token 或刪除 Firebase 帳號；須保留登入狀態並提示重試，避免留下使用者無法自行刪除的孤兒資料。
5. **紅線**：`lib/services/realtime_voice_service.dart` 主流程不得因登入而修改；登入只改「上層傳入的 userId / elderId 來源」。

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
- 失敗行為：**非阻塞** — 後端失敗（離線 / 5xx / timeout）**不得影響本機已同意狀態**，使用者照常進入 App；可在下次啟動 / 設定頁重試補送。本機 `consent.acceptedVersion` 仍是 App 內判斷是否需重新同意的唯一來源。此策略只適用同意紀錄補送，帳號刪除必須等待後端成功。

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
