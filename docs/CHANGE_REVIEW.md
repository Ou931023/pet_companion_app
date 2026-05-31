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

<!-- 新提案請往下加 CR-0004 ... -->
