# docs/TEAM_AGENTS.md — Team Agents 分工與協作

本檔是 Team Agents 分工的落地說明（人看的版本）。各 agent 的正式定義在 `.claude/agents/*.md`，架構真相在 `PROJECT_ARCHITECTURE.md`，變更流程在 `docs/CHANGE_REVIEW.md`。

---

## 1. 五個 agent

| Agent | 定位 | 正式定義 |
|-------|------|---------|
| `architecture-agent` | 守門人：架構、風險、審查、文件 | `.claude/agents/architecture-agent.md` |
| `realtime-voice-agent` | Realtime / 台語 / WebRTC / transcript | `.claude/agents/realtime-voice-agent.md` |
| `companion-memory-agent` | 陪伴回覆策略 / 長期記憶 / Care Alert 風險分析邏輯 | `.claude/agents/companion-memory-agent.md` |
| `backend-agent` | Node API / Telegram / Care Alert 持久化 / DB | `.claude/agents/backend-agent.md` |
| `frontend-ux-agent` | Flutter 長者端 + caregiver_web UI/UX | `.claude/agents/frontend-ux-agent.md` |

> 標記說明：✅ 擁有（可主導改）｜🤝 共享（需與 owner 對齊）｜🚫 禁止｜🔒 需 architecture-agent 核准

---

## 2. Ownership Matrix（可改 / 禁改檔案範圍）

### architecture-agent
- ✅ `CLAUDE.md` 🔒、`PROJECT_ARCHITECTURE.md` 🔒、`docs/**`、`README.md`、`.claude/agents/**`、根目錄設定檔說明
- 🚫 不直接大量改 `lib/**`、`backend/**` 的業務實作檔（只做協調式小修補與審查）

### realtime-voice-agent
- ✅ 獨佔：`lib/services/realtime_voice_service.dart` 🔒
- ✅ `lib/services/realtime_turn_coordinator.dart`、`realtime_timeout_registry.dart`、`taigi_asr_service.dart`、`taigi_asr_strategy.dart`、`asr_strategy_service.dart`、`language_routing_service.dart`、`taigi_text_detection_service.dart`、`speech_to_text_service.dart`、`openai_speech_to_text_service.dart`、`text_to_speech_service.dart`
- ✅ `lib/controllers/voice_agent_controller.dart`
- ✅ 測試：`test/realtime_*`、`test/voice_agent_controller_*`、`test/language_routing_service_test.dart`、`test/services/taigi_asr_service_test.dart`
- 🤝 `lib/controllers/conversation_controller.dart`（transcript 顯示）、後端 `/api/realtime/session`+`/api/realtime/call` 🔒
- 🚫 後端持久化、Telegram、UI 排版、記憶 / 陪伴策略邏輯

### companion-memory-agent
- ✅ `backend/companion/**`、`backend/memory/**`、`backend/stt_proxy/services/memoryExtractor.js`、`embeddingService.js`、`backend/stt_proxy/repositories/memoryRepository.js`
- ✅ `lib/services/companion_engine_service.dart`、`companion_reply_strategy_service.dart`、`companion_content_service.dart`、`memory_service.dart`、`emotion_services.dart`、`lib/controllers/memory_controller.dart`
- ✅ 測試：`backend/companion/*.test.js`、`backend/memory/*.test.js`、`test/companion_reply_strategy_service_test.dart`、`test/memory_management_screen_test.dart`（邏輯部分）
- 🤝 Care Alert 風險分級規則 🔒（權威值 `low/medium/high/urgent`，見 `PROJECT_ARCHITECTURE.md` §5.1；與 backend + frontend 對齊）、DB schema 🔒
- 🚫 `realtime_voice_service.dart`、UI 版面、Telegram 傳送實作、HTTP 路由結構

### backend-agent
- ✅ `backend/stt_proxy/server.js` 🔒、`backend/stt_proxy/services/careAlertStoreService.js`、`telegramNotifyService.js`、`taigiAsrService.js`、`tavilySearchService.js`、`backend/stt_proxy/db/**` 🔒、`backend/stt_proxy/repositories/**`、`backend/search/**`、`backend/agent/**`
- ✅ 測試：`backend/stt_proxy/services/*.test.js`、`backend/agent/*.test.js`、`backend/search/*.test.js`
- 🤝 `/api/realtime/*`（與 realtime-voice）、Care Alert 分級規則（與 companion-memory）
- 🚫 `lib/**`、`caregiver_web/**` UI；**絕不**把 `.env`、token、`backend/stt_proxy/data/*.json`（runtime）加進 git

