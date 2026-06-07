# docs/CHANGE_REVIEW.md — 變更提案與 phase 批次審查

本檔記錄所有觸及 🔒 邊界或跨 agent 範圍的變更提案與審查結果。
由 `architecture-agent` 維護裁決；其他 agent 在動工前於此開提案。

相關文件：`PROJECT_ARCHITECTURE.md`（架構真相）、`docs/TEAM_AGENTS.md`（分工）、`.claude/agents/*.md`（agent 定義）。

---

## 何時需要開提案

只要符合以下任一，就要先在此開提案、取得 architecture-agent 核准，才能動程式：

- 改 🔒 檔案（`CLAUDE.md`、`PROJECT_ARCHITECTURE.md`、`realtime_voice_service.dart`、`server.js` 路由/response、`db/migrate.js`、Care Alert 共用資料結構、`pubspec.yaml` / `package.json` 依賴、`.claude/agents/*`）。
- 改到別的 agent 擁有的檔案。
- 一次改動跨兩個以上 agent 的範圍。
- 任何「大改」需要拆批次時。

不需開提案：在自己擁有範圍內、不碰契約、不碰 🔒 的小修補（仍須照 CLAUDE.md 回報格式回報）。

---

## 提案範本（複製到下方「提案紀錄」）

```markdown
### CR-XXXX：<一句話標題>
- 提出 agent：
- 日期：
- 動機 / 問題：
- 影響範圍（檔案）：
- 觸及 🔒？：是 / 否（哪些）
- 牽涉哪些 agent：
- 風險等級：low / medium / high
- 建議批次切分：
  - Batch 1：...
  - Batch 2：...
- 測試計畫：
- architecture-agent 裁決：⬜ 待審 / ✅ 核准 / 🔁 退回（理由）
- 完成狀態：⬜ 未開始 / 🚧 進行中 / ✅ 完成
```

---

## 待釐清項目（Open Items）

### OI-0001：Care Alert 風險分級「規格 vs 實作」不一致 — ✅ 已結案
- 來源：`PROJECT_ARCHITECTURE.md` 第 5 節。
- 問題：CLAUDE.md 規格寫 `low / medium / high / urgent`，但 `data/care_alerts.json` 實際出現 `urgent`、`attention` 等 `riskLevel` 代碼。
- 調查發現（architecture-agent）：專案實際存在**兩套不同**的風險分類，原本被混為一談——
  1. **Care Alert / 陪伴安全**：`companion_engine.js`、`safety_guard.js`、`lib/models/care_alert.dart` 使用舊三級 `normal / attention / urgent`。
  2. **Agent Tool 風險**：`backend/agent/tool_schemas.js`、`lib/models/agent_tool_intent.dart` 使用 `low / medium / high`（衡量工具執行風險，與長者狀態無關）。
- 裁決（architecture-agent，2026-05-29）：
  - Care Alert **資料層權威分級統一為 `low / medium / high / urgent`**，定義與 label、舊代碼對照表回填 `PROJECT_ARCHITECTURE.md` §5.1。
  - **`attention`（與 `normal`）自即日起視為舊代碼 / UI label，不再作為正式資料層 level**；新寫入與 API 過濾一律用權威四級。`attention` 對映 `medium`（個案 `needsHumanSupport=true` 可由 companion-memory-agent 升 `high`）；`normal` 對映 `low`。
  - Agent Tool 的 `low/medium/high` 維持原狀，於 §5.2 明確區隔，不納入本案範圍。
  - 程式與既有資料的實際對齊屬程式變更，本輪不動，延後至 **CR-0002**。
- 狀態：✅ 已結案（治理文件已對齊；程式對齊轉 CR-0002 追蹤）

---

## 提案紀錄（Change Requests）

### CR-0001：建立 Team Agents 治理文件
- 提出 agent：architecture-agent（初始化）
- 動機：導入 Team Agents 分工，建立治理基準文件。
- 影響範圍：`CLAUDE.md`（附加 Team Agents 章節）、`PROJECT_ARCHITECTURE.md`、`docs/TEAM_AGENTS.md`、`docs/CHANGE_REVIEW.md`、`.claude/agents/*.md`（5 個）。
- 觸及 🔒？：是（`CLAUDE.md`、`PROJECT_ARCHITECTURE.md`、`.claude/agents/*`）— 屬治理初始化。
- 風險等級：low（純新增文件，未改任何程式碼）。
- 測試計畫：不涉程式，無需測試。
- architecture-agent 裁決：✅ 核准（初始化）
- 完成狀態：✅ 完成

### CR-0002：Care Alert 程式對齊權威四級分級 — ✅ 已完成（2026-05-31）
- 提出 agent：architecture-agent（由 OI-0001 衍生）
- 動機：治理文件已將 Care Alert 權威分級定為 `low/medium/high/urgent`，但程式仍輸出舊三級 `normal/attention/urgent`，需分批對齊以避免資料層與文件長期不一致。
- 觸及 🔒？：是（Care Alert 共用資料結構）。
- 風險等級：medium（跨三 agent、牽涉既有 runtime 資料相容；需保留對舊值的向下相容讀取，避免破壞現有 alert 顯示）。
- 執行批次（依 architect 建議的「容錯讀優先」順序 B3 → B2 → B1 完成）：
  - **Batch 3（frontend-ux-agent）✅** — `lib/models/care_alert.dart` 改聯集 enum（`low/medium/high/urgent` + legacy `normal/attention`），`fromJson` 兩套皆讀、`toJson` 原樣輸出不提前切換、新增 `canonical` getter；`care_alert_screen.dart` 補齊四級顏色；`caregiver_web`（app.js/styles.css/index.html）支援兩套代碼。新增 7 個相容測試，flutter test 全綠、analyze 0 issue。
  - **Batch 2（backend-agent）✅** — `careAlertStoreService.js` 新增 `normalizeRiskLevel()`（normal→low、attention→medium、urgent→urgent、未知→low），寫入正規化＋filter 雙向正規化相容舊 `care_alerts.json`；`telegramNotifyService.js` 顯示四級中文 label；`server.js` 無需改動（正規化集中於 store＋telegram）。新增 9 測試，node --test 43/43。未觸及 runtime data。
  - **Batch 1（companion-memory-agent）✅** — `safety_guard.js` 直接輸出四級（urgent 門檻不變、新增 high/medium、normal→low）；`companion_engine.js` `RISK_LEVELS` 四級化＋`normalizeRiskLevel` 舊值讀取相容＋fallback `low`。新增 13 測試，node --test 38/38。下游 `urgent` 判斷（`next_strategy_planner.js`、`backend/memory/memory_policy.js`）皆 `=== "urgent"`，未退化。
- 結果：**Care Alert 全鏈四級一致** — safety_guard 產生四級 → companion_engine 驗證 → Flutter 接收/顯示 → notify → backend store 正規化/過濾 → caregiver_web 顯示 → Telegram 四級中文 label。
- 既有 `data/care_alerts.json` 舊資料（`normal/attention`）**未改寫**，靠各層讀取容錯正常顯示/篩選（符合不動 runtime data 的決定）。
- architecture-agent 裁決：✅ 核准並驗收
- 完成狀態：✅ 完成

### CR-0003：Care Alert Telegram Demo MVP — ✅ 完成（程式 + Flutter test，2026-05-31）
- 提出 agent：architecture-agent
- 動機：建立一條可在成果發表時展示的端到端 Care Alert 流程：長者與 AI 寵物對話 → Companion Safety 判斷 `riskLevel` → 產生 Care Alert → 後端儲存 → Telegram 通知長照人員 → caregiver_web 查看。

#### 完成摘要（三批皆已實作）
- **B1 backend-agent ✅**：新增 in-memory Telegram cooldown（`careAlertCooldown.js`，env 可關/調、預設 10 分、測試預設關）；notify 端只對 `high/urgent` 推播（`low/medium` 回 `skipped_low_risk`、冷卻期回 `skipped_cooldown`、推成功才計冷卻）；新增 demo 腳本（temp 檔、不實發 Telegram）。`node --test` 57/57。
- **B2 companion-memory-agent ✅**：新增 `companion_prompt_builder.buildCareAlertSummary`（白話、非診斷、含原因/訊號/建議行動，urgent 必含「立即確認安全」、low 不誇大）；`companion_engine` 以附加欄位 `careAlertSummary` 輸出，經 `/api/companion/analyze` 自動帶到 Flutter。`node --test` 50/50。
- **B3 frontend-ux-agent ✅（程式）**：`companion_analysis_result.dart` 解析 `careAlertSummary`；`voice_agent_controller._maybeCreateCareAlert` 的 triggerSummary 改為**優先採 `careAlertSummary`、缺則 fallback `implicitMeaning`**（只改該來源 2 行，未動 Realtime/SDP/DataChannel/狀態機）；caregiver_web 既有顯示已滿足（list/detail 顯示 triggerSummary、狀態流程文字清楚），未改動。
- **驗證狀態**：
  - `flutter analyze`（5 改動檔）：**No issues found** ✅
  - caregiver_web 靜態顯示測試 `care_alert_display.test.js`：**4/4 pass** ✅
  - Flutter widget/hook 測試（triggerSummary 優先序、fallback、畫面四級 label、無工程字）：**已撰寫，但本機 `flutter test` runner 卡在冷啟動（程序在跑但 CPU 近 0、數分鐘無輸出），未能跑完。未宣稱通過。**
- **待補驗證指令**（toolchain 正常時執行）：
  ```
  flutter test test/controllers/care_alert_hook_test.dart test/models/care_alert_test.dart test/screens/care_alert_screen_test.dart
  ```
  若仍卡住，建議先 `flutter clean` 或重啟 dart server 再跑。
- **forbidden files**：三批皆未觸及禁區 — 未動 `.env`/token、未寫入正式 runtime `data/*.json`、未改 `realtime_voice_service.dart` 與 Realtime/SDP 主流程；B3 對 `voice_agent_controller.dart` 僅做「triggerSummary 來源切換」小範圍修改（realtime-voice owner 授權範圍內）。
- 現況盤點（architecture-agent，2026-05-31）：MVP 鏈路**多數已存在**，本案以「驗證 + 強化 + 摘要可讀性 + demo 腳本」為主，非全新開發：
  - ✅ Flutter：`voice_agent_controller._maybeCreateCareAlert` 已在 `result.safety.needsHumanSupport === true`（= high/urgent）時建立 alert，並 per-turn 去重（`_lastAlertedTurnId`）。
  - ✅ Backend：`/api/care-alerts/notify`（持久化 + Telegram）、`/api/care-alerts`、`/:id`、`PATCH /:id/status`（new/acknowledged/resolved）皆已就緒；`globalLimiter` 全域生效。
  - ✅ caregiver_web：list / 篩選（status, riskLevel）/ stats / detail overlay / 狀態操作按鈕皆已存在。
  - ⚠️ 缺口：無「時間型 cooldown / 跨 turn 重複防止」（僅 Flutter per-turn 去重）；無結構化 `reason / recommendedAction / detectedSignals`（目前 `triggerSummary` 用 `implicitMeaning`、`category` 寫死 `other`）；缺可重現的 demo 測試資料/腳本。
- 觸及 🔒？：可能。若採「結構化新欄位」路線會動到 Care Alert 共用資料結構（§5）→ 需 architecture-agent 核准；建議 MVP 先走「摘要字串強化」路線（不改 schema）。詳見三批計畫。
- 風險等級：medium（跨三 agent；牽涉對外 Telegram 推播與 demo 穩定性）。
- 批次：B1 backend-agent、B2 companion-memory-agent、B3 frontend-ux-agent（皆已執行，見上方完成摘要）。
- 限制：每批小範圍、可獨立驗證；不得寫入正式 runtime `data/*.json`；不碰 `.env`/token；不改 Realtime/SDP 主流程。（已遵守）
- architecture-agent 裁決：✅ 程式驗收通過（analyze 乾淨 + 後端/ caregiver_web 測試綠）；**Flutter widget/hook 測試已於 2026-05-31 磁碟釋放後補跑 +17 全綠（見 FU-0002）**，驗證收尾完成。
- 完成狀態：✅ 完成（含 Flutter test 驗證）

### CR-0004：End-to-End Demo Validation — ✅ 完成（2026-05-31）
- 提出 agent：architecture-agent
- 動機：在成果發表前，對整條 Care Alert / 陪伴 demo 鏈路做一次端到端實測，確認 CR-0002 / CR-0003 的成果在實機/實服務上可運作、無假功能。
- 影響範圍：**無程式變更**（純執行既有測試與啟動服務做黑箱驗證）；僅本檔 Markdown 登記。
- 觸及 🔒？：否（未改任何 🔒 檔案、未改契約、未改 schema）。
- 牽涉哪些 agent：跨全部（backend / companion-memory / frontend-ux / realtime-voice 的產出都被驗證），但僅 architecture-agent 做驗收紀錄。
- 風險等級：low（唯讀驗證 + 文件登記）。
- 驗證結果：
  1. **`/api/companion/analyze` 通過** — 一般情境（散步/台語）→ `neutral`/`keep_company`/risk `low`/不存記憶；異常情境（睡不好+孤單+胸悶）→ `lonely`/`grounding`/`calm_down`/risk `medium`/`shouldSave:true`，`careAlertSummary` 為陪伴語氣（非診斷、非監控），台語語氣指示正確帶入 `nextStrategy`。
  2. **Telegram 真實推播通過** — `high` alert 經 `/api/care-alerts/notify` 實際送達照護 Telegram 群（回 `success:true`），訊息標示「[測試訊息]」。
  3. **high/urgent 推播、low/medium 不推播通過** — `low` 回 `skipped_low_risk`（仍持久化、供 caregiver_web 查看），符合 CR-0003 B1 規則。
  4. **cooldown 防洗版通過** — 同 `source+riskLevel` 之 `high` 立即重送回 `skipped_cooldown`，僅推成功才起算冷卻。
  5. **Caregiver Web API / 顯示 / CORS 通過** — `GET /api/care-alerts`、`GET /:id`、`PATCH /:id/status`（new→acknowledged，含時間戳；非法狀態回 400）皆正常；CORS 對瀏覽器 origin 回 `Access-Control-Allow-Origin`；靜態頁可開（`:8080` 對 `:3001`）。
  6. **Flutter Realtime 34 項測試通過** — `realtime_voice_service_test.dart`（+15）、`realtime_turn_coordinator_test.dart` + `realtime_timeout_test.dart` + `voice_agent_controller_realtime_lifecycle_test.dart`（合計 +19），全綠；log 中 "call failed / temporary call failure" 為測試 fixture 模擬重試，屬正常。
  7. **後端 `npm test` 126 pass / 0 fail** — 含 Telegram 規則、care alert store/list/status、companion engine 等。
  8. **caregiver_web static test 4/4 pass** — `care_alert_display.test.js`（四級中文 label、new→acknowledged→resolved 流程、篩選下拉）。
  9. **注意事項（環境）**：驗證過程發現**整機磁碟一度 100% 滿、僅剩 ~148Mi**，導致 Flutter 編譯器先 hang（0% CPU）後崩潰（`No space left on device, errno=28`）。已清除**可重生的 `build/`（~660M）**與崩潰 run 殘留的 `/tmp` flutter 編譯暫存（~150M），釋出至 ~916Mi 後 Flutter 測試即正常通過。**整機磁碟仍吃緊（約 900MB），強烈建議儘快清理**，否則後續 `flutter run` / iOS build 可能再次失敗。
- forbidden files：全程未讀取 `.env` 內容（僅程式檢查變數是否存在：`OPENAI_API_KEY` / `TELEGRAM_BOT_TOKEN` / `TELEGRAM_CARE_CHAT_ID` 皆已設定）；未寫入正式 runtime `data/*.json`（僅透過 API 產生 3 筆標示 `[測試]` 的 care alert，屬 demo 資料、可隨時清）；未改 `realtime_voice_service.dart` 與 Realtime/SDP 主流程；未 commit / 未 push。
- 與既有項目關聯：本案的磁碟根因發現，回答了 **FU-0002 所述「`flutter test` runner 卡在冷啟動」的成因（= 磁碟空間不足，非 toolchain bug）**；惟 FU-0002 點名的三個 Care Alert widget/hook 測試（`care_alert_hook_test` / `care_alert_test` / `care_alert_screen_test`）本案未涵蓋，仍待補跑。
- architecture-agent 裁決：✅ 核准並驗收（端到端鏈路實測通過，無假功能）
- 完成狀態：✅ 完成

### CR-0005：Demo & Presentation Polish — ⬜ 規劃中（2026-05-31 開立）
- 提出 agent：architecture-agent
- 里程碑基準：本案以穩定標籤 **`demo-v1`（commit `a9cd510`）** 為起點——該版本端到端鏈路已於 CR-0004 實測通過，進入「發表前體驗與呈現打磨」。
- 動機 / 問題：核心功能（Realtime 陪伴、長期記憶、Care Alert → Telegram → caregiver_web）皆已可運作，但發表前需提升「第一眼觀感、長者友善度、現場展示流暢度」，避免 demo 看起來像半成品或出現工程字樣。
- 影響範圍（檔案，預計）：
  - `caregiver_web/`（`app.js` / `styles.css` / `index.html`）— 視覺美化
  - Flutter 長者端 UI 文案/排版：首頁、Care Alert 相關畫面（`lib/screens/*`、相關 widget）— **僅文案與排版，不改狀態邏輯**
  - `docs/`（新增 demo 劇本 / 5 分鐘流程腳本，例如 `docs/DEMO_SCRIPT.md`）
- 觸及 🔒？：否（純 UI/UX 美化、文案口語化、文件）。**明確不碰**：`server.js` 路由/response 契約、`realtime_voice_service.dart` 與 Realtime/SDP 主流程、DB schema、Care Alert 共用資料結構、依賴升級。若任一打磨需求牽涉上述，須回此另開提案。
- 牽涉哪些 agent：frontend-ux-agent（主，Batch 1–3）、companion-memory-agent（若口語化涉及寵物回覆策略文字）、architecture-agent（Batch 4 劇本/流程與驗收）。
- 風險等級：low（不改行為、不改契約；最大風險是改文案時誤動狀態邏輯或破壞既有 widget 測試）。
- 建議批次切分（對應你列的四項優先）：
  - **Batch 1（frontend-ux-agent）— Caregiver Web 畫面美化**：排版、配色、四級風險的視覺層級（讓長照人員一眼看到重點與待處理 alert）、狀態按鈕與篩選的清晰度；維持現有 API 串接不變。
  - **Batch 2（frontend-ux-agent）— 長者端首頁 + Care Alert 畫面口語化**：大字、大按鈕、白話狀態提示、移除任何工程/debug/demo 字樣；「現在能不能講話」一眼可辨。
  - **Batch 3（架構/文件）— Demo 劇本整理**：把「長者對話 → 情緒/記憶 → 觸發 Care Alert → Telegram 通知 → caregiver_web 處理」整理成可照著走的劇本（含預備測試資料、口白）。
  - **Batch 4（架構/文件）— 5 分鐘展示流程**：把 Batch 3 壓縮成 5 分鐘 timeline（誰按什麼、預期畫面、fallback 話術），現場可直接照表操課。
- 測試計畫：每批小範圍、可獨立驗證——`flutter test`（UI widget / 文案不破壞既有測試）、`caregiver_web` 靜態測試、人工走查 demo 流程；不得為了改文案而刪既有測試。
- 限制：不改後端 API 行為、不改 Realtime/SDP 主流程、不碰 `.env`/token、不寫入正式 runtime `data/*.json`、不 commit/push（除非另行指示）。
- architecture-agent 裁決：⬜ 待審（規劃中；各 Batch 動工前由 frontend-ux-agent / architecture-agent 依範圍確認，low 風險且不觸 🔒 者可逕行於自有範圍執行並回報）
- 執行進度：
  - **Batch 1（frontend-ux-agent）✅** — caregiver_web 美化為「長者關懷管理中心」（4 卡儀表板、卡片化列表、四級風險視覺層級、詳情風險橫幅+突顯摘要+長者名稱、收合式連線設定）；static test 7/7。
  - **Batch 2（frontend-ux-agent）✅** — 長者端首頁加口語標語、語音按鈕白話化；Care Alert 改為長者端「今日關心紀錄」溫暖卡片（隱藏 riskLevel/triggerSummary/原話）。flutter analyze 乾淨、相關測試 10/10。
  - **Batch 3+4（architecture-agent）✅** — 新增 `docs/DEMO_SCRIPT.md`：Demo 前準備、角色分工、劇本 A/B/C（含 urgent 變體）、5 分鐘 timeline、救場手冊（含真實 API 補救指令）。劇本依實際行為標註：medium 不經 App 自動建立、需用預備 API 灌入管理端；high/urgent 走 App 自然流程。
- 完成狀態：✅ 完成（B1–B4 皆已交付；純 UI/UX + 文件，未觸 🔒）

### CR-0006：登入系統（Firebase Auth 正式架構 + demo mock）— 🚧 進行中（2026-05-31 開立）
- 提出 agent：architecture-agent
- 動機 / 問題：目前無帳號概念，`userId` 硬寫死 `default_user`、無 `elderId`，導致 Care Alert / 記憶 / 情緒 / 遊戲無法依長者聚合，也無法做健康後台。導入 Firebase Authentication（Email / Google / Apple）建立固定 `userId` / `elderId`。
- 影響範圍：`backend/stt_proxy/db/migrate.js` + `migrations/006_*.sql`（users/elders）、`backend/stt_proxy/package.json`（+firebase-admin）、`server.js`（+`POST /api/auth/session`）、新增 `services/auth/*`；Flutter（後續 Batch 3）：`pubspec.yaml`、`lib/services/auth/*`、Login/Register、`lib/app.dart` gate、`memory_controller.dart`/`search_service.dart` 的 `default_user` 改為登入後 elderId（保留 fallback）。
- 觸及 🔒？：是（migrate.js/schema、server.js 路由、package.json/pubspec.yaml 依賴、跨前後端）。
- 牽涉哪些 agent：backend-agent（B1）、frontend-ux-agent（B3）、architecture-agent（契約 + 審查）。
- 風險等級：medium（新增為主、不改既有路由形狀；最大風險是登入 gate 誤擋 Demo、或動到 Realtime）。
- 建議批次切分：
  - **Batch 1（backend-agent）**：migrations 006（users/elders）、firebase-admin（缺金鑰走 mock、不 crash）、`services/auth/{firebaseAdmin,sessionService}.js`、`POST /api/auth/session`、mock 化的 `node --test`（不需真金鑰）。
  - **Batch 3（frontend-ux-agent）**：Flutter Firebase 套件 + Login/Register + auth gate + secure storage + `default_user` 相容改動；Apple 未設定保留 UI/interface 不 crash。
