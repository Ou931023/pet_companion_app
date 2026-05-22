# 愛陪伴 — 畢業專題 Demo 架構文件

本文件給畢業專題口頭報告與現場 Demo 使用，整理「AI 老人陪伴寵物 App」的整體架構、Realtime 語音主流程、長期記憶流程、各層 fallback、Demo 腳本與倫理隱私聲明。

> 本文件為說明用途，不影響程式行為。實際程式以 `lib/` 與 `backend/` 內的原始碼為準。

---

## 一、Demo 整體架構

系統分成三個獨立部分：

```
┌──────────────────────┐     WebRTC / HTTP      ┌───────────────────────────┐
│  Flutter App          │ ───────────────────▶  │  Node.js 後端 (stt_proxy)  │
│  (iPhone 實機)         │                        │  持有 OpenAI API Key       │
│                       │ ◀───────────────────  │                           │
│  - 語音互動 UI         │     transcript /       │  - Realtime session broker │
│  - 陪伴寵物動畫        │     reply / state      │  - 長期記憶 API            │
│  - 任務 / 設定 / 紀錄  │                        │  - 搜尋 / 台語 ASR         │
└──────────────────────┘                        └───────────┬───────────────┘
                                                             │
                                          ┌──────────────────┼───────────────────┐
                                          ▼                  ▼                   ▼
                                  ┌──────────────┐  ┌──────────────────┐  ┌──────────────┐
                                  │ OpenAI       │  │ PostgreSQL        │  │ 可信來源搜尋  │
                                  │ Realtime API │  │ + pgvector        │  │ (Tavily 等)  │
                                  └──────────────┘  └──────────────────┘  └──────────────┘

┌──────────────────────┐
│  長照商城網站          │  獨立靜態網站 (care_mall_website/)，與 Flutter App 分離
└──────────────────────┘
```

### 1. Flutter App（前端）

- 目標平台：iPhone 實機。
- 主控制器：`lib/controllers/voice_agent_controller.dart`（即時語音主控）。
- 對話狀態：`lib/controllers/conversation_controller.dart`。
- Realtime 連線：`lib/services/realtime_voice_service.dart`（WebRTC）。
- 語言路由：`lib/services/language_routing_service.dart`。
- 後端位址設定：`lib/config/app_config.dart`（`BACKEND_BASE_URL`，預設 `http://127.0.0.1:3001`）。

### 2. Node.js 後端（`backend/stt_proxy/`）

- 主服務：`backend/stt_proxy/server.js`。
- 由後端持有 `OPENAI_API_KEY`，App 端不會拿到正式金鑰。
- 模組化邏輯：`backend/companion/`（情緒與陪伴策略）、`backend/memory/` 與 `stt_proxy/services/memory/`（長期記憶）、`backend/search/` 與 `stt_proxy/services/search/`（搜尋）、`backend/agent/`（工具編排）。
- 資料庫：PostgreSQL + pgvector（`docker-compose.yml`）。

### 3. 長照商城網站（`care_mall_website/`）

- 獨立的 HTML / CSS / JS 靜態網站，非 Flutter 內嵌頁。
- 預設以靜態伺服器啟動於 `http://localhost:5500`。

---

## 二、Realtime 語音主流程

主流程使用 OpenAI Realtime API 搭配 WebRTC，全程即時串流，不走錄音檔上傳。

> 重要：此為核心主流程，Demo 文件不更動此流程。

### 流程步驟

1. 使用者在首頁點「啟動即時語音陪伴」，`VoiceAgentController` 啟動連線。
2. `RealtimeVoiceService.connect()` 建立 `RTCPeerConnection`，加入麥克風音訊軌與事件用 DataChannel，產生 SDP offer。
3. App 將 SDP offer 以 `Content-Type: application/sdp` POST 到後端：

   ```
   POST /api/realtime/call?petName=...&userId=...&companionContext=...
        &languageHint=...&replyLanguage=...&mode=...
   ```

4. 後端 `/api/realtime/call`：
   - 檢查 `OPENAI_API_KEY` 與 SDP 內容是否有效。
   - 呼叫 `buildMemoryContext`（含 1200ms timeout），取得使用者長期記憶摘要。
   - 組合 `REALTIME_INSTRUCTIONS` + 記憶摘要 + 語言輸出指示。
   - 將 offer 轉送 OpenAI Realtime API，取回 answer SDP。
5. App 收到 answer SDP，`setRemoteDescription`，連線進入 `ready`。
6. DataChannel 事件持續更新 UI：
   - 即時 transcript（partial / final）。
   - AI 回覆文字事件。
   - 語音回覆播放狀態。
7. 寵物狀態依事件在 `listening` / `thinking` / `speaking` 間切換。
8. 情緒輔助：透過 `/api/companion/analyze` 做情緒與陪伴需求分析，影響寵物 mood / expression / action。

### 連線重試