### frontend-ux-agent
- ✅ `lib/screens/**`、`lib/widgets/**`、`lib/routes/**`、`lib/config/**`、`assets/**`、`caregiver_web/**`、`care_mall_website/**`
- ✅ `lib/controllers/care_alert_controller.dart`、`pet_controller.dart`、`pet_stats_controller.dart`、`app_navigation_controller.dart`、`profile_controller.dart` 等純前端狀態
- ✅ 測試：`test/*_screen_test.dart`、`test/home_screen_layout_test.dart`、`test/shop_screen_test.dart`、widget 測試
- 🤝 `pubspec.yaml`（新增 UI 套件）🔒
- 🚫 `realtime_voice_service.dart`、`backend/**` 行為、Telegram token 邏輯、API response 格式

---

## 3. 🔒 必須 architecture-agent 核准才能改的檔案

| 檔案 / 範圍 | 原因 |
|---|---|
| `CLAUDE.md` / `PROJECT_ARCHITECTURE.md` | 專案契約與原則 |
| `lib/services/realtime_voice_service.dart` | Realtime 主流程核心，不可改成 mock |
| `backend/stt_proxy/server.js`（路由 / response 形狀） | API 契約，跨前後端 |
| `/api/realtime/session`、`/api/realtime/call` | 兩 agent 共管主線 |
| `backend/stt_proxy/db/migrate.js` 與 DB schema | 資料結構不可逆 |
| Care Alert 共用資料結構與分級欄位（權威 `low/medium/high/urgent`，見 §5.1） | 三 agent 共用 |
| `pubspec.yaml` / `backend/stt_proxy/package.json` 依賴 | 影響 iOS 實機與安全 |
| `.claude/agents/*` | 分工治理本身 |
| 任何跨兩個以上 agent 擁有範圍的改動 | 邊界衝突 |

---

## 4. 協作規則

1. **API 契約是合約**：改 `server.js` response 形狀 → 先更新 `PROJECT_ARCHITECTURE.md` 第 4 節 → architecture-agent 核准 → 通知 frontend / companion-memory 同步。
2. **跨邊界先提案**：要改別人擁有的檔，不直接改，先在 `docs/CHANGE_REVIEW.md` 開一筆提案。
3. **Realtime SDP 共管**：realtime-voice 定義需求、backend 實作轉送，雙方都要 architecture-agent 核准。
4. **Care Alert 三段分離**：分析邏輯（companion-memory）→ 持久化 / 狀態 / 通知（backend）→ 顯示（frontend），共用同一份資料結構定義。
5. **Care Alert 權威分級唯一**：資料層 `riskLevel` 只用 `low / medium / high / urgent`（定義見 `PROJECT_ARCHITECTURE.md` §5.1）。`attention` / `normal` 僅為 **legacy 讀取相容值**，不是正式資料層 level；新寫入與 API 過濾一律用權威四級。程式對齊已由 **CR-0002（B3→B2→B1）完成**；各層暫留 legacy 容錯，未來移除見 **FU-0001**。**注意**：`backend/agent/**` 與 tool intent 的 `low/medium/high` 是「Agent Tool 風險」（§5.2），與 Care Alert 無關，勿混用。
6. **測試跟著檔案走**：改誰的檔補誰的測試；不可為了過測刪別人的測試。
7. **回報格式**：每批次用 CLAUDE.md 規定的「完成內容 / 修改檔案 / 測試結果 / 注意事項 / 下一步」。未跑測試要誠實說明。

---

## 5. 共同鐵則

- 不讀取 / 修改 / 輸出任何 `.env` 或含 key / secret / token 的檔案；需要環境變數只說「名稱」。
- 不把 Realtime 主流程改成 mock，不加 demo-only fallback，不顯示工程錯誤訊息給長者。
- 不把 `.env`、token、`backend/stt_proxy/data/*.json`（runtime）加進 git。
- 大改要分階段說明，採最小可控修改。

---

## 6. 如何呼叫某個 agent

在 Claude Code 中可用 sub-agent 形式委派，例如：
- 「用 `realtime-voice-agent` 檢查 DataChannel 事件解析」
- 「用 `architecture-agent` 審查這個 Care Alert 欄位調整提案」

各 agent 的系統提示與工具權限定義於 `.claude/agents/*.md`。