- 限制：不改 `realtime_voice_service.dart` 與 Realtime/SDP；登入不得阻擋 Demo（mock flow + `default_user` fallback）；不把金鑰 / `google-services.json` / `GoogleService-Info.plist` 進 git；Firebase 缺 env 不 crash。
- 環境變數名稱：見 `PROJECT_ARCHITECTURE.md` §7 Firebase 區塊（只列名稱，未讀 .env）。
- 測試計畫：`services/auth/*.test.js`（mock `verifyIdToken`）、`POST /api/auth/session` endpoint test（已存在/新建分支、mock 模式）、`npm run check`。
- architecture-agent 裁決：✅ 核准 Batch 1（後端，本輪執行）；Batch 3（Flutter）待 Batch 1 ship 後另行排程。
- 完成狀態：🚧 進行中（Batch 1 後端 ✅；Batch 3 Flutter 已開提案，見下）

#### CR-0006 Batch 3：Flutter Auth Gate（🔒 依賴審查，architecture-agent 2026-05-31）

- 提出 / 審查：architecture-agent
- 目標：Flutter 端加入登入/註冊流程，**先以 mock auth + 後端 `POST /api/auth/session` 為主，不強制真 Firebase**。未登入進 LoginScreen，登入成功進原 App 首頁；auth API 失敗時 mock fallback 不擋 Demo。
- **依賴決議（🔒）：本批不新增任何 `pubspec.yaml` 依賴。** 經查現有依賴已足夠：
  - `http ^1.2.2`（已存在）→ 呼叫 `POST /api/auth/session`
  - `shared_preferences ^2.2.3`（已存在）→ 暫存 `userId/elderId/bindingStatus/authMode`（mock 階段可接受；正式 token 安全儲存延後到「真 Firebase 批次」再評估 `flutter_secure_storage`）
  - `provider ^6.1.2`（已存在）→ auth 狀態管理
  - `lib/config/app_config.dart` 的 `backendBaseUrl`（已存在）→ 組 auth session URL
  - **刻意不加 `firebase_core` / `firebase_auth` / `google_sign_in` / `sign_in_with_apple` / `flutter_secure_storage`**，避免 iOS build 風險與原生設定（`GoogleService-Info.plist`）耦合。真 Firebase 留待後續獨立批次另開 🔒 提案。
- 允許修改檔案（frontend-ux-agent owner）：
  - 新增 `lib/services/auth/auth_service.dart`（abstraction：`login()` mock + `createSession()` 呼叫後端 + 回 `userId/elderId/bindingStatus/authMode`）
  - 新增 `lib/services/auth/session_api_service.dart`（HTTP POST `/api/auth/session`，比照既有 service 慣例與 `app_config.backendBaseUrl`）
  - 新增 `lib/models/auth_session.dart`（session 結果 model）
  - 新增 `lib/controllers/auth_controller.dart`（provider，登入狀態 + 持久化 + fallback）
  - 新增 `lib/screens/login_screen.dart`、`lib/screens/register_screen.dart`（長者友善、大字大按鈕、口語繁中、Apple/Google 鈕保留但標示「即將推出」不 crash）
  - 修改 `lib/app.dart`（`_AppRootState.build` 第 ~406 行：auth gate **插在 onboarding 判斷之前** → 未登入回 LoginScreen，已登入再走既有 onboarding/MainShell）
  - 修改 `lib/main.dart`（若需註冊 AuthController provider）
  - （相容點，可本批或 Batch 5）`lib/controllers/memory_controller.dart`、`lib/services/search_service.dart` 的 `default_user` → 登入後 elderId，**保留未登入 fallback `default_user`**
- 禁止修改檔案（紅線）：
  - `lib/services/realtime_voice_service.dart`（🔒 Realtime 主流程）
  - `lib/controllers/voice_agent_controller.dart` 的 Realtime/SDP/DataChannel/狀態機
  - `backend/**`（後端契約本批不動）
  - `pubspec.yaml`（本批裁決不動）
  - 任何 `.env` / token / `GoogleService-Info.plist` / `google-services.json`
  - `backend/stt_proxy/data/*.json`
- 實作批次切分（每批小、可獨立驗證）：
  - **B3a**：AuthService/SessionApiService/AuthSession model + auth_controller（含 mock login、呼叫後端、fallback）+ 單元測試（不碰 UI、不碰 Realtime）。
  - **B3b**：LoginScreen / RegisterScreen UI（長者友善）+ widget test。
  - **B3c**：`app.dart` auth gate 接線 + `default_user` 相容點切換（保留 fallback）+ gate/相容測試。
- 測試項目：
  - auth_controller：mock 登入成功→狀態變 authenticated、持久化、登出清除；後端回 userId/elderId/bindingStatus/authMode 正確解析。
  - session_api_service：200 解析、非 200 / 連線失敗 → fallback（authMode 標 mock、elderId=default_user）不丟例外。
  - app gate：未登入顯示 LoginScreen；已登入未 onboard 顯示 OnboardingScreen；已登入已 onboard 顯示 MainShell。
  - Apple/Google 鈕點擊不 crash（顯示「即將推出」）。
  - 相容：未登入時 memory/search 仍送 `default_user`；登入後送 elderId。
  - 回歸：既有 Realtime / care alert widget 測試不被改壞；`flutter analyze` 乾淨。
- 風險與 rollback：
  - 風險：①auth gate 誤擋既有 Demo 流程（緩解：fallback + 「跳過/訪客」路徑保 `default_user`，API 失敗不阻斷）；②誤動 Realtime（緩解：紅線檔清單 + 只在上層改 userId 來源）；③`default_user` 切換破壞既有記憶/搜尋測試（緩解：保留 fallback、相容測試先行）。
  - rollback：本批全為**新增檔案 + `app.dart`/`main.dart` 少量接線 + 兩處 `default_user` 改動**，無 schema、無依賴、無後端變更；`git revert` 單一 commit 即可完全回復，不影響已 ship 的後端 checkpoint（`061d510`）。
- 限制：不 commit、不 push（除非另行指示）。
- architecture-agent 裁決：✅ 核准（**不動 pubspec.yaml**、不碰 Realtime/backend/.env）；frontend-ux-agent 可依 B3a→B3b→B3c 執行。
- 執行進度：
  - **B3a（frontend-ux-agent）✅** — 新增 AuthSession model / SessionApiService / AuthService / AuthController（mock auth + `/api/auth/session` + 失敗 fallback `default_user`、未登入 getter fallback）；flutter analyze 乾淨、16/16 測試綠。未動 pubspec/Realtime/app.dart/backend。
  - **B3b（frontend-ux-agent）✅** — 新增長者友善 LoginScreen / RegisterScreen + 共用大按鈕元件；主按鈕走 `loginAsDemoUser()`（loading/成功 callback/白話失敗三態），Google/Apple/Email 僅保留 UI 顯「即將推出」不 crash、不接真 SDK；analyze 乾淨、9/9 測試綠。未接 app.dart gate。
  - **B3c（frontend-ux-agent）⬜ 待執行** — 見下方接線核准。
- 完成狀態：🚧 進行中（3a/3b ✅；3c 已核准待執行）

#### CR-0006 Batch 3c：Auth Gate 接線核准（architecture-agent，2026-05-31）

把 3a 的 `AuthController` 與 3b 的 `LoginScreen/RegisterScreen` 接進 `lib/app.dart`。`app.dart` 屬 frontend-ux-agent 範圍但為 App root 敏感接線點，本紀錄逐項核准接線範圍。

- **核准接線點（僅限以下，對齊現況行號）**：
  1. **Provider 註冊**：在 `app.dart` 既有 `MultiProvider` providers 清單（~line 280 前）新增 `ChangeNotifierProvider<AuthController>`（內部構建 AuthService→SessionApiService，比照既有 provider 慣例）。
  2. **啟動 restore**：在 `_AppRootState.didChangeDependencies` 既有 postFrame 載入區（~line 368-387）新增 `context.read<AuthController>().restore();`（與既有 `profileController.load()` 等並列；不阻塞、不 await 卡住 UI）。
  3. **build() gate**：在 `_AppRootState.build`（~line 401-410）於既有 `profile` 判斷**之前**插入 `final auth = context.watch<AuthController>();` 並依 `auth.status` 分流：
     - `loading` → 溫暖 loading 畫面（白話，如「正在為你準備…」，可沿用既有 CircularProgressIndicator 包裝）。
     - `unauthenticated` **或 `error`** → `LoginScreen`（**error 不可變成死路**，必須回登入頁讓長者可重試 / 重新 Demo 登入）。
     - `authenticated` → **落回既有流程**（`profile.isLoading` → `!hasCompletedOnboarding` → `OnboardingScreen` / `MainShell`），既有 onboarding/MainShell 邏輯一字不改。
  4. **Login↔Register 切換**：`LoginScreen.onRegister` 以 `Navigator.push` 疊上 `RegisterScreen(onBackToLogin: () => Navigator.pop())`；`LoginScreen.onSignedIn` 可為 no-op（登入成功 AuthController notify → _AppRoot rebuild → 自動進 MainShell）或僅關閉殘留 Register 頁。**RegisterScreen 僅畫面切換、不接真 SDK。**

- **Demo 安全鐵則（核准條件，違反即退回）**：
  - `error` 狀態 → 顯示 LoginScreen（可重試），**不得鎖死或顯示工程錯誤**。
  - `restore()` 必須永遠收斂到終態（authenticated/unauthenticated/error），不得讓 gate 永久停在 loading。
  - 未登入時 `currentElderId` 維持 `'default_user'` fallback（3a 已具備），確保下游記憶/搜尋/Demo 不壞。
  - API 失敗時 `loginAsDemoUser()` 仍可成功（走 3a 的 mock fallback），長者仍能進入 App。

- **禁止（紅線，與 3a/3b 一致）**：不改 `realtime_voice_service.dart`、不改 `voice_agent_controller.dart` 的 Realtime/SDP/DataChannel/狀態機、不改 `backend/**`、不改 `pubspec.yaml`、不碰 `.env`/token、不碰 `backend/stt_proxy/data/*.json`、不 commit / 不 push。
  - 特別提醒：**不得改動 `_onGenerateRoute`、`MainShell`、既有 onboarding 判斷的行為**；gate 只「在前面加一層」，不重寫既有分流。

- **允許修改檔案**：`lib/app.dart`（僅上述三接線點 + 必要 import）。如 Login/Register callback 簽章需微調，可回頭小改 `lib/screens/login_screen.dart` / `register_screen.dart`（3b 自有範圍）。

- **測試項目**：
  - gate：`status=loading`→loading 畫面；`unauthenticated`→LoginScreen；`error`→LoginScreen（可重試）；`authenticated` 且未 onboard→OnboardingScreen；`authenticated` 且已 onboard→MainShell。
  - 啟動呼叫 `restore()` 一次。
  - demo 登入成功後 root 重建進入既有流程（authenticated 分支）。
  - 回歸：既有 `home_screen_layout_test` / onboarding / Realtime / care alert widget 測試不被改壞；`flutter analyze` 乾淨。

- **風險與 rollback**：
  - 風險：①gate 誤擋既有 Demo（緩解：error 也走 LoginScreen + mock fallback 必成功 + default_user）；②restore 卡 loading（緩解：終態收斂 + 不 await 阻塞）；③誤動既有 onboarding/MainShell 分流（緩解：只在前面加層，既有分支零改動 + 回歸測試）。
  - rollback：本批僅 `app.dart` 三處接線（+provider、+restore 呼叫、+gate 前置層）；`git revert`/還原 app.dart 單檔即可完全回復，3a/3b 新檔可獨立保留不受影響，且不影響後端 checkpoint `061d510`。

- architecture-agent 裁決：✅ **核准 B3c 接線**（限上述三接線點與 Demo 安全條件）。frontend-ux-agent 可執行。

#### Checkpoint Review（architecture-agent，2026-05-31）— CR-0006 Batch 3a/3b/3c（Flutter 登入）

- 分支：`feat/auth-admin-backend`；審查 read-only，未改程式。
- 觸及 🔒：`lib/app.dart`（auth gate 接線）。**未**觸及 realtime-voice / backend / companion-memory 範圍。風險 low。
- 9 項逐項查證：**全數 PASS**（1 個 benign WARN）：
  1. app.dart gate 只加一層 — PASS（`app.dart:411-422` build 只回 `AuthGate()`；authenticated 分支 `:454-459` 把既有 `profile.isLoading→spinner / !hasCompletedOnboarding→Onboarding / else→MainShell` 原封搬入；`_onGenerateRoute`、`MainShell` body 未動）。WARN：`_AppRoot`→`AppRoot` 公開化為 testability，行為等價且已被 `app_auth_gate_test` 覆蓋。
  2. Realtime 未動 — PASS（change set 無 `realtime_voice_service.dart`/`voice_agent_controller.dart`）。
  3. pubspec 未動 — PASS（新檔 import 僅 provider/shared_preferences/http/flutter，皆已宣告；無 firebase/google_sign_in/sign_in_with_apple/flutter_secure_storage SDK import）。
  4. backend 未動 — PASS（僅 `data/*.json` runtime 噪音，非本批，無 .js 變更）。
  5. fallback 保證 demo 不被擋 — PASS（未登入 currentElderId/currentUserId=default_user；SessionApiService 任何失敗回 mockFallback 不丟例外；gate error→LoginScreen 非死路；皆有測試）。
  6. 未接真第三方 SDK — PASS（Google/Apple/Email 僅顯示「即將推出」snackbar）。
  7. `flutter analyze` — PASS（全專案 No issues found）。
  8. 回歸測試 — PASS（指定 8 檔實跑：**41 passed / 0 failed**）。
  9. 值得 commit — PASS。