- `RealtimeVoiceService` 連線失敗時會以遞增 backoff 重試。
- DataChannel 有開啟逾時保護（預設 5 秒）。
- SDP 交換 HTTP 請求逾時為 12 秒。

---

## 三、長期記憶流程

長期記憶讓寵物記住使用者「明確說出口、且有助於陪伴」的內容，並在後續對話自然延續。完整驗證流程另見 `backend/stt_proxy/docs/memory_demo_flow.md`。

### 記憶抽取（寫入）

1. 每輪對話後，背景呼叫 `POST /api/memories/extract`，送出 `userText`、`agentReply`、`emotion`、`sessionId`、`turnId`。
2. Memory Extractor 判斷是否值得長期保存：
   - **會保存**：偏好、生活習慣、情緒狀態、提醒事項、照護需求、健康生活近況。
   - **不會保存**：普通寒暄、太短句子、一次性閒聊、AI 自行推測、醫療診斷、敏感身份推斷。
3. 值得保存者，產生一句 `memorySummary`，以 `text-embedding-3-small` 轉成 1536 維 embedding。
4. 寫入 PostgreSQL `companion_memories`（含 embedding、類型、重要性、信心分數、使用次數）與 `memory_events`。

### 記憶召回（讀取）

1. 使用者送出新訊息或 Realtime 連線建立時，呼叫 `POST /api/memories/context`。
2. 產生 `userText` 的 embedding，以 pgvector 做語意相似搜尋。
3. 以混合分數排序：

   ```
   finalScore = similarity * 0.60
              + importanceScore * 0.25
              + recencyScore * 0.15
   ```

4. 只保留達門檻的記憶，組成短版 `memoryContext` 注入 AI prompt。
5. 更新 `use_count`、`last_used_at`，並記錄 `used_in_prompt` 事件。
6. 若相似度過低或與當前問題無關，`memoryUsed` 為 `false`，對話照常進行。

### 記憶管理（隱私控制）

- App 設定頁 →「管理長期記憶」可查看目前保存的記憶（摘要、類型、重要性、建立時間、使用次數）。
- 點「忘記這筆」呼叫 `POST /api/memories/:id/archive`，後端標記 `is_active = false` 並記錄 `archived` 事件。

### 主要記憶 API

| 端點 | 用途 |
| --- | --- |
| `POST /api/memories/extract` | 從一輪對話抽取並保存記憶 |
| `POST /api/memories/context` | 召回相關記憶，產生注入用 `memoryContext` |
| `GET  /api/memories` | 列出使用者目前的長期記憶 |
| `POST /api/memories/:id/archive` | 封存（刪除）單筆記憶 |
| `GET  /api/memories/greeting` | 取得帶記憶感的問候語 |

> 後端另保留 `/api/memory/*`（單數）等早期端點作為相容用途，目前 App 以 `/api/memories/*`（複數）為主，舊端點不刪除。

---

## 四、Fallback 設計

系統採多層 fallback，目標是任何單一服務異常都不會讓 Demo 中斷。

| 層級 | 異常情況 | Fallback 行為 |
| --- | --- | --- |
| Realtime 連線 | 連線失敗 / 不穩 | 先以遞增 backoff 重試；仍失敗則提示「目前連線不穩，我先用一般語音模式陪你說話。」並可改用一般語音模式 |
| 記憶資料庫 | PostgreSQL / pgvector 不可用 | 自動切換 JSON fallback（`backend/stt_proxy/data/companion_memories.json`、`memory_events.json`），API `provider` 回傳 `json_fallback` |
| 記憶抽取 | `OPENAI_API_KEY` 不存在或失敗 | 改用 rule-based 判斷是否值得記住；無 embedding 時略過語意召回 |
| 記憶召回 | `memoryContext` 取得失敗 / 逾時 | 非阻塞設計，回到一般 AI 對話流程，使用者無感 |
| 陪伴理解 | Companion Engine 分析失敗 | 觸發本地 `_applyLocalCompanionFallback`，以本地規則維持陪伴回覆 |
| 語言 / ASR | 主策略不可用 | `LanguageRoutingService` 依 ASR 策略順序 fallback（OpenAI Realtime → Mock Taigi） |
| 台語 ASR | 模型未就緒 | 提供 `/api/asr/taigi/status` 與 `/api/asr/taigi/warmup`，App 僅顯示友善狀態文字 |
| 舊版 STT | Realtime 不可展示時 | 保留 v1 流程 `POST /api/stt/transcribe`（檔案上傳式 STT），可在設定頁切換 |

### 保留的 legacy 端點（不刪除）

- `POST /api/realtime/session`：ephemeral session-secret 模式端點，目前 App 主流程未使用，保留作相容與備援。
- `POST /api/stt/transcribe`：第一版檔案上傳式 STT proxy，保留供 Realtime 無法展示時備援。
- `/api/memory/*`（單數）：早期記憶端點，保留相容用途。

---

## 五、Demo 腳本

建議現場依下列順序操作，完整測試清單見 `docs/demo_realtime_companion_test_checklist.md`。

### 事前準備

1. 啟動後端：`cd backend/stt_proxy && npm start`（健康檢查 `GET /health`）。
2. 確認 `backend/stt_proxy/.env` 已設定 `OPENAI_API_KEY`、`DATABASE_URL`、`PGVECTOR_ENABLED`。
3. 啟動 Flutter App：`flutter pub get` 後 `flutter run`（iPhone 實機）。
4. iPhone 與後端主機需在同一 Wi-Fi；後端綁 `0.0.0.0`。

### Demo 1：Realtime 語音陪伴

1. 首次開啟進入 Onboarding，輸入寵物名字，按「開始陪伴」。
2. 進首頁後寵物先 rest 約 1 秒，再主動問候。
3. 點「啟動即時語音陪伴」，直接對手機說話。
4. 觀察：即時 transcript 同步顯示、AI 回覆文字、寵物在 listening / thinking / speaking 切換。
5. 說出「孤單、難過、擔心、開心」等情緒詞，觀察寵物 mood / expression 改變。

### Demo 2：長期記憶（睡眠）

1. 第一句說：「我最近晚上都睡不好，白天很沒精神。」→ 系統背景保存睡眠近況記憶。
2. 第二句說：「給我一個睡眠健康小知識。」→ 寵物自然提到「你之前有提到最近比較睡不好」，並給溫和建議（不做醫療診斷）。

### Demo 3：長期記憶（故事偏好）

1. 第一句說：「我喜歡聽台灣地方故事。」→ 保存偏好。
2. 第二句說：「說一個故事給我聽。」→ 回覆偏向台灣地方故事。

### Demo 4：記憶管理與隱私

1. 進設定頁 →「管理長期記憶」，展示目前寵物記得的內容。
2. 點「忘記這筆」刪除一筆記憶，確認從列表移除，且不再參與後續召回。

### Demo 5：陪伴策略與台語

1. 測試陪伴情境（孤單 / 疲累 / 睡不好 / 沒胃口），確認回覆先做情緒承接、每次最多問一個問題。
2. 測試台語輸入（如「無人陪我講話」），確認回覆使用自然台語口吻搭配繁體中文。

### 現場異常時的說法

- Realtime 不穩：可改用一般語音模式，或用 `curl` 展示 `/api/memories/extract`、`/api/memories/context` 證明記憶功能運作。
- PostgreSQL 沒開：說明系統自動切換 JSON fallback，仍能展示建立、列表、刪除與召回。

---

## 六、倫理與隱私聲明

本專題以「長者陪伴」為應用情境，使用者屬相對脆弱族群，因此在設計上特別納入下列倫理與隱私考量。

### 1. 定位與限制

- 本 App 為情感陪伴用途，**不是醫療器材，也不提供醫療診斷**。陪伴回覆只給溫和的生活建議，遇到健康問題會引導使用者尋求專業協助。
- 本專題為畢業專題展示原型，非正式上線產品。

### 2. 資料最小化與記憶界線

- 長期記憶只保存使用者**明確說出口、且有助於陪伴**的內容。
- 不保存普通寒暄、一次性閒聊、AI 自行推測的內容，也不做醫療診斷或敏感身份推斷。
- 記憶抽取會產生 importance 與 confidence，並比對摘要避免重複保存。

### 3. 使用者對記憶的控制權（被遺忘權）

- 使用者可於設定頁「管理長期記憶」查看寵物目前記得什麼。
- 可隨時對單筆記憶按「忘記這筆」刪除；刪除後不再出現於列表，也不再參與後續個人化回覆。

### 4. 金鑰與資料安全

- `OPENAI_API_KEY` 只放在後端 `backend/stt_proxy/.env`，**不寫入 Flutter App**。
- `.env` 已列入 `.gitignore`，不會提交至版本庫。
- App 透過後端取得短效連線資訊，不會持有正式 API 金鑰。
- 長期記憶資料儲存在本機 PostgreSQL；JSON fallback 檔亦在本機，僅供開發與展示備援。

### 5. 語音資料處理透明度

- 即時語音會傳送至 OpenAI Realtime API 進行辨識與回覆生成。
- 建議在實際使用時明確告知長者：對話對象是 AI 陪伴寵物，且語音會經雲端服務處理。

### 6. 互動安全

- 後端 `backend/companion/safety_guard.js` 對陪伴回覆做安全把關，避免不當或風險性內容。
- 陪伴策略以「情緒承接優先」為設計原則，每輪最多問一個問題，避免造成長者壓力。

---

## 相關文件

- `README.md` — 專案總覽與啟動方式。
- `docs/demo_realtime_companion_test_checklist.md` — Demo 前測試清單。
- `backend/stt_proxy/docs/memory_demo_flow.md` — 長期記憶展示驗證流程。
- `DEMO_TAIGI.md` — 台語短錄音 Demo 操作流程。