- 裁決：✅ 核准（含對 🔒 `lib/app.dart` 的修改）。純前端外加一層 gate，不動主線/契約/依賴，安全網與測試完整。
- Commit 切分：本批應 commit 15 檔（3a/3b/3c 新增 14 檔 + `lib/app.dart`）；排除 runtime `data/*.json`、tooling 噪音（repomix-output.xml / .claude/worktrees / .claude/scheduled_tasks.lock / devtools_options.yaml）、與本批無關的 frontend-ux 文案改動（home_screen/settings_screen/care_alert_screen/care_alert_screen_test + caregiver_web/*）、`docs/DEMO_SCRIPT.md`。
- 下一步：可進 **Batch 3d**（memory/search 的 `default_user` → `AuthController.currentElderId` wiring），無前置阻擋。紅線：3d 不得延伸到 `realtime_voice_service.dart` 或 `server.js` API 契約；若需後端依 elderId 分流則另開跨邊界提案並先更新 `PROJECT_ARCHITECTURE.md`。
- 完成狀態（CR-0006）：Batch 1 ✅ / Batch 3a ✅ / 3b ✅ / 3c ✅（已 review 通過，待 commit）；Batch 3d 待排程。

### CR-0007：健康分析後台 Admin API + caregiver_web — 🚧 進行中（2026-05-31 開立）
- 提出 agent：architecture-agent
- 動機 / 問題：caregiver_web 目前只看得到 Care Alert，要擴充為「長者健康分析後台」（Dashboard 六指標總覽、長者個人分析頁、生理 / 心理 / 情緒 / 遊戲退化指標）。
- 影響範圍：`server.js`（+`/api/admin/*` 路由）、新增 `services/admin/*` 與 demo 資料產生器、`emotion_history`/`elder_health_metrics`/`game_cognitive_metrics`（migrations 007）；caregiver_web（後續 Batch 4）：Dashboard / 長者列表 / 個人分析頁 / 卡片圖表。
- 觸及 🔒？：是（server.js 路由、migrate.js/schema）。
- 牽涉哪些 agent：backend-agent（B2 API）、frontend-ux-agent（B4 UI）、architecture-agent（契約 + 審查）。
- 風險等級：medium（純新增 GET 路由與只讀分析；demo 資料須確定性、不得出現 demo/fake 字樣於 UI）。
- 建議批次切分：
  - **Batch 2（backend-agent）**：migrations 007（emotion_history / elder_health_metrics / game_cognitive_metrics）、`/api/admin/overview`、`/api/admin/elders`、`:elderId`、`/physio`、`/emotion`、`/game-metrics`；demo 資料產生器（確定性 seed，可由 elderId 推導）；每端點 `*.test.js`。
  - **Batch 4（frontend-ux-agent）**：caregiver_web 健康後台 UI（卡片 + 輕量圖表，串上述 API）。
- 限制：純新增路由、不改既有 Care Alert API 形狀；demo 資料 UI 不得出現 demo/fake/debug 字樣；不碰 Realtime。
- 測試計畫：每端點 `node --test`（temp JSON / mock）、`npm run check`；caregiver_web 沿用 static test 模式。
- architecture-agent 裁決：✅ 核准 Batch 2（後端，本輪執行）；Batch 4（UI）待後端 ship 後排程。
- 完成狀態：🚧 進行中（Batch 2 後端）

### CR-0008：Care Alert 綁定 elderId — 🚧 進行中（2026-05-31 開立）
- 提出 agent：architecture-agent
- 動機 / 問題：Care Alert 目前無 `elderId`，健康後台無法依長者聚合警示。為 §5 共用結構新增 nullable `elderId`。
- 影響範圍：`backend/stt_proxy/services/careAlertStoreService.js`（`normalizeAlert` 加 `elderId`、`listAlerts` 支援 `?elderId=` 過濾）、`server.js`（`GET /api/care-alerts` 接受 `elderId` query）、`PROJECT_ARCHITECTURE.md` §5（已更新）。Flutter 端送出 alert 帶 elderId 屬後續 Batch 5。
- 觸及 🔒？：是（Care Alert 共用資料結構 §5）。
- 牽涉哪些 agent：backend-agent（持久化 / 過濾）、frontend-ux-agent（顯示，後續）、companion-memory（分析來源，後續）。
- 風險等級：low（nullable 新增欄位、向下相容、不改既有欄位與既有測試）。
- 限制：舊 `care_alerts.json` 不改寫、缺欄位視為 null；既有 notify/list/status 既有欄位與形狀不變；既有測試不可改壞。
- 測試計畫：`careAlertStoreService.test.js` 加 elderId 寫入/過濾/向下相容案例；既有測試全綠。
- architecture-agent 裁決：✅ 核准（隨 CR-0007 Batch 2 一併實作，因健康後台需依 elderId 聚合）。
- 完成狀態：🚧 進行中（Batch 2 一併）

#### Checkpoint Review（architecture-agent，2026-05-31）— CR-0006 B1 / CR-0007 B2 / CR-0008

- 範圍：文件（PROJECT_ARCHITECTURE §10/§11/§5 + 本檔 CR）+ 後端新增（migrations 006/007、`services/auth/*`、`services/admin/*`、6 條 `/api/admin/*`、`POST /api/auth/session`、careAlertStore `elderId` nullable）。未觸 Realtime / Flutter / UI。
- 唯讀驗證：`npm run check` EXIT 0；`npm test` **160/160 pass、0 fail**；`git status` 無 staged 且 runtime `data/{users,elders,care_alerts}.json` 未追蹤；`git check-ignore` 確認三檔命中 `.gitignore`。
- 10 項 checkpoint 檢查：**全數 PASS**（CR 狀態、契約↔實作一致、API 測試覆蓋、依賴必要性、.gitignore、runtime 未 stage、migration 順序、mock auth 不擋 demo、elderId 向下相容、可獨立回復）。
- 契約一致：§10.2 response 8 欄與 `sessionService.toSessionResult` 對齊；§10.3 schema 與 006/007 欄位逐項相符；§11 六端點形狀與 `adminAnalysisService` + `healthMetrics` 一致。auth/admin 端點 + service 雙層測試覆蓋齊全。
- 相容性：CR-0008 `elderId` 為 nullable 新增欄位——未帶寫 null、`?elderId` 明確帶才過濾（嚴格 ===）、舊資料缺欄位不被誤排除（已測）；既有 riskLevel/status/排序/形狀未變。
- 依賴：`firebase-admin ^13.0.2` 為動態 require + try/catch，缺套件/缺金鑰時 `isConfigured()=false` 安靜走 mock，不 crash、不擋 Demo（已實測未安裝套件下全綠）。
- 裁決：✅ 通過驗收，視為一個乾淨、可獨立回復的 checkpoint。**commit 範圍須顯式挑檔**：排除 runtime `data/*.json`（含歷史已追蹤的 companion_memories/memory_events/search_*）、tooling 噪音（`repomix-output.xml`、`.claude/worktrees/`、`.claude/scheduled_tasks.lock`、`devtools_options.yaml`）與本批無關的 caregiver_web / lib/screens 改動。
- 後續放行：**CR-0006 Batch 3（Flutter 登入）可開始**；動工前 `pubspec.yaml` 新增 Firebase 套件（🔒）須先於本檔開提案核准；紅線 `realtime_voice_service.dart` 不得改、未登入保留 `default_user` fallback。

---

### CR-0006 Batch 3d：memory / search 的 elderId 接線（提案＋核准，architecture-agent 2026-05-31）

- 提出 / 審查：architecture-agent；執行 owner：frontend-ux-agent
- 目標：把記憶 / 搜尋的 `userId` 由硬寫 `default_user` 改為由 `AuthController.currentElderId` 集中供給，建立「登入後綁定真實 elderId」的 plumbing，**但完全不破壞 Demo、不動後端 API 契約、不碰 Realtime**。
- 現況盤點（已驗證）：`default_user` 權威來源僅 2 處——`lib/controllers/memory_controller.dart`（`_userId` 預設 + `_init()` 硬寫）、`lib/services/search_service.dart`（`search()` body 硬寫）。後端 `/search` 與 memory API **早已接受 `userId` 參數**，本批只改傳入值，不改 API 形狀（不踩 🔒 `server.js`）。
- ⚠️ 先決風險（已拍板）：`auth_service.dart` 的 `_deriveDemoUid()` 每次回 `demo-${timestamp}` → 每次 demo 登入產生新空 elder。若直接綁 `currentElderId`，demo 登入後對到空 elder，seed 記憶（key=`default_user`）消失→「寵物記得你」失效。
- **核准決策（使用者 2026-05-31 確認）：**
  1. mock / demo session → `currentElderId = default_user`（Demo 保護）
  2. 僅「真 Firebase session（authMode=='firebase'）」使用 `session.elderId`
  3. 未登入 / 未知 authMode → `default_user`
  4. 接線限定 **`app.dart` 集中注入**，盡量不動 `conversation_controller`
  5. 本批只做 Flutter 端 elderId 傳遞，不改後端 API、不碰 Realtime / SDP、不動 `pubspec.yaml`
- 允許修改：`lib/controllers/auth_controller.dart`（`currentElderId`/`currentUserId` 加 authMode 解析）、`lib/controllers/memory_controller.dart`（新增 `syncUserId(String)`，移除 `_init()` 硬寫，保留空字串→`default_user`，**不重建 controller、不清 UI 狀態**）、`lib/services/search_service.dart`（`search()` 加 optional `userId`，預設 `default_user`，body 用傳入值）、`lib/app.dart`（集中監聽 `AuthController` → `MemoryController.syncUserId`）、`test/**`。
- 禁止修改：`lib/services/realtime_voice_service.dart`、`lib/controllers/voice_agent_controller.dart` 的 Realtime/SDP/DataChannel/語音狀態機、`backend/**`、`pubspec.yaml`、`caregiver_web/**`、`.env`/token、`backend/stt_proxy/data/*.json`、`lib/models/auth_session.dart`、`lib/services/auth/auth_service.dart` 對外介面。
- 測試清單：AuthController（mock→default_user、firebase→session.elderId、未知→default_user）、MemoryController（`syncUserId` 可切換、`syncUserId('')` fallback、預設 default_user、不丟去重狀態）、SearchService（預設 body `userId=default_user`、傳入 elderId 生效、4xx/例外仍 fallback）、端到端（demo 登入後 MemoryController.userId 仍 default_user）；回歸 `flutter analyze` + 既有 `test/` 全綠。
- Rollback：單一 feature commit（branch `feat/auth-admin-backend`，不 push）；純加法（`search` optional 參數有預設值、`syncUserId` 不傳即維持 default_user），`git revert` 即恢復「全程 default_user」；後端零改動、無 migration、無資料相容問題。
- architecture-agent 裁決：✅ 核准執行（範圍如上，frontend-ux-agent 主導）。
- 完成狀態：✅ 已完成（frontend-ux-agent 實作 + architecture-agent checkpoint commit `c71d90c`；`flutter test` 188/188、analyze 全綠；未 push）。

---

### CR-0006 Batch 4：Firebase Auth 正式登入（🔒 依賴＋原生設定提案，architecture-agent 2026-05-31）

- 提出 / 審查：architecture-agent；執行 owner：frontend-ux-agent（Flutter 端為主）
- 目標：在既有 mock auth / `AuthController` / `LoginScreen` 架構上，加入正式 Firebase 登入能力——**Email 註冊/登入 →（其次）Google Sign-In**，Apple 暫不做（UI 保留「即將推出」）。登入成功取 Firebase ID Token → 呼叫既有 `POST /api/auth/session`（`provider='email'|'google'`）→ 後端回 `userId/elderId/bindingStatus/authMode` → `AuthController` 儲存 session。**Demo 快速登入永遠保留為 fallback。**
- 關鍵現況（已驗證，決定本批範圍）：
  - 後端 `services/auth/firebaseAdmin.js` 已能驗證真實 ID Token（`GOOGLE_APPLICATION_CREDENTIALS` 或 `FIREBASE_PROJECT_ID/CLIENT_EMAIL/PRIVATE_KEY`），`POST /api/auth/session` 與 `session_api_service.createSession({firebaseUid, idToken, provider, email, displayName, photoUrl})` **早已支援真實 token** → **後端 API 契約零改動**。
  - `AuthSession.authMode` 已有 `firebase|mock` 兩態；`AuthController.currentElderId` 已是「firebase→後端 elderId、其餘→default_user」（Batch 3d 完成）→ **身份解析邏輯零改動**。
  - 現況尚無任何 Firebase 套件 / 原生設定；iOS deployment target 13.0；Android 用 `flutter.minSdkVersion`（Firebase Auth 需 ≥23，須確認/上修）。
- ⚠️ 架構依賴提醒：即使前端接上真 Firebase，**只有當後端 Firebase 環境變數已設定、`firebaseAdmin.isConfigured()=true` 時，後端才會回 `authMode='firebase'` 並給真實 elderId**；否則後端走 mock → `currentElderId` 仍為 `default_user`。本批前端完成後，需「設定後端 Firebase env（手動 ops，不在本批 code）」才會真正綁定真實 elderId。

#### 1. 需要新增的 `pubspec.yaml` 套件（🔒）
- `firebase_core`、`firebase_auth`、`google_sign_in`（本批）。
- **不**加 `sign_in_with_apple`（Apple 暫緩，UI 維持「即將推出」）。
- 實際版本：動工前以 `flutter pub add` 解析與 Flutter SDK 相容的最新穩定版並**回報鎖定版本待核准**；注意 `google_sign_in` v7 為實例化 API（與 v6 不同），實作須對齊解析到的版本。

#### 2. iOS 需要哪些設定
- 將 `GoogleService-Info.plist` 放入 `ios/Runner/`（經 Xcode 加入 target；**不進版控**）。
- `ios/Runner/Info.plist` 新增 `CFBundleURLTypes`（Google 的 `REVERSED_CLIENT_ID`）；google_sign_in 可能需 `GIDClientID`。
- 確認 iOS deployment target（現 13.0）符合解析到的 Firebase iOS SDK 需求，必要時上修。
- 須 `pod install`（CocoaPods）；專案已用 `SceneDelegate`，Google 回呼 URL handling 屬原生設定風險點，動工時驗證。

#### 3. Android 是否需要設定
- 需要。`android/build.gradle.kts`（project）與 `android/settings.gradle.kts` 加入 `com.google.gms.google-services` plugin；`android/app/build.gradle.kts` apply 該 plugin 並確認/上修 `minSdk≥23`。
- `google-services.json` 放 `android/app/`（**不進版控**）。Google 登入需在 Firebase/Console 設定 SHA-1。

#### 4. Firebase Console 需要啟用哪些登入方式
- **Email/Password**、**Google**（本批）。Apple **不啟用**（暫緩）。
- 在 Firebase 專案新增 iOS App（bundle id）與 Android App（package name）以產生 plist/json；設定 OAuth 同意畫面 / support email；Android 註冊 SHA-1。

#### 5. 是否需要 `google-services.json` / `GoogleService-Info.plist`
- 兩者都需要（Android `google-services.json`、iOS `GoogleService-Info.plist`）。
- **一律 gitignore、永不 commit、永不貼進訊息**。`.gitignore` 新增：`ios/Runner/GoogleService-Info.plist`、`android/app/google-services.json`、`**/GoogleService-Info.plist`、`**/google-services.json`。

#### 6. 哪些檔案允許修改
- `pubspec.yaml`（🔒，本提案核准後）。
- 新增 `lib/services/auth/firebase_auth_service.dart`（包一層 `FirebaseAuth`+`GoogleSignIn`，回傳 `uid/idToken/email/displayName/photoUrl`；以 interface 注入，便於測試）。
- `lib/services/auth/auth_service.dart`（**新增** `registerWithEmail/signInWithEmail/signInWithGoogle`，內部呼叫 firebase_auth_service 取 token 再 `createSession`；**`mockLogin` 維持不動**，Demo fallback 保留）。
- `lib/controllers/auth_controller.dart`（**新增** `loginWithEmail/registerWithEmail/loginWithGoogle`；`loginAsDemoUser` 維持不動；失敗進 `error` 但不可死路）。
- `lib/screens/login_screen.dart`、`lib/screens/register_screen.dart`（接 Email 欄位驗證 + Google 鈕；Demo 鈕保留；Apple 維持「即將推出」）。
- `lib/main.dart`（`Firebase.initializeApp()` 包 try/catch，**初始化失敗仍可進 App 且 Demo 可用**）。
- `ios/Runner/Info.plist`、`android/build.gradle.kts`、`android/app/build.gradle.kts`、`android/settings.gradle.kts`、`.gitignore`。
- `test/**`（新增 mock Firebase/Google 的測試）。

#### 7. 哪些檔案禁止修改
- `lib/services/realtime_voice_service.dart`、`lib/controllers/voice_agent_controller.dart` 的 Realtime/SDP/DataChannel/語音狀態機。
- `backend/**`（含 `server.js` 路由/response、`firebaseAdmin.js`、`sessionService.js`）——**API 契約不變**；後端啟用 Firebase 僅靠設定環境變數（手動 ops，非本批 code）。
- `lib/services/auth/session_api_service.dart` 的對外契約、`lib/models/auth_session.dart`、`AuthController.currentElderId` 的解析規則（皆已支援本批，不需動）。
- `caregiver_web/**`、Care Alert 結構。
- 任何 `.env` / key / secret / token / `*.plist` / `google-services.json` 內容。

#### 8. 實作批次
- **4a 地基**：pubspec 加 Firebase 套件（回報鎖定版本）+ `Firebase.initializeApp` safe try/catch + iOS/Android 原生設定 + `.gitignore`。驗收：App 能啟動、**即使缺 plist/json 或 init 失敗，Demo 登入仍可進 App**；可 build。
- **4b Email**：firebase_auth_service email 方法 + AuthService + AuthController + Login/Register 接線（`provider='email'`，idToken→session）。測試 + 真機手動驗證。
- **4c Google**：Google Sign-In 流程 + 鈕接線（`provider='google'`）。測試 + 真機手動驗證。
- Apple：本批不做（UI 不變）。每個 sub-batch 各自 review 後獨立 checkpoint commit。

#### 9. 測試方式
- 單元/Widget 測試**一律不得依賴真 Firebase 專案**（CI 無 plist/json）：Firebase/Google 行為走可注入 interface + fake。
- AuthService：`signInWithEmail/registerWithEmail/signInWithGoogle` 成功→以正確 `provider` 呼叫 `createSession` 回 session；失敗→拋出可處理錯誤且 Demo 仍可用。
- AuthController：三個新登入方法更新狀態；失敗進 `error` 非死路；`loginAsDemoUser` 仍可用。
- main.dart：模擬 `Firebase.initializeApp` 失敗→仍進 LoginScreen 且 Demo 可登入。
- Widget：Email 欄位驗證、Google 鈕觸發、Demo 鈕仍動、Apple 顯示「即將推出」。
- 回歸：既有 188 測試全綠、`flutter analyze` 乾淨。
- 手動清單（需真 Firebase 專案 + plist/json，無法自動化）：真機 Email 註冊/登入、Google 登入、後端設好 Firebase env 後確認回 `authMode='firebase'` 與真實 elderId。

#### 10. rollback 方式
- 每個 sub-batch = `feat/auth-admin-backend` 上獨立 commit、不 push → 逐批 `git revert`。
- 依賴 rollback：移除 `pubspec` 的 `firebase_*` + 還原原生設定；因 `Firebase.initializeApp` 包 try/catch 且 Demo 登入恆在，半套狀態也不擋 Demo。
- plist/json 為 gitignore → rollback 僅動已提交的 gradle/Info.plist scheme/pubspec，無金鑰清理問題。
- 最壞情境（Demo 當天）：revert 4c/4b/4a → 回到目前 mock-only auth（`c71d90c`），完整可用。

- architecture-agent 裁決：✅ 核准依賴與原生設定方向（範圍如上）。動工前置：(a) `flutter pub add` 回報鎖定版本待二次確認；(b) 你需在 Firebase Console 建專案、啟用 Email/Google、產生並放置 plist/json（不貼訊息）；(c) 後端 Firebase env 由你手動設定才會真正綁定真實 elderId。
- 完成狀態：🚧 進行中 — **4a ✅**（pubspec firebase_core 4.9.0 / firebase_auth 6.5.1 / google_sign_in 7.2.0 + safe-init wrapper，test 46/46）、**4b ✅**（Email 註冊/登入，test 210/210、analyze 綠）、**4c 待執行**（Google，見下）。皆未 commit / 未 push。

---

### CR-0006 Batch 4c：Google Sign-In（🔒 原生設定＋實作核准，architecture-agent 2026-05-31）

- 提出 / 審查：architecture-agent；執行 owner：frontend-ux-agent
- 目標：在已完成的 Firebase Auth / Email 架構上加入 Google 登入。**Google 登入成功 → 取 Firebase ID Token → 呼叫既有 `POST /api/auth/session`（`provider='google'`）**；後端回 `authMode='firebase'` 時 `currentElderId` 用真實 elderId（規則沿用 Batch 3d，不改）。Demo 與 Email 登入皆不得被破壞；Google/Firebase 失敗（含使用者取消）App 不 crash。

#### 1. `google_sign_in` 7.2.0 正確 API 使用方式（已核對安裝版本原始碼）
- v7 為**實例化 + 需先 initialize**，與 v6 完全不同：
  1. `await GoogleSignIn.instance.initialize(serverClientId: <Web client ID>, clientId: <iOS client ID 可選>)`——**只需一次**。`serverClientId` 用 Firebase 專案的 **Web OAuth client ID**，確保拿到的 Google idToken 受 Firebase 採信。
  2.（建議）先檢查平台支援：`GoogleSignIn.instance.supportsAuthenticate()`。
  3. 互動登入：`final account = await GoogleSignIn.instance.authenticate();`（型別 `GoogleSignInAccount`，失敗丟 `GoogleSignInException`）。
  4. 取 Google idToken：`final googleIdToken = account.authentication.idToken;`
  5. 轉 Firebase 憑證並登入：`final cred = GoogleAuthProvider.credential(idToken: googleIdToken); final userCred = await FirebaseAuth.instance.signInWithCredential(cred);`
  6. **送後端的是 Firebase ID Token**：`final firebaseIdToken = await userCred.user!.getIdToken();`（與 Email 流程一致，後端 `firebaseAdmin.verifyIdToken` 驗的是這個，不是 Google 的）。
- 例外 code（`GoogleSignInExceptionCode`）：`canceled`（使用者取消，**視為柔性中止、非錯誤死路**）、`interrupted`、`clientConfigurationError`、`providerConfigurationError`、`uiUnavailable`、`unknownError` → 由 wrapper 轉成應用層錯誤再給白話。
- 封裝原則：所有上述細節都封在 `FirebaseAuthService.signInWithGoogle()` 內，並把 `GoogleSignInException` / `FirebaseAuthException` 轉成既有 `EmailAuthException`（或新增 `GoogleAuthException`，擇一，沿用 code→白話 機制）；上層 Controller/UI 不直接依賴 SDK，測試以子類覆寫注入 fake。
- `initialize()` 採**惰性呼叫**（首次 `signInWithGoogle` 時 init 一次並記憶），避免動 `main.dart`。

#### 2. iOS 需要修改哪些檔案
- `ios/Runner/Info.plist`：新增 `CFBundleURLTypes` → URL scheme 填 `GoogleService-Info.plist` 內的 `REVERSED_CLIENT_ID`（Google 登入完成後導回 App）。
- `GoogleService-Info.plist`：放 `ios/Runner/`（**不進版控**，4a/4b 已列）。
- `ios/Runner/AppDelegate.swift` 或 `SceneDelegate.swift`：本專案用 `SceneDelegate`（UIScene）→ Google 回呼 URL 在 scene 架構下的處理為**風險點**，動工時驗證 `google_sign_in_ios 6.3.0` 是否需在 scene delegate 補 `openURLContexts` 轉接；多數情況外掛自動處理，但需實機確認。
- `Podfile` / `pod install`：deployment target ≥ 13（現 13.0 OK）。

#### 3. Android 需要修改哪些檔案
- `android/settings.gradle.kts`：`plugins { id("com.google.gms.google-services") version "<ver>" apply false }`。
- `android/app/build.gradle.kts`：`plugins { id("com.google.gms.google-services") }`；確認 `minSdk ≥ 23`。
- `android/build.gradle.kts`（專案級）：僅當改用 classpath 寫法時才需；採 plugins DSL 則以 settings.gradle.kts 為準。
- `google-services.json`：放 `android/app/`（**不進版控**）。

#### 4. 是否需要 `GoogleService-Info.plist` / `google-services.json`
- 需要（兩者）。Google 登入沿用 Firebase 同一組設定檔；**一律 gitignore、永不 commit、永不貼訊息**（`.gitignore` 規則 4a 已加）。

#### 5. Firebase Console 需要啟用什麼
- 啟用 **Google** 登入方式（Authentication → Sign-in method）；設定專案 support email。
- 確認 iOS App（Bundle ID）與 Android App（package name）已建立；取得 **Web client ID** 作為 `serverClientId`。

#### 6. SHA-1 / Bundle ID / URL Scheme 注意事項
- **Android SHA-1/SHA-256**：debug 與 release keystore 的指紋都要加進 Firebase Android App，**否則 Google 登入會失敗**；加完重新下載 `google-services.json`。
- **iOS Bundle ID**：須與 Firebase iOS App 一致；URL scheme = `REVERSED_CLIENT_ID`。
- **serverClientId**：用 Web client ID（不是 iOS/Android client ID），否則 Firebase 可能不採信 Google idToken。

#### 7. 允許修改檔案
- `lib/services/auth/firebase_auth_service.dart`（實作 `signInWithGoogle()` + 惰性 `initialize` + 例外轉應用層錯誤）。
- `lib/controllers/auth_controller.dart`（新增 `loginWithGoogle()`；**取消（canceled）走柔性中止**：回 `unauthenticated` 或不顯示嚇人錯誤，不可變死路）。
- `lib/screens/login_screen.dart`、`lib/screens/register_screen.dart`（Google 鈕由「即將推出」改接真流程；Demo / Email / Apple 不變，Apple 維持「即將推出」）。
- `ios/Runner/Info.plist`、`android/settings.gradle.kts`、`android/app/build.gradle.kts`（必要時 `android/build.gradle.kts`、`ios/Runner/SceneDelegate.swift`）。
- `test/**`。

#### 8. 禁止修改檔案
- `lib/services/realtime_voice_service.dart`、`lib/controllers/voice_agent_controller.dart`（Realtime/SDP/DataChannel/狀態機）。
- `backend/**`（API 契約不變）、`lib/services/auth/session_api_service.dart` 契約、`lib/models/auth_session.dart`、`currentElderId` 規則。
- `caregiver_web/**`、Care Alert 結構、`pubspec.yaml`（google_sign_in 已於 4a 加入，本批不需動）。
- 任何 `.env` / key / token / `*.plist` / `google-services.json` 內容。

#### 9. 測試策略
- 單元/Widget **不得依賴真 Google/Firebase**：`signInWithGoogle` 透過子類覆寫 / 注入 fake（同 4b Email 模式），回 canned `FirebaseSignInResult` 或丟對應例外。
- AuthService / AuthController：Google 成功 → `createSession(provider:'google')` → authenticated 且 firebase session 用真實 elderId；`canceled` → 柔性中止（不顯示錯誤死路）；其他錯誤 → 白話訊息。
- Widget：Login/Register 的 Google 鈕觸發 `loginWithGoogle`；取消不 crash；**Demo / Email 仍可用**；Apple 仍「即將推出」。
- 回歸：既有 210 測試全綠、`flutter analyze` 乾淨。
- 手動清單（需真設定，無法自動化）：iOS/Android 實機 Google 登入、SHA-1 設好後 Android 成功、後端 Firebase env 設好後回 `authMode='firebase'` 與真實 elderId。

#### 10. rollback 方式
- 本批獨立 commit（`feat/auth-admin-backend`，不 push）→ `git revert`。
- Google 鈕可一鍵改回「即將推出」；**Email + Demo 完全不受影響**。
- 原生設定（Info.plist scheme、gradle plugin）revert；plist/json 為 gitignore，無金鑰清理。
- 最壞情境：revert 回 4b 狀態（Google 入口消失，Email/Demo 正常）。

- architecture-agent 裁決：✅ 核准原生設定與實作方向（範圍如上）。前置：你需在 Firebase Console 啟用 Google、放置 plist/json、登錄 Android SHA-1，並提供 Web client ID 作 serverClientId（不貼金鑰內容，放進原生設定檔即可）。
- 完成狀態：4c-1（Dart 層＋UI）✅ 已完成（frontend-ux-agent）；4c-2（原生設定＋真機）待設定檔備齊。

#### Checkpoint Review（architecture-agent，2026-05-31）— CR-0006 Batch 4a / 4b / 4c-1

- 範圍：Firebase Auth 地基（4a）＋ Email 註冊/登入（4b）＋ Google Sign-In Dart 層與 UI 接線（4c-1）。未含 iOS/Android 原生設定（留 4c-2）。
- 唯讀驗證結果（9 項全 PASS）：
  1. **版本正確**：`pubspec.yaml` `firebase_core ^4.9.0` / `firebase_auth ^6.5.1` / `google_sign_in ^7.2.0`；`pubspec.lock` 鎖定 4.9.0 / 6.5.1 / 7.2.0。✅
  2. **Init 失敗不 crash**：`firebase_init.dart` `ensureInitialized()` try/catch 吞例外、失敗只設 `_available=false`、永不丟；`main.dart` await 後照常 `runApp`。✅
  3. **Demo Login 仍可用**：`mockLogin` 主體未變（diff 僅文件註解提及）；`loginAsDemoUser` → `currentElderId='default_user'` 不受影響。✅
  4. **Email 完成**：`AuthService.signInWithEmail/registerWithEmail` + `AuthController` 對應方法 + Login/Register 欄位齊全；失敗轉白話、後端失敗回 mockFallback。✅
  5. **Google 僅 Dart＋UI**：`signInWithGoogle` 三層皆在；**`git status` 顯示 `ios/`、`android/`、`Info.plist`、gradle 全未改**。✅
  6. **測試 223/223 全綠**（`flutter test` 全套）。✅
  7. **analyze 乾淨**（`flutter analyze lib/ test/` → No issues found）。✅
  8. **未觸邊界**：`realtime_voice_service.dart`、`voice_agent_controller.dart`、`auth_session.dart`、`session_api_service.dart` 皆未在 `git status`；`currentElderId`/`_resolveDownstreamId` 未出現在 diff（規則未動）；`backend/**` 僅 runtime data、無程式碼改動。✅
  9. **建議 commit**：✅ 視為一個乾淨、可獨立回復的 checkpoint。
- **commit 範圍須顯式挑檔**：含 4a/4b/4c-1 的 lib/test + `pubspec.yaml/lock` + `.gitignore` + `main.dart` + pub get 連帶的 desktop 產生檔（macOS/Windows plugin registrant）。**排除**：`docs/CHANGE_REVIEW.md`（另行）、runtime `data/*.json`、`caregiver_web/**`、與本批無關的 `lib/screens/{care_alert,home,settings}_screen.dart` 與 `test/screens/care_alert_screen_test.dart`、tooling 噪音（`repomix-output.xml`、`devtools_options.yaml`、`.claude/worktrees/`、`docs/DEMO_SCRIPT.md`）。
- commit message：`feat: add firebase email and google auth foundation`。
- 後續放行：**可進 4c-2**（原生設定＋真機），前置仍為使用者備妥 plist/json、Android SHA-1、Web client ID、（綁真實 elderId 需）後端 Firebase env。

---

### CR-0010：長者端新手導覽 + 功能說明入口（Checkpoint Review，architecture-agent 2026-06-01）

- 範圍：新增 `lib/widgets/feature_tour.dart`（可重用多頁導覽 + 6 頁白話內容 + `showFeatureTour`）、`lib/screens/onboarding_screen.dart`（先導覽再命名）、`lib/screens/home_screen.dart`（首頁背包旁「？」入口 + header text-scale 夾制避免溢位）、`test/widgets/feature_tour_test.dart`（新）、`test/controllers/memory_controller_test.dart`（修正：問候測試注入假 service，不依賴後端是否在跑）。
- 10 項唯讀驗證（**全數 PASS**）：
  1. **長者友善文案** ✅（歡迎使用愛陪伴 / 點麥克風說話 / 我會記得你說的事 / 「需要時，系統會協助提醒照護人員，讓你不是一個人。」/「你可以看看寵物狀態，也可以使用背包裡的物品。」/「首頁右上角的問號，可以再看一次這份說明。」）。
  2. **上一個 / 下一個 / 略過 / 開始使用** ✅（`_buildControls` + `finishLabel`，最後一頁顯示「開始使用」）。
  3. **首頁「？」入口** ✅（`_HelpIconButton` 放背包左側、`Semantics(label:'功能說明')`、`onHelpTap → showFeatureTour`）。
  4. **沿用 CR-0009 elderId namespace** ✅（**未改** `local_storage_service.dart` / `profile_controller.dart`；onboarding 狀態已依 elderId 隔離）。
  5. **Demo default_user 未破壞** ✅（`default_user` 仍用全域 key）。
  6. **無 debug/JSON/riskLevel/triggerSummary/監控/警報 字眼** ✅（僅出現在一行說明意圖的「註解」，非顯示文字；測試亦斷言禁字不出現）。
  7. **未改 backend / caregiver_web / Realtime / voice_agent / Firebase 原生 / pubspec** ✅（`xcscheme`、`care_alert_display.test.js` 為先前遺留，非本批）。
  8. **`flutter analyze lib/ test/`** → No issues found ✅。
  9. **`flutter test`** → **237/237 pass** ✅。
  10. **建議 commit** ✅（乾淨、可獨立回復）。
- 裁決：✅ 通過驗收。**commit 範圍須顯式挑檔**：`lib/widgets/feature_tour.dart`、`lib/screens/{onboarding,home}_screen.dart`、`test/widgets/feature_tour_test.dart`、`test/controllers/memory_controller_test.dart`。**排除**：`docs/CHANGE_REVIEW.md`（另行）、`caregiver_web/**`（先前遺留）、`ios/...Runner.xcscheme`（Xcode 噪音）、runtime `data/*.json`、tooling 噪音、Firebase plist/json。
- commit message 建議：`feat: add elder onboarding tour and home help entry`。

---

## CR-0011：寵物換皮 + 首頁寵物放大

- 狀態：✅ 已完成（architecture-agent checkpoint review 通過，2026-06-01）
- 目標：支援 dog / guineaPig / fox 三種外觀，預設 dog，每個 elderId 各自保存；首頁寵物放大
- Step 1：素材整理（複製 + 改名到 `assets/pets/*`）— 完成
- Step 2：換皮邏輯 + UI + 放大 + 測試 — 完成
- 範圍：`lib/models/pet_skin.dart`（新）、`lib/widgets/pet_skin_picker.dart`（新）、`lib/utils/asset_paths.dart`、`lib/widgets/pet_avatar.dart`、`lib/controllers/pet_controller.dart`、`lib/services/local_storage_service.dart`、`lib/screens/{home,settings,login,onboarding}_screen.dart`、`lib/app.dart`、四個測試檔。

### Checkpoint Review（architecture-agent 獨立蒐證：grep + analyze + test）

| # | 項目 | 結果 |
|---|------|------|
| 1 | dog / guineaPig / fox 三外觀 | ✅ `enum PetSkin` 三值，預設 dog |
| 2 | 不搬動既有 dog 圖 | ✅ dog states8/talk6/rest3/listening1 完整、無刪改 |
| 3 | guinea_pig / fox 在 talk/rest/listening/states | ✅ 兩物種四資料夾齊全 |
| 4 | PetSkin 三值 + 中文 label | ✅ 狗狗 / 天竺鼠 / 狐狸 |
| 5 | AssetPaths 動態 skin 路徑 | ✅ `talkingFrames/restFrames/listening/stateImage(skin)` |
| 6 | PetAvatar skin + fallback | ✅ `skin` 參數 + 三層 fallback（skin rest_01 → dog rest_01 → 白話佔位） |
| 7 | PetController API | ✅ `currentSkin / changeSkin / loadSkin / saveSkin` |
| 8 | LocalStorageService elderId namespace | ✅ `_k(_keyPetSkin)`：Demo=全域、正帳號加 `u:<elderId>:` |
| 9 | 首頁更換外觀入口 | ✅ 舞台右上角「更換外觀」→ bottom sheet（不擋寵物主體） |
| 10 | 設定頁外觀選擇 | ✅「換一隻陪你的夥伴」+ `PetSkinPicker` |
| 11 | 首頁放大 + 小螢幕不 overflow | ✅ 上限 430→520、`clamp(72, 520)` 防溢；1.3 字級 layout test 綠 |
| 12 | 未改 backend / Realtime / Firebase 原生 / pubspec / .env | ✅ 皆未動；`app.dart` 屬前端接線（非 🔒 鎖定檔），改動最小（provider 注入 + `loadSkin()`） |
| 13 | flutter analyze | ✅ No issues found |
| 14 | flutter test | ✅ 258/258 passed（exit 0） |

- 裁決：✅ 通過驗收，建議 commit。
- **commit 範圍須顯式挑檔**（[[commit_hygiene]]）：
  - 新增：`lib/models/pet_skin.dart`、`lib/widgets/pet_skin_picker.dart`、`test/models/pet_skin_test.dart`、`test/services/pet_skin_storage_test.dart`、`test/controllers/pet_controller_skin_test.dart`、`test/widgets/pet_avatar_test.dart`
  - 修改：`lib/app.dart`、`lib/utils/asset_paths.dart`、`lib/widgets/pet_avatar.dart`、`lib/controllers/pet_controller.dart`、`lib/services/local_storage_service.dart`、`lib/screens/{home,settings,login,onboarding}_screen.dart`、`docs/CHANGE_REVIEW.md`
  - 新增素材：`assets/pets/{talk,rest,listening,states}/{guinea_pig,fox}_*.png`
  - **排除**（與 CR-0011 無關 / 既有遺留 / 噪音）：`lib/screens/care_alert_screen.dart`、`test/screens/care_alert_screen_test.dart`、`backend/stt_proxy/data/*.json`（runtime）、`caregiver_web/**`、`ios/...Runner.xcscheme`、`docs/DEMO_SCRIPT.md`、`repomix-output.xml`、`devtools_options.yaml`、`.claude/worktrees/`、`assets/pets_raw/`（raw 暫存，不入正式 commit）。
- commit message 建議：`feat: add pet skin switching (dog/guinea pig/fox) and enlarge home pet`。

---

## CR-0012：App 完整度修正與穩定化（盤點，不新增功能）

- 提出 agent：architecture-agent
- 日期：2026-06-01
- 狀態：⬜ 盤點完成、待裁決批次（**本輪只盤點，未改任何程式**）
- 動機 / 問題：發表前盤點目前不穩定、不符正式展示、容易讓老師／使用者覺得「不完整」之處。今天不新增大型功能，只定位問題、分級、排修正順序。
- 觸及 🔒？：本盤點 CR 本身否（純文件）。**下列建議批次中，今天可做的 Batch A/B 皆不觸 🔒**（不動 `realtime_voice_service.dart`、`server.js` 契約、schema、Care Alert 結構、`pubspec.yaml`）；Batch C 觸及 realtime-voice 範圍，Batch D 觸及原生設定，列 follow-up。

### 盤點方法（實證，非臆測）
- 三組唯讀探查（UI/UX 文案、資料隔離、build/Apple/Firebase）+ architecture-agent 親自查證 HIGH 級宣稱。
- 穩定性實證：`flutter analyze lib/ test/` → **No issues found**；`flutter test`（全套）→ **258/258 passed**（含 Realtime `realtime_voice_service_test` 等套件）。
- 機密紅線查證：`GoogleService-Info.plist` / `google-services.json` → `git ls-files` **未追蹤** 且 `git check-ignore` **命中 .gitignore**（安全，無洩漏）。

### 問題清單（含嚴重度與 owner）

| # | 分類 | 問題 | 證據 | 嚴重度 | Owner |
|---|------|------|------|--------|-------|
| P1 | 資料隔離 | `check_in_storage_service`(`checkin.dates/lastDate`)、`inventory_storage_service`(`inventory.items`)、`care_alert_storage_service`(`careAlerts`)、`reminder_service`(`careReminders`) **皆用全域 key、無 `setUserId`**，且對應 controller 只在啟動 `load()` 一次、帳號切換不重載 → 跨帳號殘留（A 帳號簽到/背包/提醒/本地 alert 會出現在 B 帳號） | 四檔 `static const _key...`、`app.dart` `applyAccount` 未對這四者 setUserId/reload | **high**（與 CR-0009 主打的「帳號隔離」相矛盾；僅在真實多帳號切換時顯現，demo 單一 default_user 不顯） | frontend-ux-agent |
| P2 | 穩定性 | 帳號切換時 `ConversationController`（partial/final transcript、draft、busy/recording 旗標）與 `VoiceAgentController`（petMood/expression、pending realtime 暫態）**未 reset**，上一帳號殘留暫態可能短暫顯示 | `conversation_controller.dart` 暫態欄位、`voice_agent_controller.dart` 未在切換時清 | **medium** | realtime-voice-agent（暫態歸屬該 agent） |
| P3 | UI 工程字 | `native_tool_executor_service.dart:70` `message: '工具執行失敗：$error'` 把原始例外字串串進使用者訊息（工具呼叫失敗路徑才觸發） | grep 確認 | **medium** | frontend-ux-agent（白話化字串） |
| P4 | UI 字級 | 首頁 header 標語 `fontSize 14`（次要文字，但在主畫面 header）、寵物狀態 label `fontSize 12` | `home_screen.dart:625`、`pet_status_panel.dart:154` | **low** | frontend-ux-agent |
| P5 | build/原生 | `ios/Runner/Info.plist` 的 `CFBundleURLTypes` **硬寫單一 Firebase 專案的 REVERSED_CLIENT_ID**（公開識別碼、非機密）；換 Firebase 專案會失效。真機 Google 登入回呼（SceneDelegate 架構）尚未實機驗證 | `Info.plist` 含 1 行 reversed client id | **low/medium**（對「目前這個專案」可動；換專案/CI 才壞） | 原生設定（沿用 CR-0006 4c-2） |
| P6 | Apple 登入 | Apple 鈕點擊顯示「Apple 登入準備中，敬請期待。」軟性 placeholder（不假裝成功、不 crash） | `login_screen.dart:129-131` | **low**（合理；可選擇 demo 時隱藏鈕） | frontend-ux-agent |

### 已查證為「通過、無需修」的項目（記錄以免重工）
- 登入 / 註冊 / 登出流程：白話、大字大鈕、登出有確認對話框並回登入頁，**通過**。
- 新手導覽 `feature_tour.dart`（6 頁）+ onboarding 命名：白話、可「再看一次」，**通過**。
- 首頁寵物顯示、語音按鈕白話狀態（我在聽 / 正在想 / 連線怪怪的點我再試），**通過**。
- 英文錯誤訊息：Auth / 記憶 / 麥克風 / 商城錯誤皆白話繁中，**未見裸 English / stack trace**，**通過**。
- Firebase init 失敗：try/catch + 3 秒 timeout，**不擋 Demo**，Demo 登入恆可用，**通過**。
- Google/Email 登入失敗：全白話訊息、取消（canceled）走柔性中止非死路，**通過**。
- 寵物外觀 / 寵物名 / profile / 長期記憶 / petStats：已依 elderId namespace 並在切換時重載，**隔離正確，通過**。
- Android：`com.google.gms.google-services` plugin 已套、`minSdk maxOf(...,23)`、deployment target 15.0，**通過**。
- 機密檔（plist/json）：未進 git、已 gitignore，**通過**。
- debug/demo 字樣：`SHOW_DEV_PANELS` / `SHOW_DEMO_LOGIN` 預設 false 才隱藏，正式 build 不顯，**通過**。

### 建議修正順序 + 批次 + 由誰負責

> 鐵則：每批小範圍、可獨立驗證、補/更新測試、不刪既有測試、不碰 `.env`/token、不寫 runtime `data/*.json`、不 commit/push（除非另行指示）。

1. **Batch A〔今天可做〕資料隔離補完（P1）— frontend-ux-agent，high、不觸 🔒**
   - 為四個 storage service 加 elderId namespace（沿用 CR-0009 既有 `_k()` 慣例）+ `setUserId()`；`app.dart applyAccount()` 補四者 `setUserId` 與對應 controller 重載（checkin/inventory/careAlert(local)/reminder）。
   - 風險低：有 CR-0009/0011 既成 pattern；純前端；保留 default_user 全域行為（Demo 不破）。補 `local_storage_isolation`-style 測試。
2. **Batch B〔今天可做〕UI 白話 / 字級小修（P3、P4）— frontend-ux-agent，medium/low、不觸 🔒**
   - `native_tool_executor_service.dart:70` 改白話（如「這個動作暫時沒辦法完成，待會再試一次好嗎？」），原始 `$error` 只留 `debugPrint`。
   - 首頁標語 14→16/18；（選擇性）狀態 label 微調。純字串/字級，補 widget 斷言。
3. **Batch C〔follow-up〕帳號切換暫態清理（P2）— realtime-voice-agent，medium**
   - 切換帳號時 reset transcript/draft/voice 暫態。**因觸及 realtime-voice 範圍**，須由該 agent 評估清理點，不得動 Realtime/SDP 主流程；非今天。
4. **Batch D〔follow-up〕iOS URL scheme + 真機 Google 登入（P5）— 原生設定**
   - 評估 reversed client id 是否改為由 plist 動態取得；真機 Google 回呼驗證。併入既有 **CR-0006 4c-2**（原生＋真機）追蹤，非今天。
5. **Batch E〔follow-up / 產品決策〕Apple 入口（P6）— frontend-ux-agent**
   - demo 是否隱藏 Apple 鈕，或維持「準備中」placeholder。low，等使用者決定。

### 今天可修 vs follow-up（摘要）
- **今天可修（建議）**：Batch A（資料隔離，high，最高 CP 值且有先例）、Batch B（UI 白話/字級，快）。兩者皆 frontend-ux-agent、低風險、不觸 🔒。
- **列 follow-up**：Batch C（realtime-voice 暫態，需該 agent）、Batch D（原生/真機，併 4c-2）、Batch E（Apple 入口決策）。

- architecture-agent 裁決：⬜ **盤點完成、待使用者選定要執行的批次**。建議先放行 Batch A + B（今天可做、low risk、不觸 🔒）；Batch C/D/E 轉 follow-up（見 FU-0005 ~ FU-0007）。
- 完成狀態：盤點 ✅；**Batch A ✅（已 commit `0842357`）**；**Batch B ✅（已 review 通過，見下）**；Batch C/D/E 為 follow-up（FU-0005~0007）。

#### Checkpoint Review（architecture-agent，2026-06-01）— CR-0012 Batch A：剩餘 local storage 資料隔離補完

- 範圍：frontend-ux-agent 執行；architecture-agent 獨立蒐證（grep + analyze + full test）。觸及 🔒？**否**（純前端 storage / controller 接線；未動 🔒 鎖定檔）。風險 low。
- 11 項逐項查證（**全數 PASS**）：

| # | 項目 | 結果 |
|---|------|------|
| 1 | CheckIn 依 elderId namespace | ✅ `check_in_storage_service.dart`：`setUserId`＋`_k()`＋讀寫全走 `_k()`（`getStringList/getString/setStringList/remove/setString`） |
| 2 | Inventory / Backpack namespace | ✅ `inventory_storage_service.dart`：`_k(_keyInventory)` 讀寫一致 |
| 3 | 本地 CareAlert namespace | ✅ `care_alert_storage_service.dart`：`_k(_key)` 讀寫一致 |
| 4 | Reminder namespace | ✅ `reminder_service.dart`：`_k(_key)` 讀寫一致 |
| 5 | OS notification 切帳號先 cancelAll 再重排 | ✅ `notification_service.dart` `rescheduleAll`：`initialize → cancelAll → schedule each`（新增 `cancelAll()`；只被 `ReminderController.load()` 呼叫） |
| 6 | Demo default_user 仍用全域 key | ✅ 四檔皆 `_k = (userId==default_user) ? key : 'u:$_userId:$key'`；`setUserId(null/'')→default_user`。新測「Demo 既有全域資料不被正式帳號破壞」鎖住 |
| 7 | 正式帳號用 `u:<elderId>:` 前綴 | ✅ 同上規則 else 分支 |
| 8 | app.dart 切 elderId 重載 controller | ✅ `applyAccount()` 對六 storage `setUserId`＋重載 `checkIn/inventory/careAlert/reminder` controller；啟動段已移除原本獨立 load（無雙載、切換即重載） |
| 9 | 未改 backend / Realtime / Firebase 原生 / pubspec / .env | ✅ git status 程式檔僅 `app.dart`＋5 services＋1 新測試；未見 `realtime_voice_service`/`voice_agent_controller`/`server.js`/`migrate`/`pubspec`/`.plist`/`google-services.json`/`.env` |
| 10 | flutter analyze | ✅ No issues found |
| 11 | flutter test 全套 | ✅ **263/263 passed**（原 258＋新增 5 隔離測試，零回歸） |

- 至此**所有本機 SharedPreferences 都已依帳號隔離**（含先前 CR-0009 的 Local/PetStats）。reminder 額外補上 OS 排程層隔離，徹底滿足「A 的提醒不會在 B 響起」。
- 裁決：✅ **通過驗收**，視為乾淨、可獨立回復的 checkpoint。
- **建議 commit**：✅。commit message 建議：`fix: namespace check-in/inventory/care-alert/reminder local storage per account`。
- **commit 範圍須顯式挑檔**：
  - 修改：`lib/app.dart`、`lib/services/check_in_storage_service.dart`、`lib/services/inventory_storage_service.dart`、`lib/services/care_alert_storage_service.dart`、`lib/services/reminder_service.dart`、`lib/services/notification_service.dart`
  - 新增：`test/services/care_data_isolation_test.dart`
  - 文件（可另行 / 一併）：`docs/CHANGE_REVIEW.md`
  - **排除**（與 Batch A 無關 / 既有遺留 / 噪音）：`caregiver_web/care_alert_display.test.js`、`lib/screens/care_alert_screen.dart`、`test/screens/care_alert_screen_test.dart`（先前遺留）、`docs/DEMO_SCRIPT.md`、`backend/stt_proxy/data/*.json`（runtime）、`ios/...Runner.xcscheme`、`repomix-output.xml`、`devtools_options.yaml`、`.claude/worktrees/`、`assets/pets_raw/`
- 後續：Batch B（`native_tool_executor` 白話化＋字級，frontend-ux）可逕行；Batch C（FU-0005，realtime-voice 暫態 reset）、D（FU-0006）、E（FU-0007）維持 follow-up。

#### Checkpoint Review（architecture-agent，2026-06-01）— CR-0012 Batch B：白話小修與字級微調

- 範圍：frontend-ux-agent 執行；architecture-agent 獨立蒐證（grep + analyze + full test）。觸及 🔒？**否**（純前端字串/字級）。風險 low。
- 9 項逐項查證（**全數 PASS**）：

| # | 項目 | 結果 |
|---|------|------|
| 1 | native tool 不再顯示 exception / stack trace / error object | ✅ `native_tool_executor_service.dart` catch 區回固定白話句，整檔掃 `$error`/`工具執行失敗` 僅剩 line 68 的 debugPrint |
| 2 | UI-facing message 改白話 | ✅ `message: '這個動作暫時沒辦法完成，待會再試一次好嗎？'` |
| 3 | debugPrint 只留開發者、不外露 | ✅ 原始 `$error\n$stackTrace` 僅在 `debugPrint`，並加註解「絕不顯示給長者」 |
| 4 | 首頁標語 14→16 | ✅ `home_screen.dart:625` `fontSize: 16`（Expanded+maxLines:1+ellipsis，頂列已 clamp 1.0） |
| 5 | 寵物狀態 label 12→14 | ✅ `pet_status_panel.dart` label `fontSize: 14`（數值字 15 仍主導 Row 高度） |
| 6 | 小螢幕 / 放大字級不 overflow | ✅ `home_screen_layout_test`（含 1.3 字級不溢位）全綠；改動皆 ellipsis+maxLines:1 |
| 7 | 未改 backend / caregiver_web / Realtime / Firebase 原生 / pubspec / .env | ✅ 本批程式檔僅 `home_screen.dart`、`native_tool_executor_service.dart`、`pet_status_panel.dart` ＋對應測試；未見 `realtime_voice_service`/`voice_agent_controller`/`server.js`/`migrate`/`pubspec`/`.plist`/`google-services.json`/`.env` |
| 8 | flutter analyze | ✅ No issues found |
| 9 | flutter test 全套 | ✅ **264/264 passed**（Batch A 後 263 ＋新增 1 例外測試，零回歸） |

- 新測試「工具丟例外時回白話、不洩漏」斷言 message 不含 `secret-stack-detail`/`Exception`/`error`/`failed`/`工具執行失敗`/`$error`，有效鎖住 P3。
- 裁決：✅ **通過驗收**，乾淨、可獨立回復的 checkpoint。
- **建議 commit**：✅。commit message 建議：`fix: soften native tool failure message and enlarge home secondary text`。
- **commit 範圍須顯式挑檔**：
  - 修改：`lib/services/native_tool_executor_service.dart`、`lib/screens/home_screen.dart`、`lib/widgets/pet_status_panel.dart`、`test/services/native_tool_executor_service_test.dart`
  - 文件（可另行 / 一併）：`docs/CHANGE_REVIEW.md`
  - **排除**（與 Batch B 無關 / 既有遺留 / 噪音）：`caregiver_web/care_alert_display.test.js`、`lib/screens/care_alert_screen.dart`、`test/screens/care_alert_screen_test.dart`（先前遺留）、`docs/DEMO_SCRIPT.md`、`backend/stt_proxy/data/*.json`（runtime）、`ios/...Runner.xcscheme`、`repomix-output.xml`、`devtools_options.yaml`、`.claude/worktrees/`、`assets/pets_raw/`
- 後續：Batch C（FU-0005）、D（FU-0006）、E（FU-0007）維持 follow-up。

---

## CR-0013：簽到日曆獎勵升級（每日固定獎勵 + 禮物日）

- 提出 agent：frontend-ux-agent（實作）／architecture-agent（review）
- 日期：2026-06-01
- 動機：讓簽到更有遊戲感、適合正式展示——每格顯示當天獎勵、隨機金幣、每 4 天送商品、今日高亮、已領取狀態。
- 觸及 🔒？**否**：純前端（check-in / 日曆 UI / reward model / inventory / coins），無 backend API、無 Realtime、無 schema、無依賴新增、不跨 agent → 不需事前 CR，於 frontend-ux 範圍內小步實作，本則為事後 checkpoint review。
- 範圍：
  - 新增 `lib/models/daily_reward.dart`（`DailyReward` + `MonthlyRewardTable`）、`test/models/daily_reward_test.dart`、`test/controllers/check_in_controller_test.dart`
  - 修改 `lib/services/check_in_storage_service.dart`（持久化月度 reward 表，沿用 `_k()` elderId namespace）、`lib/controllers/check_in_controller.dart`（reward 表載入/產生 + `checkIn` 發金幣+禮物 + `lastClaim`/`rewardForDay`）、`lib/services/ai_tool_router.dart`（語音簽到補傳 `inventoryController`）、`lib/screens/home_screen.dart`（日曆 UI 升級 + `_CalendarDayCell`）

### Checkpoint Review（architecture-agent，2026-06-01）— 獨立讀碼 + grep + analyze + full test

| # | 項目 | 結果 |
|---|------|------|
| 1 | DailyReward / MonthlyRewardTable 設計完整 | ✅ `DailyReward{day,coins,hasGift,giftItemId}`＋`MonthlyRewardTable{year,month,rewards}` 含 `generate`/`forDay`/`toJson`/`fromJson` |
| 2 | 金幣區間 一般 10–25、週一 25–40 | ✅ `weekStart ? 25+rng.nextInt(16) : 10+rng.nextInt(16)`，`isWeekStart=weekday==Monday`；測試以 inInclusiveRange 鎖住 |
| 3 | 每 4 天送隨機商品 | ✅ `isGiftDay=day%4==0`，禮物日從 `giftPool` 取 id；測試覆蓋 4/8/…/28 |
| 4 | 同 elderId+年月固定、不重 random | ✅ `MonthlyRewardTable.generate` 用穩定 FNV-1a 種子（`elderId|year|month`）＋ `_ensureRewardTable` 先讀已存表、null 才產生並存回；`load()` 換帳號時清表重讀 |
| 5 | checkIn 真的發金幣 | ✅ `walletController.addCoins(coins)`；測試驗 `wallet.coins == before+N` |
| 6 | 禮物日真的發商品到 inventory | ✅ `inventoryController.addFromShop(gift)`；測試驗 `inventory.items` 含預存 giftItemId |
| 7 | 重複簽到不重複領 | ✅ `if (hasCheckedInToday) return false`；測試驗第二次回 false |
| 8 | reward table / check-in / inventory 依 elderId 隔離 | ✅ reward 表 `_k(_rewardKey())`、check-in/ inventory 已於 CR-0012 namespace；測試驗 A 表 B 讀不到 |
| 9 | Demo default_user 不被破壞 | ✅ `_k` default_user 走全域 key；測試驗 default_user reward 表獨立 |
| 10 | 日曆 UI：日期 / 金幣 / 禮物 / 今日高亮 / 已領取 | ✅ `_CalendarDayCell` 顯示日期＋🪙金幣＋🎁；今日橘框、已簽到綠底＋✓ check_circle；白話說明＋大鈕＋無工程字 |
| 11 | 未改 backend / caregiver_web / Realtime / Firebase 原生 / pubspec / .env | ✅ 本功能改動檔僅 check_in_controller / home_screen / ai_tool_router / check_in_storage ＋新 model/2 測試；`care_alert_screen*`、`caregiver_web/*` 為會話初始既有遺留，非本功能 |
| 12 | flutter analyze | ✅ No issues found（lib/ + test/） |
| 13 | flutter test 全套 | ✅ **274/274 passed**（前 264 + 新增 10，零回歸） |

- 觀察（非阻擋）：7 欄月曆在窄螢幕下金幣字偏小屬密度取捨；UI 為彈窗、不影響主畫面（`home_screen_layout_test` 1.3 字級仍綠）。`checkIn` 新增必填 `inventoryController`，兩個 production 呼叫處皆已同步更新。
- 裁決：✅ **通過驗收**，乾淨、可獨立回復的 checkpoint。
- **建議 commit**：✅。commit message 建議：`feat: upgrade daily check-in calendar with fixed monthly rewards and gift days`。
- **commit 範圍須顯式挑檔**：
  - 新增：`lib/models/daily_reward.dart`、`test/models/daily_reward_test.dart`、`test/controllers/check_in_controller_test.dart`
  - 修改：`lib/controllers/check_in_controller.dart`、`lib/services/check_in_storage_service.dart`、`lib/services/ai_tool_router.dart`、`lib/screens/home_screen.dart`
  - 文件（可另行 / 一併）：`docs/CHANGE_REVIEW.md`
  - **排除**（既有遺留 / runtime / 噪音）：`lib/screens/care_alert_screen.dart`、`test/screens/care_alert_screen_test.dart`、`caregiver_web/care_alert_display.test.js`、`docs/DEMO_SCRIPT.md`、`backend/stt_proxy/data/*.json`、`ios/...Runner.xcscheme`、`repomix-output.xml`、`devtools_options.yaml`、`.claude/worktrees/`、`assets/pets_raw/`

---

## CR-0014：語音 Realtime 連線中打字注入同一個 live 對話

- 提出 agent：realtime-voice-agent（service + controller 實作）／主代理（home_screen UI 路由）
- 日期：2026-06-01
- 動機 / 問題：打字對話（`quickAction` → companion engine）與語音對話（OpenAI Realtime live session）原本是兩套獨立回覆引擎，只共用對話紀錄與脈絡；語音連線中打字會另走 quickAction 產生平行回覆，造成「各說各話 / 互相蓋台」的體驗（使用者回報「不理我了」）。需求：語音連線中打字時，把文字注入**同一個 live realtime session**，讓寵物用語音在同一個對話裡回覆。
- 影響範圍（檔案）：
  - `lib/services/realtime_voice_service.dart`（🔒）：新增 public `sendUserText(String)`（送 `conversation.item.create`(role=user/input_text) + `response.create`，沿用既有 `_sendEventPayload` / 排隊 / try-catch）；新增 `@visibleForTesting` seam。
  - `lib/controllers/voice_agent_controller.dart`：新增 `Future<bool> sendTextDuringRealtime(String)`（可用才接手：顯示使用者氣泡 + 記 user turn + 注入；不可用回 false）。
  - `lib/screens/home_screen.dart`：`_sendTextMessage` 改為先試 `sendTextDuringRealtime`，回 false 才 fallback `quickAction`。
- 觸及 🔒？：是（`realtime_voice_service.dart`）——本次為**新增 public 方法 + 測試 seam**，不改 SDP/連線主流程、不送 `session.update`（避免動到純語音 server_vad 流程）、不改成 mock、無 demo fallback。
- 牽涉哪些 agent：realtime-voice-agent（擁有 service + VoiceAgentController）、frontend-ux（home_screen 文字框路由，由主代理代為最小接線）。
- 風險等級：medium（碰 Realtime 主流程檔，但屬純增量、純語音路徑不受影響）。
- 測試計畫 / 結果：
  - service 新增 2 測試（注入兩事件、空白忽略）、controller 新增 2 測試（未連線回 false、連線時注入 user turn + 觸發回覆）。
  - `flutter analyze lib` → ✅ No issues。
  - `flutter test test/realtime_voice_service_test.dart test/voice_agent_controller_realtime_lifecycle_test.dart test/home_screen_layout_test.dart test/realtime_timeout_test.dart test/realtime_turn_coordinator_test.dart` → ✅ 全綠（含新增 4 個）。
- architecture-agent 裁決：⬜ 待補審（事後 review；實作已通過 analyze + 測試，純語音流程未受影響）。
- 完成狀態：✅ 完成（程式 + 測試），實機驗證待使用者於語音連線中打字確認。

---

## 待釐清項目 / 後續（Follow-ups）

### FU-0001：移除 legacy 容錯（待四級資料穩定後另開 CR）
- 背景：CR-0002 完成後，前後端與 companion 皆保留對 `normal/attention` 的讀取容錯（聯集 enum、`normalizeRiskLevel`、caregiver_web legacy class/label）。
- 條件：待新四級資料穩定運行一段時間、且既有 `care_alerts.json` 舊值不再需要讀取後，可另開 CR 移除：
  - `lib/models/care_alert.dart` 的 legacy enum 值與 `fromJson` 舊值分支
  - `careAlertStoreService.js` / `companion_engine.js` 的 `normalizeRiskLevel` legacy alias
  - `caregiver_web` 的 legacy `risk-attention` / `risk-normal` class 與 label
  - （選擇性）一次性轉換既有 `care_alerts.json` 舊值的腳本（runtime data，不進 git，須先備份並回報）
- 狀態：⬜ 待排程（非緊急）

### FU-0002：補跑 CR-0003 B3 的 Flutter 測試（本機 toolchain 待修復）
- 背景：CR-0003 B3 程式已完成、`flutter analyze` 乾淨、caregiver_web 靜態測試 4/4 綠；但本機 `flutter test` runner 兩次卡在冷啟動（程序在跑但 CPU 近 0、數分鐘無輸出），故 Flutter widget/hook 測試未跑完，**未宣稱通過**。
- 待辦：toolchain 正常時執行並確認綠：
  ```
  flutter test test/controllers/care_alert_hook_test.dart test/models/care_alert_test.dart test/screens/care_alert_screen_test.dart
  ```
  若仍卡住：先 `flutter clean`、重啟 dart server，或在資源充足時段重跑。
- 涵蓋項目：#1 triggerSummary 優先採 careAlertSummary、#2 缺失時 fallback implicitMeaning、#3/#4 畫面顯示持續觀察/需通知/緊急且無工程字。
- 根因更新（CR-0004，2026-05-31）：runner 卡冷啟動的成因已查明為**磁碟空間不足（100% 滿）**，非 toolchain bug；釋放空間後 Flutter realtime 測試已能正常跑完。
- 補跑結果（2026-05-31）：磁碟釋放後執行指定三檔 `flutter test test/controllers/care_alert_hook_test.dart test/models/care_alert_test.dart test/screens/care_alert_screen_test.dart` → **+17 All tests passed**（涵蓋 #1 triggerSummary 優先採 careAlertSummary、#2 缺失時 fallback implicitMeaning、#3/#4 畫面顯示持續觀察/需通知/緊急且無工程字）。
- 狀態：✅ 已結案（指定三檔全綠，CR-0003 Flutter 驗證收尾完成）

### FU-0003：§11 physio / elder summary 鍵名補逐欄定義（非阻擋）
- 背景：Checkpoint Review 發現 `PROJECT_ARCHITECTURE.md` §11 的 `/physio` 與 `/elders/:id` 之 `summary` 以 `{...}` 概括，實作 `services/admin/healthMetrics.js` 回 `avgDailyInteractionMinutes / avgReminderCompletionRate / ...`。形狀方向一致、無欄位衝突，但文件未逐欄列出。
- 待辦：CR-0007 Batch 4（caregiver_web 串接）前，在 §11 補上 physio summary 的鍵名定義，避免前端猜欄位。
- 狀態：⬜ 待排程（非緊急）

### FU-0004：tooling 噪音檔加入 .gitignore（非阻擋）
- 背景：`repomix-output.xml`、`.claude/worktrees/`、`.claude/scheduled_tasks.lock`、`devtools_options.yaml` 目前**未被 ignore**，blanket `git add -A` 會誤收。
- 待辦：以獨立小 commit 將上述加入 `.gitignore`（符合 [[commit_hygiene]] 原則）。
- 狀態：⬜ 待排程（非緊急）

### FU-0005：帳號切換暫態清理（CR-0012 P2 / Batch C）
- 背景：帳號切換時 `ConversationController`（transcript/draft/旗標）與 `VoiceAgentController`（petMood/pending realtime）暫態未 reset，可能短暫殘留上一帳號畫面狀態。
- 待辦：由 realtime-voice-agent 評估清理點，切換時 reset；**不得動 Realtime/SDP 主流程**。
- 狀態：⬜ 待排程（medium）

### FU-0006：iOS URL scheme 硬編碼 + 真機 Google 登入（CR-0012 P5）
- 背景：`ios/Runner/Info.plist` 的 `CFBundleURLTypes` 硬寫單一 Firebase 專案 REVERSED_CLIENT_ID（公開識別碼非機密），換專案會失效；SceneDelegate 下 Google 回呼尚未實機驗證。
- 待辦：併入 **CR-0006 Batch 4c-2**（原生設定＋真機）一起處理。
- 狀態：⬜ 待排程（low/medium，需真機）

### FU-0007：Apple 登入入口決策（CR-0012 P6）
- 背景：Apple 鈕為「準備中」軟性 placeholder（不假成功、不 crash）。
- 待辦：demo 時是否隱藏 Apple 鈕，或維持 placeholder；由使用者決定。
- 狀態：⬜ 待決策（low）

### CR-0028：正式版情緒辨識與 Care Alert 分析（文件化＋管理端非醫療提示，2026-06-03）
- 提出 agent：companion-memory-agent（文件）＋ frontend-ux-agent（caregiver_web 文案）
- 動機 / 問題：情緒辨識與 Care Alert 流程其實已完整實作，但缺正式文件可向評審說明，且
  caregiver_web 缺「非醫療診斷」提示，易被誤解為醫療判定。
- 盤點結論（現況已具備，未改邏輯）：
  - 文字語意情緒辨識（`emotion_classifier`）＋語音特徵融合（`emotion_fusion_service` / `voice_feature_service`）。
  - 四級風險（`safety_guard`：low/medium/high/urgent）＋白話非診斷照護摘要（`buildCareAlertSummary`）。
  - 資料流已接通：Flutter `_maybeCreateCareAlert()`（voice_agent_controller.dart:812）僅在
    `needsHumanSupport`（high/urgent）建立 Care Alert，並 `POST /api/care-alerts/notify`；
    Telegram 僅 high/urgent 且有 cooldown。
- 影響範圍（檔案）：
  - 新增 `docs/EMOTION_RECOGNITION.md`（方法論＋評審 Q&A＋驗證步驟）。
  - `caregiver_web/index.html`：新增兩處 `.care-disclaimer` 非醫療提示。
  - `caregiver_web/styles.css`：新增 `.care-disclaimer` 樣式。
  - `caregiver_web/care_alert_display.test.js`：新增提示存在的斷言。
- 觸及 🔒？：否（未改 server.js 路由/response、未改 DB schema、未改 Care Alert 資料結構、
  未改 realtime 主流程、未改依賴）。純文件＋前端文案＋測試。
- 風險等級：low（無行為變更，僅文件 + 顯示文案 + 測試）。
- 測試計畫：`node --test caregiver_web/care_alert_display.test.js`、`admin_dashboard.test.js`；
  後端 `cd backend/stt_proxy && npm test` 確認既有情緒/care alert 測試不受影響。
- architecture-agent 裁決：✅ 自核（low risk，未觸 🔒）
- 完成狀態：✅ 完成

### CR-0029：正式版管理者端使用者帳戶管理（Admin Users API + caregiver_web，2026-06-03）
- 提出 agent：backend-agent（Admin API / DB / 權限）＋ frontend-ux-agent（caregiver_web 使用者管理頁）
- 動機：讓管理者端能從 PostgreSQL 透過受權限保護的 Admin API 查使用者帳戶清單，並以安全方式
  顯示（Email 遮蔽、不外漏敏感欄位），可向評審證明資料真的存在 DB、非本機假資料。
- 盤點結論：`users` 表已存在（006），PG 連線 `db/postgres.js`、migration 機制、登入 upsert
  到 PG 皆已具備；缺 requireAdmin、`/api/admin/users`、Email 遮蔽、caregiver_web 使用者管理頁、
  `ADMIN_API_TOKEN`、`last_login_at`。
- 修改檔案：
  - `backend/stt_proxy/server.js`（新增 `GET /api/admin/users`，requireAdmin 保護；不動既有路由）
  - `backend/stt_proxy/services/auth/sessionService.js`（PG 路徑寫入 / 更新 `last_login_at`）
  - `backend/stt_proxy/package.json`（test / check 加入新檔）
  - `backend/stt_proxy/.env.example`（新增 `ADMIN_API_TOKEN`、`PGVECTOR_ENABLED` 說明）
  - `caregiver_web/index.html`、`caregiver_web/app.js`、`caregiver_web/styles.css`（使用者管理頁）
- 新增檔案：
  - `backend/stt_proxy/db/migrations/008_add_users_last_login_at.sql`
  - `backend/stt_proxy/services/admin/requireAdmin.js`
  - `backend/stt_proxy/services/admin/adminUsersService.js`
  - `backend/stt_proxy/services/admin/adminUsersService.test.js`、`adminUsersEndpoint.test.js`
  - `caregiver_web/admin_users.test.js`
  - `docs/ADMIN_USER_MANAGEMENT.md`
- 資料庫變更：沿用既有 `users` 表，新增冪等 migration（`last_login_at` 欄 + `created_at` 索引）；
  使用者資料來源＝PostgreSQL；**不使用 JSON fallback**（PG 失敗回 `failed_to_load_users`）。
- Admin API endpoint：`GET /api/admin/users`（Bearer ADMIN_API_TOKEN；401/403/200/500）。
- 管理者端入口：caregiver_web 新增「使用者管理」分頁。
- 觸及 🔒？：是——`server.js` 新增路由（API 契約）、DB schema（新增 migration）、`sessionService`
  登入流程（最小、加性、try-catch 不阻擋登入）。皆為純新增 / 加性，未更動既有路由形狀與既有欄位。
- 風險等級：medium（碰 API 契約 + schema + 登入流程，但均加性且有測試覆蓋）。
- 是否動到 Realtime：否。Care Alert：否。Telegram：否。長期記憶：否。情緒辨識：否。
- 是否動到登入註冊：是（僅在 PG 路徑加 last_login_at 寫入 / 更新，行為相容；JSON fallback 不變）。
- 是否使用 JSON fallback：否。是否 hardcode demo users：否。是否回傳敏感欄位：否。
- 測試結果：後端 `npm test` 176/176 通過（新增 9）；caregiver_web 33/33 通過（新增 7）。
- architecture-agent 裁決：✅ 自核（medium risk，純加性、測試覆蓋齊全、未改既有契約形狀）
- 完成狀態：✅ 完成

### CR-0030：正式版管理者端健康分析儀表板（資料真實性誠實標註，2026-06-03）
- 提出 agent：backend-agent（分析聚合 dataSource）＋ frontend-ux-agent（健康頁顯示）
- 動機：健康分析儀表板（生理/心理/情緒/遊戲/摘要）雖已存在，但生理/情緒/遊戲皆由確定性
  產生器供給（看起來真但非真實）。CR-0030 要求誠實標註、優先真實來源、資料不足顯示「資料不足」、
  不可捏造。使用者決策＝Option A（誠實標註 + 資料不足）。
- 盤點結論：真實＝長者名單（PG/JSON/種子）、Care Alert；非真實＝生理/情緒/遊戲（healthMetrics
  確定性產生器）。`emotion_history` / `elder_health_metrics` / `game_cognitive_metrics` 三表存在但
  零寫入。
- 設計：
  - **示範種子長者** → 保留可重現指標，標 `dataSource:"reference"`（示範參考資料）。
  - **真實長者** → 生理/情緒/遊戲回空序列 + `dataSource:"insufficient"`（前端顯示「資料不足」，不捏造）。
  - Care Alert 維持真實顯示；個人分析新增 `emotionDataSource`。
  - `dataSource` 值用乾淨字（reference/insufficient/measured），不踩「demo/fake/mock」紅線。
- 修改檔案：
  - `backend/stt_proxy/services/admin/adminAnalysisService.js`（新增 isSeedElder + resolve* 包一層 dataSource）
  - `backend/stt_proxy/services/admin/adminAnalysisService.test.js`（更新真實長者測試 + 新增種子 reference 測試）
  - `caregiver_web/index.html`、`app.js`、`styles.css`（非醫療+資料來源橫幅、資料來源標籤、資料不足空狀態）
- 新增檔案：`docs/ADMIN_HEALTH_ANALYTICS.md`、`caregiver_web/admin_health_analytics.test.js`
- 資料庫變更：無（沿用既有表；未新增 migration）。
- 觸及 🔒？：是——admin 分析 API response 形狀（新增加性欄位 `dataSource` / `emotionDataSource`，
  真實長者序列改為空）。屬加性 + 誠實化，未移除既有欄位、未改路由。`healthMetrics` 產生器未動。
- 風險等級：medium（碰 admin 分析契約，但加性且測試覆蓋）。
- 是否動到 Realtime：否。Care Alert：否（維持真實顯示）。Telegram：否。長期記憶：否。
  情緒辨識：否（即時辨識邏輯未動）。登入註冊：否。CR-0029 使用者管理：否。
- 是否新增 fake data / hardcode demo analytics：否（反而把非真實資料誠實降級標註）。
- 是否仍有 JSON fallback：是（elders 來源；已於文件誠實記錄，未宣稱全 PostgreSQL 化）。
- 測試結果：後端 `npm test` 177/177 通過（淨 +1）；caregiver_web 38/38 通過（新增 5）。
- architecture-agent 裁決：✅ 自核（medium risk，加性誠實化、未改既有契約欄位與路由）
- 完成狀態：✅ 完成

### CR-0031：管理者端使用者姓名 fallback（email 前綴當預設名，2026-06-03）
- 提出 agent：backend-agent（CR-0029 後續微調）
- 動機：email 帳號註冊不收姓名 → `display_name` 為空，後台「使用者管理」姓名欄一排空白。
- 作法：`adminUsersService.deriveDisplayName()`——有 display_name 用之；email 帳號無名字時用
  email `@` 前綴當預設名（例 `kikigay1109`）；皆無回 null（前端顯示「—」）。純顯示用，不竄改 DB、
  不改登入流程；Google 帳號維持原名。
- 影響檔案：`backend/stt_proxy/services/admin/adminUsersService.js`、`adminUsersService.test.js`
- 觸及 🔒？：否（CR-0029 既有服務內部加 fallback，未改路由 / response 欄位集 / DB）。
- 風險等級：low。
- 測試：`adminUsersService.test.js` 新增 deriveDisplayName 案例；後端測試全綠。
- 完成狀態：✅ 完成

### CR-0032：新帳號完成設定後自動播放新手導覽（修設計矛盾，2026-06-03）
- 提出 agent：frontend-ux-agent
- 問題：onboarding 設計本意是「功能導覽由首次進首頁的 Spotlight（CoachMarkHost）自動負責」，
  但 `_startUsing()` 在完成帳號設定當下就 `saveHomeCoachMarkDone(true)`，把首頁導覽預先標記
  「已看過」→ 新使用者反而永遠看不到自動導覽（與設計自相矛盾）。
- 作法：移除完成設定時的預先標記，讓新帳號首次進首頁時 CoachMarkHost 自動播放一次導覽
  （播完才由 overlay 記錄已看過，不會重播）；移除變成未使用的 import。
- 影響檔案：`lib/screens/onboarding_screen.dart`、`test/screens/onboarding_screen_test.dart`
- 觸及 🔒？：否（純前端 onboarding 流程；未碰 Realtime / 後端 / DB）。
- 風險等級：low。
- 測試：`onboarding_screen_test` + `home_screen_layout_test` 全綠；`flutter analyze` 無問題。
- 注意：已存在、已完成設定的舊帳號其 coachMarkDone 已是 true，不會回溯自動播放；可由
  「設定 → 重新觀看新手導覽」手動觸發。新帳號才會自動播放。
- 完成狀態：✅ 完成

### CR-0033：修刪除帳號紅屏（TextEditingController use-after-dispose，2026-06-03）
- 提出 agent：frontend-ux-agent
- 問題：刪除帳號的密碼重新驗證對話框 `_promptDeletePassword` 在 `await showDialog` 一返回就
  `finally { controller.dispose() }`，但對話框關閉動畫仍會 rebuild TextField → 「TextEditingController
  used after being disposed」紅屏（後續 Duplicate GlobalKey / RenderFlex 溢位皆為連鎖）。此紅屏會
  中斷整個刪除流程 → 後端沒收到刪除請求、帳號未被清除（用 PostgreSQL 觀察到帳號殘留）。
- 作法：把密碼對話框改為獨立 StatefulWidget `_DeletePasswordDialog`，由其 `State.dispose()`
  （對話框關閉動畫結束後）釋放 controller，消除 use-after-dispose。
- 影響檔案：`lib/screens/settings_screen.dart`
- 觸及 🔒？：否（純前端對話框生命週期；未碰 Realtime / 後端 / DB / 刪除邏輯本身）。
- 風險等級：low。
- 驗證：`flutter analyze` 無問題；`home_screen_layout_test`（含刪除帳號流程）全綠；實機 release
  端到端驗證——刪除不再紅屏、PostgreSQL 舊帳號被清除、同 email 可重新註冊。
- 完成狀態：✅ 完成

### CR-0034：語音模式工具用寵物聲音回應 + 修中文 partial 轉錄崩潰 debug log（2026-06-03）
- 提出 agent：realtime-voice-agent
- 問題：
  1. 語音對話下，生活工具（找新聞 / 播音樂 / 打電話…）由 `agentToolController.routeFromUserText`
     在背景判斷與執行，但結果**沒接回 Realtime 語音** → 寵物只閒聊、不講工具結果 → 使用者覺得「沒聽懂」。
  2. `[TRANSCRIPT] partial=$transcript` 直接印中文 partial 轉錄，多位元組字被切斷會產生無效 UTF-8，
     使 `flutter run` 的 stdout 解碼器崩潰（debug session 中斷，難以實機抓 log）。
- 作法：
  - `realtime_voice_service.dart` 新增 `speakToolOutcome(line)`：只送一次性 `response.create` +
    `response.instructions` 讓寵物用語音念出該句；**不建立 user 訊息（無假泡泡）、不動 SDP / VAD
    純語音主流程**，沿用既有 `_sendEventPayload`。
  - `voice_agent_controller.dart`：`routeFromUserText` 完成後 `_maybeSpeakToolOutcome()`——低風險工具
    念出執行結果；需確認的高影響工具念出確認問句（實際動作仍由確認 UI 完成，安全閘門不變）。
  - `realtime_voice_service.dart`：`[TRANSCRIPT]` partial 只印長度、final 才印原文，避免無效 UTF-8。
- 影響檔案：`lib/services/realtime_voice_service.dart`（🔒）、`lib/controllers/voice_agent_controller.dart`
- 觸及 🔒？：是（`realtime_voice_service.dart`）——僅**新增 public 方法 + 修 debug log**，未改連線 /
  SDP / DataChannel / server_vad 主流程、未改成 mock、無 demo fallback。
- 風險等級：medium（碰 Realtime 檔，但屬純增量；純語音路徑不受影響）。
- 驗證：`flutter analyze` 無問題；realtime / voice / agent_voice 整合測試 43 項全綠。實機語音回應待使用者驗證。
- 備註：找新聞要回真實結果需後端設定 `TAVILY_API_KEY`（非本 CR 範圍，屬環境設定）。
- 完成狀態：✅ 完成（實機語音體驗待驗證）

### CR-0035：搜尋來源政策改為「盡量不限制，只擋成人內容」（2026-06-03）
- 提出 agent：backend-agent（依使用者產品決策）
- 動機：原 `trusted_source_filter` 採白名單（只放行 gov/edu/cna/pts/rti…），Tavily 回的主流新聞
  （reuters / nbcnews / cbsnews / udn…）被全數濾掉 → 「找新聞」永遠 fallback。實測確認 Tavily 有回 4 筆
  新聞但被白名單擋光。
- 使用者決策：除限制級 / 成人內容外，一律不過濾。
- 作法：`filterTrustedSources` 從「白名單才放行」改為「全部放行、只擋成人內容」
  （`isAdultSource`：成人網域清單 + 網址/標題關鍵字）。保留 `TRUSTED_DOMAINS` / `isTrustedSource`
  作為「特別可信」標記用途（非過濾門檻）。
- 影響檔案：`backend/search/trusted_source_filter.js`、`backend/search/search_service.test.js`
- 觸及 🔒？：否（搜尋來源過濾模組內部邏輯；未改 server.js 路由 / response 形狀 / DB）。
- 風險等級：low–medium（放寬內容來源；以成人內容阻擋為唯一限制，符合長者陪伴情境）。
- 註：此政策刻意放寬原 CLAUDE.md「可信來源優先」設計，依使用者明確決策。
- 驗證：`search_service.test.js` 5 項全綠；實打 `/api/search`（news）→ `provider=web_search`、
  回 4 筆真實新聞 + 長輩版摘要。需後端 `TAVILY_API_KEY`（使用者已設定）。
- 完成狀態：✅ 完成

<!-- 新提案請往下加 CR-0004 ... -->

### CR-0036：consent_records 後端持久化 API（知情同意稽核軌跡）— ⬜ 未開始（2026-06-08 開立）
- 提出 agent：architecture-agent（依 Phase 1 production 升級需求）
- 動機 / 問題：App Store / Google Play 與 `CLAUDE.md`（根目錄版）§9、`pet_companion_app/CLAUDE.md` §3.3/§9 要求「知情同意需可稽核」。前端 Batch 1.1 已做**本機**同意 Gate（`lib/services/consent_service.dart`，僅存 shared_preferences：`consent.acceptedVersion` / `consent.grantedAt`，無後端、無稽核軌跡）。本 CR 補後端持久化（PostgreSQL）與查詢/撤回稽核能力。`PROJECT_ARCHITECTURE.md` §3.3 已將 `consent_records` 列為核心表，本案屬「補齊已規劃 schema」，非新架構。
- 影響範圍（檔案）：
  - 新增 `backend/stt_proxy/db/migrations/010_create_consent_records.sql`（next 編號＝010，現有最高為 `009_create_marketplace.sql`）。
  - 新增 `backend/stt_proxy/services/consentStoreService.js`（pg insert / list / withdraw；dev-only JSON fallback 比照既有 store，正式以 PG 為準）。
  - `backend/stt_proxy/server.js`（新增 `POST /api/consent`、`GET /api/consent`；**不改既有路由形狀**）。
  - 新增 `backend/stt_proxy/services/consentStoreService.test.js` 與端點測試。
  - 文件：`PROJECT_ARCHITECTURE.md` §10（新增 consent API 契約，B2 動工前先更新）。
  - （後續、非本 CR 後端範圍）`lib/services/consent_service.dart` best-effort 補送。
- 觸及 🔒？：**是** — ① DB schema / migration（新 `consent_records` 表）；② `server.js` API 契約（新增 2 條路由）。
- 牽涉哪些 agent：backend-agent（B1 migration、B2 service+route）、frontend-ux-agent（B3 ConsentService 補送，後續排程）、architecture-agent（契約 + 審查）。
- 風險等級：low–medium（純新增表與新增路由，不改任何既有流程 / 既有路由形狀 / 既有測試；最大風險是 schema 欄位設計需一次到位避免日後再 migration，以及 PII 欄位的隱私處理）。
- migrate.js 機制（已查證）：`db/migrate.js` 啟動時 glob `migrations/*.sql` 依檔名排序逐一執行、**無 schema_migrations 追蹤、每次啟動重跑**，全靠 `IF NOT EXISTS` 冪等。→ 010 **無需改 migrate.js**，但 SQL 必須完全冪等（沿用 006/008 的 `CREATE TABLE IF NOT EXISTS` + `ALTER TABLE ADD COLUMN IF NOT EXISTS` + `CREATE INDEX IF NOT EXISTS` + `pgcrypto`/`gen_random_uuid()` 慣例）。
- `consent_records` 欄位建議（沿用既有 UUID/TIMESTAMPTZ 慣例）：
  - `id UUID PK DEFAULT gen_random_uuid()`
  - `user_id UUID REFERENCES users(id)` **nullable**（同意可能在後端尚未建 user 前發生；有 firebaseUid/idToken 時解析回填）
  - `elder_id UUID REFERENCES elders(id)` **nullable**
  - `consent_type TEXT NOT NULL`（enum-by-convention：`privacy_terms`（對應目前單一 gate）/ `data_collection` / `microphone` / `notification`，預留細分）
  - `consent_version TEXT NOT NULL`（對應前端 `consent.acceptedVersion`）
  - `action TEXT NOT NULL DEFAULT 'granted'`（`granted` | `withdrawn`，撤回不刪舊列、改寫新列＝完整稽核軌跡）
  - `source TEXT`（`elder_app_onboarding` | `settings` …）
  - `agreed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`、`withdrawn_at TIMESTAMPTZ`（nullable）
  - `app_version TEXT`、`platform TEXT`（nullable，稽核用）
  - `ip TEXT`、`user_agent TEXT`（**nullable、可選**；§9 要求 log 不可輸出完整個資 → 僅落 DB，server log / API response 不得回顯，蒐集前需在隱私政策揭露）
  - `created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`
  - 索引：`idx_consent_user_id (user_id)`、`idx_consent_type_version (consent_type, consent_version)`
- 路由契約建議（**沿用既有風格**：`app.post`/`res.json({success:true,...})`、缺欄 `400 {success:false,error:"invalid_payload"}`、例外 `500 {success:false,error:"consent_failed"}`，**絕不回 stack trace**；auth 比照 `/api/auth/delete`：`authFirebaseAdmin.isConfigured()` → 驗 `idToken` 取權威 uid 解析 user_id；否則 mock-allowed 採信傳入識別）：
  - `POST /api/consent`：body `{ firebaseUid?, idToken?, userId?, elderId?, consentType, consentVersion, action?, source?, appVersion?, platform? }` → 寫一列，回 `{ success:true, record:{ id, consentType, consentVersion, action, agreedAt } }`（**不回 ip/user_agent**）。
  - `GET /api/consent?userId=...`（或 `?firebaseUid=`）：回該使用者同意歷史 `{ success:true, records:[...] }`（供設定頁/稽核；同樣遮蔽 PII）。
  - （延後）caregiver_web 稽核檢視走 `/api/admin/*`，本 CR 不含。
- 與前端 ConsentService 對接點（後續 B3，非本 CR 後端範圍）：`recordConsent(version)` 成功後 best-effort `POST /api/consent`（**非阻塞、失敗不擋長者**，比照 `deleteAccount` best-effort 模式）；帶當前 `AuthController` 的 firebaseUid/idToken/userId/elderId。前端目前僅存單一 `version`，後端 `consent_type` 先以 `privacy_terms` 對應，細分留待後續。
- 建議批次切分：
  - **Batch 1（backend-agent）**：只加 `010_create_consent_records.sql`（完全冪等）。驗收：對 dev DB 跑 migrate 成功、重跑冪等不報錯；不接任何路由。最小、可獨立 revert。
  - **Batch 2（backend-agent）**：`consentStoreService.js` + `POST /api/consent` + `GET /api/consent` + `node --test`。**動工前先更新 `PROJECT_ARCHITECTURE.md` §10 契約**（architecture-agent 規則：跨契約改動先更新架構文件再放行）。
  - **Batch 3（frontend-ux-agent，後續排程）**：ConsentService best-effort 補送，不阻塞同意 Gate。
- 測試計畫（node --test）：`consentStoreService.test.js`（insert / list / withdraw 寫新列不刪舊 / 缺必填欄位→拒絕 / 冪等）、端點測試（`400 invalid_payload`、`200 success` 形狀、mock-auth 採信傳入 uid 路徑、PII 不回顯）、`npm run check`；migration 以 dev DB 實跑 + 重跑驗冪等。
- architecture-agent 裁決：**✅ 核准 Batch 1（migration 010，已 ship）**；**✅ Batch 2 放行（2026-06-08，前置治理完成）** — consent API 正式契約已定稿於 `PROJECT_ARCHITECTURE.md §10.4`（`POST /api/consent` / `GET /api/consent` request/response 形狀、辨識沿用既有 auth 中介、錯誤碼 `400 invalid_payload` / `401 invalid_id_token` / `500 consent_failed`、PII 不回顯），backend-agent 可依該契約實作 `consentStoreService.js` + 2 條路由 + `node --test`；Batch 3（前端 best-effort 補送）待 B2 ship 後排程。
  - **backend-agent 實作紅線（B2）**：① `ip`/`user_agent` 後端自 `req` 擷取、僅落 DB，**response 與 server log 一律不回顯**；② 錯誤一律 `{success:false,error}`，**絕不回 stack trace**（細節只進 `logError`）；③ 辨識沿用 `authFirebaseAdmin.isConfigured()` → 驗 `idToken` / 否則 `authMockAllowed()`，**不新發明 auth**；④ 只新增 2 條路由，**不改任何既有路由形狀**；⑤ 不破壞既有測試（現基線需全綠）、不碰 `.env`/token、不把 runtime `data/*.json` 進 git；⑥ 無新增環境變數（沿用 `AUTH_ALLOW_MOCK` 與既有 PG / Firebase 設定）。
- 完成狀態：🔁 進行中 — **Batch 1 ✅ 已 ship**（migration 010）；**Batch 2 ✅ 放行（前置治理完成：契約已寫入 `PROJECT_ARCHITECTURE.md §10.4`）**，待 backend-agent 實作；Batch 3 待排程

### CR-0037：移除正式環境 mockFallback 造假登入（正式登入失敗應白話錯誤＋重試）— ⬜ 未開始（2026-06-08 開立）
- 提出 agent：architecture-agent（依 Phase 1 production 升級需求）
- 動機 / 問題：`lib/services/auth/session_api_service.dart` 的 `createSession` 在後端 **non-2xx / timeout / JSON 解析失敗時一律回 `AuthSession.mockFallback()`**（`authMode='mock'`、`provider='mock'`、`elderId='default_user'`）。對「正式帳號的後端失敗」而言，這是**未經後端驗證就捏造一個 authenticated session**（§2.1 fake user、§9 隱私），且把後端故障對使用者**靜默成功**、無白話錯誤、無重試。
- ⚠️ 現況校正（architecture-agent 已查證，誠實修正任務前提）：任務描述的「真實使用者被塞進共用 `default_user` → 跨使用者資料混用」**對 email/google 路徑其實已被部分緩解**：`auth_service.dart` `_createSessionFromFirebase`（行 118–126）在 createSession 回 mockFallback 時，會以 **Firebase uid 取代 default_user 當隔離 key**（且有測試 `auth_service_test.dart:431` 斷言此行為）。因此不同正式帳號**不會**塌縮成同一個 default_user 命名空間。**真正殘留的正式版問題**是：
  1. 正式（email/google）登入遇後端 non-2xx/timeout/parse-fail 時，App **捏造一個後端從未驗證的 authenticated session**，使用者被當成已登入；其資料 key 在後端未知（server 端記憶/Care Alert/elder 聚合無法正確歸戶）→ 把後端中斷對使用者**靜默成假成功**，且**沒有**白話錯誤＋重試路徑。
  2. 後端 `401 invalid_id_token`（真正的 token 拒絕）目前與一般 5xx **一視同仁**走 fallback → 無效 token 也被捏造成 session。
  3. `mockLogin`（Demo 路徑）本就刻意捏造 demo user（`provider='mock'`、`default_user`），**這是 Demo 專用**且登入頁 Demo 按鈕已被 `AppConfig.showDemoLoginButton`（`SHOW_DEMO_LOGIN`，預設 false）隔離 — 此路徑**應保留**，不在移除範圍。
- 影響範圍（檔案）：
  - `lib/services/auth/session_api_service.dart`（核心：`createSession` 改為 provider-aware；真實 provider 失敗 → 丟 typed 例外，不捏造）。
  - `lib/services/auth/auth_service.dart`（`_createSessionFromFirebase` 的 uid-substitution offline 捏造需重新評估：正式版預設不捏造 authenticated session；如保留離線能力須 dev-flag 隔離）。
  - `lib/controllers/auth_controller.dart`（email/google 路徑失敗 → `error` 狀態 + 白話訊息；已有 `_friendlyEmailError`/`_friendlyGoogleError` 基礎，補上「後端 session 失敗」對映）。
  - 測試：`test/services/auth_service_test.dart`（行 431、542 兩個**斷言舊捏造行為**的測試需改寫為「丟例外/surface error」）、`test/services/session_api_service` 相關、`test/controllers/auth_controller` 相關、`test/screens/login_screen_test.dart`（test double 內用 mockFallback，多半不受影響）。
- 觸及 🔒？：**是** — auth 契約（`session_api_service` 對外行為 + `AuthController` 對失敗的處理語意）。**後端 `server.js /api/auth/session` 不需改**（已正確回 401 invalid_id_token / 500 auth_session_failed，問題在前端一律吞成 fallback）。
- 牽涉哪些 agent：frontend-ux-agent（主，全部三批）、architecture-agent（契約 + 審查）。backend-agent 不需動。
- 風險等級：medium（改既有 auth 行為、且涉及一條 Demo 也會經過的程式路徑；需嚴守「不破壞 Demo」「不回工程錯誤訊息給長者」）。
- 建議批次切分（依任務建議順序）：
  - **Batch 1（frontend-ux-agent）— 把 mockFallback 隔離為「Demo 專用」**：`createSession` 改 provider-aware —— `provider=='mock'`（Demo）→ 維持回 `mockFallback`（行為不變，Demo 安全）；真實 provider（email/google/apple）→ 後端 non-2xx/timeout/parse 改丟新的 typed `SessionApiException`（含可分類 code，如 `network`/`server`/`invalid_token`，**不含後端原文**）。保留 `AuthSession.mockFallback` factory（Demo 仍用）。同批重新評估 `auth_service.dart` 的 uid-substitution：正式版預設**不捏造** authenticated session（移除或 dev-flag 隔離）。
  - **Batch 2（frontend-ux-agent）— 正式路徑白話錯誤＋重試**：`AuthController.signInWithEmail/registerWithEmail/signInWithGoogle` 捕捉 `SessionApiException` → `error` 狀態 + 白話訊息（沿用既有 `_friendly*Error` 風格，如「現在連線不太順，待會再試一次好嗎？」）；確認 `error` 狀態在 `app.dart` AuthGate 仍回 LoginScreen（非死路、可重試，CR-0006 B3c 已保證）。
  - **Batch 3（frontend-ux-agent）— 測試**：改寫 `auth_service_test.dart` 兩個斷言舊捏造行為的測試為「真實 provider 後端失敗 → 丟 `SessionApiException` / AuthController 進 error + 白話訊息」；補 `session_api_service` 的 provider-aware 分支測試（mock→fallback、real→throw、401→可辨識）；回歸 `flutter analyze` + 既有 auth/login widget 測試全綠。
- 測試計畫：`flutter test test/services/auth_service_test.dart test/services/session_api_service_test.dart test/controllers/auth_controller_test.dart test/screens/login_screen_test.dart`；回歸全 `test/` + `flutter analyze`。
- 風險評估與緩解：
  - ①**誤擋 Demo**：`provider=='mock'` 路徑零改動、Demo 按鈕已 `SHOW_DEMO_LOGIN` 隔離 → Demo 不受影響。緩解：Batch 1 只動真實 provider 分支。
  - ②**回工程錯誤給長者**：嚴禁把 `SessionApiException`/Firebase 原文顯示 → 一律經 `_friendly*Error` 轉白話（§11.6）。
  - ③**改壞既有測試**：行 431/542 兩測試**斷言的正是要修正的捏造行為**，屬「刻意重新規格化」非「破壞既有正確測試」；須在 Batch 3 同步改寫並說明理由，不得偷刪。
  - ④**離線能力退化**：原 uid-substitution 讓「後端連不到也能進 App」；正式版改為「白話錯誤＋重試」是正確取捨（§5 網路中斷要清楚告知並可重連）。如產品仍要離線 Demo，走 Demo 登入（已 flag 隔離），不靠正式帳號捏造。
  - rollback：純前端、單一 feature commit，`git revert` 即恢復；後端零改動、無 schema。
- architecture-agent 裁決：**✅ 核准 Batch 1（provider-aware 隔離，可即刻執行）**；Batch 2/3 隨後依序執行（同 owner，不需再審，但 Batch 3 改寫既有測試須於回報中逐項說明理由）。限制：`provider=='mock'` Demo 路徑不得改、不碰 Realtime / `server.js` / `.env`/token、白話錯誤不得含工程字眼、`error` 狀態不得成死路。
- 完成狀態：✅ 已完成（2026-06-08，frontend-ux-agent；Batch 1+2+3 一次連貫提交）
  - 實作：
    - `session_api_service.dart`：新增 typed `SessionApiException`（code: `network`/`server`/`invalid_token`，不含後端原文）；`createSession` 改 provider-aware —— `provider=='mock'`（Demo）維持 mockFallback；正式帳號 non-2xx → 401 丟 `invalid_token`、其餘丟 `server`；解析失敗（FormatException）丟 `server`；timeout/連線錯誤丟 `network`。`AuthSession.mockFallback` factory 保留（Demo 仍用）。
    - `auth_service.dart`：移除 `_createSessionFromFirebase` 行 118–126 的 uid-substitution 離線捏造——正式帳號後端失敗改往上拋，不再捏造 authenticated session。
    - `auth_controller.dart`：`_runEmailAuth` 與 `signInWithGoogle` 新增 `on SessionApiException` 捕捉 → 新 `_friendlySessionError(code)` 白話訊息（`invalid_token`→「登入的資料好像過期了，請重新登入一次好嗎？」；`network`→網路白話；`server`→「登入暫時有點忙不過來…」），維持 `error` 狀態可在 LoginScreen 重試。
  - 重新規格化的既有測試（非破壞，斷言的正是要修正的捏造行為）：`auth_service_test.dart` 原「Firebase 成功但後端不可達 → 用 uid 當隔離 key」「Google 成功但後端失敗 → mockFallback」兩測試，改寫為「正式帳號後端失敗 → 丟 `SessionApiException` 且不持久化」，並補 401/連線錯誤分支。
  - 測試：`flutter analyze` 0 issue；`flutter test` 全綠 **464 passed**（基線 452 → 新增/改寫 auth 測試）。

### CR-P2A：Care Alert 改 PostgreSQL 持久化（DB-優先、向下相容既有 JSON）— 🚧 進行中（2026-06-08 開立）
- 提出 agent：architecture-agent（Phase 2 production 升級 / 治理）
- 動機 / 問題：`careAlertStoreService.js` 目前**只**用 `fs.writeFile` 寫 `data/care_alerts.json`，等於把 Care Alert 核心資料以 JSON 檔當正式資料來源，違反 `pet_companion_app/CLAUDE.md §3.3`「正式版不可依賴 JSON file 作為主要資料庫」、且 §3.3 已把 `care_alerts` / `care_alert_status_events` 列為核心表。本 CR 補 PostgreSQL 持久化與狀態事件軌跡，**DB-優先**，JSON 降為 dev-only fallback。
- ⚠️ 與 CR-0036（consent）DB-only 的關鍵差異（architecture-agent 裁定）：consent 是**稽核資料**（不可 JSON 假成功，連不到 DB 就丟例外）；**Care Alert 是可降級的營運資料**——high/urgent 通知不能因 DB 連不上就整條 `/notify` 失敗（會漏掉長者異常通知，比暫存 JSON 更糟）。故 Care Alert 採 **DB-優先 + JSON fallback（dev/容錯雙用）**，與 consent 的 DB-only 刻意不同，並在架構文件 §5 明記此差異與理由。
- 現況查證（architecture-agent）：
  - store 介面：`saveAlert / listAlerts / getAlertById / updateAlertStatus / deleteAlertsByElderId`（+ `normalizeAlert / normalizeRiskLevel / RISK_LEVEL_LABELS / VALID_STATUSES`）。
  - 資料形狀：見 `PROJECT_ARCHITECTURE.md §5`（id/elderId/receivedAt/status/riskLevel/riskLevelLabel/category/categoryLabel/triggerSummary/transcriptSnippet/createdAt/source/statusUpdatedAt/acknowledgedAt/resolvedAt）。
  - 狀態機：`VALID_STATUSES = ["new","acknowledged","resolved"]`，`new → acknowledged → resolved`。
  - `riskLevel` 權威四級 + legacy 讀取容錯（`normalizeRiskLevel`：normal→low、attention→medium、未知→low）已實作，DB 寫入沿用同一正規化。
  - server.js 路由：`POST /api/care-alerts/notify`、`GET /api/care-alerts`、`GET /api/care-alerts/:id`、`PATCH /api/care-alerts/:id/status`；回應形狀 `{success,alert}` / `{success,alerts}`。`deleteAlertsByElderId` 另由 `/api/auth/delete` 帳號刪除級聯呼叫（行 ~538）。
  - `telegramNotifyService` 用到欄位：riskLevel / riskLevelLabel / category / categoryLabel / triggerSummary / transcriptSnippet / createdAt / source（DB 化不得改這些欄位語意）。
  - 測試：`careAlertStoreService.test.js`（用 `options.filePath` temp 檔）、`careAlertListEndpoint.test.js` / `careAlertNotifyEndpoint.test.js` / `careAlertStatusEndpoint.test.js` / `careAlertDemoFlow.test.js`（用 `CARE_ALERTS_DATA_FILE` env 指 temp 檔）。**這些測試跑在無 `DATABASE_URL` 環境 → 必須仍走 JSON 路徑且全綠**，是本 CR 最重要的相容紅線。
  - migrate.js：glob `migrations/*.sql` 依檔名排序、每次啟動重跑、無 schema_migrations 追蹤 → 新 migration **必須完全冪等**（沿用 `CREATE TABLE IF NOT EXISTS` + `ADD COLUMN IF NOT EXISTS` + `CREATE INDEX IF NOT EXISTS` + `pgcrypto`/`gen_random_uuid()`）。現有最高編號 `010_create_consent_records.sql` → 本 CR 用 **011**。
  - `db/postgres.js` 提供 `query()` 與 `isPostgresAvailable()`（`DATABASE_URL` 未設或 `PGVECTOR_ENABLED!=true` 即回 false）→ 作為「DB 可用才走 DB、否則 JSON fallback」的天然 gate；store 沿用 consentStoreService 的 `options.pg` / `setPgForTest` 注入模式以便單測。
- 影響範圍（檔案）：
  - 新增 `backend/stt_proxy/db/migrations/011_create_care_alerts.sql`（`care_alerts` + `care_alert_status_events` 兩表，完全冪等）。
  - 改 `backend/stt_proxy/services/careAlertStoreService.js`（DB-優先讀寫；DB 不可用 → JSON fallback；**對外 5 個函式簽章與回傳形狀完全不變**）。
  - 新增 `backend/stt_proxy/services/careAlertStoreService.db.test.js`（注入 mock pg 測 DB 路徑；既有 JSON 測試保留不改）。
  - 文件：`PROJECT_ARCHITECTURE.md §5`（標註後端持久化已 DB 化、DB-優先 + dev-only JSON fallback 的差異理由；schema 對映 011）。
  - **不改 server.js 任何既有路由形狀**（核心批次）。任何新增「狀態歷史 GET 路由」屬契約改動，延後且需先更新架構契約。
- 觸及 🔒？：**是** — ① DB schema / migration（新 `care_alerts` / `care_alert_status_events`）；② Care Alert 三方共用資料結構（§5）；③ `careAlertStoreService.js`（backend-agent owner，但屬共用 store）。**核心批次不觸 server.js 路由形狀**。
- 牽涉哪些 agent：backend-agent（B1 migration、B2 store DB 化、B3 狀態事件軌跡）、architecture-agent（schema/契約 + 審查）。frontend-ux-agent / companion-memory-agent 不需動（欄位與回傳形狀不變）。
- 風險等級：**medium**（改到核心 store 的讀寫實作；最大風險是破壞既有 JSON 測試與 `/notify` 不可因 DB 故障而漏掉 high/urgent 通知）。
- `care_alerts` 欄位（對映 §5 JSON 形狀，沿用 UUID/TIMESTAMPTZ 慣例）：
  - `id UUID PK DEFAULT gen_random_uuid()`、`elder_id UUID REFERENCES elders(id)` nullable
  - `received_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`、`status TEXT NOT NULL DEFAULT 'new'`（CHECK in new/acknowledged/resolved）
  - `risk_level TEXT NOT NULL DEFAULT 'low'`（寫入前以 `normalizeRiskLevel` 收斂為四級）、`risk_level_label TEXT`
  - `category TEXT`、`category_label TEXT`、`trigger_summary TEXT`、`transcript_snippet TEXT`
  - `created_at TIMESTAMPTZ`（payload 來源時間，可空）、`source TEXT`
  - `status_updated_at TIMESTAMPTZ`、`acknowledged_at TIMESTAMPTZ`、`resolved_at TIMESTAMPTZ`
  - 索引：`idx_care_alerts_elder (elder_id)`、`idx_care_alerts_risk (risk_level)`、`idx_care_alerts_status (status)`、`idx_care_alerts_received (received_at DESC)`
  - **id 由 service 端產生（`randomUUID`）並帶入 INSERT**，與既有 JSON 形狀一致，避免 DB 與 JSON 兩路徑 id 來源不同。
- `care_alert_status_events`（狀態軌跡，append-only）：
  - `id UUID PK DEFAULT gen_random_uuid()`、`alert_id UUID NOT NULL REFERENCES care_alerts(id) ON DELETE CASCADE`
  - `from_status TEXT`、`to_status TEXT NOT NULL`、`changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`、`source TEXT`（誰改：caregiver_web / system）
  - 索引：`idx_alert_status_events_alert (alert_id)`
- DB-優先 / fallback 規則（紅線）：
  - 讀寫先試 DB（`isPostgresAvailable()` 為 true 時）；DB 例外 → 記 `logError`（不含原文/PII）後**降級 JSON**，不丟例外、不讓 `/notify` 失敗。
  - 無 `DATABASE_URL`（含所有現有測試與 Demo 無 DB 機）→ 直接走 JSON，行為與今日**完全一致**。
  - **向下相容既有 `care_alerts.json` runtime 資料**：JSON 路徑保留 `normalizeAlert` / 讀取容錯（缺欄位視 null、legacy riskLevel 容錯），既有 alert 顯示與篩選不破壞。
  - 不做 JSON↔DB 自動雙寫或遷移（避免重複 alert / id 衝突）；歷史 JSON 資料留在 JSON 路徑，新環境啟用 DB 後新資料進 DB。如需一次性匯入另開 follow-up，不在本 CR。
- 建議批次切分：
  - **Batch 1（backend-agent）— migration only**：加 `011_create_care_alerts.sql`（兩表，完全冪等），不接任何 store / 路由。驗收：dev DB 跑 migrate 成功 + 重跑冪等不報錯。最小、可獨立 revert。**不觸 server.js，不需先改契約。**
  - **Batch 2（backend-agent）— store DB 優先（保留 JSON fallback）**：改 `careAlertStoreService.js` 的 `saveAlert / listAlerts / getAlertById / updateAlertStatus / deleteAlertsByElderId` 為「DB 可用走 DB、否則 JSON」，**對外簽章/回傳形狀零變更**；新增 `setPgForTest` / `options.pg` 注入。新增 `careAlertStoreService.db.test.js`，**既有 JSON 測試一字不改且全綠**。**server.js 路由形狀不變 → 不需先改契約**（僅在 §5 補一句「後端已 DB 化、DB-優先」說明，B2 動工前更新）。
  - **Batch 3（backend-agent）— 狀態事件軌跡**：`updateAlertStatus` 在寫 status 同時 append 一列 `care_alert_status_events`（DB 路徑；JSON 路徑維持現狀不寫軌跡表，僅更新 alert 本體）。**不新增對外路由**。若日後要開 `GET /api/care-alerts/:id/history` 暴露軌跡 → 屬契約改動，須**先更新 `PROJECT_ARCHITECTURE.md §5` 契約再放行**（比照 CR-0036 規則），不在本 CR 核心批次。
- 測試計畫（node --test）：`careAlertStoreService.db.test.js`（mock pg：save/list/get/updateStatus/deleteByElder 的 DB 路徑、DB 例外→JSON 降級不丟例外、狀態軌跡 append）；既有 `careAlertStoreService.test.js` + 4 個端點測試**回歸全綠**（驗證無 DB 環境行為不變）；`npm run check`；migration 以 dev DB 實跑 + 重跑驗冪等。
- architecture-agent 裁決：**✅ 核准 Batch 1（migration 011，可即刻執行）**；**✅ 預核准 Batch 2/3 方向**（DB-優先 + JSON fallback、對外形狀零變更），但 **Batch 2 動工前需先在 `PROJECT_ARCHITECTURE.md §5` 補「後端持久化 DB 化 / DB-優先 vs consent DB-only 差異」說明**（治理前置，非契約形狀改動）。**任何新增路由（如狀態歷史 GET）一律退回，須另開契約更新後再審**。
  - backend-agent 實作紅線：① 既有 JSON 測試**一字不改、全綠**（無 DATABASE_URL 行為與今日一致）；② `/notify` 絕不因 DB 故障而失敗——DB 例外→降級 JSON+`logError`，**不回 stack trace**；③ log / response **不得含完整 `transcriptSnippet` 之外的對話原文、不得含 PII / token**（snippet 沿用既有 200 字截斷規則）；④ 向下相容既有 `care_alerts.json`（不改寫舊資料、legacy riskLevel 容錯）；⑤ 對外 5 函式簽章/回傳形狀零變更、server.js 路由形狀零變更；⑥ 不碰 `.env`、不把 runtime `data/*.json` 進 git；⑦ 無新增環境變數（沿用既有 PG 設定）。
- **Batch 2/3 正式放行（architecture-agent，2026-06-08）：✅ 放行（前置治理完成）。** 動工前置已完成——`PROJECT_ARCHITECTURE.md` 新增 **§5.3「後端 Care Alert 持久化（DB-優先 + JSON fallback）」**，明記與 CR-0036 consent **DB-only** 的差異與理由（care alert 為可降級營運資料，`/notify` 不可因 DB 故障漏掉 high/urgent 通知）、`careAlertStoreService` 對外 5 函式（`saveAlert / listAlerts / getAlertById / updateAlertStatus / deleteAlertsByElderId`）簽章與回傳形狀**零變更**、legacy riskLevel 讀取容錯、既有 `care_alerts.json` 不自動遷移 / 不雙寫。backend-agent 可依 **B2（store DB 化）→ B3（狀態軌跡）** 執行，恪守上方實作紅線；**任何新增路由（狀態歷史 GET 等）一律另開 CR、先更新 §4/§5 契約再審**。
- 完成狀態：🚧 進行中（Batch 1 migration 011 ✅ 已 ship；Batch 2/3 ✅ 放行待實作，前置治理 §5.3 / §6.1 已完成）

### CR-P2B：notification_logs + audit_logs（通知與敏感操作稽核）— 🚧 進行中（2026-06-08 開立）
- 提出 agent：architecture-agent（Phase 2 production 升級 / 治理）
- 動機 / 問題：`pet_companion_app/CLAUDE.md §8.7`「每次通知必須寫入 notification log」、§9.13「所有敏感操作需寫 audit log」、§8.10「通知失敗需可追蹤，不可靜默失敗」目前**完全未實作**（`grep notification_log / audit_log` 於 services + server.js = NONE；通知失敗只 `console` / `logError`，無持久化軌跡）。本 CR 補兩張稽核表與最小寫入點。
- 現況查證（architecture-agent）：
  - `telegramNotifyService.sendCareAlertNotification` 回 `{success}` / `{success:false,error,status?}`；`server.js /notify` 已分流 `skipped_low_risk` / `skipped_cooldown` / 真送（成功 `markTelegramSent`、失敗 `logError`）。→ notification_logs 寫入點集中在 `/notify` route（涵蓋 sent / failed / skipped 三種結局）。
  - cooldown：`careAlertCooldown`（in-process，`canSendTelegram` / `markTelegramSent`），與 log 正交，不改。
  - 敏感操作（server.js 既有）：帳號刪除 `/api/auth/delete`、Care Alert 狀態變更 `PATCH /api/care-alerts/:id/status`、consent 寫入（CR-0036 後）、登入 session（`/api/auth/session`）。**最小範圍先涵蓋前三者**（明確的資料/狀態變更與刪除），登入留待後續以免量大洗稽核。
  - `logError` 風格：`logError(message, extra)`，extra 只放 error code / status，不放原文 → audit log 沿用「結構化、不含原文/PII」原則。
  - migrate.js / postgres.js 機制同 CR-P2A；新 migration 用 **012**（在 CR-P2A 的 011 之後；若 P2A 未先 ship 則本 CR 取當下 next 編號並於動工時確認不撞號）。
- 影響範圍（檔案）：
  - 新增 `backend/stt_proxy/db/migrations/012_create_notification_audit_logs.sql`（`notification_logs` + `audit_logs` 兩表，完全冪等）。
  - 新增 `backend/stt_proxy/services/notificationLogService.js`、`backend/stt_proxy/services/auditLogService.js`（pg insert；**DB-only-best-effort**：寫入失敗只 `logError`、回 `{success:false}`，**絕不丟例外影響主流程**——稽核 log 失敗不可拖垮通知或操作本身）。
  - 改 `backend/stt_proxy/server.js`：在 `/notify`（通知三結局）、`/api/auth/delete`、`PATCH /api/care-alerts/:id/status` 補 best-effort 寫 log。**不改任何既有路由的 request/response 形狀**（只新增 fire-and-forget 寫入）。
  - 新增對應 `*.test.js`（mock pg）。
  - 文件：`PROJECT_ARCHITECTURE.md §3.3`（補列 `notification_logs` / `audit_logs` 核心表現況；目前架構文件僅 CLAUDE.md §3.3 列出，PROJECT_ARCHITECTURE 未明列）。
- 觸及 🔒？：**是** — ① DB schema / migration（兩新表）；② `server.js`（在既有路由內**新增 log 寫入**，但**不改路由 request/response 形狀**）。
- 牽涉哪些 agent：backend-agent（全部批次）、architecture-agent（schema + 審查）。
- 風險等級：**low–medium**（純新增表 + best-effort 寫入；最大風險是 log 誤含原文/PII，或稽核寫入例外拖垮主流程——兩者皆以紅線封死）。
- `notification_logs` 欄位：
  - `id UUID PK DEFAULT gen_random_uuid()`、`alert_id UUID REFERENCES care_alerts(id)` nullable、`elder_id UUID` nullable
  - `channel TEXT NOT NULL DEFAULT 'telegram'`、`risk_level TEXT`、`outcome TEXT NOT NULL`（`sent` | `failed` | `skipped_low_risk` | `skipped_cooldown`）
  - `error_code TEXT`（失敗時的 error code，如 `telegram_send_failed`；**不存原文/URL/token**）、`http_status INT`（nullable）
  - `created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`
  - 索引：`idx_notif_log_alert (alert_id)`、`idx_notif_log_created (created_at DESC)`
  - **不存**：完整對話原文、`transcriptSnippet`、chat_id、bot token、URL（§8.8 / §9.14）。
- `audit_logs` 欄位：
  - `id UUID PK DEFAULT gen_random_uuid()`、`actor_type TEXT`（`elder` | `caregiver` | `system`）、`actor_id TEXT` nullable（user_id / 識別；非 PII 明碼）
  - `action TEXT NOT NULL`（`account_delete` | `care_alert_status_change` | `consent_record` …）、`target_type TEXT`、`target_id TEXT`
  - `outcome TEXT`（`success` | `failed`）、`metadata JSONB`（**僅結構化非敏感欄位**：如 from/to status、刪除計數；**禁放原文 / email / ip / token**）
  - `created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`
  - 索引：`idx_audit_action (action)`、`idx_audit_actor (actor_id)`、`idx_audit_created (created_at DESC)`
- 建議批次切分：
  - **Batch 1（backend-agent）— migration only**：加 `012_create_notification_audit_logs.sql`（兩表，完全冪等），不接任何寫入。驗收：dev DB migrate + 重跑冪等。**不觸 server.js。**
  - **Batch 2（backend-agent）— notification_logs**：`notificationLogService.js`（best-effort insert）+ 在 `/notify` 三結局（sent / failed / skipped）寫一列。**不改 `/notify` response 形狀**（純新增 fire-and-forget）。最小可行先只涵蓋 Care Alert 通知。
  - **Batch 3（backend-agent）— audit_logs**：`auditLogService.js` + 在 `/api/auth/delete`、`PATCH /api/care-alerts/:id/status`（、CR-0036 ship 後的 consent 寫入）補 best-effort 稽核寫入。**不改既有路由 response 形狀**。
- 測試計畫（node --test）：`notificationLogService.test.js` / `auditLogService.test.js`（mock pg：insert 形狀、寫入失敗→回 `{success:false}` 不丟例外、**斷言 log 物件不含 token/原文/PII 欄位**）；端點回歸：`/notify`、`/api/auth/delete`、`/status` 既有測試全綠（驗證新增寫入不改回應）；`npm run check`；migration dev DB 實跑 + 冪等。
- architecture-agent 裁決：**✅ 核准 Batch 1（migration 012，可即刻執行）**；**✅ 預核准 Batch 2/3 方向**（best-effort、不改既有路由形狀）。因 Batch 2/3 在既有路由內新增寫入（屬 🔒 server.js 範圍），**動工前需先更新 `PROJECT_ARCHITECTURE.md §3.3`** 補列兩表現況（治理前置）；**只要任一批次改動 `/notify` 或敏感路由的 request/response 形狀即退回**。
  - backend-agent 實作紅線：① 稽核/通知 log 寫入**一律 best-effort**——失敗只 `logError` + 回 `{success:false}`，**絕不丟例外、不拖垮通知或操作主流程**；② log **絕不含**完整對話原文 / `transcriptSnippet` / email / ip / chat_id / bot token / 含 token 的 URL（§8.8、§9.14）；③ 既有路由 request/response 形狀**零變更**、既有測試全綠；④ 錯誤**不回 stack trace**（細節只進 `logError`）；⑤ 不碰 `.env`、不把 runtime `data/*.json` 進 git；⑥ 無新增環境變數。
- **Batch 2/3 正式放行（architecture-agent，2026-06-08）：✅ 放行（前置治理完成）。** 動工前置已完成——`PROJECT_ARCHITECTURE.md` 於 **§6.1「核心資料表（對映 CLAUDE.md §3.3）」** 正式列入 `notification_logs`、`audit_logs` 兩表（用途、欄位、「不存原文 / PII / token」紅線）；`notification_logs` 涵蓋 `/api/care-alerts/notify` **三結局**（sent / failed / skipped_*），`audit_logs` 先涵蓋**帳號刪除 / Care Alert 狀態變更 / consent 寫入**。backend-agent 可依 **B2（notification_logs）→ B3（audit_logs）** 執行，恪守上方實作紅線（best-effort、既有路由 request/response 形狀零變更、不含對話原文 / PII / token、不碰 `.env`、runtime `data/*.json` 不進 git、無新增環境變數）；**只要任一批次改動 `/notify` 或敏感路由 request/response 形狀即退回**。
- 完成狀態：🚧 進行中（Batch 1 migration 012 ✅ 已 ship；Batch 2/3 ✅ **已實作**——`notificationLogService.js`（/notify 三結局 sent/failed/skipped_low_risk/skipped_cooldown 各一列）、`auditLogService.js`（帳號刪除 / Care Alert 狀態變更 / consent 寫入）皆 DB-only-best-effort、fire-and-forget 接入 server.js 既有路由，**未改任何 request/response 形狀**；新增 `notificationLogService.test.js` / `auditLogService.test.js` / `notificationAuditEndpoint.test.js`，`npm test` 225→**246 pass**（既有 225 一字未改）、`npm run check` 綠；無新增環境變數。待 dev DB 實連驗證 INSERT。）

### CR-0038：Realtime 失敗訊息白話化（移除 UI 工程字眼）— ✅ 核准（2026-06-08 開立）
- 提出 agent：architecture-agent（Phase 3 production 升級 / 治理）
- 執行 owner：**realtime-voice-agent**（`lib/services/realtime_voice_service.dart` 唯一可主導修改者）
- 動機 / 問題：`RealtimeFailureTypeLabel.message` getter 回傳的失敗字串會經 `_recordFailure` → `_lastFailureMessage` → `_emit(RealtimeEventType.error, failure.message)`（行 ~350-351、228、886、1126）**顯示給長者**，目前內含工程字眼，違反 `pet_companion_app/CLAUDE.md §5.9`（UI 不得出現 SDP / ICE / DataChannel / token / .env / backend / session / WebRTC / Realtime）。違規字串：backendUnavailable（含「後端」「Realtime backend」）、missingApiKey（含「OpenAI API Key」「backend .env」）、sessionCreateFailed（「Realtime session」）、sdpExchangeFailed（「WebRTC SDP」）、peerConnectionFailed（「WebRTC peer connection」）、dataChannelFailed（「Realtime data channel」）、responseTimeout（「Realtime」）、unknown（「Realtime」）。microphonePermissionDenied 已屬白話可操作，維持。
- 現況查證（architecture-agent，read-only）：
  - 違規來源唯一集中在 `realtime_voice_service.dart` 行 22-37 的 `message` getter（enum 行 9-20）。
  - 這些字串確實面向使用者：`_emit(RealtimeEventType.error, failure.message)`（行 351）、`RealtimeFailureType.missingApiKey.message`（行 228）、`RealtimeFailureType.dataChannelFailed.message`（行 1126）皆把 getter 結果當對外 error 訊息傳出。
  - **既有測試硬編字串需同步更新**：`test/voice_agent_controller_realtime_lifecycle_test.dart:70` 斷言 `expect(harness.petController.message, 'WebRTC SDP 交換失敗。')`（精確字串），改字串必同步改此斷言。
  - 另注意（**不在本 CR 範圍，列為觀察**）：同檔 `lifecycle_test.dart:128/139` 的 `RealtimeHealthStatus.unavailable('後端未啟動')` + `expect(... contains('後端'))` 屬**測試注入的 health status fixture**，非 `message` getter；行 795 `'Realtime API 發生錯誤'` 屬 server error event 透傳字串。二者本 CR 不動；若日後確認其會直接顯示給長者，另開 follow-up（見 FU 備註）。
- 影響範圍（檔案）：
  - 改 `lib/services/realtime_voice_service.dart`（**僅** `message` getter 行 25-35 的回傳字串）。
  - 改 `test/voice_agent_controller_realtime_lifecycle_test.dart`（行 70 斷言對齊新字串；如有其他斷言到舊字串一併更新）。
- 觸及 🔒？：**是**（`realtime_voice_service.dart` 為 🔒 Realtime 主流程檔）。本 CR 僅改使用者可見字串常數，不碰連線流程／契約。
- 牽涉哪些 agent：realtime-voice-agent（唯一實作者）；architecture-agent（審查）。frontend / backend / companion-memory 不需動。
- 風險等級：**low**（純字串常數替換，無行為、無狀態機、無契約、無 enum 變更；唯一回歸風險為硬編字串測試需同步）。
- 建議批次切分：**單批**（字串替換 + 同步測試斷言）。
- 放行範圍（realtime-voice-agent 可改）：
  - 僅 `RealtimeFailureTypeLabel.message` getter 內各 case 的「回傳字串」。
  - 同步 `test/voice_agent_controller_realtime_lifecycle_test.dart` 對舊字串的精確斷言（建議改為新字串精確比對，或對中性詞 `contains('連線')` 之類，由 agent 擇一，但須真實對齊新值）。
- 紅線（違反即退回）：
  - **不得**改 `RealtimeFailureType` enum 成員（名稱、數量、順序）。
  - **不得**改任何 WebRTC / SDP / ICE / peer connection / data channel 連線流程、`connect()`／重連邏輯、語音狀態機（idle/listening/thinking/speaking/error/reconnecting）、event parser、`_emit`／`_recordFailure` 的呼叫結構與對外事件型別。
  - **不得**改對外行為（回傳值型別、event type、failure type 對映關係不變）。
  - 內部 `_log` / `debugPrint` / `toString()`（行 47、795-799、1108-1109）含技術細節**可保留**（不顯示給長者者不在此限）。
  - 不碰 `.env`／token；不寫入 runtime `data/*.json`；不 commit／push（除非另行指示）。
  - 新字串須長者友善、溫暖、零工程字眼（不得出現 SDP/ICE/DataChannel/token/.env/backend/後端/session/WebRTC/Realtime/API Key 等）。
- 建議白話版本（realtime-voice-agent 可微調語氣，但須符合上述紅線）：
  - backendUnavailable → 「現在連不上線，我們正在幫你重新連接，請稍等一下。」
  - missingApiKey → 「語音服務暫時還沒準備好，請稍後再試一次。」
  - sessionCreateFailed / sdpExchangeFailed / peerConnectionFailed / dataChannelFailed → 統一「連線不太穩，正在幫你重新連接。」
  - responseTimeout → 「剛剛沒聽清楚，我回到聆聽狀態了，請再說一次好嗎？」
  - unknown → 「連線出了點小狀況，我們正在處理，請稍候再試。」
  - microphonePermissionDenied → 維持白話可操作；可選軟化為「我聽不到你的聲音耶，請到手機設定打開麥克風權限，這樣才聽得到你說話喔。」
- 測試計畫：更新並執行 `flutter test test/voice_agent_controller_realtime_lifecycle_test.dart`（含行 70 斷言）＋ 既有 Realtime 套件（`realtime_voice_service_test.dart` 等）回歸；`flutter analyze` 須 0 issue；全量 `flutter test` 維持全綠（基線 476）。如改字串致其他斷言失敗，須一併對齊（不得為過測刪測）。
- architecture-agent 裁決：**✅ 核准（單批字串替換）**。理由：違規明確且來源單一、僅改使用者可見字串常數、不觸連線主流程／契約／enum／狀態機，風險 low、可獨立 `git revert`；唯一前置條件為同步硬編字串測試斷言。
- 完成狀態：⬜ 未開始（待 realtime-voice-agent 實作）

---

## CR-0033 — Production Audit

### Goal
Audit the entire project for production-readiness risks before converting the graduation-project demo into a formal App Store / Google Play ready system.

### Summary
- 純稽核 + 文件 CR，**無任何程式碼 / schema 改動**。
- 反映現況（已計入 CR-0036/0037/0038、CR-P2A/P2B 既有修補，未重複列為未修）。
- 全量測試維持全綠：flutter analyze 0 issue、flutter test 476 pass、backend npm run check 0、npm test 246 pass、caregiver_web 51 pass。
- 整體結論：**尚非 production ready**。Realtime / 陪伴 / 情緒分級 / 醫療安全用語 / 長者友善 UI / consent gate 品質佳；阻斷集中在「照護端授權邊界」與「正式環境隔離」。

### Key Findings
- P0（4）：
  - P0-1 多數 admin / elder 讀取 API 未驗證（住民情緒/生理/健康/遊戲指標外洩）。
  - P0-2 Care Alert API 無驗證、無住民-照護者授權邊界（可讀全部 alert、改狀態、觸發 Telegram）。
  - P0-3 後端 auth mock 模式預設開啟（Firebase 未設或 AUTH_ALLOW_MOCK!=='false' → 採信前端 firebaseUid）。
  - P0-4 缺正式環境 fail-fast / build flavor，缺 env 時靜默降級 JSON fallback / mock auth。
- P1（7）：CORS 預設 allow-all；單一共享 ADMIN_API_TOKEN 無 RBAC；Telegram 單一 chat 非授權推導；JSON fallback 仍為正式降級/唯一來源（marketplace、dailyCareTask 為 JSON-only）；iOS ATS 全關 + 預設 http localhost；caregiver_web token 存 localStorage 無正式登入；長者端顯示 "Mock STT" 工程字眼。
- P2（6）：§3.3 多核心表缺 migration；demo/mock 種子資料進版控；Android applicationId/label 未正式化；memoryExtractor log 印 stack/input；Flutter mock service 未 flavor 隔離；mockFallback 仍存（已收斂至 Demo 路徑）。
- P3（6）：pubspec description 含 "demo"；iOS 品牌名未定案；debugPrint 散布；Demo/Dev flag 預設安全；demo 文件待正式化；realtime 內部 log 含技術字（非使用者可見）。

### Files Created / Updated
- docs/PRODUCTION_AUDIT_CR0033.md（新建，完整稽核報告）
- docs/CHANGE_REVIEW.md（本區段）

### Tests / Commands Run
- flutter analyze → No issues found
- flutter test → All tests passed (476)
- backend `npm run check` → EXIT 0
- backend `npm test` → 246 pass / 0 fail
- caregiver_web `node --test *.test.js` → 51 pass / 0 fail
- 未跑：backend lint（無 script）、flutter release build（RC 前再驗證）

### Production Blockers Identified
- 照護端 / Care Alert API 未授權與無住民授權邊界（P0-1, P0-2）。
- Auth mock 預設開啟（P0-3）。
- 缺正式環境 fail-fast 與 dev 路徑隔離（P0-4）。

### Recommended Next CR
CR-0034 — Production Environment and Config


---

## CR-0034 — Production Environment & Config（治理規劃與裁決）

> 類型：Governance / 架構守門人裁決（**本區段不改業務程式碼**；僅更新 `PROJECT_ARCHITECTURE.md` §5.3.1 / §7.1 與本檔）。
> 目標：把 CR-0033 稽核 P0-3（auth mock 預設開）、P0-4（無 fail-fast、缺 env 靜默降級）轉成可交付 backend-agent / frontend-ux-agent 的精確實作規格與批次。

### 影響範圍 / Owner / 🔒 / 風險

| 範圍 | Owner agent | 觸 🔒？ | 風險 |
|---|---|---|---|
| 後端集中 config + fail-fast + masked log | backend-agent | 是（server.js 啟動段） | medium |
| 後端 JSON-fallback / mock guard（含 mockAllowed production=false） | backend-agent | 是（auth 行為 + server.js /notify 順序） | high |
| Flutter EnvironmentConfig / AppConfig / dev-panel·mock guard | frontend-ux-agent | 否（不得碰 `realtime_voice_service.dart` 主流程） | low-medium |
| caregiver_web API base URL config | frontend-ux-agent | 否 | low |
| docs（.env.example / ENVIRONMENT_SETUP / PRODUCTION_CONFIG_CHECKLIST） | backend-agent | 否（`.env.example` 不得含真值） | low |

### 裁決一：環境與 flag 治理
統一 `development / staging / production`。flag 對應表與相容收斂規則見 `PROJECT_ARCHITECTURE.md §7.1`。重點：舊命名（`AUTH_ALLOW_MOCK` / `ALLOWED_ORIGINS` / `BACKEND_BASE_URL`）保留為可讀別名，由新模組 `backend/stt_proxy/config/env.js` 統一映射；不一次大破壞。`NODE_ENV=test` 永不解析為 production。

### 裁決二：Backend fail-fast 規格
集中於新模組 `config/env.js`：純函式 `validateProductionEnv(env)→{ok,missing[]}`（可單測）+ `assertProductionEnvOrExit()`（缺→印安全訊息+`process.exit(1)`）。呼叫點在 `server.js` `dotenv.config()` 後、掛路由前，**非 production / `NODE_ENV=test` 一律 no-op**。production 必檢 `DATABASE_URL` / `OPENAI_API_KEY` / `CORS_ALLOWED_ORIGINS` / Firebase 服務帳戶 / `ADMIN_API_TOKEN`；條件必檢 `TELEGRAM_BOT_TOKEN` / `PGVECTOR_ENABLED`；`SESSION_SECRET|JWT_SECRET` 待 CR-0038 納入。production + `ALLOW_JSON_FALLBACK=true` / `ALLOW_MOCK_SERVICES=true` / `REQUIRE_AUTH=false` / CORS 空 → 拒絕啟動。**只列缺哪些變數名稱、絕不印值**；提供 mask helper。詳見 `PROJECT_ARCHITECTURE.md §7.1.1`。

### 裁決三：JSON fallback 在 production 的政策（關鍵，依環境分流）
完整裁決見 `PROJECT_ARCHITECTURE.md §5.3.1`。摘要：
- **care alert**：dev/staging 維持 DB-優先 + JSON fallback（零變更）；production（`ALLOW_JSON_FALLBACK=false`）改 **DB-required** — DB 例外時 `saveAlert` 回 `{success:false,error:'care_alert_persist_failed'}`（清楚錯誤、不丟例外、不寫 JSON 當權威），且 `/notify` 必須**解耦通知與持久化**：high/urgent 通知照送、持久化失敗以 `notification_logs` 明確記一列，**絕不靜默漏通知、絕不假成功、不改 /notify request/response 形狀**。
- **auth / memory / consent / search**：production DB-required，缺 `DATABASE_URL` 由啟動層擋；runtime DB 例外回清楚錯誤，不降級 JSON 當權威。
- **marketplace / dailyCareTask（JSON-only）**：production 以清楚 guard 阻擋（長者友善訊息），列為 **CR-0042 blocker**；屬已知且已文件化限制，需產品確認接受。

### 裁決四：批次切分（逐批可驗證）

- **B1（backend，🔒 server.js 啟動）**：新增 `config/env.js`（`APP_ENV` 正規化 / `isProduction` / boolean 安全解析 / `validateProductionEnv` / `assertProductionEnvOrExit` / mask helper）+ 接入 server.js 啟動段 + 單測。**先做這批**。
- **B2（backend，🔒 auth 行為 + /notify 順序）**：`mockAllowed()` production 強制 false（修 P0-3）；`ALLOW_JSON_FALLBACK` 接入 careAlert（production DB-required + /notify 解耦）/ auth / memory / consent / search；marketplace / dailyCareTask production guard；補測試。
- **B3（frontend-ux）**：Flutter `EnvironmentConfig`/`AppConfig` 加 `APP_ENV` / `API_BASE_URL` / `ALLOW_MOCK_SERVICES`；production 強制 `SHOW_DEV_PANELS`/`SHOW_DEMO_LOGIN`=false、`API_BASE_URL` 為 localhost/空時阻擋進正式主流程；mock service 注入改 guard；移除給長者看的 "Mock" 字樣（與 CR-0039/0040 協調，不重工）。**不得碰 `realtime_voice_service.dart` 主流程**。
- **B4（frontend-ux）**：caregiver_web API base URL 改可配置、移除 `http://127.0.0.1:3001/api` 作為 production 預設、production 不顯示 debug UI。
- **B5（backend / docs）**：`.env.example` 分區補齊（只列名稱、不放真值）、`docs/ENVIRONMENT_SETUP.md`、`docs/PRODUCTION_CONFIG_CHECKLIST.md`。

### 🔒 核准裁決（架構守門人）
- **B1 server.js 啟動段插入 fail-fast**：**核准（附條件）** — 僅啟動層、掛路由前；`NODE_ENV=test` / 非 production no-op；不得改任何路由 request/response；不得印 secret 值。
- **B2 `mockAllowed()` production=false**：**核准** — `createSession` 對外契約不變；dev/test 行為不變；僅 production 收斂為強制驗證（修 P0-3）。
- **B2 careAlert production DB-required + /notify 解耦**：**核准（附條件）** — 不得改 `/notify` request/response 形狀；不得讓 high/urgent 通知靜默漏掉；持久化失敗須 loud error + `notification_logs`，不得 JSON 假成功。
- **B3 / B4 / B5**：**非 🔒，可直接執行**（B3 紅線：不得觸碰 Realtime 主流程；caregiver_web 屬 frontend-ux）。

### 紅線（本 CR 全程）
不碰 `.env`；不寫死 secret；不移除 Realtime 主流程 / Care Alert / 長期記憶；production 缺設定**不可自動切 mock / JSON**；不為過測試硬編假資料；**不改既有路由 request/response 形狀**（fail-fast 是啟動層、非 API 契約）；不破壞既有測試基線（flutter 476 / backend 246 / caregiver_web 51）。

### 建議先做
**B1**。第一步：建立 `backend/stt_proxy/config/env.js`，先實作純函式（`resolveAppEnv` / boolean 安全解析 / `validateProductionEnv→{ok,missing[]}` / `maskSecret`）與其單測，**暫不接入 server.js**（確保 246 測試全綠），再以 no-op-on-test 的 `assertProductionEnvOrExit()` 接入 server.js 啟動段。

### 各批第一步（交付 owner）
- B1 → 建 `config/env.js` 純函式 + 單測（backend-agent）。
- B2 → 先改 `sessionService.mockAllowed()` 讀 `config.isProduction`（backend-agent），單測 production=false。
- B3 → 建 `lib/config/environment_config.dart`（或擴充 `AppConfig`）加 `APP_ENV`/`API_BASE_URL`/`ALLOW_MOCK_SERVICES`（frontend-ux-agent）。
- B4 → caregiver_web 抽出 `API_BASE` 設定來源、移除 localhost production 預設（frontend-ux-agent）。
- B5 → 起草 `.env.example` 分區骨架（只列名稱）（backend-agent）。

### Files Updated（本治理 CR）
- `PROJECT_ARCHITECTURE.md`（新增 §5.3.1 production JSON fallback 政策、§7.1 環境/flag 治理 + §7.1.1 fail-fast 規格）
- `docs/CHANGE_REVIEW.md`（本區段）
- **無任何程式碼 / schema 改動。**

### 測試
本治理 CR 未改程式，未跑測試。基線維持 CR-0033：flutter 476 / backend 246 / caregiver_web 51。B1-B5 落地時各自補測並回報實跑結果。

---

### CR-0034 B3 實作落地（frontend-ux，Flutter）

集中正式環境設定於 `lib/config/app_config.dart`（沿用既有 `AppConfig` 命名，不另開模組）：

- 新增 compile-time（`--dart-define`）：`APP_ENV`（預設 development）/ `API_BASE_URL`（收斂 `BACKEND_BASE_URL` 為可讀別名，預設 localhost）/ `ALLOW_MOCK_SERVICES`（預設 false）。
- 新增 getter：`isProduction`、`apiBaseUrl`（= `backendBaseUrl`）、`mockServicesEnabled`（production 一律 false）、`devPanelsVisible`（= `showDevPanels && !isProduction`）、`demoLoginVisible`（= `showDemoLoginButton && !isProduction`）、`isApiBaseUrlProductionSafe`（production 但 base URL 為 localhost / 空 → false）。
- 原始 const（`showDevPanels` / `showDemoLoginButton` / `backendBaseUrl`）保留，維持既有測試與相容。

production 行為保證：

- `MaterialApp.debugShowCheckedModeBanner` 維持 false（確認，未改）。
- 開發面板（`settings_screen.dart`）改讀 `AppConfig.devPanelsVisible` → production 強制不顯示。
- Demo 登入（`login_screen.dart`）改讀 `AppConfig.demoLoginVisible` → production 強制隱藏。
- mock service 注入改 guard：未使用的 `MockShopService` 改 `if (AppConfig.mockServicesEnabled)` 注入；production 不注入。`MockAiService` / `MockSpeechToTextService` 為 `AiToolRouter` / `ConversationController` 建構子結構性後援依賴，維持注入（不改契約），正式互動走 Realtime + 正式 STT proxy；其後援文案「Mock」工程字樣移除屬 CR-0039。
- API base URL 一律由 `AppConfig` 取得，UI 頁面不硬編。
- production 但 API base URL 仍指向本機 / 空 → `home` 改顯示長者友善 `_ServiceUnavailableView`，AppRoot 不掛載、不觸發正式主流程載入。

未碰 `lib/services/realtime_voice_service.dart`、未改後端、未改 auth 契約。

測試：新增 `test/config/app_config_test.dart`（依 `isProduction` 分流斷言）。
- `flutter analyze` → No issues found。
- `flutter test` → 483 passed（476 基線 + 7 新增）。
- `flutter test test/config/app_config_test.dart --dart-define=APP_ENV=production --dart-define=SHOW_DEV_PANELS=true --dart-define=SHOW_DEMO_LOGIN=true --dart-define=ALLOW_MOCK_SERVICES=true --dart-define=API_BASE_URL=http://127.0.0.1:3001` → 7 passed（證明 production 強制關閉所有開發 / mock 旗標，且 localhost 觸發守門）。
- 同檔 `--dart-define=APP_ENV=production --dart-define=API_BASE_URL=https://api.example.com` → 7 passed（正式網域放行）。

