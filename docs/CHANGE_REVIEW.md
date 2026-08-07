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

### CR-0101A：App Store Readiness Foundation — 登入與 production 入口收斂 — ✅ 完成（2026-08-07）
- 提出 agent：architecture-agent / frontend-ux-agent
- 日期：2026-08-07
- 動機 / 問題：正式送審前，登入頁不得出現未完成的 Apple placeholder；若 Google 第三方登入可見，App Store 也會要求 Sign in with Apple。另 CR-0096S 後仍有幾個 production 例外旗標可顯式開啟 demo / marketplace / daily-care 入口，與 Store checklist「production 完全隱藏」不一致。
- 影響範圍（檔案）：`lib/config/app_config.dart`、`lib/screens/login_screen.dart`、`lib/screens/register_screen.dart`、`test/config/app_config_test.dart`、`test/screens/login_screen_test.dart`、`test/screens/register_screen_test.dart`、`docs/RELEASE_BUILD_SIGNING_CHECK.md`、`docs/APP_STORE_METADATA.md`、`docs/STORE_RELEASE_CHECKLIST.md`、`docs/PRODUCTION_CONFIG_CHECKLIST.md`。
- 觸及 🔒？：否（未改 API 契約、DB schema、Realtime 主流程或依賴；僅 Flutter 上架入口 gating、文案與文件）。
- 牽涉哪些 agent：architecture-agent（上架風險 / 文件）、frontend-ux-agent（登入 / 註冊 UI）。
- 風險等級：medium-low（正式版隱藏未完成入口；dev/test 仍保留 Google / Apple UI 測試能力。若產品決定正式啟用 Google，必須先完成 Apple Sign in 並另開 CR）。
- 變更摘要：
  - production 強制隱藏 Demo 登入、marketplace、daily-care，不再提供 `ALLOW_*_IN_PROD` 例外路徑。
  - 新增 `AppConfig.socialSignInVisible`：Apple Sign in 完成前，production 隱藏 Google / Apple 第三方登入入口，只保留 Email login / register。
  - 註冊頁移除「想用 Google 或 Apple」誤導文案。
  - 設定頁補支援說明；正式 `SUPPORT_URL` / `CONTACT_EMAIL` 有注入時才顯示外部聯絡按鈕，未注入時不露 TODO。
  - 刪除帳號確認文案補清楚：會刪除伺服器帳號資料與本機寵物 / 記憶 / 提醒 / 使用紀錄。
  - release build 文件改為真正送審用 dart-define，不再把展示用 Render URL 或入口例外旗標列為 canonical。
- 測試計畫：`dart format`；`flutter test test/config/app_config_test.dart test/screens/login_screen_test.dart test/screens/register_screen_test.dart test/home_screen_layout_test.dart`；production dart-define 反向測試；`flutter analyze`；`flutter test`。
- architecture-agent 裁決：✅ 核准
- 完成狀態：✅ 完成

### CR-0097 Addendum：Usage Tracking 隱私揭露補強 — ✅ 完成（2026-08-07）
- 提出 agent：architecture-agent / frontend-ux-agent
- 日期：2026-08-07
- 動機 / 問題：CR-0097 已新增 `app_usage_events` 與管理者 / 照護者使用統計，但正式上架前必須讓同意畫面、App 內隱私政策、Google Play Data Safety 與 App Store Privacy 申報基礎一致，避免「後台有收數據、商店/政策未揭露」。
- 影響範圍（檔案）：`lib/config/legal_content.dart`、`lib/config/legal_config.dart`、`test/consent_gate_test.dart`、`docs/GOOGLE_PLAY_DATA_SAFETY.md`、`docs/STORE_RELEASE_CHECKLIST.md`、`docs/APP_STORE_METADATA.md`、`docs/PRODUCTION_CONFIG_CHECKLIST.md`。
- 觸及 🔒？：否（未改 API 契約、DB schema、Realtime 主流程或依賴；僅 App 內法遵文案版本與 release 文件）。
- 牽涉哪些 agent：architecture-agent（上架風險 / 文件）、frontend-ux-agent（同意畫面文案）。
- 風險等級：low（文案與測試補強；`LegalConfig.consentVersion` 更新會要求舊版同意者重新同意，屬隱私變更必要行為）。
- 測試計畫：`flutter test test/consent_gate_test.dart test/config/legal_config_test.dart`；`flutter analyze`。
- architecture-agent 裁決：✅ 核准
- 完成狀態：✅ 完成

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

---

### CR-0034 B2 實作落地（backend，🔒 auth 行為 + /notify 順序）

以 B1 `config/env.js` 為單一 env 語義來源，把 production 不允許的降級 / mock 路徑加 guard，並修稽核 P0-3。**未改任何路由 request/response 形狀**（guard 屬行為層）。

新增 `config/env.js` helper：`isJsonFallbackAllowed(env)`（非 production 一律 true；production 預設 false，僅顯式 `ALLOW_JSON_FALLBACK=true` 才 true，但該值在 production 會被 `validateProductionEnv` fail-fast 擋下）、`FeatureUnavailableInProductionError` / `FEATURE_UNAVAILABLE_IN_PRODUCTION`、`describeMaskedConfig(env)`（啟動摘要，一律走 mask helper）。

1. **P0-3 修補**：`sessionService.mockAllowed(env)` 改先判 `isProduction` → **production 一律 false**（不採信 client `firebaseUid`，必須真正驗 `idToken`）；非 production 維持 `AUTH_ALLOW_MOCK` 預設 true。`createSession` 對外契約不變。

2. **care alert production DB-required（§5.3.1）**：`saveAlert` / `updateAlertStatus` 在 `isJsonFallbackAllowed=false`（production）時，DB 例外或 DB 不可用 **不降級寫 JSON**，回 `{success:false,error:'care_alert_persist_failed'}`（不丟例外、不回 stack）。dev/staging（含 `NODE_ENV=test`）維持 DB-優先 + JSON fallback，**零變更**。

3. **`/notify` 解耦通知與持久化（不改契約）**：作法是「持久化與通知本就是 endpoint 內前後兩段、通知段不依賴持久化結果」，再補一條 **旁路 side-bus 稽核**——持久化失敗時 fire-and-forget 寫一列 `notification_logs`（`channel='care_alert_store'`、`outcome='persist_failed'`、`error_code=持久化錯誤碼`、`alert_id=null`），high/urgent 通知仍照送、Telegram 結局照常各記一列（`sent`/`failed`/`skipped_*`）。response body 與 status 與既有完全一致（成功仍回 Telegram 結果物件），故 **不改 request/response 形狀**。

4. **marketplace / dailyCareTask（JSON-only）production guard（CR-0042 blocker）**：production 一律阻擋——回 envelope 的函式回 `{ok/success:false,error:'feature_unavailable_in_production'}`；回值（陣列 / 物件 / task）的 read 函式拋 `FeatureUnavailableInProductionError`（由各 route 既有 try/catch 轉成既有錯誤回應，不外洩 stack）；`seedDefaultProducts` production no-op。dev/staging 不受影響。屬已知且文件化限制，需產品確認接受。

5. **mask 接入**：盤點現有 `console.*`——`db/postgres.js` / `firebaseAdmin.js` / `telegramNotifyService.js` 既有 log 僅印 `error.message`，本就未輸出 token/secret/DATABASE_URL/email（已驗證）。新增啟動摘要 log（`require.main` 段）`describeMaskedConfig(process.env)`：DATABASE_URL→`maskDatabaseUrl`、OPENAI/TELEGRAM token / ADMIN_API_TOKEN→`maskSecret`、FIREBASE_CLIENT_EMAIL→`maskEmail`、chat id 僅回 `(set)/(unset)`，**絕不輸出完整值**。

**修改檔案**：`config/env.js`、`services/auth/sessionService.js`、`services/careAlertStoreService.js`、`services/marketplace/marketplaceStore.js`、`services/dailyCareTask/dailyCareTaskStore.js`、`server.js`（`/notify` 旁路稽核 + 啟動 masked 摘要，未動路由形狀）、`package.json`（新增 dailyCareTask store 測試與 check）。

**測試**：`cd backend/stt_proxy && npm test` → **289 passed / 0 fail**（263 基線 + 既有 dailyCareTask store 11 條納入執行 + 新增 env/auth/careAlert-db/marketplace/notify 共約 15 條）。`npm run check` 全綠。既有測試斷言一字未改（僅在既有測試檔擴充 import 名單與新增 test，未動原斷言）。production 行為以 `options.env={APP_ENV:'production'}` 注入驗證（`NODE_ENV=test` 恆為 dev，基線不受影響）。

---

### CR-0034 B4 實作落地（frontend-ux，caregiver_web）

caregiver_web API base URL 改為可配置、移除 localhost production 預設：

- `app.js getApiBase` 解析順序：頁面「連線設定」手動輸入（localStorage，dev / 區網）→
  `window.APP_CONFIG.apiBaseUrl`（部署注入）→ 同源相對路徑 `/api`（`DEFAULT_API_BASE`，**無 localhost 硬編**）。
- 新增 `config.example.js`（部署範本，複製為 `config.js` 注入正式後端位址；`config.js` 不進版控）。
- production 不顯示 debug UI。

**修改檔案**：`caregiver_web/app.js`、`caregiver_web/config.example.js`、`caregiver_web/index.html`、`caregiver_web/config_api_base.test.js`。

---

### CR-0034 B5 實作落地（backend / docs，純文件）

收尾批次，**只改文件、不動任何程式碼 / schema**。依 CR-0034 §四批次切分產出三份環境設定文件，所有檔案只列變數名稱與用途、**未放任何真實 secret**。

- `backend/stt_proxy/.env.example`：依分區重整為 Environment / Server / Database / OpenAI·Realtime·Memory·Search / Auth·Session / Telegram / Admin / Privacy·Store Links / Development-only Flags，每個變數一行用途註解，值留空或佔位。變數名稱一律對齊 `config/env.js` 與後端實際讀取者；治理表 §7.1 中後端尚未全面接入者（`REQUIRE_CONSENT` / `ENABLE_VERBOSE_LOGS`）已明註，未捏造不存在的變數。Privacy 連結明記由 Flutter `LegalConfig` 管理、非後端 env。
- `docs/ENVIRONMENT_SETUP.md`（新建）：development / staging / production 三端（backend / Flutter / caregiver_web）啟動步驟、Flutter production build dart-define 範例、backend production fail-fast 行為與訊息範例、caregiver_web production config、production 不允許旗標、常見錯誤與排查表。
- `docs/PRODUCTION_CONFIG_CHECKLIST.md`（新建）：env / flag 對照表（引用 §7.1）、production 必要 env、fail-fast 驗收、不安全旗標、JSON fallback 政策（§5.3.1，含 marketplace / dailyCareTask 為 **CR-0042 blocker**）、Flutter build define、caregiver_web APP_CONFIG、待辦（LegalConfig 4 個 hosted URL/email、migrations 010/011/012 實跑、iOS/Android 上架身份正式化）。

**修改檔案**：`backend/stt_proxy/.env.example`、`docs/ENVIRONMENT_SETUP.md`（新）、`docs/PRODUCTION_CONFIG_CHECKLIST.md`（新）、`docs/CHANGE_REVIEW.md`（本區段）。

**測試**：純文件未跑程式測試。`config/env.js` 未動，後端測試基線不受影響。

---

### CR-0034 收尾狀態（B1–B5）

| 批次 | 範圍 | 狀態 |
|---|---|---|
| B1 | backend `config/env.js`（fail-fast / mask helper）+ server.js 啟動段接入 + 單測 | ✅ shipped |
| B2 | backend mock/JSON-fallback guard（`mockAllowed` production=false、careAlert DB-required + `/notify` 解耦、marketplace/dailyCareTask production guard） | ✅ shipped |
| B3 | Flutter `AppConfig`（`APP_ENV`/`API_BASE_URL`/`ALLOW_MOCK_SERVICES` + production 守門） | ✅ shipped |
| B4 | caregiver_web API base URL 可配置、移除 localhost production 預設 | ✅ shipped |
| B5 | docs（`.env.example` 分區 / `ENVIRONMENT_SETUP.md` / `PRODUCTION_CONFIG_CHECKLIST.md`） | ✅ shipped |

**CR-0042 blocker 登錄確認**：marketplace / dailyCareTask（JSON-only）在 production 由 guard 阻擋、無持久化保證，須待 PG 化（CR-0042）才能於 production 提供；已記於 §5.3.1、B2 落地說明、`PRODUCTION_CONFIG_CHECKLIST.md` §5 與 §8。屬已知且文件化限制，需產品確認接受。

---

### CR-0039 — Backend Authorization Boundary Part 1（Audit CR0033 §12 #2；原規劃代號「CR-0035」）
- 提出 agent：architecture-agent（依使用者指派 + Audit CR0033 §12 第 2 項）
- 日期：2026-06-08
- 完成狀態：✅ 完成（Batch 1/2/3 已落地、測試全綠、architecture-agent 已驗收，2026-06-08）

#### 0. 編號治理註記（重要）
- 使用者 / 稽核 §12 把本案稱為「CR-0035 後端授權邊界 Part 1」，但帳本中 **CR-0035 已被佔用**（2026-06-03「搜尋來源政策」，本檔行 941）。稽核 §12 的整段規劃編號（CR-0034…CR-0047）與既有 live CR（CR-0035 搜尋、CR-0036 consent、CR-0037 mockFallback、CR-0038 Realtime）**全面撞號**；稽核報告自身的開頭（把 CR-0036/0037/0038 列為「已完成」）與 §12（把 0036/0038 重新指派為新工作）也互相矛盾。
- 裁決：本案帳本正規 ID = **CR-0039**（帳本下一個空號），標題保留稽核別名以利追溯。§12 後續項目一律改用「下一個空號」分配，不再沿用 §12 字面編號。對照如下（避免再撞號）：
  - §12 #2 後端授權邊界 Part 1 → **CR-0039**（本案）
  - §12 #3 resident_caregiver_links + 授權範圍過濾 → 之後開 CR-0040
  - §12 #4 production Firebase auth 強制（AUTH_ALLOW_MOCK=false fail-fast）→ 之後開 CR-0041
  - （其餘 §12 項目於開立時依序取空號，並在該 CR 標註對應 §12 編號）

#### 1. 動機 / 問題
- 修補 Audit CR0033 的 **P0-1**（admin 讀取 API 多數未掛 `requireAdmin`，任何能連到後端者可讀住民情緒 / 生理 / 健康 / 遊戲指標）與 **P0-2 的「擋門」層**（Care Alert 讀取 / 狀態變更未驗證）。
- 本案只做 **authentication（擋門）**：要求合法 admin 憑證才能到達上述讀取 / 管理路由。**不做** per-resident 授權範圍過濾（需 `resident_caregiver_links`，該表不存在＝P2-1）。

#### 2. 擋門 vs 授權範圍過濾 — 邊界裁決
- ✅ **CR-0039（本案）= authentication 擋門**：對既有未保護的 admin 讀取路由與 Care Alert 讀取 / 管理路由掛上**既有** `requireAdmin`（與 `/api/admin/users`、marketplace 一致）。
- ⏭ **授權範圍過濾（依授權住民過濾 alert / elder 資料）= 另開 CR-0040**（Audit §12 #3），需先建 `resident_caregiver_links` schema。本案完成後，所有持 `ADMIN_API_TOKEN` 者仍可見全部住民（這是已知殘留風險，由 CR-0040 收斂；與稽核 P1-2「無 RBAC / 無住民 scope」一致）。
- 理由：使用者任務 #3「檢查住民與照護人員授權關係」依賴尚不存在的關聯表；硬塞進本案會把「小批次擋門」變成「大改 + schema 變更」，違反最小可控修改。明確分界可獨立驗證、獨立回滾。

#### 3. `/api/care-alerts/notify` 裁決 —— 採「選項 B」（本案不擋 /notify caller，列為明確 blocker follow-up）
- 現況（已覆核）：`POST /api/care-alerts/notify`（server.js:384）是**長者端 App 建立 Care Alert + 觸發 Telegram 的核心路徑**；caller `lib/services/care_alert_notification_service.dart:36-50` 為 fire-and-forget，**只帶 `Content-Type`、不帶任何 auth**。這不是 admin 動作。
- 裁決：**本案不對 /notify 掛任何驗證**。理由：
  1. 紅線「不得擋掉長者端 Care Alert 建立流程」。掛 `requireAdmin` 會直接打斷長者端（且長者端永遠不該持有 admin token）。
  2. 選項 A（改長者 Firebase session 驗證）是**正確的最終狀態**，但牽涉：(a) 長者端要把 session token 接進 fire-and-forget 的 notify 呼叫；(b) 依賴 production Firebase auth 強制（CR-0041 / Audit §12 #4）才有可信 session 可驗；(c) fire-and-forget 不可因驗證失敗而靜默漏報高風險 alert。這是跨前後端、體量大於「擋門 Part 1」的改動，應於 **auth 強化（CR-0041）之後**獨立成 CR。
- **殘留風險（誠實記錄，blocker）**：/notify 在本案後仍可被未驗證端 POST → 可偽造 Care Alert + 觸發 Telegram（spam / 偽造警示）。現有緩解：`globalLimiter`（全域 rate limit）+ Care Alert cooldown + `invalid_payload` 形狀檢查；Telegram 僅 high/urgent 推播且有 cooldown。**正式上架前必須**以「選項 A：長者 session 驗證」收斂 → 開 **FU-CR：/notify caller 驗證（排程於 CR-0041 auth 強化之後，正式版 blocker）**。本案不視為已修 P0-2 全部，只修 P0-2 的「讀取 / 管理擋門」子集。

#### 4. 影響範圍（檔案 + 行號，已覆核）
- backend：`backend/stt_proxy/server.js`
  - admin 讀取路由（掛 `requireAdmin`）：`/api/admin/daily-care-tasks`(951)、`/api/admin/overview`(1006)、`/api/admin/elders`(1016)、`/api/admin/elders/:elderId`(1026)、`/api/admin/elders/:elderId/physio`(1039)、`/api/admin/elders/:elderId/emotion`(1052)、`/api/admin/elders/:elderId/game-metrics`(1065)。
  - Care Alert 讀取 / 管理路由（掛 `requireAdmin`）：`GET /api/care-alerts`(498)、`GET /api/care-alerts/:id`(514)、`PATCH /api/care-alerts/:id/status`(527)。
  - **不動**：`POST /api/care-alerts/notify`(384)（見 §3）。
  - 沿用既有中介層 `backend/stt_proxy/services/admin/requireAdmin.js`（不改其行為：無 token→401 `missing_admin_token`；token 不符 / 未設→403 `admin_permission_required`）。
- 測試：`backend/stt_proxy/__tests__/`（或既有 test 目錄）新增本案路由的權限測試。
- frontend：`caregiver_web/app.js`
  - care-alerts fetch 補 header：列表 `fetch(url)`(256) + `buildQuery`、詳情 `fetch(.../:id)`(285) → 補 `adminAuthHeaders()`；狀態 PATCH `fetch(.../:id/status,{...})`(408) → headers 由 `{ "Content-Type": ... }` 改為 `adminJsonHeaders()`。
  - admin-analytics fetch 補 `adminAuthHeaders()`：daily-care-tasks(912)、overview(937)、elders(962)、elders/:id(1044)。
  - 沿用既有 `adminAuthHeaders()`(668) / `adminJsonHeaders()`(1598) / `getAdminToken()`(663)，不新增 token 機制。
- 註：後端 `/elders/:id/physio|emotion|game-metrics`(1039/1052/1065) caregiver_web 目前未直接呼叫（走合併的 `/elders/:id`(1044)），但仍需掛驗證（defence-in-depth，這些路由獨立可達）。

#### 5. 觸及 🔒？
- 是。`server.js` 路由為 🔒（路由 / response 契約）。**但本案只加 middleware、不改任何成功路徑的 request/response 形狀**；新增的只有「未授權時的 401/403」錯誤回應（沿用 requireAdmin 既有格式 `{ ok:false, error }`）。需 architecture-agent 核准（本提案即核准）。
- 不觸及：Realtime / SDP / DataChannel、Memory schema、Care Alert 共用資料結構、`.env` / token 值、`db/migrate.js`、`pubspec.yaml` / `package.json`。

#### 6. 牽涉 agent
- backend-agent：server.js 掛 `requireAdmin` + 後端測試（B2、B3）。
- frontend-ux-agent：caregiver_web 補 auth header（B1）。
- 不牽涉 realtime-voice-agent、companion-memory-agent（Care Alert 建立邏輯 /notify 不動）。

#### 7. 風險等級：medium
- 跨前後端契約（401/403 新增）+ caregiver_web 一旦後端啟用驗證、未帶 header 會 401。需嚴格控制落地順序（見 §8）。
- 殘留：/notify 未擋（§3）、無住民 scope（§2）— 皆已明確轉後續 CR，非本案宣稱已修。

#### 8. 批次切分（順序重要：先前端帶 header，再後端啟用驗證，避免管理端 401 空窗）
- **Batch 1 — frontend-ux-agent（先做，向下相容、可獨立合併）**
  - 範圍：`caregiver_web/app.js` 為 care-alerts(256/285) 與 admin-analytics(912/937/962/1044) 的 GET fetch 補 `adminAuthHeaders()`；PATCH(408) 改用 `adminJsonHeaders()`。
  - 為何先做：對「尚未檢查 token 的路由」多帶一個 Authorization header 完全無害；先落地可消除後端啟用驗證後的破窗期。
  - 不得：改後端、改 token 取得方式、改 response 解析邏輯。
  - 驗證：`cd caregiver_web && node --test *.test.js`（既有 51 應維持綠；若新增 header 相關斷言則一併更新）。手動：帶正確 token 時各頁正常載入。
- **Batch 2 — backend-agent（admin 讀取路由擋門）**
  - 範圍：`server.js` 對 §4 列的 7 條 `/api/admin/*` 讀取路由插入既有 `requireAdmin`（與 `/api/admin/users`(1081) 同寫法）。不改成功路徑 response。
  - 驗證：新增測試 — 無 header→401 `missing_admin_token`；錯 token / 未設 `ADMIN_API_TOKEN`→403 `admin_permission_required`；正確 token→原 response 形狀不變。`cd backend/stt_proxy && npm run check && npm test`。
- **Batch 3 — backend-agent（Care Alert 讀取 / 管理擋門）**
  - 範圍：`server.js` 對 `GET /api/care-alerts`(498)、`GET /api/care-alerts/:id`(514)、`PATCH /api/care-alerts/:id/status`(527) 插入 `requireAdmin`。**明確不動 `POST /api/care-alerts/notify`(384)**（程式註解標明「長者端建立路徑，caller 驗證見 follow-up CR」）。
  - 驗證：新增測試 — 三條路由 401/403/通過；外加一條**回歸測試**：未帶 auth 的 `POST /notify` 仍維持既有行為（high/urgent→嘗試通知、low/medium→`skipped_low_risk`、形狀不變），確保長者端建立流程未被波及。`cd backend/stt_proxy && npm run check && npm test`。
- 批次相依：Batch 1 先合併；Batch 2 / Batch 3 可平行（皆 backend-agent，建議依序提交以利審查）。三批合併後才視為本 CR 完成。

#### 9. 測試計畫（彙整）
- backend（node --test）：每條受保護路由覆蓋 missing_token(401) / wrong_token(403) / valid_token(pass + 原 response 形狀)。/notify 未受影響回歸測試。
- caregiver_web（node --test DOM）：既有測試維持綠；fetch 帶 header 的單元斷言（可選）。
- 不需真 DB / 真金鑰（requireAdmin 純比對 env token；測試以注入 `ADMIN_API_TOKEN` 或測試替身）。**測試需要的環境變數：`ADMIN_API_TOKEN`（測試值，請手動設定，勿貼真實值）**。
- 全域回歸：`flutter analyze` / `flutter test` 不受本案影響（未改 Flutter；長者端 /notify caller 不動），可選跑確認 0 回歸。

#### 10. 紅線（落地時必守）
- 不得破壞 Realtime / Memory / Care Alert 既有**成功路徑契約**（只新增 401/403，不改 200 形狀）。
- 不得擋掉長者端 Care Alert 建立流程（`POST /notify` 不掛驗證）。
- 不碰 `.env` / token 值；沿用既有 `requireAdmin` 與既有 caregiver_web token 機制，不新增憑證來源。
- 不做 RBAC / 住民 scope / 正式 admin 登入（分別屬 CR-0040 / 後續），本案僅「擋門」。

#### 11. architecture-agent 裁決
- ✅ 核准（按 §8 批次與順序執行；Batch 1 先行）。
- 範圍鎖定為 authentication 擋門；/notify 採選項 B（caller 驗證轉 follow-up，正式版 blocker）；授權範圍過濾轉 CR-0040。
- 本案完成僅代表 P0-1 全修、P0-2 的「讀取 / 管理擋門」子集修復；P0-2 的 /notify caller 驗證與住民 scope 尚未關閉，需後續 CR，**不得對外宣稱 P0-2 已全數修復**。

#### 12. 落地與 checkpoint review（architecture-agent，2026-06-08）

**執行進度**
- ✅ Batch 1（frontend-ux-agent）：`caregiver_web/app.js` 為 care-alerts（loadAlerts GET `/care-alerts`、openDetail GET `/care-alerts/:id`、updateStatus PATCH `/care-alerts/:id/status` 由純 `Content-Type` 改 `adminJsonHeaders()`）與 admin-analytics（loadDailyTasks、loadHealthOverview、loadElderList、loadElderAnalysis 的 GET）補上既有 `adminAuthHeaders()` / `adminJsonHeaders()`。未新建 token 邏輯、未改 UI 文案。
- ✅ Batch 2（backend-agent）：`server.js` 對 7 條 admin 讀取路由（daily-care-tasks、overview、elders、elders/:id、elders/:id/physio|emotion|game-metrics）插入既有 `requireAdmin`。
- ✅ Batch 3（backend-agent）：`server.js` 對 `GET /api/care-alerts`、`GET /:id`、`PATCH /:id/status` 插入 `requireAdmin`。`POST /api/care-alerts/notify` 依 §3 選項 B 未掛驗證，僅加程式註解標明長者端建立路徑。

**驗收結果（architecture-agent 獨立覆驗，全綠）**
- backend：`cd backend/stt_proxy && npm test` → tests 296 / pass 296 / fail 0。（npm run check 由實作 agent 回報 OK）
- caregiver_web：`cd caregiver_web && node --test *.test.js` → tests 55 / pass 55 / fail 0。
- Flutter：本案 0 行 `lib/` 變更，長者端 /notify caller 未動 → 判定不受影響、未跑 `flutter test`（判斷合理）。
- 測試覆蓋確認：careAlertListEndpoint / careAlertStatusEndpoint / adminEndpoint / notificationAuditEndpoint / careAlertDemoFlow / dailyCareTaskEndpoint 皆補 admin header；新增 401(missing_admin_token) / 403(admin_permission_required) 擋門案例；demo flow 的 `postNotify` 全程不帶 admin header 仍 200 → 構成 /notify 無 auth 回歸保護。

**checkpoint 核對（read-only，git diff / grep 覆核）**
- (a) ✅ 只新增 401/403：server.js 各路由僅於 handler 前插入 `requireAdmin`，handler 函式體與成功 200 response 形狀完全未改。
- (b) ✅ /notify 確未掛驗證：diff 僅新增註解、無 middleware；測試以無 auth postNotify 證明長者端建立流程不受影響。
- (c) ✅ 未碰 `.env` / 真實 token：測試使用字面值 `test-admin-token`；`requireAdmin.js` 行為未改；未觸 Realtime / SDP / DataChannel、Memory schema、Care Alert 共用資料結構。
- (d) ✅ 未做住民 scope 過濾：無任何 resident scope 邏輯，依裁決保留至 CR-0040。

**殘留 / 觀察**
- daily-care-tasks 無「專屬」401/403 案例（door 覆蓋集中於 adminEndpoint 與 careAlert 測試），同一 `requireAdmin` 中介層；視為可接受的次要覆蓋缺口，非 blocker。
- /notify caller 驗證（選項 A）與住民 scope 仍為已知殘留風險，分別轉 FU-CR / CR-0040；本案不宣稱 P0-2 全修。

#### 13. architecture-agent 裁決（checkpoint）
- ✅ **核准並驗收（PASS）**。三批均符合 §8 範圍與 §10 紅線：只加擋門、不改成功契約、/notify 不擋、未碰 .env/token、未做住民 scope。CR-0039 標記為完成。

---

### CR-0040 — Resident-Caregiver Authorization Model（Audit CR0033 §12 #3；修 P0-2 scope 層 + P1-2 部分）
- 提出 / 裁決 agent：architecture-agent（依使用者指派 + Audit CR0033 §12 第 3 項，CR-0039 後續）
- 日期：2026-06-08
- 完成狀態：📋 已規劃 / 已裁決，待派工（Batch A/B/C 進本案；Batch D 拆後續 CR）

#### 0. 編號治理 / 對照
- 帳本正規 ID = **CR-0040**（沿用 CR-0039 §0 的「下一個空號」治理）。對應 Audit §12 #3「resident_caregiver_links + 授權範圍過濾」、P0-2 的「scope 層」子集、P1-2「無 RBAC / 已驗證端點無住民 scope」的**部分**修補。
- 後續依賴：caregiver 個別登入 = Audit §12 #5 → 之後開 **CR-00xx（caregiver web 正式登入）**；本案 Batch D 與「真 per-caregiver 強制」依賴它。

#### 1. 動機 / 問題
- CR-0039 已完成「擋門」（admin 讀取 + Care Alert 讀取/管理路由掛 `requireAdmin`），但**所有持 `ADMIN_API_TOKEN` 者仍可見全部住民**（CR-0039 §11 明列為已知殘留風險，轉本案）。
- 本案目標：建立正式版 **resident-caregiver authorization model**（schema + Authorization Service + 角色分界 + 路由 scope plumbing），讓「依授權住民過濾資料」成為**已存在且可測**的機制，並把共享 `ADMIN_API_TOKEN` 由「token 即全看」的意外行為，改為**明確的 `super_admin` 角色**（full scope）。

#### 2. 現況盤點（architecture-agent 已獨立覆核，與使用者盤點一致）
1. **無** residents / caregivers / resident_caregiver_links 任何表；migrations 只到 `012`，實體只有 `006_create_users_elders.sql` 的 **users + elders**。專案語彙為 **user / elder**，非 resident / caregiver。
2. 程式碼**無 caregiver 身分**：`grep caregiver_id|caregiverId|getAuthorizedResident|resident_caregiver` 在 backend 業務碼**無命中**（僅 `actorType:"caregiver"` 標籤與註解、稽核 log 字面值）。
3. CR-0039 後，admin + care-alert 讀取/管理路由全掛**單一共享 `ADMIN_API_TOKEN`**（`requireAdmin`，fail-closed Bearer，401 `missing_admin_token` / 403 `admin_permission_required`）。caregiver_web 僅在設定頁手動輸入此共享 token，**無每位 caregiver 個別身分/登入**（= §12 #5，排在本案之後）。
4. `services/admin/adminAnalysisService.js` 以 `elderId` 為 key（`getOverview` / `getElderAnalysis` / `getElderPhysio` / `getElderEmotion` / `getElderGameMetrics` / `listElderSummaries`），有 `SEED_ELDER_IDS` 參考資料；`care_alerts`（migration 011）已有 **nullable `elder_id UUID REFERENCES elders(id)`**（CR-0008），`careAlertStoreService.listAlerts` 已支援 `elderId` 過濾。
5. care alert store = DB-first + JSON fallback（dev/staging）；本機無 Postgres，**migration 無法對真 DB 跑**；`careAlertStoreService` 已有 `setPgForTest(pg)` 注入 seam，測試走 mock pg。

#### 3. 核心張力與裁決 — caregiver 身分如何建立？採 **路線 B（精修版）**
- **張力**：任務 §4.2/§4.3/§4.4 要「caregiver 只能看授權住民」「不可『持 token 即全看』作為正式行為」，但**目前請求無法識別是哪位 caregiver**（只有共享 admin token）。沒有 caregiver 身分就無法真正依 caregiver 過濾。
- **路線 A（駁回）**：本案就導入 caregiver 登入 + 個別身分 + JWT/role。→ **駁回**：與 §12 #5 重疊，等同一次重寫整個 auth，違反任務 §5.8 與 CLAUDE.md「不一次重寫整個 auth」。
- **路線 B（採用，精修）**：本案建立 **schema（resident_caregiver_links，resident=elder）+ Authorization Service（純函式 + pg seam）+ super_admin 角色定義 + 路由 scope plumbing（經單一 authContext resolver）**。caregiver 身分**不在本案偽造**：production 唯一可解析身分 = `ADMIN_API_TOKEN` → **`super_admin`（full scope）**；caregiver-scoped 程式路徑為**真實碼**，由**注入式 authContext（測試 seam）**驅動單元/端點測試。per-caregiver 真實登入留待 §12 #5。
- **裁決**：採**路線 B（精修）**。理由：
  1. 在不重寫 auth 的前提下，讓「依授權住民過濾」成為**已存在、已測、可獨立回滾**的機制（修 P0-2 scope 層）。
  2. 把共享 token 明確命名為 `super_admin` 角色 → P1-2 的「token 即全看是意外行為」轉為「明確角色」（部分修 P1-2）。
  3. super_admin 路徑**完全保留 CR-0039 契約與 200 形狀**（行為零變更），caregiver 路徑由測試 seam 驗證 → 風險可控、checkpoint 可驗。
  4. **嚴禁**：不得引入 production 可用的假 caregiver token / 不得 hardcode caregiver / 不得用 demo seed 假裝授權完成（任務 §5.6/§5.7、CLAUDE.md §2.1）。caregiver 身分解析 seam 在 production 只認得 super_admin，直到 §12 #5。

#### 4. 最小切片邊界裁決 — 哪些進 CR-0040、哪些拆後續
- **進 CR-0040（Batch A/B/C）**：
  - schema（migration 013 resident_caregiver_links）。
  - Authorization Service（`getAuthorizedResidentIdsForCaregiver` / `assertCanAccessResident` / `filterAlertsByAuthorizedResidents`）+ `super_admin` 角色常數。
  - 路由 scope plumbing：care-alert 三條 + admin analytics 涉住民讀取路由，經單一 `resolveAuthContext(req)` 取得角色；super_admin→full scope（行為不變），caregiver→scoped（測試 seam 驅動）。
- **拆後續 CR-00xx（Batch D，依賴 §12 #5）**：
  - caregiver_web 整合（空狀態、403 友善處理、不壞版）。
  - 真實 per-caregiver 登入 resolver（讓 `resolveAuthContext` 回傳真 caregiverId）。
- **理由**：route enforcement 在「請求尚無 caregiver 身分」前對 production 是 no-op（一律 super_admin）；caregiver_web 串接與真強制需要 §12 #5 提供的真實身分。但 plumbing + service + schema + 注入式測試**現在就能落地且可獨立驗證**，正是 P0-2 scope 層所需，且不重寫 auth。Batch C 嚴格 behavior-preserving（super_admin），blast radius 受控。

#### 5. resident_caregiver_links 最小 schema（migration 013，提案規格；由 backend-agent 實作，本提案不寫 migration 檔）
- **命名橋接裁決**：表名保留 **`resident_caregiver_links`**（對齊 CLAUDE.md §3.3 核心表清單與稽核字面，避免 §3.3 檢查清單缺項）；欄位用 **`elder_id`**（對齊真實 `elders` 表與既有 `care_alerts.elder_id` FK 慣例）。「resident」概念即本專案 **elder**。
- **caregiver_id FK 錨點裁決**：FK 至 `users(id)`（caregiver 將是 `users.role='caregiver'`，§12 #5 建立 caregiver 帳號時自然落位）；沿用既有身分表，前向相容，不另造孤立 UUID。
- 提案 SQL（idempotent、`IF NOT EXISTS`、沿用 006/011 的 pgcrypto + gen_random_uuid 慣例）：
  - `id UUID PK DEFAULT gen_random_uuid()`
  - `elder_id UUID NOT NULL REFERENCES elders(id)`（resident = elder）
  - `caregiver_id UUID NOT NULL REFERENCES users(id)`（caregiver 身分錨於 users）
  - `role TEXT NOT NULL DEFAULT 'primary'`（primary | secondary | viewer）
  - `status TEXT NOT NULL DEFAULT 'active'`（active | revoked）
  - `created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()` / `updated_at TIMESTAMPTZ` / `revoked_at TIMESTAMPTZ`
  - 索引：`idx_rcl_caregiver_active`(caregiver_id) WHERE status='active'；`idx_rcl_elder`(elder_id)；UNIQUE `idx_rcl_unique_active`(elder_id, caregiver_id) WHERE status='active'
  - 冪等補欄位：`ALTER TABLE ... ADD COLUMN IF NOT EXISTS ...`（同 006/011 寫法）
- **不變**：不改 elders / users / care_alerts 既有欄位（純新增表 → 對既有資料零破壞）。

#### 6. 影響範圍（檔案 + 行號，已覆核）
- 新增：`backend/stt_proxy/db/migrations/013_create_resident_caregiver_links.sql`（Batch A）。
- 新增：`backend/stt_proxy/services/admin/authorizationService.js` + 測試（Batch B）。
- 改：`backend/stt_proxy/server.js`
  - care-alert：`GET /api/care-alerts`(501)、`GET /api/care-alerts/:id`(517)、`PATCH /api/care-alerts/:id/status`(530) → 於 `requireAdmin` 後加 `resolveAuthContext` + scope（super_admin 不變；caregiver 過濾/403）。
  - admin analytics：`/api/admin/overview`(1009)、`/api/admin/elders`(1019)、`/api/admin/elders/:elderId`(1029)、`/elders/:elderId/physio|emotion|game-metrics`(1042/1055/1068)、`/api/admin/daily-care-tasks`(954) 涉住民讀取部分套 scope。
  - **不動**：`POST /api/care-alerts/notify`(387)（長者端建立路徑，紅線）。
- 後續（Batch D，拆出）：`caregiver_web/app.js` + 真 per-caregiver 登入 resolver。

#### 7. 觸及 🔒？
- **是（兩處）**：
  - DB schema（migration 013）→ 🔒。屬**純新增表**、additive、idempotent → low（不改既有表/欄位/契約）。
  - `server.js` 路由（Batch C）→ 🔒（路由/response 契約）。但 super_admin 路徑**行為零變更**，僅新增「caregiver 角色時的過濾 / 403」分支；不改任何 200 成功形狀、不改 Care Alert 三方共用資料結構欄位 → medium。
- **不觸及**：Realtime / SDP / DataChannel、Memory 成功契約、`.env` / token 值、`requireAdmin.js` 行為（CR-0039 擋門保留）、Care Alert 既有 200 形狀。
- architecture-agent 對 🔒 改動之核准：**Batch A/B 核准**；**Batch C 條件式核准**（須落地 checkpoint 覆核 CR-0039 門 + 200 形狀 + /notify + 無 production 假 caregiver；見 §11）。

#### 8. 牽涉 agent
- backend-agent：migration 013（A）、Authorization Service（B）、server.js scope plumbing + 測試（C）。**主要 owner。**
- frontend-ux-agent：caregiver_web 整合（**Batch D，拆後續 CR**；本案不動 caregiver_web）。
- 不牽涉 realtime-voice-agent、companion-memory-agent（Care Alert 建立邏輯 / /notify / 分級不動）。

#### 9. 風險等級：medium
- schema additive（low）+ 新 service（low）+ server.js scope plumbing（🔒，medium，behavior-preserving for super_admin）。
- 殘留（誠實記錄）：production 尚無真 caregiver 身分 → 真 per-caregiver 強制與 caregiver_web 串接未閉合（依 §12 #5，轉 Batch D / 後續 CR）。本案**不宣稱 P0-2 / P1-2 全修**，只修「scope 機制存在且可測 + super_admin 明確角色」子集。

#### 10. 批次切分（順序：A→B→C；D 另開 CR）
- **Batch A — backend-agent（schema）**
  - 範圍：新增 migration 013（§5 規格）。idempotent / `IF NOT EXISTS`。不改既有表。
  - 驗證：SQL 靜態審查（所有 CREATE/ALTER 皆 IF NOT EXISTS，可重跑）。**migration 不可對真 DB 跑**（本機無 PG）→ 見 §11 測試策略。
- **Batch B — backend-agent（Authorization Service，純函式 + pg seam）**
  - 範圍：`authorizationService.js`：`getAuthorizedResidentIdsForCaregiver(caregiverId, {pg})`、`assertCanAccessResident(caregiverId, elderId, {pg})`、`filterAlertsByAuthorizedResidents(authContext, alerts, {pg})` + `ROLE_SUPER_ADMIN` 常數。super_admin → full scope（直接放行）；caregiver → 查 `resident_caregiver_links` WHERE status='active'。**不 hardcode** elder/caregiver id；**不把所有 caregiver 當 super admin**；區分「已驗證」與「有權限」。
  - 驗證：單元測試以注入 mock pg（回傳 canned links rows）覆蓋：super_admin full scope、caregiver 僅授權 elder、無授權→空集合、跨住民→assert 拋錯/false。不需真 DB。
- **Batch C — backend-agent（路由 scope plumbing，🔒，behavior-preserving）**
  - 範圍：加 `resolveAuthContext(req)`（production：valid ADMIN_API_TOKEN → `{role:super_admin}`；**不引入 production 可用 caregiver token**）。care-alert 三條 + admin analytics 涉住民讀取路由：super_admin→原行為；caregiver→list 過濾、detail/update 跨住民 403。`/notify` 不動。
  - 驗證：端點測試 — (1) super_admin（valid token）→ 原 200 形狀、list 全量、/notify 無 auth 仍 200（CR-0039 回歸）；(2) 注入 caregiver authContext（測試 seam，stub `resolveAuthContext`）→ list 僅授權 elder / detail 跨住民 403 / update 跨住民 403 / 無授權 list 空集合。對齊任務 §6.1–6.3。
- **Batch D — 拆後續 CR-00xx（依賴 §12 #5，本案不做）**
  - frontend-ux-agent：caregiver_web 空狀態 / 403 友善處理 / 不壞版 / 不假資料。
  - backend-agent：真 per-caregiver 登入 resolver（`resolveAuthContext` 回傳真 caregiverId）。
- 相依：A→B→C 依序；D 待 §12 #5。三批（A/B/C）合併後視為 CR-0040 完成。

#### 11. 測試計畫 + migration 不可對真 DB 跑 之策略
- **Authorization Service（B）**：以注入 mock pg（`{ query: async () => ({ rows:[...] }) }`）驅動，斷言授權集合 / 跨住民拒絕；零真 DB。
- **路由 scope（C）**：沿用既有測試模式（注入 `setPgForTest` / stub store + stub `resolveAuthContext`）。super_admin 路徑用字面 `test-admin-token`（同 CR-0039）；caregiver 路徑用注入 authContext。
- **migration 013（A）— 不可對真 DB 跑**：本機無 Postgres，**不執行實際 migrate**。策略：
  1. SQL 靜態審查（idempotency：全 IF NOT EXISTS；重跑安全；FK 指向既有 elders/users）。
  2. 若 `db/migrate.js` 支援 mock pg client，加「migration 檔被載入並依序送出」之 runner 測試；否則以檔案存在 + 含 IF NOT EXISTS guard 的解析測試替代。
  3. 回報需誠實標註「migration 未對真 DB 驗證，僅靜態 + mock」。
- **回歸**：`cd backend/stt_proxy && npm run check && npm test`（CR-0039 後 backend 296 應維持綠 + 新增案例）。Flutter 不受影響（本案 0 行 `lib/` 改動，/notify caller 不動）→ 可選跑確認 0 回歸。
- **測試所需環境變數**：`ADMIN_API_TOKEN`（測試值，請手動設定，勿貼真實值）。不需真 `DATABASE_URL` / 真金鑰。

#### 12. 紅線（落地必守）
- 不破壞 CR-0039 `requireAdmin` 擋門（401/403 行為保留）。
- 不破壞 `POST /api/care-alerts/notify` 長者端建立流程（不掛驗證、不加 scope）。
- 不改 Realtime / Memory 成功契約；不改 Care Alert 既有 200 回傳形狀與三方共用資料結構欄位。
- super_admin 路徑行為零變更。
- **不 hardcode resident/caregiver 作為正式授權；不引入 production 可用假 caregiver token；不用 demo seed 假裝授權完成。**
- 不一次重寫整個 auth（caregiver 登入 = §12 #5，本案外）。
- 不碰 `.env` / token 值；不改 `requireAdmin.js` 行為。

#### 13. architecture-agent 裁決
- ✅ **核准規劃**（按 §10 批次 A→B→C 執行；Batch D 拆後續 CR-00xx，依賴 §12 #5）。
- 路線裁決：**路線 B（精修）** — schema + Authorization Service + super_admin 明確角色 + 路由 scope plumbing（經 resolver seam）；caregiver 身分 production 只認 super_admin，scoped 路徑由測試 seam 驗證；真 per-caregiver 登入 + caregiver_web 留 §12 #5 後續。
- 最小切片裁決：A/B/C 進本案；caregiver_web 整合 + 真 per-caregiver resolver 拆 Batch D。
- 🔒 裁決：Batch A/B 核准；**Batch C 條件式核准**，落地後須 architecture-agent checkpoint 覆核（CR-0039 門完整 / 200 形狀不變 / /notify 不受影響 / 無 production 假 caregiver / 無 hardcode 授權）方可結案。
- 完成定義：A/B/C 合併 + 測試綠 + checkpoint PASS。本案**僅**修 P0-2 的 scope 層（機制存在且可測）與 P1-2 的「super_admin 明確角色」子集；**不宣稱 P0-2 / P1-2 全修**（真 per-caregiver 強制依 §12 #5）。

#### 14. 落地 checkpoint 覆核（architecture-agent，2026-06-08）— PASS
- **結論：PASS（Batch C 條件式核准之 checkpoint 通過，CR-0040 結案）。** read-only 覆核（git diff / grep），未改業務碼。
- **執行進度**：Batch A ✅（migration 013）／Batch B ✅（authorizationService + 15 案）／Batch C ✅（server.js scope + 12 案）。
- **驗收結果**：backend `npm run check` OK；`npm test` → 331/331 pass、0 fail（296 基線 + 35 新）。獨立覆驗一致。
- **§11 checkpoint 逐項（全數通過）**：
  - (a) super_admin 行為零變更：`resolveAuthContext` production 恆回 `{role:super_admin}`；care-alert list 走 `filterAlertsByAuthorizedResidents`（super_admin 原樣同參考回傳）、`:id` 與 PATCH 對 super_admin 跳過前置讀取 → 200 形狀/排序/欄位不變；測試含 list 全量、:id 200、PATCH 200、PATCH 不存在→404 回歸。✅
  - (b) requireAdmin 擋門完整：scope 路由 `requireAdmin` 皆仍在最前；測試「caregiver 無 token → 401 先於 scope」通過，未被繞過。✅
  - (c) `/notify`（server.js:391）未受影響：CR-0040 diff 未觸及該行，維持無 auth、無 scope；測試「notify 無 auth → 200」回歸通過。✅
  - (d) caregiver scope override 無法經 HTTP 觸發：`setAuthContextResolverForTest` / `authContextResolverOverride` 僅出現於兩支測試檔與 service 自身；production resolver 恆回 super_admin。無 production 可用假 caregiver token、無 hardcode elder/caregiver id（`!caregiverId → 空集合` fail-closed）。✅
  - (e) migration 013 additive + 冪等：全 CREATE/ALTER/INDEX 皆 IF NOT EXISTS；純新增表，未 ALTER elders/users/care_alerts；FK 指向既有表；partial UNIQUE(elder_id,caregiver_id) WHERE active。靜態解析測試 8 案把關。✅
- **兩處刻意缺口裁決**：
  - **`GET /api/admin/overview`（server.js:1044）— 接受結案，列已知殘留（低嚴重度）**。僅回 `getOverview()` 聚合計數、無 per-resident 識別資訊；scope 需動 adminAnalysisService，超出 Batch C「只改 server.js」邊界。轉後續 CR。
  - **`GET /api/admin/daily-care-tasks`（server.js:989）— 接受結案，但列「Batch D BLOCKER」（中嚴重度）**。此端點回 per-resident 資料（`elderId` 可篩、tasks 綁 elder），與已 scope 的 elder analytics 同類。今日零實際暴露（production 無 caregiver 身分，resolver 恆 super_admin），故可結 CR-0040；但**啟用真 per-caregiver 登入（§12 #5 / Batch D）前必須先補 scope**，否則真 caregiver 可跨住民讀任務 → 違反 CLAUDE.md §6#8（不可跨住民洩漏）、§9#11（照護人員只能查看授權住民）。Batch D 開案時須將此端點納入 scope 範圍並列為前置條件。
- **裁決依據**：CR-0040 scope 層在 production 對所有路由皆為 no-op（恆 super_admin），故兩缺口今日實際暴露皆為零；差異只在 Batch D 啟用 caregiver 身分後浮現。據此接受 A/B/C 結案，缺口轉後續 CR，其中 daily-care-tasks 標為 Batch D 硬前置。
- **完成狀態：CR-0040（Batch A/B/C）COMPLETE。** 殘留明確標註：
  - **P0-2 scope 機制已具備且可測，但 production 強制仍待 §12 #5 per-caregiver 登入（Batch D 後續 CR）**；本案不宣稱 P0-2 / P1-2 全修。
  - **migration 013 未對真 DB 驗證**（本機無 Postgres），僅靜態 + mock 解析測試把關；首次對真 DB migrate 時需人工確認冪等與 FK。
  - 後續 CR（Batch D）待辦：真 per-caregiver 登入 resolver、caregiver_web 整合（空狀態 / 403 友善）、補 scope `daily-care-tasks`（BLOCKER）+ `overview`（低）。

---

### CR-0041 — Caregiver Web Auth Integration and Scoped Admin Session（Audit CR0033 §12 #5 / P1-2 / P1-6；Batch D 正餐，接 CR-0039 擋門、CR-0040 scope 機制）
- 提出 / 裁決 agent：architecture-agent（依使用者指派；CR-0040 結案殘留「Batch D 後續」收斂）
- 狀態：**✅ 完成（後端正餐 D1+D2+D3 落地，350/350 綠，architecture-agent checkpoint PASS — 見 §17）**。caregiver_web 登入 UI=CR-0042、provisioning=CR-0043、/notify caller 驗證=FU-CR 為已知殘留。
- 帳本正規 ID = **CR-0041**（沿用 CR-0039 §0「下一個空號」治理）。對應 Audit §12 #5「per-caregiver 登入」、P1-2「無 RBAC / 無逐人 admin 身分」收斂主體、P1-6「caregiver_web 無正式登入」。

#### 1. 動機 / 問題
- CR-0040 已建 scope 機制（`authorizationService` + `resident_caregiver_links`），但 **production 無真正 per-caregiver 身分可經 HTTP 觸發**：`resolveAuthContext` 在 production 恆回 `{role:'super_admin'}`，caregiver 路徑只由測試 seam（`setAuthContextResolverForTest`）驅動。
- 結果：持共享 `ADMIN_API_TOKEN` 者仍可看全部住民（CR-0040 §13 明列轉本案）；CR-0040 §14 標記 `GET /api/admin/daily-care-tasks`（server.js:989）為 **Batch D 硬前置 BLOCKER**（per-resident 資料未 scope）。
- 本案目標：讓 caregiver 身分**真正能經 HTTP 觸發**並驅動既有 scope 過濾，且補上 daily-care-tasks scope，不重寫整個 auth。

#### 2. 影響範圍（檔案層級）
- 後端（CR-0041 本體，owner=backend-agent）：
  - 🔒 `backend/stt_proxy/server.js`（care-alerts ×3 / elders analytics ×5 / daily-care-tasks 路由的 authN 中介層接線；route body 改讀 `req.authContext`）
  - 新增 `backend/stt_proxy/services/admin/adminAuthContext.js`（身分解析：shared token→super_admin｜firebase idToken→users.role）+ 新中介層 `resolveAdminAuthContext` / `requireCaregiverOrAdmin`
  - `backend/stt_proxy/services/admin/authorizationService.js`（保留純 scope 函式；`resolveAuthContext` 由中介層取代為資料來源，測試 seam 可退役或保留為相容）
  - `backend/stt_proxy/services/admin/requireAdmin.js`（**不改行為**；保留為 super_admin-only 路由的擋門）
  - `backend/stt_proxy/.env.example`（僅補註解，不增新 secret）
  - 後端測試（新增 HTTP 層 authN + scope 案例）
- caregiver_web（拆子 CR **CR-0042**，owner=frontend-ux-agent）：
  - 🔒 `caregiver_web/app.js`、`caregiver_web/index.html`、`caregiver_web/config.example.js`、`caregiver_web/*.test.js`、`caregiver_web/README.md`
- 文件：`docs/CHANGE_REVIEW.md`（本筆）、新增 `docs/AUTHORIZATION_MODEL.md`、`docs/CAREGIVER_WEB_AUTH.md`（CR-0042）

#### 3. 觸及 🔒 檔案
- `server.js`（後端 API 契約 / Care Alert 管理路由）→ **本案核心 🔒**。
- `caregiver_web/app.js`（管理端行為）→ 拆 CR-0042 處理。
- **不觸及**：`realtime_voice_service.dart`、Realtime/SDP/DataChannel、Memory 成功契約、Care Alert 既有 200 形狀、`/api/care-alerts/notify`、`.env` 值。

#### 4. 牽涉 agent
- backend-agent（CR-0041 本體：身分機制 + middleware + scope + daily-care-tasks + 後端測試 + docs）
- frontend-ux-agent（CR-0042 子 CR：caregiver_web Firebase 登入 + per-role header + 401/403/empty-state + 前端測試）
- architecture-agent（裁決 + 落地 checkpoint 覆核）

#### 5. 風險等級
- **High**（觸及 server.js 授權主線；錯誤即跨住民洩漏或把所有人當 super_admin）。緩解：分批 + 每批回歸 CR-0039/0040 測試 + 落地 checkpoint。

---

#### 6. 核心裁決一：caregiver 身分機制 = **路線 A（Firebase idToken 當 bearer）**
- **裁決：採路線 A。** caregiver_web 取得 Firebase web idToken → 以 `Authorization: Bearer <idToken>` 呼叫後端 → 後端 `firebaseAdmin.verifyIdToken` → 由 `decoded.uid` 查 `users.firebase_uid` → 讀 `users.role` → 建 authContext。
- **理由（對齊「不重寫整個 auth」「最小改動」「不可 production 假 token」）**：
  1. **重用既有設施**：`firebaseAdmin.isConfigured()/verifyIdToken()` 已由 `/api/auth/session` 使用且已測；`users.role`（migration 006）與 `resident_caregiver_links.caregiver_id FK→users(id)`（013）的資料模型**本來就假設 caregiver = Firebase-backed users row**（013 註解明寫「§12 #5 落位」）。路線 A 是此模型的自然完成。
  2. **零新 secret**：路線 B 需自發 JWT（新增 `SESSION_SECRET/JWT_SECRET` + 簽發 / 刷新 / 撤銷機制）；路線 C 需 per-caregiver token 生命週期（雜湊儲存 / 撤銷 / 輪替），等同更差的 JWT。兩者都新增攻擊面、都違反「最小改動」。路線 A 不需任何新後端密鑰。
  3. **production 不可假 token 的保證直接複用 CR-0034 B2**：production（`isProduction(env)`）下 `mockAllowed()` 恆 false；中介層在 production **必須** `firebaseAdmin.isConfigured()===true` 且 idToken 真實可驗，否則 401。與長者 auth 走同一條已測的 production 守門線。
- **dev/mock 如何不成為 production 漏洞（關鍵）**：
  - mock 路徑沿用 `sessionService.mockAllowed()` 完全相同語義：production 一律關閉，無例外、無寬鬆預設。
  - **fail-closed 且絕不預設 super_admin**：通過 Firebase 驗證但 `users.role` 非 caregiver/admin → **403**，不是 super_admin。唯一產生 super_admin 的路徑是「bearer 字面等於 env `ADMIN_API_TOKEN`」。
  - 即使 dev mock 模式，解析出的 caregiver **仍須對應真實 `users` row（以 firebase_uid 查得、role='caregiver'）**；mock 只略過 idToken 的密碼學驗證（採信 firebaseUid），與長者端 dev 行為一致，**production 不可達**。無 hardcode id、無 demo seed 進 production。
- **super_admin token 命名**：保留 `ADMIN_API_TOKEN`（向後相容），文件統一稱 **super_admin token**（最高權限，不發給一般照護人員）；log 不印 token。

#### 7. 核心裁決二：範圍與拆分
- **裁決：CR-0041 = 後端正餐（identity + middleware + scope + daily-care-tasks），caregiver_web 完整 Firebase 登入 UI 拆為子 CR CR-0042。**
- **理由**：(a) owner 邊界乾淨（backend-agent vs frontend-ux-agent）；(b) 驗收標準 #2「caregiver-scoped 可經正式 HTTP 觸發」在後端即可用 HTTP 層測試（stub firebaseAdmin + 注入 pg）證明，**不依賴 web SDK**；(c) caregiver_web Firebase web SDK 整合 + 登入頁 + session 生命週期是新的非小型前端面，硬塞會讓本案過大、checkpoint 難切。
- **daily-care-tasks 硬 blocker 裁決：納入 CR-0041 scope（必修、fail-closed）。** 它是 CR-0040 §14 明定的 Batch D 前置，與已 scope 的 elder analytics 同類、改動小（route body 加 scope，比照 `/api/admin/elders`）。**不拆出**。
- **/notify**：維持不擋（CR-0039 裁決）；caller 驗證仍是另開的 FU-CR（正式版 blocker），**不在本案**。
- **overview（server.js:1044）**：低殘留（純聚合計數），維持 super_admin-only `requireAdmin`，不納入本案 caregiver scope；轉後續。

#### 8. Middleware 設計（裁決：分三層，最小改動）
1. **`requireAdmin`（保留，零行為變更）** — 純 super_admin 共享 token 擋門。續用於 super_admin-only 路由：`/api/admin/users`、`/api/admin/overview`、marketplace admin、`/api/auth/*` 不適用。
2. **`resolveAdminAuthContext`（新增，= `requireCaregiverOrAdmin`）** — 做 authN + 角色解析，fail-closed，掛在「caregiver-or-admin」路由（care-alerts ×3、elders analytics、daily-care-tasks）：
   - 取 bearer（重用 `requireAdmin.extractBearerToken`）。無 token → **401 `missing_admin_token`**（保留 CR-0039 契約）。
   - bearer 字面等於 `ADMIN_API_TOKEN`（且 env 有設）→ `req.authContext = {role:'super_admin', scope:'all', userId:null, caregiverId:null}` → next（super_admin 路徑與 CR-0039/0040 行為完全一致）。
   - 否則走 Firebase caregiver 解析：production 須 `isConfigured()`；`verifyIdToken` 失敗 → **401 `invalid_session`**；查 `users` by firebase_uid，role='caregiver' → `{role:'caregiver', caregiverId:users.id, userId:users.id, scope:'assigned_residents'}`；role 非 caregiver/admin → **403 `admin_permission_required`**。
   - dev mock：依 `mockAllowed()` 採信 firebaseUid 但**仍須查得真實 users row**。
3. **resident scope 檢查（保留 in-route）** — route body 續呼叫 `authorizationService.assertCanAccessResident / filterAlertsByAuthorizedResidents`，但 authContext 來源從 `authz.resolveAuthContext(req)` 改為 `req.authContext`（由 #2 中介層填）。可選抽 `requireScopedResidentAccess(req,res,next)` 包 `:elderId` 路由 DRY（非必要，B 批可做）。
- **不得讓所有 authenticated user 成為 super_admin**：只有 shared-token 字面比對成功才是 super_admin（裁決 §6）。

#### 9. 批次切分（每批 owner + 順序）
- **D1（backend-agent）**：新增 `adminAuthContext.js` 身分解析 + `resolveAdminAuthContext` 中介層（authN + 角色，fail-closed，super_admin 經 shared token 保留）。單元測試（stub firebaseAdmin、注入 pg）。**不接路由**或僅接 care-alerts 試點。
- **D2（backend-agent）**：把中介層接到所有 §5.5 路由（care-alerts ×3、elders list/detail/physio/emotion/game-metrics、**daily-care-tasks scope 修補**）；route body 改讀 `req.authContext`。回歸 CR-0039/0040 全綠 + 新增 HTTP 層 scope 測試（§7.1 #1–#10，含 caregiver A vs B、空 scope、daily-care-tasks 跨住民隔離、無 token 401、invalid session 401、production 不收假 caregiver token）。
- **D3（backend-agent / docs）**：本筆收尾 + 新增 `docs/AUTHORIZATION_MODEL.md`（super_admin vs caregiver、授權如何取得、resident_caregiver_links 用途）+ `.env.example` 註解（super_admin token 命名）。
- **CR-0042（frontend-ux-agent，子 CR，排 D2 之後）**：caregiver_web Firebase web 登入 + per-role auth header（super_admin token vs caregiver session）+ 401/403/empty-state 友善處理 + 前端測試（§7.2）+ `docs/CAREGIVER_WEB_AUTH.md` + README。
- 相依：D1→D2→D3；CR-0042 待 D2 後端契約穩定後開。

#### 10. Migration 是否需要 + 測試策略
- **不需新 migration**：caregiver = `users.role='caregiver'`（006 已有 role 欄）；`resident_caregiver_links.caregiver_id FK→users(id)`（013 已有）。本案只「解析」role，不新增表 / 欄。
- **caregiver 帳號 / 授權關聯的「建立」（provisioning）= 殘留，拆後續 CR-0043**：目前 `createUserPostgres` 寫死 role='elder'，無 caregiver 帳號建立路徑。dev 以 SQL / seed 提供；production 的「把 user 升為 caregiver、建 resident_caregiver_links」需 super_admin-only 端點（屬 §12 #5 帳號管理 / CR-0029 延伸）。**本案不建 provisioning，只實作身分解析 + scope**。
- **不可對真 DB 跑的測試策略**：沿用既有 seam —— `authorizationService.setPgForTest(mockPg)`（link 查詢注入授權 rows）；新中介層比照 `sessionService` 以 `options.firebaseAdmin` 注入 stub（`isConfigured`/`verifyIdToken`），達成「不需真 DB、不需真 Firebase 金鑰」單測 + HTTP 層測試；super_admin 路徑用字面 `test-admin-token`（同 CR-0039）。

#### 11. 需要的環境變數（僅列名稱，不碰值）
- 既有、續用：`ADMIN_API_TOKEN`（= super_admin token，文件改名概念）、`FIREBASE_PROJECT_ID`、`FIREBASE_CLIENT_EMAIL`、`FIREBASE_PRIVATE_KEY`、`GOOGLE_APPLICATION_CREDENTIALS`（caregiver idToken 驗證所需，與長者 auth 共用）、`AUTH_ALLOW_MOCK`（同時治理 caregiver dev mock）、`APP_ENV`/`NODE_ENV`（production 守門）。
- **無新增後端 secret**（路線 A 的關鍵優勢；不需 `JWT_SECRET`/`SESSION_SECRET`）。
- CR-0042（前端）：caregiver_web Firebase **web** config（apiKey/authDomain/projectId…）屬**公開 client config**，放 `caregiver_web/config.example.js`，**不進 `.env`、非 secret**。

#### 12. 紅線（本案全程，依任務 §9）
- 不破壞 `/api/care-alerts/notify`（長者端建立，續無 auth）。
- 不破壞 Realtime / Memory 成功契約、不改 Care Alert 既有 200 形狀；super_admin 路徑行為零變更。
- 不把所有登入者視為 super_admin；不 hardcode caregiver id；production 不收假 token。
- 不移除 CR-0039/0040 測試；不為過測試放寬授權。
- 不在 production log 印 token / email / 完整對話 / 敏感資料（PATCH 稽核 metadata 維持結構化、無 PII）。
- 不一次重寫整個 auth。

#### 13. 測試計畫（驗收門檻）
- backend：`cd backend/stt_proxy && npm run check && npm test`，CR-0040 後 331 基線維持綠 + 新增 D1/D2 案例（§7.1 #1–#10）。
- caregiver_web（CR-0042）：`cd caregiver_web && node --test *.test.js`，既有綠 + §7.2 新增。
- 落地後 architecture-agent checkpoint 覆核：CR-0039 門完整 / 200 形狀不變 / /notify 不受影響 / 無 production 假 caregiver / 無 hardcode / 無 sensitive log / daily-care-tasks 已 scope。

#### 14. 🔒 裁決（architecture-agent）
- **D1 核准**（純新增 service + middleware，未改既有路由契約）。
- **D2 條件式核准**（觸及 server.js 授權主線）：須落地 checkpoint 覆核——(a) super_admin 200 形狀 / 排序 / 欄位零變更；(b) `requireAdmin` 仍擋 super_admin-only 路由；(c) `/notify` 未觸及；(d) caregiver 跨住民 detail/PATCH → 403、空 scope → 空 list；(e) daily-care-tasks 跨住民隔離且 fail-closed；(f) production 無法以假 caregiver token 通過；(g) 無 sensitive log。通過方可結案。
- **D3 核准**（純文件）。
- **CR-0042 另案裁決**（frontend-ux，D2 後端穩定後開）。
- **完成定義**：D1+D2+D3 合併 + 測試綠 + checkpoint PASS。本案修 P1-2（per-caregiver 身分 + scope 強制經 HTTP）主體與 P0-2 scope 的「production 可觸發」缺口 + daily-care-tasks BLOCKER；**不宣稱** P1-6 全修（caregiver_web 登入屬 CR-0042）、不宣稱 /notify caller 驗證已修（FU-CR）、不宣稱 caregiver provisioning 已做（CR-0043）。

#### 15. 殘留 / 下一個 CR
- **CR-0042**（frontend-ux）：caregiver_web Firebase 登入 + per-role header + 401/403/empty-state（修 P1-6）。
- **CR-0043**：caregiver 帳號與 resident_caregiver_links provisioning（super_admin-only 端點；§12 #5 帳號管理層）。
- **FU-CR**：`/api/care-alerts/notify` caller 驗證（長者 session，正式版 blocker）。
- **後續**：`/api/admin/overview` 若改回 per-resident 需補 scope（目前低殘留）。

#### 16. 落地紀錄（backend-agent，D1→D2→D3）— 待 architecture-agent checkpoint
- **狀態：D1+D2+D3 已落地，測試綠。等 architecture-agent 落地 checkpoint 覆核（§14 D2 條件式核准）。** 未 commit。
- **新增檔案**：
  - `backend/stt_proxy/services/admin/adminAuthContext.js`（身分解析 + `resolveAdminAuthContext` 中介層；`buildAuthContext` 純函式 + `setFirebaseAdminForTest` / `setPgForTest` 測試 seam）。
  - `backend/stt_proxy/services/admin/adminAuthContext.test.js`（D1 單元，12 案）。
  - `docs/AUTHORIZATION_MODEL.md`（D3）。
- **修改檔案**：
  - `backend/stt_proxy/server.js`：import `resolveAdminAuthContext`；care-alerts ×3 / elders analytics ×5 / daily-care-tasks 路由由 `requireAdmin` 換 `resolveAdminAuthContext`，route body 改讀 `req.authContext`；daily-care-tasks 新增 resident scope（super_admin 全量 / caregiver 授權過濾 / 帶非授權 elderId→403 / 無授權→空）；PATCH status 稽核 actorId 改取 `authContext.userId`、actorType 依角色。super_admin-only 路由（users / overview / marketplace）維持 `requireAdmin` 不動；`/api/care-alerts/notify` 未觸及。
  - `backend/stt_proxy/package.json`：check + test script 納入新檔。
  - `backend/stt_proxy/.env.example`：Admin 區段補 super_admin token vs caregiver Firebase idToken 說明（只列名稱）。
  - `backend/stt_proxy/services/admin/authorizationService.js`：**未改**（保留純 scope 函式 + 既有 seam，供 authorizationService.test.js 與相容）。
- **既有測試斷言調整（合理語意變更，無刪除、無放寬授權）**：
  1. `services/careAlertListEndpoint.test.js`：GET /api/care-alerts「錯 token → 403 admin_permission_required」改為「非共享/無效 token → 401 invalid_session」。原因：路由改接受 caregiver idToken，非匹配 token = 無效 session = 401（非 admin_permission 403）。無 token 仍 401 missing_admin_token、共享 token 仍 200（保留）。
  2. `services/careAlertStatusEndpoint.test.js`：PATCH 同上 403→401 invalid_session。
  3. `services/admin/adminEndpoint.test.js`：原「錯 token→403」一案拆兩案——super_admin-only `/api/admin/overview` 仍斷言 403 admin_permission_required（requireAdmin 不動）；elders analytics ×5 改斷言 401 invalid_session（已換 resolveAdminAuthContext）。無 token→401 missing_admin_token 一案原樣保留。
  4. `services/careAlertAuthScopeEndpoint.test.js`：caregiver 身分注入機制由 CR-0040 的 `authz.setAuthContextResolverForTest` 測試 seam，改為**真 HTTP 路徑**（stub firebaseAdmin verifyIdToken + mock pg 查 users/role + caregiver Firebase idToken header）。super_admin 案（共享 token）原樣保留；新增 daily-care-tasks scope ×5、非共享/無效 token→401 invalid_session ×1。斷言的 scope 行為（只見授權住民 / 跨住民 403 / 空集合）不變。
- **驗收（本機，未對真 DB / 真 Firebase）**：`npm run check` OK；`npm test` → **350/350 pass、0 fail**（331 基線 + 19 新；含 12 D1 單元 + daily-care-tasks/invalid-session HTTP 案 + adminEndpoint 拆案）。
- **誠實標註**：身分解析以 stub firebaseAdmin + mock pg 驗證，**未對真 Firebase 金鑰 / 真 Postgres 驗證**；production「關 mock / 不收假 token」以單元測試（注入 production env 物件）涵蓋，未實際在 production 環境執行。caregiver provisioning 仍未做（CR-0043）。
- **§14 checkpoint 對應自評（待 architecture-agent 覆核）**：(a) super_admin 200 形狀/排序/欄位零變更（共享 token 路徑 authContext.role=super_admin，filter 原樣回傳）✅；(b) requireAdmin 仍擋 super_admin-only 路由 ✅；(c) `/notify` 未觸及 ✅；(d) caregiver 跨住民 detail/PATCH→403、空 scope→空 list ✅；(e) daily-care-tasks 跨住民隔離且 fail-closed ✅；(f) production 無法以假 caregiver token 通過（單元覆蓋）✅；(g) 無 sensitive log（中介層例外只印 error.message，不印 token/email）✅。

#### 17. 落地 checkpoint 覆核（architecture-agent，2026-06-08）— ✅ PASS，CR-0041 結案
- **結論：PASS。** D1 ✅ / D2 ✅ / D3 ✅。read-only checkpoint（git diff + grep + 獨立跑測試）通過 §14 七項 D2 條件式核准門檻。**完成狀態：完成（後端正餐）。** 未自行 commit（交付清單見下）。
- **獨立驗收**：`npm test` → **tests 350 / pass 350 / fail 0**（與 backend-agent 自評一致；331 基線 + 19 新）。
- **§14 七項覆核（architecture-agent 親查 server.js / adminAuthContext.js diff）**：
  - (a) super_admin（共享 token）行為零變更 ✅ — 中介層 `token === ADMIN_API_TOKEN` 字面相符即回 `superAdminContext()`，route body 維持 `authz.isSuperAdmin` 早退；Care Alert 200 形狀 / 排序 / 欄位由原 service 回傳，未動。
  - (b) fail-closed、絕不預設 super_admin ✅ — 唯一 super_admin 來源 = bearer 字面 == env token 或 DB role∈{admin,super_admin}；驗過身分但 role=elder / 查無 row / DB 不可用 → 403；中介層 catch 例外一律 401，無任何路徑預設 super_admin。單元 12 案明確覆蓋（role=elder→403、查無→403、DB 不可用→403、forged→401）。
  - (c) production 關 mock、無假 caregiver token、無 hardcode id、無 demo seed ✅ — 未 configured 時 `mockAllowed(env)` 在 production 恆 false → 401；caregiverId 來源恆為 `users.id`（DB 查得），無寫死；無 seed 進 production 路徑。
  - (d) `/notify` 未受影響 ✅ — server.js:395 `/api/care-alerts/notify` 仍無 authN 中介層，route body 與排序 / cooldown / notification log 未動。
  - (e) daily-care-tasks 已 scope 且 fail-closed ✅ — super_admin 全量；caregiver 帶非授權 elderId→403、未帶 elderId 取全量後依 `getAuthorizedResidentIdsForCaregiver` 過濾、無授權→空陣列。HTTP 層 5 案覆蓋。
  - (f) requireAdmin 在 super_admin-only 路由仍完整 ✅ — overview / users / marketplace（products/orders CRUD）共 8 處仍掛 `requireAdmin`，行為零變更；adminEndpoint.test.js overview 仍斷言 403。
  - (g) 無 sensitive log ✅ — `adminAuthContext.js` 唯一 log 為 `console.error("[admin-auth] resolve failed", { error: error.message })`，不印 token / email / idToken / PII；PATCH 稽核 metadata 維持結構化（actorId=users.id 純識別子）。
  - 旁證：`authorizationService.js` 經 `git diff --stat` 確認未改（保留純函式 + seam）。
- **斷言調整裁決：合理語意變更，非放寬授權（核可）。** 關鍵判準——未授權者仍被擋下，僅錯誤碼語意改變：
  1. care-alerts GET/PATCH + elders ×5「錯 token 403→401 invalid_session」：路由改接受 caregiver idToken 後，非匹配 bearer 一律當 idToken 驗證，驗失敗即「無效 session」(401) 而非「身分對但權限不足」(403)；語意上 401 更精確。**門未開**：無 token 仍 401 missing_admin_token、共享 token 仍 200、forged/elder/查無一律被拒。已獨立驗證：未 configured 之 default firebaseAdmin `verifyIdToken` 回 null → 401；即使解析出 uid，DB 查不到 row 亦 403，雙重 fail-closed。
  2. overview 仍 requireAdmin → 維持 403，正確（未換中介層）。
  3. careAlertAuthScopeEndpoint.test.js caregiver 注入由 CR-0040 測試 seam 改走「真 HTTP 路徑」（stub firebaseAdmin + mock pg 查 users.role + caregiver idToken header）：此為**測試強化**（更貼近 production），非放寬；scope 斷言（只見授權住民 / 跨住民 403 / 空集合）不變，super_admin 案保留，新增 daily-care-tasks scope ×5 + 無效 token→401 ×1。
  4. 無刪除測試。
- **明確殘留（誠實標註，非本案缺陷）**：
  - caregiver_web Firebase 登入 UI = **CR-0042**（frontend-ux，待開）。
  - caregiver 帳號 + resident_caregiver_links provisioning = **CR-0043**（super_admin-only 端點，未做）。
  - `/api/care-alerts/notify` caller 驗證 = **FU-CR**（長者 session，正式版 blocker，本案未動）。
  - `/api/admin/overview` per-resident scope = 低殘留（目前 super_admin-only，純聚合）。
  - 身分解析以 stub firebaseAdmin + mock pg 驗證，**未對真 Firebase 金鑰 / 真 Postgres 驗證**；production「關 mock / 不收假 token」以注入 production env 物件之單元測試涵蓋，未在真 production 環境執行。
- **commit 交付清單（architecture-agent 建議，交使用者決定 commit 時機，未自行 commit）**：
  - 納入 CR-0041 commit：`backend/stt_proxy/services/admin/adminAuthContext.js`、`backend/stt_proxy/services/admin/adminAuthContext.test.js`、`backend/stt_proxy/server.js`、`backend/stt_proxy/services/admin/adminEndpoint.test.js`、`backend/stt_proxy/services/careAlertAuthScopeEndpoint.test.js`、`backend/stt_proxy/services/careAlertListEndpoint.test.js`、`backend/stt_proxy/services/careAlertStatusEndpoint.test.js`、`backend/stt_proxy/package.json`、`backend/stt_proxy/.env.example`、`docs/AUTHORIZATION_MODEL.md`、`docs/CHANGE_REVIEW.md`、`tasks/CR-0041-caregiver-web-auth-integration-and-scoped-admin-session.md`。
  - **排除（噪音 / 非本案）**：`CLAUDE.md`、`ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme`、`PROJECT_REPORT_DRAFT.md`（未追蹤草稿）。

---

### CR-0042 — Caregiver Web Auth UI, Role Header, 401/403 Handling, and Empty State（P1-6；CR-0041 後端正餐的前端收尾）
- 提出 / owner agent：frontend-ux（依使用者指派；架構守門人於 CR-0041 §16「裁決」預先界定本 CR 範圍 = caregiver_web 完整 Firebase 登入 UI 子 CR）
- 日期：2026-06-08
- 動機 / 問題：CR-0041 已固定後端身分契約（`resolveAdminAuthContext`：super_admin 共享 token / caregiver Firebase idToken / 401 / 403），但 caregiver_web 仍只有單一共享 admin token 機制，無 caregiver 身分、無 401/403/empty-state 友善處理（稽核 P1-6）。
- 影響範圍（檔案，皆 frontend-ux 擁有）：
  - `caregiver_web/app.js`：身分狀態 + 統一 header helper + 401/403/empty-state + super_admin-only 入口控管。
  - `caregiver_web/index.html`：身分 / 登入列（caregiver / super_admin 模式選擇 + token 輸入 + 登入/登出）。
  - `caregiver_web/styles.css`：`.auth-bar` 等樣式。
  - `caregiver_web/auth_mode.test.js`（新增，14 案）、`caregiver_web/README.md`、`caregiver_web/config.example.js`。
  - `docs/CAREGIVER_WEB_AUTH.md`（新增）、`docs/CHANGE_REVIEW.md`（本筆）。
- 觸及 🔒？：否。**未改任何 backend**（server.js / Realtime / Memory / `/api/care-alerts/notify` 皆未動）、未改 API response 契約、未動 `.env`。純前端消費既有 CR-0041 契約。
- 牽涉哪些 agent：frontend-ux（本案）；消費 backend-agent 既有契約（無需 backend 改動）。
- 風險等級：low（純前端、靜態頁、向後相容）。
- 範圍決策（依任務 §5.3，架構守門人預先界定）：**最小可行 UI** —— 不在靜態頁堆完整 Firebase Web SDK popup 登入，改做清楚標示的 caregiver token / super_admin token 輸入；完整 Firebase 一鍵登入列為 follow-up CR。嚴禁 fake login / hardcode token / 未驗證進 dashboard / 把共享 super_admin token 當一般照護人員登入方式。
- auth mode 設計：
  - `authState = { authMode: 'super_admin'|'caregiver'|'none', token, displayName(null,不偽造), role }`。
  - localStorage 三 key：super_admin `caregiver_admin_token`（沿用）、caregiver `caregiver_login_token`（**獨立 key，不與 admin 共用**）、模式 `caregiver_auth_mode`。
  - 向後相容：無 `caregiver_auth_mode` 但有 admin token → 視為 super_admin（既有管理者體驗零變更）。
- header / token 行為：
  - 統一 helper `authHeaders()` / `authJsonHeaders()`（caregiver-or-admin 端點：care-alerts ×3、elders 列表 + 個人分析、daily-care-tasks）依 `authMode` 帶對的 token（`getActiveToken`）。
  - `adminAuthHeaders()` / `adminJsonHeaders()` 僅 super_admin-only 端點用（users / overview / marketplace），只帶 super_admin token。
  - caregiver token 不寫入 admin key、不命名為 admin token；無任何 `console.*` 印 token；無 token 時 `ensureCanFetch` 守門不發請求。
- 401 / 403 / empty state：
  - 401 → 「登入已失效，請重新登入」+ `sessionInvalid=true` 停止重複請求 + 捲回登入列；不顯示 stack / 完整 token / 工程錯誤碼。
  - 403 → 「目前帳號沒有權限查看此資料」；不清 token；detail/update 顯權限不足、list 依語意顯權限不足或空狀態。
  - caregiver 空授權 / API 回空陣列 → 「目前尚未被指派可查看的住民。請聯絡管理者確認權限設定。」不顯示全部資料 / 假資料 / undefined。
  - super_admin-only 入口：caregiver 模式隱藏 users / products / orders 分頁；overview 不打 API（避免 403 洗版，留「—」）；loadUsers / loadOrders 對 caregiver 顯權限不足、不打 API。
- 測試計畫 / 結果：`cd caregiver_web && node --test *.test.js` → **tests 69 / pass 69 / fail 0**（既有 55 仍綠 + 新增 14）。靜態來源檢查（與本資料夾既有測試一致，無 DOM runner）。
- 紅線自評（任務 §9）：未改 `/notify`、未改 backend、未 hardcode caregiver id、未 fake token、未把 caregiver 當 super_admin、未把所有 API 改 super_admin-only、UI/console 不顯完整 token、空狀態不用假資料、未為過測試放寬後端授權。
- 殘留 / follow-up：完整 Firebase popup 登入（免手貼 token）= 後續 CR；caregiver 帳號 + `resident_caregiver_links` provisioning = CR-0043；`/notify` caller 驗證 = FU-CR。
- 完成狀態：✅ 完成（前端）。未自行 commit。
- architecture-agent 裁決：✅ **核准並驗收**（2026-06-08，checkpoint review，read-only）。
  - 觸 🔒 判定：**否**。改動僅 `caregiver_web/*` + `docs/*`，屬 frontend-ux-agent 自有範圍 + 文件。`git diff --name-only` 確認 **0 行 backend**（無 `backend/`、`server.js`、Realtime、Memory、`/api/care-alerts/notify`）；未動 API response 契約、未動 `.env`、未動依賴。
  - 安全紅線覆驗（grep / read-only）：(a) caregiver token 只寫入 `CAREGIVER_TOKEN_KEY`、super_admin 只寫入 `ADMIN_TOKEN_KEY`，`applyLogin`/`saveAdminTokenFrom` 無交叉污染；(b) 無 `console.*` 印 token、無硬編 `Bearer <token>`、無 hardcode caregiver id/token、無 fake login（grep 命中之 "mock-safe" 僅後端連不到時的白話降級註解，非假資料）；(c) 向後相容：無 `caregiver_auth_mode` 但有 admin token → `loadAuthState` 回 super_admin，既有管理者 dashboard 行為零變更。
  - 端點 header 映射覆驗：`authHeaders()`/`authJsonHeaders()`（caregiver-or-admin）僅用於 care-alerts ×3（L289/342/484）、daily-care-tasks（L1254）、elders 列表（L1339）、個人分析（L1442）；`adminAuthHeaders()`/`adminJsonHeaders()`（super_admin-only）僅用於 users（L1071）、overview（L1306，caregiver 模式直接 return 不打 API）、marketplace products/orders（L2196/2224/2274/2458）。與 CR-0041 caregiver-scoped 契約一致。
  - 401/403/empty/隱藏覆驗：401→`handleSessionExpired`（`sessionInvalid=true` 阻止重複請求）；403→顯 `FORBIDDEN_MSG` 不清 token；caregiver 空授權→`EMPTY_CAREGIVER_MSG`（care-alerts L309 / daily-tasks L1270 / elders L1353，皆 server 回空、非假資料）；`applyAuthModeUi` 對 caregiver 隱藏 users/products/orders 分頁並自 super_admin-only view 切回 alerts。UI/CSS 無工程術語（grep SDP/ICE/DataChannel/socket/Demo/debug = NONE）。
  - 驗收（architecture-agent 獨立重跑）：`cd caregiver_web && node --check app.js` OK、`node --check auth_mode.test.js` OK；`node --test *.test.js` → **tests 69 / pass 69 / fail 0**（55 基線 + 14 新）。backend 未改、未重跑（CR-0041 契約不變）。
  - 殘留（已登錄、非本 CR blocker）：完整 Firebase popup 一鍵登入（免手貼 token）= follow-up CR；caregiver 帳號 + `resident_caregiver_links` provisioning = **CR-0043**；`/api/care-alerts/notify` caller 驗證 = **FU-CR**。
  - Commit 建議（本 CR 應納入）：`caregiver_web/app.js`、`caregiver_web/index.html`、`caregiver_web/styles.css`、`caregiver_web/README.md`、`caregiver_web/config.example.js`、`caregiver_web/auth_mode.test.js`（新）、`docs/CAREGIVER_WEB_AUTH.md`（新）、`docs/CHANGE_REVIEW.md`（本筆）。**排除噪音**（與本 CR 無關，勿混入）：`CLAUDE.md`（root 中→英整檔重寫）、`ios/.../Runner.xcscheme`（CRLF/行尾噪音）、`PROJECT_REPORT_DRAFT.md`（未追蹤草稿）、`tasks/CR-0042-*.md`（任務筆記，依團隊慣例可另計）。

---

### CR-0043 — Caregiver Account and Resident-Caregiver Link Provisioning（接 CR-0040/0041/0042；補 §12 #5 帳號管理層）
- 提出 / 裁決 agent：architecture-agent（架構守門人；依使用者指派）
- 日期：2026-06-08
- 狀態：**✅ 完成（後端 B1–B5 落地，399/399 綠，architecture-agent B3/B4 落地 checkpoint PASS — 見 §15）**。caregiver_web 管理 UI=CR-0044、email 自動認領=FU-CR-0043a、email DB unique index=FU-CR-0043b、`/notify` caller 驗證=FU-CR 為已知殘留。原規劃 / 裁決見 §1–§13、落地紀錄見 §14。
- 帳本正規 ID = **CR-0043**（沿用空號治理）。對應 Audit §12 #5「帳號管理」provisioning 層、CR-0041 §15/§17 明列之殘留「caregiver 帳號 + `resident_caregiver_links` provisioning（super_admin-only 端點）」。

#### 1. 動機 / 問題
- CR-0040 建 scope 機制、CR-0041 建 caregiver 身分解析（Firebase idToken→`users.role='caregiver'`→scope）、CR-0042 建 caregiver_web 登入 UI。但**沒有正式 provisioning 流程**：`createUserPostgres` 寫死 `role='elder'`（sessionService.js:152），無「建立 caregiver 帳號」「指派 `resident_caregiver_links`」「停用 caregiver / link」的 super_admin-only 端點。今日只能靠 SQL / seed 手動造資料 → caregiver scoped auth 無法端到端驗證。
- 本案目標：建立 super_admin-only 的 caregiver 帳號 + resident-caregiver 授權關聯 provisioning，使 CR-0040/0041 的 scope 能被真實管理並端到端驗證。

#### 2. 現況盤點（architecture-agent 已驗證）
- caregiver = `users.role='caregiver'`（**無獨立 caregivers 表**）。`users`（migration 006）：id / firebase_uid(UNIQUE, 可空) / elder_id FK→elders / role(預設 elder) / email(**無 UNIQUE**) / email_verified / display_name / auth_provider / provider_user_id / binding_status(預設 pending) / binding_deadline / created_at / verified_at / updated_at / last_login_at。**無 `status` 欄**（只有 binding_status，語意=長者端 Firebase 綁定生命週期，與「caregiver 啟用/停用」無關）。
- `resident_caregiver_links`（migration 013）：id / elder_id FK→elders / caregiver_id FK→users / role(primary|secondary|viewer, 預設 primary) / **status(active|revoked, 預設 active)** / created_at / updated_at / revoked_at；部分唯一索引 `idx_rcl_unique_active`（elder_id+caregiver_id WHERE status='active'）。
- `authorizationService.js`（CR-0040）：`getAuthorizedResidentIdsForCaregiver` 查 `status='active'` link；`assertCanAccessResident` / `filterAlertsByAuthorizedResidents`；pg seam。
- `adminAuthContext.js`（CR-0041）：`buildAuthContext` 解析 super_admin（共享 token / DB role∈admin,super_admin）/ caregiver（DB role=caregiver）；`findUserByFirebaseUid` 只 SELECT id, role；**未檢查 caregiver 是否停用**。
- `auditLogService.logAudit(input, options)`：白名單 actorType/actorId/action/targetType/targetId/outcome/metadata，DB-only-best-effort、絕不丟例外、PII 紅線——可直接重用（targetType 新增 `caregiver` / `resident_caregiver_link`）。
- `adminUsersService.js`：`SELECT_SAFE_USERS_SQL` 白名單 + `maskEmail` + `toSafeUser`，絕不回 password_hash/provider_user_id——provisioning 對外格式沿用同模式。
- super_admin-only 既有路由（`/api/admin/users`、`/api/admin/overview`、marketplace admin ×6）皆掛 `requireAdmin`（共享 token only）；caregiver-or-admin 路由掛 `resolveAdminAuthContext`。

#### 3. 關鍵設計裁決（6 點）
1. **caregiver status 模型 → 新增 migration 014 `users.status`（裁決：獨立欄，不復用 binding_status）。** `binding_status` 語意是長者端 Firebase 綁定（pending/verified），復用會污染語意且影響長者登入流程。新增 `users.status TEXT NOT NULL DEFAULT 'active'`（值域 active|inactive），`ADD COLUMN IF NOT EXISTS` 冪等，比照 006/013 寫法。**migration 014 需要**。無法對真 DB 跑 → 測試策略：migration 檔只做「冪等性 / 語法人工覆核」，service / 中介層一律以 mock pg seam 注入 rows 單測（沿用 `setPgForTest`），不要求真 Postgres。
2. **pending caregiver provisioning 與 firebase_uid 綁定 → 裁決：本案採「super_admin 顯式設定 firebase_uid」(路線 B)；「首次登入以 Firebase-verified email 自動認領」(路線 A) 拆為 FU-CR-0043a。** 理由：路線 A 會重開 CR-0041 的**登入解析路徑**（需把 decoded.email + email_verified 接進 `findUserByFirebaseUid`、處理多筆 / 未驗證 email 的劫持風險），逾本案最小切片且觸及 auth 主線。本案：`POST /api/admin/caregivers` 可建 pending caregiver（role=caregiver, firebase_uid=null, email 設定, status=active, **無密碼欄位**——路線 A 全程 Firebase，`users` 無 password_hash）；`PATCH /api/admin/caregivers/:id` 可後補 `firebaseUid`（caregiver 由 App/Firebase console 取得自己的 uid，經機構帶給 super_admin 設定）。綁定後該 caregiver 首次以 idToken 登入即被 `findUserByFirebaseUid` 命中→解析為 caregiver。**不明文密碼、不 fake token、不 hardcode**。FU-CR-0043a（email 自動認領）需嚴格：僅接受 `email_verified===true` 且唯一一筆 pending caregiver row，否則 403。
3. **管理 API middleware → 裁決：用 `requireAdmin`（共享 super_admin token only），與既有 super_admin-only 路由（users/overview/marketplace）一致。** 保證持有效 caregiver idToken 者**也進不來**（requireAdmin 只認字面 ADMIN_API_TOKEN，非匹配→403，連 idToken 驗證都不走）。fail-closed。**取捨（誠實標註）**：共享 token 無 per-actor 身分 → audit `actorType='super_admin'`、`actorId=null`（與現有 super_admin-only 路由同限制）。若未來要 DB-backed super_admin（role=admin via idToken）也能用這些管理路由，需另做 `requireSuperAdmin = resolveAdminAuthContext + assert role==='super_admin'` 包裝 → 列 FU，不進本案。
4. **inactive caregiver 即時失效 → 裁決：改 `adminAuthContext.js`（CR-0041 檔），在身分解析加「user.status==='inactive' → 403」閘。** 範圍最小且 fail-closed：`findUserByFirebaseUid` 的 SELECT 補 `status` 欄；`buildAuthContext` 取得 user row 後、**role 分派之前**，若 `status==='inactive'` 一律回 403 `admin_permission_required`（對 caregiver 與 DB-admin 皆適用，更安全）。共享 token 路徑（super_admin）不受影響（不查 DB）。**此為 CR-0041 owned 檔案改動 → 條件式核准 + 落地 checkpoint**。需補測試：inactive caregiver→403、active caregiver→照舊解析、status 欄不存在（舊 row, NULL）視為 active（向後相容）。
5. **scope refresh → 裁決：`authorizationService.js` 零改動即已涵蓋。** 新增 link（status='active'）→ 立即可見；停用 link（status→'revoked'）→ 查詢 `status='active'` 自動排除→不可見；inactive caregiver→由 #4 在身分層擋下（403，根本進不到 scope）；inactive link→同停用；super_admin→`isSuperAdmin` 早退不受限。**link 狀態詞彙裁決**：DB 維持 `active`/`revoked`（對齊 migration 013 + authorizationService 查詢 + 唯一索引），**不改 schema**；provisioning API 對外以 `active`/`inactive` 呈現，service 層做 `inactive↔revoked` 映射（停用 link = UPDATE status='revoked', revoked_at=NOW()）。避免任何 authorizationService 破壞。
6. **範圍 / 拆分 → 裁決：拆兩個 CR。CR-0043 = 後端（migration + provisioning service + 8 路由 + audit + adminAuthContext 閘 + 後端測試 + 文件）；CR-0044 = caregiver_web 兩個管理 UI（owner=frontend-ux-agent）。** 比照 CR-0041（後端正餐）/ CR-0042（前端收尾）成功模式：後端先固定契約並上綠，前端再消費。caregiver_web app.js 已 2646 行、tab 架構，新增兩個管理 view（caregiver 管理 + 授權指派）+ 表單 + 14+ 測試，體量足以獨立成 CR，且 owner 邊界不同。

#### 4. 影響範圍（檔案）
**CR-0043（backend-agent）**
- 新增 `backend/stt_proxy/db/migrations/014_add_users_status.sql`（🔒 schema，純新增欄、冪等）。
- 新增 `backend/stt_proxy/services/admin/caregiverProvisioningService.js`（建立/查詢/改/停用 caregiver；email 重複檢查；安全對外格式 + maskEmail；pg seam）。
- 新增 `backend/stt_proxy/services/admin/residentLinkProvisioningService.js`（建立/查詢/改/停用 link；resident+caregiver 存在性檢查；重複 active 防護；active↔revoked 映射；pg seam）。
- 新增對應 `*.test.js`（service 單元，mock pg）+ HTTP 層測試（沿用既有 endpoint test 模式）。
- 修改 `backend/stt_proxy/server.js`（🔒 API 契約 — **純新增** 8 條 super_admin-only 路由掛 `requireAdmin`，不動既有路由 / 回應形狀）。
- 修改 `backend/stt_proxy/services/admin/adminAuthContext.js`（🔒 CR-0041 auth 路徑 — 加 inactive 閘 + SELECT 補 status；附測試）。
- 修改 `backend/stt_proxy/package.json`（check + test script 納新檔）。
- `backend/stt_proxy/.env.example`：無新增 secret（僅文件註解，若需要）。
- 文件：`docs/CHANGE_REVIEW.md`（落地紀錄）、`docs/AUTHORIZATION_MODEL.md`（補 provisioning 段 + status 閘）、新增 `docs/CAREGIVER_PROVISIONING.md`。
- **不改**：`authorizationService.js`（#5 裁決零改動）、`/api/care-alerts/notify`、Realtime、Memory、Care Alert 既有回應形狀。

**CR-0044（frontend-ux-agent，子 CR，待 CR-0043 後端契約穩定後開）**
- `caregiver_web/app.js` / `index.html` / `styles.css`：新增「照護人員管理」「住民授權指派」兩個 super_admin-only view（caregiver 模式隱藏 / 顯示權限不足）；沿用 CR-0042 `adminAuthHeaders`（super_admin-only）+ 401/403/empty-state；操作成功/失敗友善提示；不顯完整 token / 敏感資料 / 假資料。
- `caregiver_web/auth_mode.test.js` 或新測試檔；`caregiver_web/README.md`；`docs/CAREGIVER_WEB_AUTH.md`（補管理頁）。

#### 5. 觸及 🔒？
**是。** 觸及三類受控線，但皆**新增 / fail-closed 閘、無既有契約破壞**：
- `db/migrations/014`（schema）：純 `ADD COLUMN IF NOT EXISTS users.status`，對既有 row 預設 active、零破壞。
- `server.js`（API 契約）：純新增 8 條 super_admin-only 路由；既有路由 / response 形狀 / 排序零變更。
- `adminAuthContext.js`（CR-0041 auth 主線）：新增 inactive 閘（更嚴格），不放寬任何既有判定。
→ **條件式核准 + 落地 checkpoint**（見 §8）。

#### 6. 牽涉 agent
- **backend-agent**：CR-0043 全部（migration + 2 services + 8 路由 + audit 接入 + adminAuthContext 閘 + 後端測試 + 後端文件）。
- **frontend-ux-agent**：CR-0044 子 CR（caregiver_web 兩管理 UI + 前端測試 + 前端文件），待 §7 B4 契約穩定後開。
- **architecture-agent**：本提案 + adminAuthContext / server.js 落地 checkpoint 覆核。
- companion-memory-agent / realtime-voice-agent：**不牽涉**（本案不碰陪伴策略 / Realtime）。

#### 7. 批次切分（CR-0043 backend，依序；每批可獨立回滾）
- **B1（migration only）**：`014_add_users_status.sql`。只建欄、冪等，不接任何 service。owner=backend-agent。低風險。
- **B2（provisioning services）**：`caregiverProvisioningService` + `residentLinkProvisioningService` + 單元測試（mock pg）。純新增、無路由、無 server.js。owner=backend-agent。低風險。
- **B3（adminAuthContext inactive 閘）**：改 CR-0041 檔 + 測試（inactive→403 / active→照舊 / NULL→active 相容）。owner=backend-agent。**條件式核准**（觸 auth 主線）。中風險。
- **B4（server.js 8 路由 + audit 接入 + HTTP 測試）**：caregivers ×4（GET/POST/PATCH/PATCH status）+ links ×4（GET/POST/PATCH/PATCH status 或 DELETE soft）掛 `requireAdmin`；每筆寫 `logAudit`。owner=backend-agent。**條件式核准**（觸 API 契約）。中風險。
- **B5（文件）**：CHANGE_REVIEW 落地紀錄 + AUTHORIZATION_MODEL + 新增 CAREGIVER_PROVISIONING.md。owner=backend-agent。低風險。
- 相依：B1→B2→B3→B4→B5。B4 完成且契約穩定 → 開 **CR-0044**（frontend-ux）。

#### 8. 落地 checkpoint 門檻（B3/B4，architecture-agent 覆核後方可結案）
- (a) 既有路由 200 形狀 / 排序 / 欄位**零變更**（care-alerts / elders / daily-care-tasks / users / overview / marketplace）。
- (b) 新增 8 路由皆 `requireAdmin`：無 token→401、caregiver idToken→403、共享 token→2xx；**caregiver 進不來**。
- (c) `/api/care-alerts/notify` 未觸及（仍無 authN）。
- (d) adminAuthContext inactive 閘：inactive caregiver→403、active→照舊、status NULL→視為 active（向後相容）；共享 token super_admin 路徑不受影響。
- (e) 停用 link 後 caregiver 立即看不到該 resident（scope refresh，authorizationService 未改仍成立）；重複 active link 不建第二筆。
- (f) API 回應**不含** token / password_hash / provider_user_id；email 經遮蔽（除非 super_admin 明示需要全 email，且仍不回敏感）。
- (g) audit：建立/停用/修改 caregiver 與 link 各寫一列，metadata 結構化、**無 token / email 原文 / PII**。
- (h) 無 hardcode caregiver/elder id、無 fake token、無 production 假身分、log 不印 token。

#### 9. 測試計畫（驗收門檻）
- backend：`cd backend/stt_proxy && npm run check && npm test`，CR-0041 後 **350 基線維持綠** + 新增（任務 §8.1 #1–#12）：caregiver 呼叫管理 API→403、無 token→401、super_admin 建 caregiver→2xx、重複 email→409、建 link→2xx、重複 active link 不建第二筆、停用 link 後 caregiver 看不到該 alert、inactive caregiver 讀 scoped API→擋、super_admin 看全部、audit 有寫、API 不回 token、invalid resident/caregiver id→400/404。
- **不可對真 DB / 真 Firebase**：全程 mock pg（`setPgForTest`）+ stub firebaseAdmin（沿用 CR-0041 seam）。migration 014 只人工覆核冪等性，不實跑。誠實標註未對真 Postgres / 真 Firebase 驗證。
- CR-0044：`cd caregiver_web && node --test *.test.js`，既有 69 綠 + 任務 §8.2 新增。

#### 10. 環境變數（僅列名稱，不碰值）
- 既有續用：`ADMIN_API_TOKEN`（super_admin 共享 token，management 路由 fail-closed）、`FIREBASE_PROJECT_ID` / `FIREBASE_CLIENT_EMAIL` / `FIREBASE_PRIVATE_KEY` / `GOOGLE_APPLICATION_CREDENTIALS`（caregiver idToken 驗證）、`AUTH_ALLOW_MOCK`、`APP_ENV` / `NODE_ENV`（production 守門）。
- **無新增後端 secret**。

#### 11. 紅線（本案全程，依任務 §10）
- 不破壞 `/api/care-alerts/notify`、Realtime、Memory、Care Alert 既有契約。
- 不 hardcode caregiver id、不 fake token；caregiver 不可自我授權、不可管理其他 caregiver（管理路由 super_admin-only）。
- inactive link/caregiver 不得當 active；停用即時生效。
- log / UI 不顯完整 token；audit metadata 無 PII。
- 不放寬 CR-0039/0040/0041 授權；不一次重寫 auth。

#### 12. 🔒 裁決（architecture-agent）
- **B1 核准**（純新增欄、冪等，零破壞）。
- **B2 核准**（純新增 service + seam，未改既有路由 / 契約）。
- **B3 條件式核准**（觸 CR-0041 auth 主線）：須落地 checkpoint §8(d)——inactive 閘 fail-closed、active 照舊、NULL 相容、共享 token 不受影響、無放寬既有判定。
- **B4 條件式核准**（觸 server.js API 契約）：須落地 checkpoint §8(a)(b)(c)(e)(f)(g)(h)——既有路由零變更、新路由 super_admin-only 擋 caregiver、/notify 未動、scope refresh 成立、不回敏感、audit 無 PII、無假身分。
- **B5 核准**（純文件；AUTHORIZATION_MODEL 跨契約段落先於 B4 對齊）。
- **CR-0044 另案裁決**（frontend-ux，待 B4 契約穩定後開）。
- **完成定義**：B1–B5 合併 + 測試綠 + B3/B4 checkpoint PASS。本案修 §12 #5 provisioning 層；**不宣稱** caregiver_web 管理 UI 已做（CR-0044）、不宣稱 email 自動認領已做（FU-CR-0043a）、不宣稱 /notify caller 驗證已修（FU-CR）。

#### 13. 殘留 / 下一個 CR
- **CR-0044**（frontend-ux）：caregiver_web caregiver 管理 + 授權指派 UI（super_admin-only）。
- **FU-CR-0043a**：caregiver 首次登入以 Firebase-verified email 自動認領 pending caregiver（重開登入路徑，需嚴格防劫持）。
- **FU**：`requireSuperAdmin`（resolveAdminAuthContext + assert role==super_admin）讓 DB-backed super_admin 也能用管理路由（目前僅共享 token）。
- **FU**：caregiver email 全域唯一（DB 層 unique index）——本案以 app-level SELECT 檢查（super_admin-only 低併發可接受，誠實標註競態窗口），未加 DB 約束以免衝撞既有 elder email。
- **FU-CR**：`/api/care-alerts/notify` caller 驗證（長者 session，正式版 blocker）。

#### 14. 落地紀錄（backend-agent，2026-06-08；B1–B5 執行）
- 狀態：**後端 B1–B5 落地，399/399 綠（CR-0041 後 350 基線維持綠 + 新增 49）**。caregiver_web 管理 UI（CR-0044）未做、email 自動認領（FU-CR-0043a）未做、`/notify` caller 驗證（FU-CR）未做——皆如裁決保留。**待 architecture-agent B3/B4 落地 checkpoint 覆核**。
- 新增檔案：
  - `backend/stt_proxy/db/migrations/014_add_users_status.sql`（B1，`ALTER TABLE users ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'active'`，冪等）。
  - `backend/stt_proxy/db/migration014.test.js`（靜態冪等覆核）。
  - `backend/stt_proxy/services/admin/caregiverProvisioningService.js` + `.test.js`（B2，pg seam）。
  - `backend/stt_proxy/services/admin/residentLinkProvisioningService.js` + `.test.js`（B2，pg seam，active↔revoked 映射）。
  - `backend/stt_proxy/services/admin/caregiverProvisioningEndpoint.test.js`（B4，HTTP 端到端，任務 §8.1 #1–#12）。
  - `docs/CAREGIVER_PROVISIONING.md`（B5）。
- 修改檔案：
  - `backend/stt_proxy/services/admin/adminAuthContext.js`（B3，SELECT 補 `status` + inactive 閘；`adminAuthContext.test.js` 加 6 測試，既有測試全綠）。
  - `backend/stt_proxy/server.js`（B4，純新增 8 條 super_admin-only 路由掛 `requireAdmin` + audit；既有路由 / response 形狀零變更）。
  - `backend/stt_proxy/package.json`（check + test 納新檔）。
  - `docs/AUTHORIZATION_MODEL.md`（§6.5 停用閘、§7 provisioning）、`docs/CAREGIVER_WEB_AUTH.md`、`caregiver_web/README.md`（標 CR-0043 後端完成 / CR-0044 前端未做）。
- 落地 checkpoint 自評（§8）：(a) 既有路由零變更（純新增，full suite 既有測試全綠）；(b) 8 路由皆 `requireAdmin`，無 token→401、caregiver idToken→403、共享 token→2xx（HTTP 測試覆蓋）；(c) `/notify` 未觸及；(d) inactive→403 / active→照舊 / NULL→active 相容 / 共享 token 不受影響（單元+HTTP 測試）；(e) 停用 link 後 caregiver 立即看不到（端到端測試）、重複 active link 不建第二筆；(f) 回應不含 token / password_hash / provider_user_id，email 遮蔽；(g) audit 每筆寫一列、metadata 無 PII / token（capture mock 驗證）；(h) 無 hardcode id、無 fake token、log 不印 token。
- 誠實標註：全程 **mock pg（`setPgForTest`）+ stub firebaseAdmin**；**未對真 Postgres / 真 Firebase 金鑰驗證**；migration 014 **未對真 DB 跑**（只靜態冪等覆核）。

#### 15. 落地 checkpoint 覆核（architecture-agent，2026-06-08；B3/B4 條件式核准結案）
- **裁決：PASS。** B1–B5 落地符合 §8 八項門檻與 §12 條件式核准要件；B3（adminAuthContext auth 主線）、B4（server.js API 契約）准予結案。覆核方式：read-only（git diff / grep / 檔案閱讀）+ architecture-agent 獨立重跑測試，未改任何程式碼。
- **獨立驗收（非僅採信回報）**：`npm run check` exit 0；`npm test` → tests 399 / pass 399 / fail 0（CR-0041 後 350 基線 + 49 新；既有斷言零調整）。測試 log 中的 stack trace 屬負路徑測試刻意觸發的錯誤記錄，非失敗。
- 八項門檻獨立覆核（對映使用者指派 a–h）：
  - (a) 管理 8 路由 super_admin-only：`server.js` 全掛 `requireAdmin`（grep 確認 1253/1263/1287/1313/1336/1346/1372/1394）；`requireAdmin.js` 只認字面 `ADMIN_API_TOKEN`，不走 idToken 驗證 → caregiver idToken 進不來。端點測試覆蓋 caregiver idToken→403、無 token→401（caregiverProvisioningEndpoint.test.js:295/309/578）。✅
  - (b) caregiver 不可自我授權 / 不可管理其他 caregiver：所有 provisioning 路由 super_admin-only（同 a），caregiver 角色無任何路徑寫 `users` / `resident_caregiver_links`。✅
  - (c) inactive caregiver→403 即時、inactive link→不授權：`adminAuthContext.js` 在 role 分派前加 `status==='inactive'→403` 閘（diff 確認）；`authorizationService.js` **git status 零改動**，`status='active'` 查詢自動排除 revoked link。端到端測試：建 link→看得到 alert→停用 link（DELETE=soft revoked）→看不到（caregiverProvisioningEndpoint.test.js:428）；inactive caregiver 讀 scoped API→403（:469）。✅
  - (d) super_admin 行為零變更 + 既有測試全綠：inactive 閘只在 DB-查詢路徑（caregiver/DB-admin）生效，共享 token super_admin 路徑不查 DB → 不受影響；server.js diff 僅兩個 hunk（require 區 +3 行、1199 後純新增 admin block +215 行），既有路由 handler 零觸及；399/399 既有斷言未動。✅
  - (e) API 不回 token/password_hash/provider_user_id、email 遮蔽：`toSafeCaregiver` 白名單只回 id/displayName/emailMasked/role/status/firebaseUid/createdAt/updatedAt（firebaseUid 為綁定識別、非 token/密碼）；`toSafeLink` 只回 id/residentId/residentName/caregiverId/caregiverName/role/status/時間，無 email 原文。`users` 無 password 欄（全程 Firebase）。✅
  - (f) audit 無 PII/token、actorId=null 合理：`auditProvisioning` 固定 `actorType='super_admin'`、`actorId=null`、metadata 僅結構化非敏感欄（bound/status/fields/role/reason）—無 email/token/PII。actorId=null 為共享 token 無 per-actor 身分之誠實標註（§3 #3），合理可接受。✅
  - (g) /notify / Realtime / Memory / Care Alert 契約未破壞：server.js diff 未觸及這些 handler（僅 require 區 + 新增 admin block）；`/api/care-alerts/notify` 維持無 authN（如 §8(c) 預期，仍列 FU-CR）。✅
  - (h) migration 014 additive+冪等、無 hardcode/fake token：`ALTER TABLE users ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'active'`，純加欄、可重跑；新檔 grep 無 sk-/token=/password= 等硬編祕鑰。✅
- **競態窗口裁決（B2 email app-level 唯一檢查，無 DB unique index）：可接受結案。** 理由：(1) 觸發面僅 super_admin-only 管理路由，單一管理者循序操作，實務並發極低；(2) 競態需兩個同 email 的 `POST /api/admin/caregivers` 落在 SELECT→INSERT 間隙，最壞結果 = 多一筆重複 caregiver row，**不跨任何安全邊界**（無權限升級、無跨住民記憶/alert 洩漏，scope 仍由顯式 link 控制）；(3) 不加 DB unique index 是為避免衝撞既有 elder email（`users.email` 無 UNIQUE，歷史資料可能重複），屬保守正確取捨。→ **裁定 CR-0043 不因此阻擋結案**，DB 層 unique index 收斂為下列 FU-CR-0043b。
- **完成狀態：✅ 完成（CR-0043 後端 B1–B5 落地，399/399 綠，architecture-agent B3/B4 落地 checkpoint PASS）。** 後續 commit 由使用者執行（architecture-agent 不自行 commit）。
- **明確標註殘留（不宣稱已做）**：
  - **CR-0044**（frontend-ux-agent）：caregiver_web caregiver 管理 + 授權指派 UI（super_admin-only），未做。
  - **FU-CR-0043a**：caregiver 首次登入以 Firebase-verified email 自動認領 pending caregiver（重開登入解析路徑，需嚴格防劫持），未做。
  - **FU-CR-0043b**：caregiver email 全域唯一之 DB 層 unique index（本案以 app-level SELECT 檢查、誠實標註競態窗口），未做。
  - **FU**：`requireSuperAdmin`（resolveAdminAuthContext + assert role==='super_admin'）讓 DB-backed super_admin 也能用管理路由（目前僅共享 token），未做。
  - **FU-CR**：`/api/care-alerts/notify` caller 驗證（長者 session，正式版 blocker），未做。
  - **未驗證**：全程 mock pg（`setPgForTest`）+ stub firebaseAdmin；**未對真 Postgres / 真 Firebase 金鑰驗證**；migration 014 **未對真 DB 跑**（僅靜態冪等覆核）。真 DB/Firebase 端到端驗證列為部署前 checklist，非本案 code-level blocker。

---

### CR-0044 — Caregiver Web Provisioning UI（super_admin-only；接 CR-0043 後端 8 路由）— ✅ 完成（2026-06-08）

- **owner**：frontend-ux-agent。**範圍**：caregiver_web 純前端，**未改後端**（server.js / Realtime / Memory / 授權規則零改動）。
- **目標**：補齊 caregiver_web 兩個 super_admin-only 管理頁，前端消費 CR-0043 provisioning 端點。
- **修改檔案**：
  - `caregiver_web/index.html`：新增 `tab-caregivers` / `tab-assignments` 兩入口、`view-caregivers` / `view-assignments` 兩 view、caregiver 表單 modal（`caregiver-overlay`）、授權表單 modal（`assignment-overlay`）。
  - `caregiver_web/app.js`：新增 `elCG` / `elAS` 元素快取；`loadCaregivers` / `renderCaregivers` / `submitCaregiverForm` / `toggleCaregiverStatus` / `loadAssignments` / `renderAssignments` / `populateAssignmentSelects` / `submitAssignmentForm` / `submitProvisioning` / `disableAssignment` / `enableAssignment` 等；`showView` / `applyAuthModeUi` / `currentViewName` / `reloadActiveView` / init 事件接線擴充；新增空狀態 / role 文案常數。
  - 文件：`caregiver_web/README.md`、`docs/CAREGIVER_WEB_AUTH.md`（§6）、`docs/CAREGIVER_PROVISIONING.md`。
  - 測試：`caregiver_web/caregiver_provisioning_ui.test.js`（新增，16 項靜態回歸）。
- **header 行為（紅線達成）**：provisioning 讀用 `adminAuthHeaders()`、寫用 `adminJsonHeaders()`（**只帶 super_admin token**）；不使用 caregiver scoped `authHeaders()` / `authJsonHeaders()`。caregiver 模式**隱藏入口且 `fetch` 前 `isCaregiverMode()` 早退（不發 management API request）**。
- **採用的 role enum**：**`primary` / `secondary` / `viewer`**（後端 migration 013 真值；任務書誤植的 `backup` 未採用，僅後端接受作 `secondary` alias）。
- **link 修改 / 停用 / 重新啟用對應後端實況**：`PATCH` 只支援改 role；停用走 `DELETE`（soft-disable→`status:'inactive'`）；後端**無 re-activate 端點**，UI「重新啟用」以相同 residentId+caregiverId+role 呼叫 `POST` 另建一筆有效授權（不改後端）。
- **401 / 403 / 空狀態**：401「登入已失效，請重新登入」（`handleSessionExpired`，停止重複請求）；403「目前帳號沒有權限查看此資料」（不清 token）；空 caregiver「目前尚無照護人員」、空授權「目前尚無住民授權指派」；select 來源為空時提示需先建立 caregiver / 住民資料。不顯 undefined / null / raw stack / 假資料。
- **測試結果**：`cd caregiver_web && node --test *.test.js` → tests 85 / pass 85 / fail 0（既有 69 全綠 + 新增 16）。後端未改，未跑 backend tests。
- **正式版風險自評**：caregiver 看不到 provisioning UI 且不發 API（✅）；provisioning 一律 admin header（✅）；無 hardcoded caregiver id / fake token（✅）；select 由後端真資料帶入、無假住民 / 假照護人員（✅）；UI / console 不顯完整 token（✅，無 `console.*` 印 token、無硬編 Bearer）；未改 backend（✅）。
- **殘留**：caregiver email 編輯無法預填（後端只回 `emailMasked`，留空＝不變更，屬後端契約限制）；授權「重新啟用」會留下舊的已停用 row 作稽核軌跡（後端無 re-activate 端點，非 bug）；caregiver_web 仍為靜態源碼檢查、無 DOM 測試環境（沿用既有測試策略）。

#### checkpoint 覆核（architecture-agent，2026-06-08；read-only，未改任何程式碼）
- **裁決：✅ 核准並驗收（PASS）。** CR-0044 純前端（caregiver_web + docs），**未觸 🔒**（backend/stt_proxy/server.js 路由與 response 形狀、DB schema / migration、Realtime 主流程、Care Alert 三方共用資料結構與分級欄位、Memory、授權規則、notify 全部零改動）。覆核方式：read-only（git status / git diff / grep / 檔案閱讀）+ architecture-agent 獨立重跑測試。
- **🔒 確認**：`git status --porcelain backend/` 為空（後端 0 行）；`git diff --stat` 改動僅 `caregiver_web/{index.html,app.js,README.md}` + `docs/{CAREGIVER_PROVISIONING,CAREGIVER_WEB_AUTH,CHANGE_REVIEW}.md` + 新增 `caregiver_web/caregiver_provisioning_ui.test.js`。`CLAUDE.md` / `ios/...Runner.xcscheme` / `PROJECT_REPORT_DRAFT.md` 為本案無關的既存工作區噪音，不屬 CR-0044，commit 時排除。
- **獨立驗收（非僅採信回報）**：`cd caregiver_web && node --check app.js` exit 0；`node --test *.test.js` → tests 85 / pass 85 / fail 0（69 既有基線維持綠 + 16 新；既有 dashboard / Care Alert / CR-0042 斷言零調整）。
- 七項門檻獨立覆核（對映使用者指派 a–g）：
  - (a) 未改 backend / server.js / Realtime / Memory / 授權規則 / notify：`git status backend/` 空、`git diff` 無後端檔。✅
  - (b) provisioning 一律 admin header、caregiver 模式絕不發 management request 且入口隱藏：provisioning 讀全走 `adminAuthHeaders()`（caregivers / resident-caregiver-links / elders GET）、寫全走 `adminJsonHeaders()`（POST/PATCH/DELETE 與 status），皆 super_admin token，無一處用 caregiver scoped `authHeaders()/authJsonHeaders()`；每個 provisioning 函式 `fetch` 前 `if (isCaregiverMode() ...) return` 早退（app.js 2619/2767/2843/2918/3177/3195/3213/3291/3334）；`applyAuthModeUi` 對 `elCG.tab`/`elAS.tab` `classList.toggle("hidden", caregiver)` 且 caregiver 停在 super_admin-only view 時 `showView("alerts")` 反彈。雙重保護。✅
  - (c) 無 console.* 印 token、無硬編 Bearer：`grep -nE "console\.(log|debug|info|warn|error)" app.js` 零命中（全檔無 console 語句）；`Bearer` 僅出現在 header helper 以 runtime `getActiveToken()/getAdminToken()` 串接，無字面 token。✅
  - (d) 無 hardcode caregiver id、無假住民 / 假照護人員填 select：`populateAssignmentSelects` 由 `GET /api/admin/elders` + `GET /api/admin/caregivers`（真資料）填入，任一來源為空時清楚提示需先建資料並 `save.disabled=true`，不以假資料補。✅
  - (e) role enum 用後端真值 primary / secondary / viewer：`ROLE_LABELS = {primary, secondary, viewer}`（對齊 migration 013），預設 fallback `"primary"`；任務書誤植的 `backup` 未採用。✅
  - (f) 空狀態 / 401 / 403 沿用 CR-0042、不顯 undefined / null / raw stack：401→`handleSessionExpired` + 「登入已失效」、403→`FORBIDDEN_MSG`（不清 token）、空狀態走 `EMPTY_*` 常數；render 全程 `escapeHtml`、`l.role || "primary"` 等保底，無 raw error 外洩。✅
  - (g) 既有 dashboard / Care Alert / CR-0042 測試未破壞：85/85 綠，含「長者端文案不外洩工程訊息」「商品 / 訂單管理帶 Admin 權杖」等既有案全通過。✅
- **兩個契約限制裁決：可接受結案。**
  - email 編輯留空＝不變更：後端 `toSafeCaregiver` 只回 `emailMasked`（不回原文，正確隱私設計），前端無從預填屬**後端契約必然**，非 bug。以文件標註結案，若日後要支援可開 **FU-CR-0043a**（caregiver 首次登入以 Firebase-verified email 自動認領）順帶收斂。
  - 重新啟用＝另建 active row（舊 row 留稽核）：後端 CR-0043 無 re-activate 端點（DELETE 為 soft→`inactive`），UI 以相同 resident+caregiver+role `POST` 另建一筆，舊列保留為稽核軌跡，**不跨安全邊界、不破壞授權 scope**。可接受結案；如要單列復用可開可選 **FU-CR-0044a**（後端新增「重新啟用 link」端點 + 前端改呼叫）。
- **完成狀態：✅ 完成（CR-0044 caregiver_web provisioning UI 落地，85/85 綠，architecture-agent checkpoint PASS，未觸 🔒）。** commit 由使用者執行（architecture-agent 不自行 commit）。
- **明確標註殘留（不宣稱已做）**：
  - **行為層測試**：caregiver_web 仍為靜態源碼回歸，無 DOM / headless 互動測試環境（沿用既有策略，非本案 blocker）。
  - **FU-CR-0043a**：caregiver 首次登入 email 自動認領（順帶解決編輯預填），未做。
  - **FU-CR-0044a（可選）**：後端「重新啟用既有 link」端點，使 UI 復用單列而非另建，未做。
  - **未驗證**：未對真 Postgres / 真 Firebase / 真 super_admin token 端到端驗證；provisioning UI 與後端 8 路由之實連屬部署前 checklist，非 code-level blocker。

---

### CR-0045 — Care Alert Notify Caller Authentication（Audit P0-2 殘留收斂；接 CR-0039–0044 授權鏈；正式上架 BLOCKER）
- 提出 / 裁決 agent：architecture-agent（依使用者指派；CR-0039 §11 / AUTHORIZATION_MODEL §8 明列之 FU-CR「/notify caller 驗證」正式化）
- 狀態：**提案 + 裁決完成，待派工落地**（本筆為規劃 / 裁決紀錄，未改業務碼）
- 帳本正規 ID = **CR-0045**（沿用 CR-0039 §0「下一個空號」治理）

#### 1. 動機（為何現在做）
- `POST /api/care-alerts/notify` 是長者端 App 從 Realtime 對話建立 Care Alert + 觸發 Telegram 的核心路徑，CR-0039 起**刻意保留無 auth**（長者端不持 admin token，掛 requireAdmin 會打斷核心流程）。
- 現有緩解：`globalLimiter` + Care Alert cooldown + `invalid_payload` 形狀檢查 + Telegram 僅 high/urgent。但正式版不能允許未驗證端任意 POST 偽造警示 / spam Telegram（Audit P0-2 殘留、CR-0039 §11 明列 blocker）。
- 既有缺口（順帶修）：/notify 目前**不收 elderId** → 經此路徑建立的 alert 多為 `elderId=null`，使 CR-0040 resident scope 對這些 alert 形同無關聯。本案以「由 token 推導 elderId 並蓋上」一併修復。

#### 2. 盤點覆核（architecture-agent 已驗證）
- **Schema**：`users.elder_id UUID REFERENCES elders(id)`（migration 006）— 已存在「Firebase user → 自己的 elder」唯一綁定。token→firebase_uid→users.elder_id 即為 alert 擁有者，無需新欄位 / 新 migration。
- **後端可重用件**：`adminAuthContext.js`（CR-0041）已有 idToken→firebase_uid→users row 驗證（含 `mockAllowed()` production 守門、CR-0043 status 停用閘、`setFirebaseAdminForTest`/`setPgForTest` seam）。但其輸出語意為 admin/caregiver（elder 角色 → 403），**不能直接複用為 resident caller**；可抽共用 primitive。
- **/notify handler**（server.js ~398–470）：response 形狀 `{success, telegram}`；persist 與 Telegram 解耦；cooldown key=`source::riskLevel`；notification_logs 結構化白名單。本案須**完全保留**此形狀與規則。
- **careAlertStoreService**：`normalizeAlert` 的 `elderId = payload.elderId ?? null`。本案改由 handler 在 saveCareAlert 前以 token 推導的 elderId 覆蓋 body.elderId。store 契約 0 改動。
- **Flutter**：`care_alert_notification_service.dart` `notify()` 目前 body 不含 elderId、不帶 Authorization、fire-and-forget 全 try/catch（非 200 / 網路錯誤只 debugPrint，不 throw、不阻斷 Realtime 與本機 CareAlert）。Provider 為 `CareAlertNotificationService()` 裸建（app.dart:111），無 auth 注入。呼叫點唯一在 `voice_agent_controller.dart:890`（`_maybeCreateCareAlert` 旁路，非狀態機）。
- **Flutter token**：`firebase_auth_service.currentUserAuthInfo()` / `user.getIdToken()` 可取新 idToken；`AuthService` mock 登入用 `idToken: 'mock-id-token-<uid>'`（非真 token）。AuthController authMode = firebase | mock（CR-0006/0041）。

#### 3. 影響範圍（檔案）
- 後端（owner=backend-agent）：
  - 新增 `backend/stt_proxy/services/auth/residentCallerContext.js`（`resolveResidentCallerContext` / `requireResidentCaller`，新檔）。
  - 共用 primitive 抽取（見 §5）：`backend/stt_proxy/services/admin/adminAuthContext.js` 的 `findUserByFirebaseUid` →（可選）抽到共用模組；**adminAuthContext 對外行為須 byte-identical**（CR-0041 350 測試回歸守）。
  - 🔒 `backend/stt_proxy/server.js`：`/api/care-alerts/notify` 掛 `requireResidentCaller` + 以 token-derived elderId 覆蓋 body。
  - 測試：新增 resident-caller 單元 + /notify HTTP 層（比照 `careAlertAuthScopeEndpoint.test.js`）。
- 前端（owner=frontend-ux-agent）：
  - `lib/services/care_alert_notification_service.dart`：`notify()` 帶 `Authorization` header；新增 `authTokenProvider` 注入。
  - `lib/app.dart:111`：`CareAlertNotificationService` 注入 token 取得器（從 AuthController / firebase auth）。
  - （如需）`lib/controllers/auth_controller.dart` / `lib/services/auth/firebase_auth_service.dart`：暴露 `getFreshIdToken()` 存取器。
  - Flutter 測試：notify 帶 header / 取 token 失敗不送 / 401·403 可接受處理 / log 不顯 token。
  - **`lib/controllers/voice_agent_controller.dart` 不改**（見 §6 設計：token 由 service 建構注入，呼叫點維持 byte-identical）。
- 文件：`docs/CHANGE_REVIEW.md`（本筆）、`docs/AUTHORIZATION_MODEL.md`（§8 殘留改為已收斂 + 新增 resident-caller 段）、`.env.example`（若需註記，僅變數名）、（可選）新增 `docs/CARE_ALERT_NOTIFY_AUTH.md`。

#### 4. 觸及 🔒 與牽涉 agent
- 🔒 **server.js /notify 路由 + 行為契約**：是（高風險主線）。response 形狀（`{success, telegram}`）、persist/cooldown/notification-log 規則**不得變**；只在最前面加 caller gate、並在 persist 前覆蓋 elderId。
- 🔒 **Care Alert 三方共用資料結構**：elderId 由「多為 null」變「token 推導非 null」——**填值，不改欄位 / 不改 schema / 不改 store 契約**。屬正向收斂，非破壞。
- **DB schema / migration**：不觸及（users.elder_id 已存在）。
- **Realtime 主流程 / Memory**：不觸及（notify 為旁路 fire-and-forget，呼叫點不動）。
- 牽涉 agent：backend-agent（主）、frontend-ux-agent。**不需 realtime-voice-agent**（見 §6）。

#### 5. 六項核心裁決
1. **caller 身分機制 — 核准**：/notify 改用 Firebase idToken bearer → firebase_uid → users row → **users.elder_id** 為 alert 擁有者。**由 token 推導 elderId 並覆蓋 body**（server-authoritative，防偽造），順帶修 elderId=null 缺口。
   - **共用 verifier 重構 — 核准（受限）**：新建 `residentCallerContext.js`（`resolveResidentCallerContext`/`requireResidentCaller`），**重用** firebaseAdmin verify + `findUserByFirebaseUid` + `mockAllowed()` 守門 + CR-0043 status 停用閘 + 既有 test seam 模式。允許將 `findUserByFirebaseUid`（含可選 status 欄位）**抽成共用小模組**供兩者引用，但 **adminAuthContext 對外行為必須 byte-identical**（CR-0041 350 測試為回歸守門）；不在本案改寫 adminAuthContext 的角色分派語意。更深層的 admin/resident verify 統一列為 FU，不在本案。
   - resident caller context 形狀：`{ userId, firebaseUid, elderId, role:'resident', isSuperAdmin:false }`，其中 `elderId = users.elder_id`。`users.elder_id` 為 null → **403 `resident_not_linked`**（fail-closed：無 elder 綁定者不可建 alert）。
2. **demo/mock 不破壞核心流程 — 核准（三道保險，同 AUTHORIZATION_MODEL §6）**：
   - production（`mockAllowed()===false`）：**強制真 idToken + 真 users row + 非 null elder_id**；無 token / invalid → 401，無權 / 查無 → 403。fail-closed。
   - dev/test（`mockAllowed()===true`，由 `AUTH_ALLOW_MOCK`/`APP_ENV`/`NODE_ENV` 守門）：允許 mock caller 路徑，仍須由（stub/dev）verifyIdToken 解析出 uid，讓 demo 仍能建 alert。
   - **dev 與 admin 的刻意差異（明列）**：admin 路徑 dev mock 仍要求真 users row（§6 #3）；但長者 demo 常跑於**無 DB / JSON 模式**，要求 users row 會打斷 demo。故裁決：**dev + mockAllowed + 查無 users row** 時，resident verifier 可由 verified uid 推導 scoping elderId（dev-only seam，對齊 Flutter AuthController 已以 `session.elderId` 逐帳號隔離的做法）。**此寬鬆僅限 mockAllowed；production 恆 false → 必走真 token + 真 row**。嚴禁 production fake token / hardcoded resident。
3. **caregiver / super_admin 代建 notify — 不納入（裁決）**：本路徑 caller **僅長者本人（resident self）**。理由：alert 由長者自己的 Realtime 對話觸發，caregiver/super_admin 無對話可觸發、代建非必要且擴大攻擊面。若日後有需求 → 另開 FU-CR 並走 `resident_caregiver_links` 檢查 + 明確測試。本案 super_admin 共享 token 命中 /notify → 視為非 resident caller → **不放行（403 或不適用該路徑）**，由落地測試固定。
4. **resident ownership — 核准（hybrid，server-authoritative）**：
   - body **無 elderId** → 用 token 推導之 elderId（填 null 缺口）。
   - body **有 elderId 且 == token 推導** → 放行。
   - body **有 elderId 且 != token 推導** → **403 `forbidden_resident`**（防偽造 + 滿足驗收 §10.3「resident 不符→403」）。
   - 一律以 token 推導之 elderId 寫入 alert（client 值僅用於一致性檢核，永不採信為擁有者）。
   - **建議 Flutter 不送 elderId**（server 推導即可），避免 403 誤殺。
5. **Flutter token 取得 — 核准**：
   - firebase 模式：呼叫 `getIdToken()` 取**新** token → `Authorization: Bearer <idToken>`。
   - mock/demo 模式：無真 token → 送現有 `mock-id-token-<uid>`（dev 後端 mock 路徑接受）；**production 不會在 mock 模式**。
   - notify 維持 fire-and-forget：401/403 不 throw、不阻斷 Realtime、本機 CareAlert 照常保留。production firebase 模式若取 token 失敗 → **不送 notify**（不發無 auth 請求），記長者友善狀態，本機 alert 仍在。
   - log 不顯 token。
6. **範圍 / 拆分 — 核准：單一 CR-0045，三批，不拆子 CR**（後端是核心、前端薄）。批次見 §7。

#### 6. Flutter 注入設計（避免動到 realtime-voice 範圍）
- token 取得器於 **建構期注入** `CareAlertNotificationService`（app.dart:111，frontend-ux 範圍），`notify()` 內部自取新 token 加 header。
- `voice_agent_controller.dart:890` 呼叫點維持 `notify(sttProxyUrl, alert)` **byte-identical** → 不觸 realtime-voice controller、不碰狀態機 / SDP / DataChannel。**故本案不需 realtime-voice-agent 派工**。

#### 7. 批次切分（owner / 順序 / 相依）
- **B1（backend-agent）**：新建 `residentCallerContext.js`（`resolveResidentCallerContext`/`requireResidentCaller`）+（可選）抽共用 `findUserByFirebaseUid`。純模組 + 單元測試（無 token 401 / invalid 401 / mockAllowed 守門 / status 停用 / elder_id null→403 / dev no-row seam）。**不 wiring**。🔒 無（新檔；抽取若動 adminAuthContext 須回歸 CR-0041 350 綠）。
- **B2（backend-agent）**：把 `requireResidentCaller` 掛上 `/api/care-alerts/notify`；persist 前以 token-derived elderId 覆蓋 / 檢核 body.elderId（mismatch→403）；**完全保留** persist/cooldown/notification-log/`{success,telegram}` 形狀。HTTP 層測試（§9 #1–#12）。🔒 server.js /notify（**最高風險批**，落地後須 architecture-agent checkpoint）。
- **B3（frontend-ux-agent）**：`care_alert_notification_service` 加 `authTokenProvider` + Authorization header；app.dart 注入；（如需）auth 暴露 `getFreshIdToken()`；mock 模式送 mock token。Flutter 測試（§9 Flutter 段）。相依 B2 的 header 契約凍結後進行。
- **順序**：B1 → B2 →（B2 契約凍結後）B3。B1+B2+B3 合併 + 測試綠 + checkpoint PASS = CR-0045 完成。
- **不拆子 CR**（與 CR-0041 拆 CR-0042/0043 不同：本案前端薄、無獨立 UI 子系統）。

#### 8. 環境變數（只列名稱，無新增 secret）
- production 守門（既有）：`AUTH_ALLOW_MOCK`、`APP_ENV`、`NODE_ENV`。
- Firebase 服務帳戶（與長者 / caregiver auth 共用，既有，擇一）：`GOOGLE_APPLICATION_CREDENTIALS`，或 `FIREBASE_PROJECT_ID` + `FIREBASE_CLIENT_EMAIL` + `FIREBASE_PRIVATE_KEY`。
- **無新增後端 secret**（路線 A，不需 JWT_SECRET / SESSION_SECRET）。

#### 9. 測試計畫（不可對真 DB / 真 Firebase 跑）
- 後端 seam：`residentCallerContext.setFirebaseAdminForTest(stub)`（注入 isConfigured/verifyIdToken）、`setPgForTest(mockPg)`（users 查詢回 role/elder_id/status）、`careAlertStoreService.setPgForTest`、Telegram 發送 stub/spy；HTTP 層比照 `careAlertAuthScopeEndpoint.test.js`。
- 後端案（§7.1）：無 header→401 / invalid→401 / valid 但查無 users row→（production 403、dev seam 放行）/ resident 自建→200 原契約 / resident A 建 B（body elderId 不符）→403 / 未授權不建 alert / 未授權不觸發 Telegram / high·urgent 授權仍通知 / cooldown 仍生效 / low 仍依規則不推 / production 不收 fake token / response 不含 token·sensitive error。
- Flutter seam：注入 `http` MockClient + stub `authTokenProvider`；案：notify 帶 Authorization / 取 token 失敗不送 / 401·403 不 throw 且不破壞本機 alert / log 不顯 token。

#### 10. 風險
- **High（B2，server.js /notify 主線）**：錯誤即（a）打斷長者建 alert 成功路徑、或（b）放行未驗證 caller。緩解：B1 純模組先綠 → B2 小範圍掛載 + 保留 response 形狀 + HTTP 層全案 + 落地 checkpoint 覆核（CR-0039/0040/0041 回歸 + /notify 形狀不變 + 無 production 假 caller）。
- **Medium（整體）**：dev mock seam 若洩入 production = 漏洞 → 由 `mockAllowed()` 三道保險擋（production 恆 false）。

#### 11. 必守紅線（任務 §9，裁決確認全數納入）
不破壞長者端建 Care Alert 成功路徑、不破壞 Realtime / Memory、不移除 cooldown、production 不放行未驗證 caller、不 hardcoded resident、不 fake token 過 production、log 不顯完整 token、不把所有 authenticated user 當可為任意 resident 建 alert、不為過測試關閉通知。保留 low/medium/high/urgent 規則 + cooldown + notification log + Care Alert store 契約 + `{success,telegram}` response 形狀。

#### 12. 裁決
- **✅ 核准本案（CR-0045）依 §5 六項裁決 + §7 三批（B1→B2→B3）落地，不拆子 CR，不需 realtime-voice-agent。**
- 🔒 server.js /notify 改動：**條件式核准**——B2 落地後須 architecture-agent checkpoint 覆核（CR-0039/0040/0041 回歸綠 / `{success,telegram}` 形狀不變 / persist·cooldown·notification-log 規則不變 / production fail-closed 真 token+真 row / 無 hardcoded resident / 無 fake token / log 無 token / elderId 由 token 推導）方可結案。
- AUTHORIZATION_MODEL §8 之「FU-CR：/notify caller 驗證」於本案結案後改標為已收斂。

#### 13. 落地紀錄（B1 + B2，backend-agent）
- **B1**：新建 `backend/stt_proxy/services/auth/residentCallerContext.js`
  （`resolveResidentCallerContext` + `requireResidentCaller`）+ 共用測試 stub 安裝器
  `residentCallerContext.testsupport.js` + 純單元測試 `residentCallerContext.test.js`（11 案）。
  **未抽共用 `findUserByFirebaseUid`**：residentCallerContext 自帶（SELECT 多取 `elder_id`），
  `adminAuthContext.js` **完全未改（git byte-identical）**，CR-0041 既有測試照常綠。
- **B2**：`server.js` `/api/care-alerts/notify` 前掛 `requireResidentCaller`；handler 在 persist 前
  以 caller context 的 elderId 蓋寫 / 檢核 `body.elderId`（不符→403 `forbidden_resident`）。
  persist / cooldown / notification-log / `{ success, telegram }` response 形狀**未改**。
  新增 HTTP 層測試 `careAlertNotifyAuthEndpoint.test.js`（§7.1 #1–#12）。
- **既有 /notify 測試調整**：因加驗證，原本「無 auth → 200」的 seeding 測試改為帶 resident
  idToken（透過 testsupport stub）。受影響檔：`careAlertNotifyEndpoint`、`careAlertListEndpoint`、
  `careAlertStatusEndpoint`、`notificationAuditEndpoint`、`careAlertDemoFlow`、
  `careAlertAuthScopeEndpoint`（postNotify 依 elderId 帶對應住民 token；原
  「super_admin /notify 無需 auth → 200」改名為「resident 帶 idToken → 200」並新增「無 token→401」）、
  `admin/caregiverProvisioningEndpoint`。
- **測試結果**：`npm run check` 綠；`npm test` 424 pass / 0 fail（既有 + 新增）。
  **未對真 DB / 真 Firebase 驗證**（全程 mock pg + stub firebaseAdmin + Telegram spy）。
- **待 architecture-agent checkpoint**（§12 條件式核准）後結案；Flutter B3 另案。

#### 14. 落地 checkpoint 覆核（architecture-agent，§12 條件式核准之履行）
- **裁決：✅ PASS — B1 + B2 可結案**（B3 Flutter header 另案待做）。read-only（git diff / grep / 獨立 `npm run check` + `npm test`）覆核，未對真 DB / 真 Firebase 跑。
- **(a) /notify 成功契約零變更**：`server.js` diff 僅兩處 hunk —（i）import `requireResidentCaller`、（ii）route 前掛中介層 + persist 前的 elderId 蓋寫/檢核區塊。persist / cooldown / notification-log / low·medium·high·urgent / `{success,telegram}` 形狀程式碼一字未動。測試 #4（`{success:false, telegram_not_configured}` 形狀不變）、#8（urgent→`{success:true}` + 1 次外連）、#9（cooldown→`skipped_cooldown`、僅 1 次外連）、#10（low→`{success:true, telegram:"skipped_low_risk"}`、0 次外連、仍持久化）佐證。
- **(b) production fail-closed**：模組 L119（未 configured + `!mockAllowed`→401）、L132（查無 row + `!mockAllowed`→403）。測試 #11（production + 未 configured firebase→401，且事後 listAlerts 為空）佐證；dev-only seam（L137–140 uid 推導 elderId）僅 `mockAllowed()===true` 生效，production 恆 false（三道：`AUTH_ALLOW_MOCK` / `APP_ENV` / `NODE_ENV`）。
- **(c) 未授權不建 alert、不觸發 Telegram**：Telegram spy（攔截 `api.telegram.org` 計數）驗證——#6（無 auth high/urgent→401、spy 0 次、listAlerts 空）、#7（forged token→401、spy 0 次）；#1/#2/#5 另以 listAlerts 為空確認不建 alert。
- **(d) server 權威 elderId**：handler `body.elderId = callerElderId ?? bodyElderId ?? null`，一律以 token 推導值寫入；client 值僅供一致性檢核。#5（resident A 帶 B 的 elderId→403 `forbidden_resident`、不建 alert）、#5b（帶自己 elderId 相符→200）、#4（不帶 elderId→server 填 token 推導 = ELDER_A）佐證。
- **(e) 無 hardcoded resident / 無 fake token 過 production / log 不顯 token / 錯誤不暴露 Firebase detail·stack**：模組無寫死住民；fake token 於 production 被 L119/L132 擋（#11）；`requireResidentCaller` catch 之 `console.error` 僅印 `error.message`（L177，不印 token）；#12 斷言 401 body 不含原 token 字面值、不含 `stack|Error:|firebase`，403 body 僅 `{success:false, error:"forbidden_resident"}`。
- **(f) adminAuthContext.js byte-identical**：`git diff` 空輸出確認；CR-0039/0040/0041/0043 既有測試（authScope / list / status / audit / demoFlow / provisioning / adminAuthContext）全綠。
- **(g) 既有 /notify 測試調整裁決：合理（加驗證後 seeding 帶 token），非放寬授權**：受影響檔僅在 postNotify seeding 加 resident idToken header（透過 testsupport stub），斷言主體不變。`careAlertAuthScopeEndpoint` 的「super_admin /notify 無需 auth→200」改為「resident 帶 idToken→200」**並新增「無 token→401 且不建 alert」**——屬授權收斂（tighten），非放寬。`careAlertNotifyEndpoint` 的 invalid_payload 測試帶 token 後仍回 400，佐證「中介層先於 payload 驗證」之順序正確。**無任何「為過測試關閉通知 / 降授權」之調整。**
- **獨立覆驗**：`npm run check` 綠；`npm test` → tests 424 / pass 424 / fail 0（與 backend-agent 回報一致）。`git diff backend/stt_proxy/services/admin/adminAuthContext.js` 空。
- **殘留（明確標註）**：
  - **B3（Flutter）未做**：長者端 `/notify` 呼叫尚未帶 `Authorization: Bearer <idToken>`。**正式 build 一旦關閉 mock（production `mockAllowed()===false`），長者端建 Care Alert 會被 401/403 擋住** → B3 為正式上架 BLOCKER，須於 production flavor 啟用前完成。dev / mock 環境不受影響（現況 demo 可跑）。
  - **未對真 DB / 真 Firebase 驗證**：全程 mock pg + stub firebaseAdmin + Telegram spy；真實 Firebase idToken 驗證、`users.elder_id` 真資料路徑、Telegram 真外送未在 CI 覆蓋（與既有 auth 測試策略一致，屬已知邊界）。
- **結論**：§12 之 🔒 server.js /notify「條件式核准」其覆核條件全數滿足 → **B1 + B2 結案**。CR-0045 整體待 B3 合併後總結案；AUTHORIZATION_MODEL §8「FU-CR：/notify caller 驗證」於 B1+B2 結案後可標為已收斂（B3 僅補前端 header，不影響後端授權結論）。

#### 15. 落地紀錄（B3 Flutter 長者端 /notify 帶 Authorization，frontend-ux-agent）— 執行進度 ✅
- `lib/services/care_alert_notification_service.dart`：建構子加 `authTokenProvider`（`Future<String?> Function()`）；notify() 先取 token，組 `Authorization: Bearer <token>`；token null/空→不送 POST（避免必然 401）；維持 fire-and-forget（token 取得失敗 / 401 / 403 / 網路錯誤都不 throw、不阻斷 Realtime 與本機 CareAlert；log 不印完整 token）；body 不含 elderId（server 由 token 推導）。
- `lib/controllers/auth_controller.dart`：新增 `resolveNotifyAuthToken()`——正式帳號(email/google/apple)→取「新」Firebase idToken（`AuthService.currentIdToken()`→`FirebaseAuthService.currentIdToken()` 用 `user.getIdToken()` 續期）；Demo/未登入→非 production 回 `mock-id-token-<currentUserId>`、**production 一律回 null（不偽造身分）**；全程 try/catch 不 throw、不記錄完整 token。
- `lib/services/auth/auth_service.dart` + `firebase_auth_service.dart`：加 `currentIdToken()` 封裝（Firebase 不可用 / 無 currentUser / 取得失敗→null，不 throw）。
- `lib/app.dart`：`CareAlertNotificationService` 的 Provider **由原第 111 行（AuthController 之前、讀不到 AuthController）移到 AuthController 之後（第 123 行）**，注入 `() => context.read<AuthController>().resolveNotifyAuthToken()`。
- 測試：`test/services/care_alert_notification_service_test.dart`（13 案，含 firebase/mock header、token=null 不送、provider 丟例外略過、401/403 不阻斷、log 不顯完整 token、body 不含 elderId）。
- **驗收（frontend-ux-agent 自驗）**：`flutter analyze`（5 改動檔）No issues found；`flutter test` → care_alert_notification_service 13/13、auth_controller 27/27、voice_agent_controller_realtime_lifecycle 23/23 綠。

#### 16. B3 落地 checkpoint 覆核（architecture-agent）
- **裁決：✅ PASS — B3 結案；CR-0045 全案（B1+B2+B3）總結案。** read-only（`git diff` / `grep`）覆核，未跑整包 flutter test、未對真 DB / 真 Firebase 端到端聯調。
- **(a) Realtime 主線零觸碰**：`git diff HEAD -- lib/services/realtime_voice_service.dart lib/controllers/voice_agent_controller.dart` 空輸出 → 兩檔 byte-identical；呼叫點 / 狀態機 / SDP / DataChannel 一字未動。`voice_agent_controller.dart:64`（`CareAlertNotificationService?` 欄位）為既有，未變。
- **(b) fire-and-forget 維持**：notify() 全段 try/catch；token 取得另包一層 try/catch（例外→null）；token null/空→`debugPrint` 後 `return`，不送 POST；後續非 200（含 401/403）/ success:false / 網路錯誤沿用既有吞錯路徑，不 throw、不阻斷 Realtime 與本機 CareAlert。production demo/未登入 → `resolveNotifyAuthToken()` 回 null → 不送、不偽造。
- **(c) header 行為正確**：firebase 真帳號→`Bearer <新 idToken>`（每次 `getIdToken()` 續期、不用舊存）；mock→`Bearer mock-id-token-<uid>`。測試三案（mock-id-token-default_user / 真 idToken / mock-id-token-elder_42）斷言 `Authorization` 值佐證。
- **(d) app.dart provider 位移 — blast radius 可接受**：原位於 AuthController **之前**（closure 內 `context.read<AuthController>()` 會讀不到），移到 AuthController **之後**為正確修正。全專案 `CareAlertNotificationService` consumer 僅 `lib/app.dart` 三處 `context.read`（行 232 / 347 / 366），皆位於 MultiProvider 子樹深處（遠在新宣告位置 123 下游），**無任何上游 consumer 受位移影響**；注入的 closure 為 lazy（notify() 時才讀 AuthController），建立順序亦安全。其餘 provider 樹未動。**位移安全。**
- **(e) 無 token 外洩 / 無 hardcoded token / production 不 fake**：service 與 auth 兩處 `debugPrint` 均不含 token 字面；測試「debug log 不顯示完整 token」以 401 分支斷言 log 不含 secret。`eyJ...` 僅出現在測試 fixture，非程式碼寫死。production fake 由 `resolveNotifyAuthToken()` 的 `AppConfig.isProduction → null` 封死（`app_config.dart:13`）。
- **(f) 既有 Flutter 測試未破壞**：frontend-ux-agent 自驗 analyze 乾淨 + 三組相關測試綠（care_alert 13 / auth_controller 27 / realtime lifecycle 23）；architecture-agent **未重跑整包 flutter test**（誠實標註，見殘留）。
- **AUTHORIZATION_MODEL §8「FU-CR：/notify caller 驗證」總標收斂**：B1+B2 後端授權鏈 + B3 前端 header 全到位，正式 build 關閉 mock（production `mockAllowed()===false`）後長者端 `/notify` 可帶真 idToken 通過驗證，CR-0045 BLOCKER 解除。§8 該項標為**已收斂**。
- **殘留（明確標註）**：
  - **未對真 DB / 真 Firebase 端到端聯調**：Flutter 端真 `getIdToken()` → 後端真 Firebase 驗證 → `users.elder_id` 真資料 → Telegram 真外送之完整鏈路未在自動化覆蓋（前後端各自 mock / stub，與既有測試策略一致）。建議正式 flavor 啟用前手動端到端 smoke 一次。
  - **整包 `flutter test` 未跑**：僅跑相關三組測試；建議下次 CI 全量回歸。
- **結論**：CR-0045 三批（B1 後端 caller context + B2 server.js /notify 掛驗證 + B3 Flutter header）全數 PASS，**CR-0045 全案完成結案**。

---

### CR-0046 — Store Readiness and Production Platform Hardening（雙平台上架前平台設定 + 商店/隱私文件；不碰授權鏈/Realtime/Memory/notify auth）
- 提出 / 裁決 agent：architecture-agent（依使用者指派；接 CR-0033 §11 / §12 第 11–14 項與 P1-5 / P2-3 / P3-1 / P3-2 殘留）
- 日期：2026-06-08
- 狀態：**提案 + 裁決完成，待派工落地**（本筆為規劃 / 裁決紀錄，未改任何 config / 業務碼）
- 帳本正規 ID = **CR-0046**（沿用「下一個空號」治理；CR-0045 已結案）

#### 1. 動機（為何現在做）
- CR-0039–0045 授權鏈已在 code 層閉合（P0-1 / P0-2 解除），重心轉向「正式上架前的平台設定與 production hardening」。
- 仍未處理之上架阻擋項（CR-0033 殘留）：iOS ATS 全域 `NSAllowsArbitraryLoads=true`（P1-5）、Android `applicationId` 帶個人名 + `android:label` 為 dev 名（P2-3）、`pubspec.yaml` description 含 "demo"（P3-1）、iOS/Android 顯示名與品牌未定案（P3-2）、缺商店 metadata / 隱私政策 URL / data safety 文件（§11）。
- 本案目標：把「現在能安全改、不破壞授權鏈/Realtime/更新路徑」的平台設定收斂，並把「需 owner 拍板或需外部素材/部署」的項目明確列為 blocker 文件，不假完成。

#### 2. 盤點覆核（architecture-agent 已驗證，覆核使用者盤點）
- **iOS Info.plist**：`NSAppTransportSecurity → NSAllowsArbitraryLoads=true`（全域 ATS 關閉，P1-5）；權限文案（Camera/Microphone/PhotoLibrary*2/SpeechRecognition/LocalNetwork）皆長者友善、**無 demo/test/mock/工程字眼**（已逐條讀過，符合 §5.2）；`CFBundleDisplayName="Pet Companion App"`、`CFBundleName="pet_companion_app"`（未定案，P3-2）；bundle id 走 `$(PRODUCT_BUNDLE_IDENTIFIER)`（pbxproj = `com.Andrew.petCompanionApp`）；`CFBundleURLSchemes` 為 Google OAuth **public client ID**（非 secret，維持）。
- **Android**：`build.gradle.kts` `applicationId="com.Andrew.petCompanionApp"`（個人名 + 大小寫混用，P2-3）、`namespace="com.example.pet_companion_app"`（內部套件名，改動會牽動 MainActivity.kt 套件路徑，**非上架顯示項**）、`minSdk=maxOf(flutter,23)`、`targetSdk=flutter 預設`、release `signingConfig=debug`（TODO 佔位，未提交 keystore，符合紅線）；`AndroidManifest` `android:label="pet_companion_app"`（dev 名，P2-3）、`usesCleartextTraffic="true"`（Android 端對應 iOS ATS 的明文流量開關，與 P1-5 同源問題）；權限 INTERNET/RECORD_AUDIO/MODIFY_AUDIO_SETTINGS/POST_NOTIFICATIONS/ACCESS_NETWORK_STATE/READ_MEDIA_IMAGES/READ_EXTERNAL_STORAGE(maxSdk32) — **與功能相符，無多餘權限**。
- **pubspec.yaml**：`description: Ai companion pet demo for elderly care interactions.`（含 "demo"，P3-1）；`version: 1.0.0+1`。
- **app_config.dart（CR-0034 既有）**：`isProduction`、`isApiBaseUrlProductionSafe`（production 指向 localhost/127.0.0.1/10.0.2.2/空/無 scheme → false）、`mockServicesEnabled`/`demoLoginVisible`/`devPanelsVisible` 在 production 強制 false；dev 預設 `http://127.0.0.1:3001`。已是「production 不 silent fallback localhost」的守門基礎。
- **caregiver_web/config.example.js**：`apiBaseUrl: null` → 預設同源 `/api`（CR-0034 B4，非 localhost 預設，符合）。
- **docs/ENVIRONMENT_SETUP.md**：已完整描述三環境 + production fail-fast + Flutter 守門畫面行為。**三份商店/隱私文件尚不存在**（待本案新建）。

#### 3. 影響範圍（檔案）
- **可安全改（本案落地）**：
  - `ios/Runner/Info.plist`（ATS 收斂；見 §5 結構建議）。
  - `android/app/src/main/AndroidManifest.xml`（`usesCleartextTraffic` 收斂以對齊 iOS ATS；`android:label` 改正式顯示名 — 但顯示名最終字串需 owner 定案，故本案僅在 owner 給名後改，預設列 blocker）。
  - `pubspec.yaml`（description 移除 "demo" → 正式描述；**description-only**）。
- **新建文件**：`docs/STORE_RELEASE_CHECKLIST.md`、`docs/APP_STORE_METADATA.md`、`docs/GOOGLE_PLAY_DATA_SAFETY.md`。
- **更新文件**：`docs/CHANGE_REVIEW.md`（本筆）、（如需）`docs/ENVIRONMENT_SETUP.md` 補 ATS / cleartext 設定說明。
- **不改**：`lib/config/app_config.dart`（CR-0034 守門已足夠，見 §裁決 1c）、`caregiver_web/config.example.js`（已正確）、`build.gradle.kts` 的 `applicationId`/`namespace`/signing（列 owner blocker，見 §裁決 1d）、任何授權鏈 / Realtime / Memory / notify auth 檔。

#### 4. 觸及 🔒 與牽涉 agent
- **🔒 判定（裁決 2）**：
  - `pubspec.yaml` description-only 編輯：**非 🔒**。🔒 原意是「跨前後端契約 / 主線依賴 / schema」，metadata 文字不影響任何契約或依賴；屬 low-risk doc-adjacent 編輯。
  - `ios/Runner/Info.plist` ATS 收斂：**準 🔒 / medium**。不改 API 契約或 schema，但**直接影響 Realtime 同網段語音連線可達性**（LocalNetwork + 區網 http 後端），錯改會打斷 iOS 實機語音主流程 → 需 architecture-agent checkpoint + 實機/模擬器連線驗證後才結案。
  - `android/app/src/main/AndroidManifest.xml` `usesCleartextTraffic` 收斂：**準 🔒 / medium**（同上，影響 Android 端區網 http 後端可達性）。
  - `build.gradle.kts` `applicationId` / iOS bundle id：**🔒 / high**（改動破壞已安裝 App 的更新路徑與 Firebase/OAuth 設定綁定）→ **不在本案自動改，列 owner blocker**。
  - `namespace`（Android 內部套件）：**非上架顯示項**，改動牽動 Kotlin 套件路徑，無上架必要 → 不改。
- 牽涉 agent：
  - **architecture-agent（主）**：規劃 / 裁決 / 文件（本案產出大宗為文件 + 平台設定審查）。
  - **frontend-ux-agent**：Flutter 長者端 + caregiver_web UI owner，但 **iOS/Android 原生平台 config（Info.plist / Gradle / Manifest）非其明列範圍**（見 §裁決 3 ownership 釐清）。
  - **不需** realtime-voice-agent（不改 `realtime_voice_service.dart` / SDP / DataChannel）、**不需** backend-agent（不改 server.js / DB）、**不需** companion-memory-agent。

#### 5. 風險等級
- 整案：**low–medium**。文件新建 = low；description-only = low；ATS / cleartext 收斂 = medium（可達性風險，需連線驗證）；owner blocker 項本案不動 = 0 風險。
- 紅線守護：不破壞 CR-0039–0045 授權鏈、不改 Realtime/Memory/notify auth、不 hardcoded secret、不提交 keystore、不偽造已部署 privacy URL / 商店設定、不讓 production 預設 localhost、不為 release build 暫關必要權限或安全檢查。

#### 6. 四項核心裁決

##### 裁決 1 — 「現在改」清單 vs「owner blocker」清單
**(1a) iOS ATS 收斂 — ✅ 核准本案做（medium，需連線驗證）。**
- 移除全域 `NSAllowsArbitraryLoads=true`，改為「僅 localhost / 區網明文例外」。production https 後端不需任何例外（預設即被 ATS 接受）；dev / iPhone 實機 Demo 連區網 http 後端仍可走例外網域。
- **保留理由覆核**：Realtime 採 WebRTC（媒體走 DTLS-SRTP，**不受 ATS 管制**）；ATS 只管 App 發起的 `URLSession`/HTTP（SDP 交換 `/api/realtime/call`、STT、各 REST API）。故收斂 ATS **不影響 WebRTC 媒體**，但**會影響 SDP 交換與 REST 打 http 區網後端**——因此例外必須涵蓋「明文 IP / 區網主機」情境（見 §7 結構建議含 `NSAllowsLocalNetworking`）。
- **驗證為結案前置**：iOS 模擬器 / 實機對區網 http 後端跑一次語音連線 smoke（SDP 交換成功 + DataChannel 開 + transcript），通過才結案；失敗則回退保留全域 arbitrary loads 並改列 blocker（誠實標註，不假完成）。

**(1b) Android `usesCleartextTraffic` 收斂 — ✅ 核准本案做（medium，與 1a 同源同驗證）。**
- 對齊 iOS：移除全域 `usesCleartextTraffic="true"`，改用 `res/xml/network_security_config.xml` 僅允許區網明文 + production https 預設拒明文。
- 同樣需 Android 區網 http 後端語音 smoke 驗證；失敗回退 + 列 blocker。

**(1c) app_config production URL fail-fast — ✅ 維持 CR-0034，不強化（驗證已足夠）。**
- 覆核：`isApiBaseUrlProductionSafe` 在 production 對「空 / 無 scheme / host 空 / localhost·127.0.0.1·10.0.2.2」回 false；ENVIRONMENT_SETUP §3.3 記載 App 據此顯示「服務暫時無法使用」長者友善守門畫面、**不進正式主流程**（非 silent fallback）。符合任務 §7 #4「fail-fast 或顯示部署 blocker，不可 silent fallback」。
- **唯一待確認（移交 frontend-ux-agent 覆核，非本案改碼）**：守門邏輯是否真的在 App 啟動 / 進入 Realtime 前**被消費**（有對應 guard view 攔截），而非僅定義了 getter 卻無人讀。若覆核發現 getter 未被任何啟動流程消費 → 另開小 FU（不在 CR-0046 大改）。本案以文件記此覆核點，不主動改 app_config。

**(1d) owner blocker 清單（本案 document，不自動改）：**
1. **最終品牌 display name**（iOS `CFBundleDisplayName`/`CFBundleName`、Android `android:label`）— 需 owner 定案正式中/英文 App 名與在地化後才改。
2. **Android `applicationId` / iOS bundle id 正式化**— 改動破壞已安裝更新路徑 + 綁定 Firebase/OAuth/Push 憑證，需 owner 拍板 + 同步重設第三方專案。
3. **hosted privacy policy URL / terms URL / support URL / contact email**— Phase 1 `LegalConfig` 為 TODO 佔位；需實際部署可公開存取頁面，**嚴禁偽造已部署 URL**（紅線）。
4. **app icon / adaptive icon / launch screen / screenshots**— 需設計素材，缺則文件列 placeholder，不假完成。
5. **release signing key（keystore / iOS distribution cert）**— **嚴禁提交**；本案僅在 gradle 留 signing config 文件說明，不放實際 key。
6. **production env**（Firebase / OpenAI / Telegram / DB / `CORS_ALLOWED_ORIGINS` 正式網域）— 走部署環境 secret，本案只列變數名（已在 ENVIRONMENT_SETUP §3.1）。

##### 裁決 2 — 🔒 判定（見 §4，摘要）
- pubspec description-only：**非 🔒**（low，無契約依賴）。
- Info.plist ATS / Manifest cleartext：**準 🔒 medium**，需 checkpoint + 連線驗證。
- applicationId / bundle id：**🔒 high**，列 blocker 不自動改。
- app_config / 其餘文件：**非 🔒**。

##### 裁決 3 — ownership / 批次 owner
- **iOS/Android 原生平台 config（Info.plist / build.gradle.kts / AndroidManifest.xml）**：現有 5 agent 中**無明確 owner**（frontend-ux-agent 範圍為 Flutter UI + caregiver_web，明列「不改後端行為與 Realtime」，未涵蓋原生 build config；且 ATS/cleartext 改動有 Realtime 可達性風險，屬跨界）。**裁決：原生 config 由 architecture-agent 規劃 + 使用者（main）執行**，frontend-ux-agent 僅提供「Flutter 端是否依賴明文區網後端」之事實覆核與連線 smoke 協助。
- **三份商店/隱私文件 + CHANGE_REVIEW + ENVIRONMENT_SETUP**：屬 architecture-agent 文件職責，由 architecture-agent / main 撰寫。
- **pubspec description**：可由 main 直接改（low、非 🔒）。
- **app_config 守門消費點覆核**：移交 frontend-ux-agent（Flutter 範圍內 read-only 覆核）。

##### 裁決 4 — 三份新文件範圍與「佔位/blocker 明示」原則
- **`docs/STORE_RELEASE_CHECKLIST.md`**：雙平台上架前 checklist（任務 §8.3 全項）。每項標狀態：✅ 已備 / ⏳ owner blocker / ❌ 缺。含 iOS build / Android build / privacy / terms / support / icon / screenshots / production backend URL / Firebase / PG migration / Telegram / OpenAI / no demo·mock·debug / no hardcoded secret / auth·Realtime·CareAlert smoke。
- **`docs/APP_STORE_METADATA.md`**：App name / subtitle / short·full description（草稿，**移除 demo 字樣**）/ keywords / category / age rating 建議 / privacy·support URL **placeholder（明標「待部署，禁偽造」）** / review notes draft / demo account 策略。
- **`docs/GOOGLE_PLAY_DATA_SAFETY.md`**：依任務 §8.2 列資料類型（account / voice·audio / messages·conversation / health-related inferred care signals / app activity / device id / notifications）× collected? shared? purpose? encrypted-in-transit? deletion-support?，對齊 Manifest 實際權限與後端實際蒐集（不得宣稱未實作的保護）。
- **共同原則**：凡未部署 / 未定案 / 需外部素材 → 一律標 **「⏳ BLOCKER：<負責方> / <待辦>」**，不得寫成已完成；privacy/support URL 一律 placeholder + 明文警告禁偽造。

#### 7. iOS ATS 收斂具體 plist 結構建議（若 1a 落地）
取代現有 `NSAppTransportSecurity → {NSAllowsArbitraryLoads:true}`，改為（概念結構，實際 IP 由部署環境決定，不寫死正式網域於此）：
- `NSAllowsArbitraryLoads` = `false`（或整個移除該 key，預設即 false）。
- `NSAllowsLocalNetworking` = `true`（允許 .local / 區網 IP 明文，供 iPhone 實機連同網段 http 後端 + LocalNetwork 語音；此 key 不放寬公網 https 以外的任意明文）。
- 如仍需顯式 localhost 例外，加 `NSExceptionDomains` → `localhost` → `{NSExceptionAllowsInsecureHTTPLoads:true, NSIncludesSubdomains:true}`。
- **不加** 任何正式網域例外（production 走 https，預設即被接受，零例外）。
- Android 對應：`network_security_config.xml` 設 `<base-config cleartextTrafficPermitted="false">` + `<domain-config cleartextTrafficPermitted="true">` 僅列區網 / localhost，Manifest 移除全域 `usesCleartextTraffic="true"` 改引用該 config。
- **註**：`NSAllowsLocalNetworking` 對 App Store 審查友善度遠高於全域 `NSAllowsArbitraryLoads`，且保留 Demo 區網語音可達性——是「收斂 P1-5 又不破壞實機 Demo」的最小變更。最終仍以 §6 (1a) 連線 smoke 驗證為準。

#### 8. 批次切分（owner / 順序 / 相依）
- **B1（文件，architecture-agent / main）**：新建三份商店/隱私文件 + 本 CR 紀錄 +（如需）ENVIRONMENT_SETUP 補 ATS/cleartext 說明。**零程式 / 零 config 風險**，可先行。🔒 無。
- **B2（low config，main）**：`pubspec.yaml` description 移除 "demo" → 正式描述。🔒 無。可與 B1 併。
- **B3（medium config，architecture-agent 規劃 + main 執行 + frontend-ux 協助驗證）**：iOS Info.plist ATS 收斂 + Android Manifest cleartext 收斂（+ 新增 `network_security_config.xml`）。**相依：需先完成區網 http 後端語音 smoke 驗證**。落地後 architecture-agent checkpoint（確認 SDP 交換 / DataChannel / transcript 正常）。🔒 準（medium）。**失敗則回退並改列 blocker，不假完成**。
- **B4（owner blocker 文件化，不改碼）**：把 §6 (1d) 六項 blocker 寫入 STORE_RELEASE_CHECKLIST 並標負責方 + 待辦。零風險。
- **順序**：B1 + B2 + B4（文件 / low，可同批）→ B3（需驗證，最後）。**applicationId / bundle id / signing / 品牌名 / hosted URL / 素材 / production secret 全部不在落地批，僅 B4 文件化**。
- **不拆子 CR**（範圍集中於平台 config + 文件，無獨立子系統）。

#### 9. 測試 / build 策略
- **B1 / B2 / B4（文件 + pubspec description）**：`flutter pub get`（確認 pubspec 仍可解析）+ `flutter analyze`。文件無需測試。預期通過。
- **B3（ATS / cleartext）**：
  - `flutter analyze` + `flutter test`（確認無 Dart 端回歸；ATS 為原生設定，Dart 測試不直接覆蓋，主要靠連線 smoke）。
  - **連線 smoke（結案前置，手動）**：iOS 模擬器/實機 + Android 對「區網 http 後端」跑語音對話一次（麥克風 → SDP 交換 → DataChannel → partial/final transcript → assistant 回覆）。通過才結案。
  - `flutter build ios --release --no-codesign --dart-define=APP_ENV=production --dart-define=API_BASE_URL=https://<正式網域>`：**嘗試**；若因簽章 / 素材 / 環境缺失失敗，**記錄 blocker 與錯誤摘要，不假裝通過**（任務 §9 / §12 #8）。
  - `flutter build apk --release ...`：同上嘗試 + 誠實記錄。
- **backend / caregiver_web**：本案不改其程式（僅可能補 ENVIRONMENT_SETUP 文字），不需跑 npm / node --test；若僅動文件則跳過，並於回報誠實標註「未跑」。
- **誠實原則**：未實際跑的測試 / build 一律標「未執行 / 因 X blocker 未完成」，不偽造綠燈。

#### 10. 紅線自檢（提案層）
- production 仍預設 localhost？**否**（app_config 守門 CR-0034 維持；本案不改預設）。
- iOS 仍全域 arbitrary loads？**B3 後否**（收斂為區網例外）；B3 未落地前維持現狀並標 blocker。
- Android 仍 com.example？applicationId 已是 `com.Andrew.*`（非 com.example，但帶個人名，列 owner blocker 正式化）；namespace 仍 com.example 但**非上架顯示項**，不改。
- demo/test/mock 字樣？pubspec "demo" 由 B2 移除；Info.plist 權限文案已無；文件一律不得新增 demo 字樣於正式 metadata。
- hardcoded secret / 提交 signing key / 偽造 privacy URL / 偽造商店設定？**全否**（紅線，blocker 一律 placeholder + 明標）。
- 破壞授權鏈 / Realtime / Memory / notify auth？**否**（本案完全不觸及該等檔案）。

#### 11. architecture-agent 裁決
- **✅ 核准本案（CR-0046）**依 §6 四項裁決 + §8 批次（B1+B2+B4 文件/low 先行 → B3 ATS/cleartext 經連線驗證後落地）落地。
- **B3 為唯一 medium 批**，落地後須 architecture-agent checkpoint（連線 smoke PASS 才結案；FAIL 則回退 + 改列 blocker）。
- **applicationId / bundle id / signing / 品牌名 / hosted privacy·support URL / 素材 / production secret**：**一律列 owner blocker，本案不自動改**。
- 不需 realtime-voice-agent / backend-agent / companion-memory-agent 派工；frontend-ux-agent 僅 (1c) 守門消費點覆核 + B3 連線 smoke 協助。

#### 12. 完成狀態
- ⬜ 未開始（本筆為提案 + 裁決；待 main 依 §8 批次派工 / 執行）。

#### 13. Checkpoint Review（architecture-agent，2026-06-08，main 執行 B1+B2+B4 後）

**結論：PASS（B1/B2/B4 結案；B3 ⛔ 轉 blocker 待真環境 smoke）。**

Read-only 核對結果：
- (a) **pubspec 僅 description 文字改動** — `git diff pubspec.yaml` 確認只 1 行：description 由「Ai companion pet demo for elderly care interactions.」→ 正式描述，移除 "demo"（P3-1）。非依賴變更、非 🔒。✅
- (b) **未碰授權鏈 / Realtime / Memory / notify auth / server.js / 原生 ATS config** — working tree 中 CR-0046 相關改動僅 `pubspec.yaml` + 三份新文件 + 本帳本；`realtime_voice_service.dart`、`backend/stt_proxy/server.js`、授權/記憶/通知碼皆未動。✅
- (c) **三份文件無假值 / 無偽造已部署 URL / 無寫死 secret** — secret/real-URL 掃描（sk-/bot/AIza/外部網域）無命中；placeholder 一律標 ⛔ 待定 / TODO；醫療紅線用語皆為「非醫療診斷」否定式陳述，無診斷宣稱；§5 六項 owner blocker + ⛔ 標示清楚。✅
- (d) **B3 確實未落地** — `ios/Runner/Info.plist` 仍 `NSAllowsArbitraryLoads=true`（行 45–46）；`AndroidManifest.xml` 仍 `usesCleartextTraffic="true"`、未加 `networkSecurityConfig`；`res/xml/network_security_config.xml` 不存在。收斂片段已備妥於 STORE_RELEASE_CHECKLIST §6（含 iOS plist / Android manifest+xml 片段 + smoke 驗證步驟 + checkout 回退規則），iOS/Android §2/§3 標 ⛔🔁 BLOCKER。✅

**B3 裁決：符合 CR-0046 §11 validate-or-rollback。** 本環境無實機 / 真後端 / 真 OpenAI key / 區網，無法執行「區網 http 後端 iOS/Android 語音 smoke」。依規則「FAIL 或無法驗證 → 維持現狀 + 列 blocker + 不假完成」，B3 以「備妥片段 + 轉 blocker」結案正確，**不在無法 smoke 的環境盲套**。架構主線（WebRTC 媒體走 DTLS-SRTP，不受 ATS 管制；ATS 只管 SDP/REST 明文後端）未受影響。

**驗收：** `flutter pub get` OK、`flutter analyze` → No issues found（main 回報，架構端未重跑；無實機/真環境故未跑 build/語音 smoke，誠實記錄）。

#### 14. 完成狀態（更新，取代 §12）
- ✅ **B1（文件）** STORE_RELEASE_CHECKLIST.md 完成。
- ✅ **B2（config，low）** pubspec description 移除 "demo" 完成。
- ✅ **B4（文件）** APP_STORE_METADATA.md + GOOGLE_PLAY_DATA_SAFETY.md 完成。
- ⛔ **B3（medium config）** 轉 blocker — 區網語音 smoke PASS 後才套用 §6 片段；FAIL 則回退維持現狀。
- **殘留 blocker：** (1) B3 真環境區網語音 smoke 後套用；(2) §5 六項 owner blocker（品牌名 / app 識別碼 / hosted 法務·支援 URL / 視覺素材 / signing / production 環境 + secret）；(3) §1·§7 真 Postgres+真 Firebase 端到端授權鏈驗證 + 真環境 release build / 三大 smoke。

### CR-0047 — Production Logging Redaction and PII De-identification（接 CR-0046；修 Audit P2-4 / P3-3 / P3-6；正式上架隱私治理項，不碰授權鏈/Realtime 主流程/Memory·CareAlert 成功契約）
- 提出 / 裁決 agent：architecture-agent（依使用者指派；任務書 `tasks/CR-0047-production-logging-redaction-and-pii-deidentification.md`）
- 日期：2026-06-08
- 狀態：**提案 + 裁決完成，待派工落地**（本筆為規劃 / 裁決紀錄，未改任何程式碼）
- 帳本正規 ID = **CR-0047**（沿用「下一個空號」；CR-0046 文件批 B1/B2/B4 已結案、B3 轉 blocker）

#### 1. 動機（為何現在做）
- 授權鏈（CR-0039–0045）已在 code 層閉合，CR-0046 收斂平台/商店設定。剩餘正式上架隱私治理風險：**production log 可能輸出 email / phone / token / 完整對話 / Care Alert reason·summary / Firebase·OpenAI·Telegram 原始錯誤 payload / DATABASE_URL**（CLAUDE.md §9.14「正式環境 log 不可輸出完整個資與 API key」）。
- 對應 Audit 殘留：**P2-4**（`memoryExtractor.js` console.error 印完整 stack；extractAndStoreMemory 另印 input 片段）、**P3-3**（Flutter debugPrint 散布、release 仍輸出）、**P3-6**（realtime `_log` 內部技術 log）。
- 既有資產：`config/env.js` 已有 `maskSecret / maskEmail / maskPhone / maskDatabaseUrl / describeMaskedConfig`（CR-0034）；`server.js` 已有 `logInfo / logError`（行 199/203）。本案不是從零造輪，是「在既有 mask primitive 上補 object/error 層 + 套用到高風險點 + Flutter 補集中 helper」。

#### 2. 盤點覆核（architecture-agent 已驗證，覆核使用者盤點）
- **Backend console.\*（非測試）= 54 處**，高風險點實測：
  - `services/memoryExtractor.js:171, 249` → `err.stack` 完整輸出（**P2-4，high**）；`:251-254` 另印 userText 前 200 字（對話片段 PII，**high**）。
  - `services/memory/memoryStore.js`（339/364/431/511/566/615/654/670）、`search/documentStore.js`（69/114/156）、`embeddingService.js`、`search/*`、`memory/memoryContextService.js` → 多為 `error?.message || error`（**已相對安全**，但 `|| error` 在 message 缺時會落回完整 error 物件，**medium**：需確保只取 safe message、不落回完整 error/stack）。
  - `server.js:200/204`（`logInfo/logError`）→ 直接 `console.log/error(msg, extra)`，`extra` 未經遮蔽（呼叫端若塞 token/email/body 即外洩，**medium**：屬「管道」風險，須讓 extra 過 redaction）。
  - **授權鏈 auth-context log 已合規（覆核確認）**：`adminAuthContext.js:172`、`residentCallerContext.js:177` 皆只印 `{ error: (error && error.message) || error }`，**不印 token**（CR-0041/0045 紅線已落實）。→ **本案不需改動此二檔**（避免授權鏈 churn，見 §裁決 5）。
  - 對外 response 覆核：admin 路徑回 `{ok:false,error:<code>}`、resident/notify 回 `{success:false,error:<code>}`，**不回 stack**（Audit §4.2 已確認）。✅
- **Flutter debugPrint = 70 處（~17 檔）**，高風險實測：
  - `lib/controllers/voice_agent_controller.dart:620` → `[EMOTION] text=$transcript ...`（**完整 transcript 外洩，high**）；`:1406` recovering reason（technical，low）。
  - `lib/services/care_alert_notification_service.dart:84/89/93` → 印 statusCode / `decoded['error']`（後端錯誤碼）/ error（**non-token，CR-0045 已不印 token；medium**：reason/summary 不應外洩，statusCode/錯誤碼可保留）。
  - `lib/controllers/auth_controller.dart:88`、`care_alert_notification_service.dart:51` → 僅白話訊息**無 token**（low，CR-0045 已收斂）。
  - `lib/services/realtime_voice_service.dart`（🔒）`_log`（定義行 1107：`debugPrint('[RealtimeVoiceService] $message')`）→ 內容為 connectionState / iceConnectionState / DataChannel state / status code / 技術字串，**不含 transcript / summary / token**（逐點覆核 254–509）。屬 Audit P3-6「僅內部 debug、release 抑制即可」。
  - **重要事實**：Flutter `debugPrint` 在 **release build 仍會輸出**（未受 `kReleaseMode/kDebugMode` 包者不會被 strip）。`lib/` 目前幾乎無集中 log gate（無 `lib/utils/app_log.dart`）。
- **caregiver_web console.\* = 0**（CR-0042/0044 已確認 `app.js` 不印 token）→ 本案僅「加守護測試 + 文件」，**非改碼**。

#### 3. 影響範圍（檔案）
- **新建**：
  - `backend/stt_proxy/services/privacy/redaction.js`（object/error 遮蔽層，delegate env.js primitive）。
  - `backend/stt_proxy/test/redaction.test.js`（node --test）。
  - `lib/utils/app_log.dart`（Flutter 集中 redacted log helper）。
  - `test/utils/app_log_test.dart`（或併入既有測試目錄）。
  - `docs/LOGGING_AND_REDACTION.md`（logging 原則文件）。
- **改寫（高風險 log 套用 redaction，行為不變）**：
  - `backend/stt_proxy/server.js`（`logInfo/logError` 讓 `extra` 過 `safeLogPayload`）。
  - `backend/stt_proxy/services/memoryExtractor.js`（移除 stack 全文 + input 片段，改 `safeErrorMessage`）。
  - `backend/stt_proxy/services/memory/memoryStore.js`、`memory/memoryContextService.js`、`memory/embeddingService.js`、`embeddingService.js`、`search/documentStore.js`、`search/searchService.js`、`search/summarizer.js`、`search/crawlerService.js`、`memory/memoryExtractor.js`（確保只取 safe message，不落回完整 error/stack）。
  - `lib/controllers/voice_agent_controller.dart`（transcript log 改 redacted / kDebugMode）、`lib/services/care_alert_notification_service.dart`（reason/summary 不外洩）、`lib/controllers/auth_controller.dart`、`lib/controllers/conversation_controller.dart`、`lib/services/auth/session_api_service.dart`（高風險點改用 app_log）。
- **新增守護測試 + 文件（不改業務碼）**：`caregiver_web/*.test.js`（斷言不 console.log token）。
- **更新文件**：`docs/CHANGE_REVIEW.md`（本筆）、`docs/GOOGLE_PLAY_DATA_SAFETY.md`、`docs/STORE_RELEASE_CHECKLIST.md`。
- **不改（紅線保護）**：`adminAuthContext.js` / `residentCallerContext.js` / `sessionService.js` / `firebaseAdmin.js`（授權鏈，已合規，避免 churn）、`realtime_voice_service.dart`（🔒，見 §裁決 4）、任何 Realtime SDP/DataChannel 流程、Memory/Care Alert 成功 response 契約、`config/env.js` 既有 primitive（只新增 delegate，不改其行為與既有測試基線）。

#### 4. 觸及 🔒 與牽涉 agent
- **🔒 判定**：
  - `realtime_voice_service.dart`（realtime-voice-agent 專屬 🔒）→ **本案不動**（裁決 4）。若日後納入，須 realtime-voice-agent owner + architecture checkpoint，列為獨立 🔒 批。
  - 授權鏈檔（adminAuthContext / residentCallerContext / sessionService / firebaseAdmin）→ **準 🔒**；本案**不改**（已合規），避免動到 CR-0039–0045 守門測試基線。
  - `config/env.js` mask primitive → **準 🔒**（CR-0034 既有測試守護）；本案**只在新檔 require 它、不改其輸出/簽章**。
  - `server.js logInfo/logError`、各 service log、Flutter 非-realtime log → **非 🔒**（log 管道改寫，不動契約/schema/主線）。
- 牽涉 agent：
  - **backend-agent（主力）**：redaction.js + backend 高風險 log 改寫 + backend 測試 + LOGGING 文件。
  - **frontend-ux-agent**：`app_log.dart` + Flutter 非-realtime 高風險 log 改寫 + Flutter 測試 + caregiver_web 守護測試。
  - **companion-memory-agent**：**不需派工**（見裁決 5：memory log 為「管道遮蔽」非「記憶/分級邏輯」，歸 backend-agent；companion-memory-agent 僅知會、可覆核 memory log 不誤刪必要診斷資訊）。
  - **realtime-voice-agent**：**本案不需**（不動 🔒）；僅在使用者要求把 `_log` 納入 release 抑制時才開獨立批。
  - **architecture-agent**：本提案 + 裁決 + 文件審查 + 批次 checkpoint。

#### 5. 風險等級
- 整案：**low–medium**。redaction.js + 文件 + caregiver_web 守護測試 = low；backend/Flutter log 改寫 = medium（觸及多檔但機械式、不改邏輯）。
- **最大風險 = 「為安靜 log 而吞錯」**（任務 §11 #6）：改寫須維持原本 try/catch 控制流與 fallback 行為，**只遮蔽輸出內容，不刪除/縮減錯誤處理、不改 return 值、不改 throw 時機**。
- 紅線守護：不破壞 CR-0039–0045 授權鏈、不改 Realtime WebRTC 主流程、不改 Memory API / Care Alert 成功 response 契約、不移除必要錯誤處理、測試不硬編真 secret、不大量重寫無關 code。

#### 6. 五項核心裁決

##### 裁決 1 — `redaction.js` 與 `config/env.js` 既有 mask 的分工（✅ delegate，不重造）
- **核准**：新 `services/privacy/redaction.js` **delegate** `config/env.js` 既有 primitive，**不得重新實作** masking 規則（避免兩套遮蔽邏輯分歧）。
- 分工：
  - `config/env.js`（既有，**單一 masking primitive 來源**）：`maskSecret / maskEmail / maskPhone / maskDatabaseUrl`、`describeMaskedConfig`（啟動設定摘要）。**本案不改。**
  - `services/privacy/redaction.js`（新，**組合/物件/錯誤層**）：
    - `redactToken(v)` → 直接 delegate `maskSecret`（語意別名，供呼叫端語意清楚）。
    - `redactEmail(v)` / `redactPhone(v)` / `redactDatabaseUrl(v)` → delegate 對應 env.js mask。
    - `redactObject(value)` → **遞迴**遮蔽常見敏感 key（任務 §5 清單：token/accessToken/idToken/authorization/apiKey/key/secret/password/chatId/telegramToken/openaiApiKey/databaseUrl/email/phone/transcript/message/conversation/memory/reason/summary）；key 命中 → 套對應 mask 或 `[REDACTED]`；自由文字長欄位（transcript/message/conversation/memory/reason/summary）→ **截斷 + 標記**（如前 N 字 + `…[truncated]`，避免完整對話/摘要落 log）；**不可 mutate 原物件**（回新物件/深拷貝）；需防循環參照與過深遞迴（設深度上限）。
    - `safeErrorMessage(error)` → 只回 `error.code` / `error.message` 之**安全摘要**，**不含 stack、不含 request body、不回完整 error 物件**；message 本身再過 token/email/phone 遮蔽（防第三方 SDK 把 key 塞進 message）。
    - `safeLogPayload(payload)` → 對 log 附帶物件套 `redactObject`，production 走完整遮蔽 + 截斷。
- `server.js logInfo/logError`、各 service log 改用之；`describeMaskedConfig` 維持由 env.js 提供（啟動摘要既有路徑不動）。

##### 裁決 2 — production vs dev log 策略（用 env.js `isProduction` 控制；secret 兩環境恆遮蔽）
- **核准分層**：
  - **production**（`isProduction(env)===true`）：一律 safe/redacted。log 只保留 error code / request id（如有）/ route / status code / safe message / redacted id / timestamp（任務 §6）。**不印** request body 全文、headers、完整 error 物件、stack、完整對話/summary/reason。
  - **development / staging**：可較詳細（保留較長截斷上限、可保留 stack 供除錯），**但 secret/token/key/DATABASE_URL/email/phone 仍恆走 mask**（不因 dev 就印明文金鑰）。
  - 差異**只在自由文字截斷長度與是否附 stack**，**不在「是否遮蔽 secret」**（secret 兩環境都遮）。
- 由 `redaction.js` 內部讀 `require('../../config/env').isProduction` 決定截斷/stack 行為（保持 env 單一判定來源）。
- **對外 response 覆核（維持）**：admin `{ok:false,error}`、resident/notify `{success:false,error}`，**不回 stack / 不回完整 error**（現況已符合，本案僅覆核不改契約）。

##### 裁決 3 — Flutter log 策略（新建 `lib/utils/app_log.dart`，release 抑制 + redact）
- **核准**：因 `debugPrint` release 仍輸出，建集中 helper `lib/utils/app_log.dart`：
  - 提供 `AppLog.debug/info/warn/error(...)`；**release（`kReleaseMode`）抑制非必要 log**，或僅輸出已遮蔽的 safe message。
  - 提供 redact 工具（遮蔽 token、截斷 transcript/summary/reason）；**敏感參數一律經遮蔽再輸出**。
  - **不破壞 Realtime 狀態追蹤**：狀態機/連線診斷訊息可保留，但走 helper 在 release 抑制（dev 仍可見），不得改 controller 狀態流。
- 套用對象（高風險先行）：`voice_agent_controller.dart:620`（transcript → redact/kDebugMode）、`care_alert_notification_service.dart`（reason/summary 不外洩、保留 statusCode/錯誤碼）、`auth_controller.dart`、`conversation_controller.dart`、`session_api_service.dart` 之 token/error 點。其餘低風險 technical debugPrint 可批次改 helper 或 `kDebugMode` 包覆（非阻斷，可漸進）。

##### 裁決 4 — `realtime_voice_service.dart`（🔒）→ 本案不動，列 FU
- **裁決：本案不修改 `realtime_voice_service.dart`。** 理由：
  - 逐點覆核其 `_log`（行 1107）僅輸出**技術字串**（connectionState / iceConnectionState / DataChannel state / status code），**不含 transcript / summary / token / PII**；Audit P3-6 評**低風險「release 抑制即可」**。
  - 它是 realtime-voice-agent 專屬 🔒；為「release 噪音」這種低風險項動 🔒 檔不划算，且會牽動 Realtime 主線守門。
- **FU（後續，非本案）**：若要把 `_log` 也納入 release 抑制，開**獨立 🔒 批**，owner = realtime-voice-agent（把 `_log` 改 delegate `AppLog`，僅 release gate，不改任何訊息語意/狀態追蹤），落地後 architecture-agent checkpoint（確認 Realtime 狀態機/連線診斷不受影響）。本 CR 僅在 §10 列此 FU，不執行。

##### 裁決 5 — 批次切分 + owner + 順序 + 子 CR + 🔒 checkpoint
- **不拆子 CR**（同一主題「logging 去識別化」，批次足夠；無獨立子系統）。
- **memory log 歸屬**：`memoryExtractor.js` / `memory/*` 的 log 改寫屬「輸出管道遮蔽」（非陪伴回覆策略 / 記憶邏輯 / Care Alert 分級邏輯）→ 歸 **backend-agent**，**不派 companion-memory-agent**（僅知會 + 可覆核「未誤刪必要診斷資訊、未改記憶判定流程」）。
- 批次：
  - **B1（backend-agent）**：新建 `services/privacy/redaction.js`（delegate env.js）+ `test/redaction.test.js`。**純新增、零行為變更、零 🔒**。先行。
  - **B2（backend-agent，相依 B1）**：套用 redaction 到 backend 高風險 log —— `server.js logInfo/logError`（extra 過 safeLogPayload）、`memoryExtractor.js`（P2-4：移除 stack 全文 + input 片段）、`memory/*`、`search/*`、`embeddingService`（確保只取 safe message、不落回完整 error/stack）。**不改授權鏈四檔**（已合規）。**不吞錯**（只改輸出）。medium。
  - **B3（frontend-ux-agent，可與 B1/B2 並行）**：新建 `lib/utils/app_log.dart` + 套用到 Flutter 非-realtime 高風險 log（voice_agent_controller transcript、care_alert_notification_service、auth_controller、conversation_controller、session_api_service）+ Flutter 測試。**不碰 `realtime_voice_service.dart`（🔒）**。medium。
  - **B4（frontend-ux-agent，low）**：caregiver_web 加守護測試（斷言不 console.log token / 401·403 不輸出 raw sensitive payload）+ 文件註記。**不改 app.js 業務碼**（console.\*=0 已合規）。
  - **B5（backend-agent / architecture，low）**：文件 —— 新建 `docs/LOGGING_AND_REDACTION.md` + 更新 `GOOGLE_PLAY_DATA_SAFETY.md` / `STORE_RELEASE_CHECKLIST.md` + 本 CR 帳本。
- **順序**：B1 →（B2 backend）∥（B3 frontend）並行 → B4 → B5 文件收尾。
- **🔒 checkpoint**：本 CR **無 🔒 落地批**（`realtime_voice_service.dart` 不動、授權鏈四檔不動）。B2 雖鄰近授權鏈，但**明令不改 adminAuthContext/residentCallerContext/sessionService/firebaseAdmin**；architecture-agent 於 B2 落地後做 read-only checkpoint，確認：(a) 授權鏈四檔 git diff = 空；(b) 無吞錯（控制流/return/throw 不變）；(c) 既有 backend/Flutter 測試全綠。FU（realtime `_log`）若啟動 → 屆時為獨立 🔒 批 + checkpoint。

#### 7. 測試計畫
- **Backend（node --test，不需真 DB/真金鑰）**：`redaction.test.js` 涵蓋任務 §9.1 全項 —— token / email / phone / DATABASE_URL 遮蔽、nested object 遞迴遮蔽、**原物件不被 mutate**、敏感 key 命中遮蔽、`safeErrorMessage` 不含 token/stack、Care Alert summary/reason 不在 safe log 完整出現、`describeMaskedConfig` 不洩 secret（覆核既有）。**測試不得硬編真 secret**（用假值如 `sk-test-xxxx`）。跑 `npm run check` + `npm test`。
- **Flutter**：`app_log` 單元測試（release gate 行為以可注入 flag 模擬；token/transcript 遮蔽斷言）；更新/新增 care_alert_notify 不 log token、transcript log 受 guard 控制之測試。跑 `flutter analyze` + `flutter test`。
- **caregiver_web**：新增守護測試（auth token 不被 console.log、401/403 不顯示 raw token、provisioning error 不輸出完整敏感 response）。跑 `node --test *.test.js`。
- **誠實原則**：未實際執行的測試/build 一律標「未執行 / 原因」，不偽造綠燈（CLAUDE.md 回報規範）。

#### 8. 紅線自檢（提案層）
- production log 仍可能印 token / secret？**目標：否**（safeLogPayload + safeErrorMessage + env.js mask；兩環境恆遮 secret）。
- 仍可能印完整 email / phone？**否**（redactEmail/redactPhone delegate）。
- 仍可能印完整 transcript / Care Alert summary·reason？**否**（自由文字截斷 + 敏感 key 遮蔽；Flutter transcript log redact/kDebugMode）。
- 為安靜 log 而吞錯？**否**（只改輸出，不動 try/catch 控制流 / return / throw；architecture checkpoint 驗證）。
- 破壞授權鏈 CR-0039–0045？**否**（授權鏈四檔不改，已合規）。
- 改 Realtime 主流程 / Memory·CareAlert 成功契約？**否**（不動 🔒 realtime、不動成功 response 形狀）。
- 測試硬編真 secret？**否**（一律假值）。

#### 9. architecture-agent 裁決
- **✅ 核准本案（CR-0047）** 依 §6 五項裁決 + §6 裁決 5 批次（B1 → B2∥B3 → B4 → B5）落地。
- redaction.js **delegate** env.js primitive、**不重造**；production/dev 由 `isProduction` 控制截斷/stack，secret 兩環境恆遮。
- Flutter 建 `lib/utils/app_log.dart`（release 抑制 + redact），**不碰 `realtime_voice_service.dart`（🔒）**。
- realtime `_log` **本案不動，列 FU**（獨立 🔒 批，owner=realtime-voice-agent，需 checkpoint）。
- 授權鏈四檔已合規、**本案不改**；B2 落地後 architecture read-only checkpoint（驗 diff 空 + 不吞錯 + 測試綠）。
- 不需 companion-memory-agent / realtime-voice-agent 派工（前者知會、後者僅 FU 才啟動）。

#### 10. 執行進度 / 驗收 / checkpoint 裁決（2026-06-08 architecture-agent read-only checkpoint）

執行進度（依 §6 裁決 5 批次）：
- B1 ✅ backend-agent：`services/privacy/redaction.js`（delegate env.js mask primitive；redactToken/Email/Phone/DatabaseUrl + redactObject 遞迴不 mutate + 防循環/深度 + safeErrorMessage 無 stack + safeLogPayload）+ `redaction.test.js`（14 案）。
- B2 ✅ backend-agent：server.js logInfo/logError 套 safeLogPayload；memoryExtractor.js 移除 err.stack 全文 + 對話原文（userText）片段（修 P2-4）改 safeErrorMessage；memory/* · search/* · embeddingService 把 `error?.message||error` 改 safeErrorMessage。**授權鏈四檔未改**。
- B3 ✅ frontend-ux-agent：`lib/utils/app_log.dart`（kReleaseMode no-op + previewTranscript/redactToken/redactSummary）；voice_agent_controller.dart 僅第 ~621 行 EMOTION transcript log 改 previewTranscript；auth_controller/conversation_controller/session_api_service/consent_api_service/care_alert_notification_service 高風險 debugPrint 改 AppLog。**realtime_voice_service.dart 未碰**。
- B4 ✅ frontend-ux-agent：`caregiver_web/logging_safety.test.js` + README logging 段。
- B5 ✅ backend-agent：`docs/LOGGING_AND_REDACTION.md` + 更新 GOOGLE_PLAY_DATA_SAFETY.md / STORE_RELEASE_CHECKLIST.md。

驗收結果（architecture-agent 獨立覆驗，全綠）：
- backend `npm test` → tests 438 / pass 438 / fail 0（424 基線 + 14 新 redaction）。
- backend `node --test services/privacy/redaction.test.js` → 14/14。
- caregiver_web `node --test *.test.js` → 88/88（85 + 3 新 logging_safety）。
- flutter analyze（8 個改動檔）→ No issues found。
- flutter test `test/utils/app_log_test.dart` → 5/5。

checkpoint 裁決（read-only git diff / grep 覆核）：
- (a) 🔒 邊界：adminAuthContext / residentCallerContext / sessionService / firebaseAdmin / realtime_voice_service.dart **`git diff --quiet` 全空（UNCHANGED）**——覆核通過。
- (b) 不吞錯：backend 改動全是 `error?.message||error` → `safeErrorMessage(error)` 或 logInfo/logError 套 safeLogPayload，**try/catch 控制流 / return / throw / json fallback 均未動**；memoryExtractor P2-4 僅移除 stack 全文 + userText 片段 log，return 形狀不變；Flutter 全為 debugPrint → AppLog.debug/error 之純 log 置換，狀態機 / fallback / 例外語意保留——通過。
- (c) 對外 response 不回 stack：backend services 無 `console.*(...stack)` 殘留（grep 0 命中）——通過。
- (d) memoryExtractor 不再印 stack / 對話原文——通過。
- (e) production log 不輸出 token/secret/email/phone/完整對話/Care Alert summary·reason/DATABASE_URL：由 redaction TOKEN/EMAIL/PHONE/DBURL/FREETEXT_KEYS + production freetext limit=0 保證，redaction.test.js 含對應斷言——通過。
- (f) voice_agent_controller 僅 EMOTION log 行改動（previewTranscript 截斷），狀態機未動——通過。
- (g) 測試不含真 secret：全用 `sk-test-*` / `example.com` / `123456:fake-bot-token-*` 等假值——通過。
- (h) 既有 CR-0039–0046 測試全綠（438/438 含授權鏈與 telegram 測試）——通過。
- **裁決：✅ PASS。** 未發現吞錯、未觸 🔒、未破壞既有契約與測試。

#### 11. 完成狀態 / FU
- ✅ 已完成（B1–B5 全部落地並通過 architecture checkpoint；待 main 提交，commit 範圍見本筆殘留說明）。
- **FU-1**：realtime `_log` release 抑制（獨立 🔒 批，realtime-voice-agent + checkpoint）。
- **FU-2**：低風險 technical debugPrint 全面收斂為 `AppLog` / `kDebugMode`（漸進，非阻斷）。
- **FU-3**：考慮在 server.js 全域 error handler 統一套 safeLogPayload（若後續發現散點仍有未遮蔽 extra）。
- **FU-4**：CI lint 守護——新增 `debugPrint` 高風險用法須走 `AppLog`/`kDebugMode`（lint rule / pre-commit grep），避免回潮。
- **FU-5**：裝置端驗證——以 release build 在 iOS 實機實測，確認 `kReleaseMode` 路徑下 AppLog 確為 no-op、log 不外洩 token/逐字稿（本案僅靜態 + 單元/分析層驗證，未跑 release 裝置驗證）。


### CR-0048 — Production Mock Service Build-Flavor Isolation（接 CR-0047；修 Audit P2-5 / P2-6；只做 Flutter mock 注入隔離，不碰 Realtime 主流程/Memory 契約/Care Alert notify auth/後端授權鏈）
- 提出 / 裁決 agent：architecture-agent（依使用者指派；任務書 `tasks/CR-0048-production-mock-service-build-flavor-isolation.md`）
- 日期：2026-06-09
- 帳本正規 ID = **CR-0048**（沿用「下一個空號」；CR-0047 已結案）

#### 1. 動機
授權鏈（CR-0039–0045）、平台/商店（CR-0046）、log redaction（CR-0047）已收斂。殘留正式版風險（Audit P2-5 / P2-6）：
> Flutter `lib/app.dart` provider tree 仍有**無條件注入的 mock service**。即使 `AppConfig` 已把 `mockServicesEnabled` 在 production 強制 false，正式 build 的 provider 樹仍建立 `MockAiService` / `MockSpeechToTextService` / `MockTaigiAsrStrategy`，且這些 mock **被 consumer 於 runtime 選用**（非死碼）。

CLAUDE.md（store 版）§2.1：正式版不得包含 mock service / fake response / JSON fallback 作為正式資料來源；§2.2：mock 只能於 dev/test，且須以環境變數 / build flag 明確隔離。

#### 2. consumer 調查結論（已精讀，本案最關鍵的前置）
逐一追 line 189/190/199 三個 mock 的真實 runtime 路徑，結論是**三者性質不同，不能一刀切**：

1. **MockTaigiAsrStrategy（app.dart line 199）** — 以 `const` 元素塞進 `AsrStrategyService(strategies: [...])` 的清單，**不是 provider、不被任何 `context.read` 取用**。
   - `AsrStrategyService.strategyFor()`（asr_strategy_service.dart 66-70）查無對應 strategy 時**已 graceful fallback** 到 `defaultOpenAiRealtime`；`taigiStrategy` getter（74-79）找不到 supportsTaigi 時回 `null`。
   - `LanguageRoutingService._routeTaigiPreferred()`（language_routing_service.dart 162-172）對 `taigiStrategy == null` **已有正式 fallback**（回 openai-realtime，isFallback=true，不丟例外）；`_routeManualOverride()`（206-210）經 `strategyFor()` 同樣 graceful。
   - 結論：**consumer 不依賴此 mock 的存在**。production 不注入它，settings 的 `mockTaigiAsr` 選項只會解析成 OpenAI Realtime。**屬純 wiring、可安全 gating（比照 MockShopService line 179）。**

2. **MockAiService（app.dart line 189→216）** — 是 `Provider`，被 `AiToolRouter` 建構子 `context.read<MockAiService>()` 取用，於 `AiToolRouter._chat()`（ai_tool_router.dart 476-502）**always** 呼叫 `replyForChat()` 產生回覆文字。
   - `_chat` 是 `AiToolRouter.route()`（39-68）所有非工具語句的**最終落點**。
   - 被**兩條 production 路徑**選用：(a) 按住說話 `ConversationController`（toolRouter.route）；(b) **Realtime 本地指令路由** `VoiceAgentController._handleLocalRealtimeCommand()`（voice_agent_controller.dart 677）→ `toolRouter.route(text)`，非工具語句會落到 `_chat` 並 `shouldSpeak=true`。
   - 結論：**MockAiService 是 production runtime live 依賴，非死碼。** 直接從 provider 樹移除 → `context.read<MockAiService>()` 丟 ProviderNotFoundException（crash）；改 optional → `_chat` 在 production 無回覆引擎。要安全隔離**必須改 consumer 選用邏輯**（為 `_chat` 接正式回覆引擎），屬陪伴回覆策略 / 對話邏輯，**非純 wiring**。

3. **MockSpeechToTextService（app.dart line 190→286）** — 是 `Provider`，被 `ConversationController` `context.read` 取用。`_currentSttService()`（conversation_controller.dart 371-376）在 `sttMode != openAiProxy` 時回傳它；`onPressToTalkEnd()`（417-422）在 `sttMode == mock` 時直接用它。
   - **預設 `sttMode == 'mock'`**（user_profile.dart line 62 / profile_controller.dart 36-37）。即 production 按住說話**預設走 mock STT**。
   - 結論：同樣**runtime live 依賴**。安全隔離需 (a) production 預設 `sttMode → openAiProxy` 且 (b) consumer 不依賴 mock 存在，**亦屬 consumer 邏輯改動，非純 wiring。**

> 核心裁定：三 mock 中只有 **MockTaigiAsrStrategy 可純 wiring gating**；MockAiService / MockSpeechToTextService 是「被 production runtime 選用」的 live 依賴，移除等於改變按住說話與 Realtime 本地指令的回覆/STT 引擎，**牽涉 companion-memory-agent（回覆策略）與對話/Realtime owner，須另批、另 owner**，不可由 frontend-ux-agent 在 wiring 批內硬拔（會 crash 或產生無回覆 / 假回覆）。

#### 3. 影響範圍（檔案 / 行號）
本案（CR-0048）允許觸及：
- `lib/app.dart` 195-202（`AsrStrategyService` strategies 清單，gating `MockTaigiAsrStrategy`）— App root 敏感 wiring，須 architecture checkpoint。
- `lib/screens/settings_screen.dart` 214-236（手動 ASR strategy dropdown，production 隱藏 `mockTaigiAsr` 選項）— 選配 B2。
- `test/**`（新增 production-wiring / AppConfig gating 測試）。
- `docs/CHANGE_REVIEW.md`（本筆）、`docs/ENVIRONMENT_SETUP.md`、`docs/STORE_RELEASE_CHECKLIST.md`、新增 `docs/FLUTTER_BUILD_FLAVORS.md`。

本案**明確不動**（移交 CR-0049）：
- `lib/app.dart` 189-190（MockAiService / MockSpeechToTextService 注入）。
- `lib/services/ai_tool_router.dart`（`_chat`）、`lib/controllers/conversation_controller.dart`（STT 選用）、`sttMode` 預設。

#### 4. 觸及 🔒 / 牽涉 agent
- 🔒：不觸及。`realtime_voice_service.dart`、`backend/stt_proxy/server.js`、授權鏈四檔、Memory API、Care Alert notify auth **全部不碰**。
- agent：**frontend-ux-agent**（純 Flutter wiring + 測試 + 文件）。**companion-memory-agent / 對話·Realtime owner 僅在 CR-0049 才派工**（本案知會即可）。

#### 5. 風險
- CR-0048 本批：**low**。MockTaigiAsrStrategy gating 有既存 graceful fallback 兜底；既有測試**自建** `AsrStrategyService(strategies:[..., MockTaigiAsrStrategy()])`（見 conversation_controller_ui_state_test 683 / voice_agent_controller_realtime_lifecycle_test 740/757），**不依賴 app.dart 注入**，故 gating 不破壞 dev/test。app.dart 為 App root → 仍要 checkpoint。
- 延後項（CR-0049）：**medium**。改 `_chat` 回覆引擎 / `sttMode` 預設牽動按住說話與 Realtime 本地指令回覆品質，須 owner 審。

#### 6. 裁決（針對任務 5 問）
1. **隔離策略**：分流。
   - **MockTaigiAsrStrategy → 本案純 wiring gating**：`strategies: [const OpenAiRealtimeAsrStrategy(), if (AppConfig.mockServicesEnabled) const MockTaigiAsrStrategy()]`。consumer 不需改（已 graceful fallback）。
   - **MockAiService / MockSpeechToTextService → 不在本案處理，移交 CR-0049**：須先讓 consumer 在 production 改用正式回覆引擎 / 正式 STT（`_chat` 接正式來源、`sttMode` production 預設 `openAiProxy`），再 gating 注入。理由：兩者為 runtime live 依賴，純拔會 crash 或破壞 Realtime 本地指令/按住說話，且屬回覆策略 owner（companion-memory-agent）+ 對話/Realtime owner 的邏輯權責。
2. **不破壞 dev/test**：development/test 維持以 dart-define `ALLOW_MOCK_SERVICES=true` 或**直接於測試建構 mock**（既有測試即此模式）。本案 gating 只影響 app.dart 注入，已驗證既有 mock 測試自建依賴 → 不受影響。要求 frontend-ux-agent 跑全 `flutter test` 回歸確認綠。
3. **fail-fast vs 安全錯誤**：本案範圍**沿用 CR-0034 既有機制即足**，不需新增 fail-fast。MockTaigiAsr 缺席由 AsrStrategyService graceful fallback 處理（非缺正式 config 情境）；production 缺正式 API base URL 仍由 `isApiBaseUrlProductionSafe` + `_ServiceUnavailableView`（app.dart 391-393）攔截。**不新增 mock fallback。**
4. **Demo/Dev UI**：`demoLoginVisible` / `devPanelsVisible` 已於 CR-0034 production 強制 false，覆核無遺漏。settings 的 `mockTaigiAsr` dropdown **label 已是「台語 ASR adapter」非工程字樣**；建議本案 **B2 將該選項於 `!AppConfig.mockServicesEnabled` 時隱藏**（避免 production 殘留無實效的 mock 選項）。**「Mock STT」工程字樣維持 CR-0039 範圍**，本案不動。
5. **批次切分 + owner + checkpoint**：見 §7。**需 checkpoint**（app.dart 為 App root 敏感 wiring）。

#### 7. 批次切分（owner = frontend-ux-agent）
- **B1**（low，須 architecture read-only checkpoint）：`lib/app.dart` 195-202 gating `MockTaigiAsrStrategy` 於 `AppConfig.mockServicesEnabled`。**只准動這段清單**，不得碰 189-190。
- **B2**（low，選配）：`lib/screens/settings_screen.dart` 214-236 在 `!AppConfig.mockServicesEnabled` 隱藏 `mockTaigiAsr` 選項；不得改 VoiceLanguageMode 行為、不得改 manualOverride 路由邏輯。
- **B3**（low）：測試。新增/更新：production AppConfig 強制 `mockServicesEnabled==false`（即使 dart-define 傳 ALLOW_MOCK_SERVICES=true）；app.dart production 樹不含 MockTaigiAsrStrategy（或以 AsrStrategyService.taigiStrategy 斷言）；dev/test flag 下 mock 仍可注入；既有 mock 測試全綠回歸。
- **B4**（low）：文件。更新 ENVIRONMENT_SETUP（mock 隔離現況：哪些已 gating、哪兩個延後 CR-0049）、STORE_RELEASE_CHECKLIST（mock isolation 狀態）、新增 FLUTTER_BUILD_FLAVORS（dev/staging/production 切換、production dart-define 範例、release 前確認 mock 已關）。
- 順序：**B1 →（checkpoint）→ B2∥B3 → B4**。

#### 8. 測試計畫
- `flutter analyze`（改動檔）→ No issues。
- `flutter test test/config/app_config_test.dart`（補 production mock 強制關閉斷言）。
- 新增 app.dart / AsrStrategyService 注入測試（production 無 taigi mock strategy；dev flag 下有）。
- `flutter test`（全量回歸，確認既有 mock 依賴測試不被改壞）。
- 無法跑 release 裝置驗證者誠實列為殘留（同 CR-0047 慣例）。

#### 9. 允許修改檔案清單（CR-0048 紅線）
**允許**：`lib/app.dart`（限 195-202）、`lib/screens/settings_screen.dart`（限手動 ASR dropdown）、`test/**`、`docs/CHANGE_REVIEW.md` / `docs/ENVIRONMENT_SETUP.md` / `docs/STORE_RELEASE_CHECKLIST.md` / `docs/FLUTTER_BUILD_FLAVORS.md`。
**紅線（不得碰）**：`lib/app.dart` 189-190、`realtime_voice_service.dart`、`voice_agent_controller.dart` 狀態機、`conversation_controller.dart` STT 選用、`ai_tool_router.dart` `_chat`、`sttMode` 預設、後端任何檔、授權鏈、Memory API、Care Alert notify auth。不得為過測試把正式 service 改 mock、不得 production fallback mock、不得移除 dev/test 測試替身、不得 hardcoded token、不得偽造 release build 通過。

#### 10. 裁決結論
- **✅ 核准 CR-0048（縮減範圍版）**：本案僅隔離 **MockTaigiAsrStrategy**（B1）+ 選配隱藏 mock dropdown（B2）+ 測試（B3）+ 文件（B4），由 frontend-ux-agent 執行，B1 後須 architecture read-only checkpoint（驗 diff 僅 195-202、189-190 未動、既有測試綠、無新 mock fallback）。
- **MockAiService / MockSpeechToTextService 隔離 → 退回本案範圍，另開 CR-0049**（owner=companion-memory-agent + 對話/Realtime owner；需先以正式回覆引擎 / 正式 STT 取代 consumer 選用，再 gating 注入；medium 風險、需 checkpoint）。理由：兩者為 production runtime live 依賴，純 wiring 移除會 crash 或破壞 Realtime 本地指令與按住說話，逾越 frontend-ux-agent 權責與本 CR「純 wiring 隔離」定位。
- **待辦（未由 architecture 親自改碼）**：B1–B4 交 frontend-ux-agent；CR-0049 待派工。本筆為提案 + 裁決，尚未執行任何程式改動與測試。

#### 11. 執行進度與 checkpoint 裁決（frontend-ux-agent 實作；architecture read-only checkpoint）
- **執行進度**：
  - B1 ✅ `lib/app.dart` AsrStrategyService strategies → `[const OpenAiRealtimeAsrStrategy(), if (AppConfig.mockServicesEnabled) const MockTaigiAsrStrategy()]`（加註解說明 fallback 與 CR-0049 移交）。
  - B2 ✅ `lib/screens/settings_screen.dart` 手動 ASR dropdown 的 `mockTaigiAsr` 選項以 `if (AppConfig.mockServicesEnabled)` 條件化（production 隱藏）。
  - B3 ✅ `test/config/asr_strategy_mock_gating_test.dart`（鏡像 app.dart 注入條件，dev/production 分流）。
  - B4 ✅ `docs/FLUTTER_BUILD_FLAVORS.md`（§3 隔離現況表誠實標註）+ `docs/ENVIRONMENT_SETUP.md` / `docs/STORE_RELEASE_CHECKLIST.md` 更新。
- **驗收（architecture 獨立覆驗）**：
  - `flutter test test/config/asr_strategy_mock_gating_test.dart`（dev）→ **5/5 passed**（architecture 親跑）。
  - 同檔 `--dart-define=APP_ENV=production --dart-define=API_BASE_URL=https://api.example.com --dart-define=ALLOW_MOCK_SERVICES=true`（誤帶 mock=true）→ **5/5 passed**（architecture 親跑；production 強制 mockServicesEnabled=false、不注入台語 mock、`strategyFor('mockTaigiAsr')` graceful fallback 回 `OpenAiRealtimeAsrStrategy`）。
  - frontend-ux-agent 回報全量 `flutter test` 501 passed + `flutter analyze` 乾淨（architecture 未親跑全量，採信其回報；單檔 gating 已親驗）。
- **checkpoint 逐項裁決（read-only diff / grep / 親跑）**：
  - (a) ✅ `app.dart` diff 僅限 AsrStrategyService strategies 區段；**189-190 MockAiService / MockSpeechToTextService 原樣未動**（`sed` 確認無條件 Provider 仍在）。
  - (b) ✅ `settings_screen.dart` 僅手動 ASR dropdown 條件化，其餘設定未動。
  - (c) ✅ production（mockServicesEnabled=false）不注入 MockTaigiAsrStrategy；`AsrStrategyService` 仍以 OpenAiRealtimeAsrStrategy 建構，`strategyFor` 三層 fallback（具名 → defaultOpenAiRealtime → `const OpenAiRealtimeAsrStrategy()`）保 Realtime ASR 不破（親跑測試佐證）。
  - (d) ✅ 無新增 mock fallback；未為過測試把正式 service 改 mock；未移除 dev/test 測試替身（既有自建 `AsrStrategyService(strategies:[...MockTaigiAsrStrategy()])` 測試不依賴 app.dart 注入，續綠）。
  - (e) ✅ `realtime_voice_service.dart` / `voice_agent_controller.dart` / `conversation_controller.dart` / `ai_tool_router.dart` `git diff --quiet` 確認**未碰**；`sttMode` 預設、`_chat`、狀態機、STT 選用未動（不在 diff 名單）。
  - (f) ✅ 文件誠實標註 `MockAiService` / `MockSpeechToTextService` 仍為 production runtime live 依賴、延後 **CR-0049**，未聲稱已全數隔離（FLUTTER_BUILD_FLAVORS.md §3 表格 ⛔ + §送審 blocker 註記）。
- **checkpoint 裁決：✅ PASS**。CR-0048（縮減範圍版）按核准紅線落地，未越界、未破壞 Realtime 主流程。
- **完成狀態：CLOSED（已實作 + 已驗收 + checkpoint PASS）**。commit 由 frontend-ux-agent 執行（排除噪音檔 `CLAUDE.md` / `ios/.../Runner.xcscheme` / `PROJECT_REPORT_DRAFT.md`）。
- **明確殘留（移交 CR-0049，送審 blocker）**：
  1. `MockAiService` production 隔離：`AiToolRouter._chat()` 須先改接正式回覆引擎，再 gating 注入。
  2. `MockSpeechToTextService` production 隔離：`ConversationController` 的 `sttMode` production 預設須改 `openAiProxy`，再 gating 注入。
  3. release 裝置（iOS Release build，無 debug banner / 無 mock）驗證列為 CR-0049 後續 FU；本案僅 host/test 驗證，未做 release 裝置驗證。

---

### CR-0049 — Production AI and STT Service Replacement Before Mock Gating（接 CR-0048；解 CR-0048 揭露的兩個送審 blocker：`MockAiService` / `MockSpeechToTextService` 仍為 production runtime live 依賴；高風險跨層 CR，先替換正式 service 再 gating，不得破壞 Realtime 主流程 / Care Alert notify auth / Memory / Companion Engine）
- 提出 / 裁決 agent：architecture-agent（依使用者指派；任務書 `tasks/CR-0049-production-ai-and-stt-service-replacement-before-mock-gating.md`）
- 日期：2026-06-09
- 帳本正規 ID = **CR-0049**（沿用「下一個空號」；CR-0048 已 CLOSED）
- 狀態：**提案 + 裁決（含拆 CR）+ 批次切分。尚未執行任何程式改動，未跑測試。** 內含一個需使用者拍板的產品/範圍決策點（見 §8）。

#### 1. 動機
CR-0048 收斂時明確標註兩個未解送審 blocker（本檔 2580-2582、`FLUTTER_BUILD_FLAVORS.md` §3 表格 ⛔）：正式 build 仍**無條件**注入 `MockAiService`（app.dart:189）與 `MockSpeechToTextService`（app.dart:190），且兩者**被 production runtime 選用**（非死碼）。CLAUDE.md（store 版）§2.1 列「mock service / fake response / fake transcript / JSON fallback 作為正式資料來源」為正式版不可接受內容。本 CR 須先讓 consumer 在 production 改用**正式回覆引擎 / 正式 STT**，再做注入 gating（純拔會 crash 或產生假回覆/無回覆）。

#### 2. 深入調查結論（A–D，已逐檔精讀並覆核 CR-0048 盤點）

**A. press-to-talk `_chat` 罐頭回覆是正式功能還是 dev/demo-only？**
- **正式語音主路徑 = OpenAI Realtime**（`VoiceAgentController` + `RealtimeVoiceService`，data channel 產生真回覆）。`_chat`→`MockAiService.replyForChat()` 是**同步罐頭文字**（mock_ai_service.dart 全檔為關鍵字模板），非真 AI。
- **press-to-talk 音訊方法（`onPressToTalkStart/End`）目前在 UI 完全未接線**（`grep` 全 lib 僅 controller 內定義，無任何 screen/widget 呼叫）→ 屬 legacy/dead 入口，**「按住說話 STT」目前不對使用者開放**。
- `_chat` 的**真正 production live consumer**是：
  1. **打字聊天**：`home_screen._sendTextMessage()`（535）在「**不在 Realtime live 對話**」時 → `conversationController.quickAction()` → `_handleUserText` → `toolRouter.route()` → 非工具語句落 `_chat` → MockAiService 罐頭。**這是 production 可達、且會產生假回覆的路徑 → blocker 主因。**
  2. `task_screen` 指令按鈕 → `quickAction()`（多為工具意圖，但自由語句也會落 `_chat`）。
  3. **Realtime 本地指令邊界**：`voice_agent_controller._routeToolsForTranscript()`（741）→ `shouldHandleAsLocalCommand()` 為 true 時呼叫 `_handleLocalRealtimeCommand()`（674-685）→ `toolRouter.route(text)`。`shouldHandleAsLocalCommand` 含**提醒指令**，但 `route()` **沒有提醒分支**（提醒在 `_handleUserText` 處理，不在 router），故「提醒類」transcript 進 `route()` 會**穿透落 `_chat`**，且 `result.shouldSpeak=true` → 經 `realtimeVoiceService.speakToolOutcome()` **把罐頭句念出來**（疊在真正的 Realtime 回覆之上）。
- 結論：press-to-talk `_chat` 罐頭在 production **是會被觸發的假回覆**（主要經打字聊天 offline + Realtime 提醒邊界），**非單純 dev-only**；正式語音對話本體仍是 Realtime 真回覆。

**B. 是否已有可用的正式「聊天回覆」來源？**
- **沒有。** 後端 `/api/companion/analyze`（server.js:1579）回的是 `emotion / replyStrategy / implicitMeaning / memory / safety / nextStrategy / fusion`——**分析資料，不含可顯示的 chat reply 文字**。
- 後端唯二用 LLM 產生自然語句的端點是 `/api/memory/greeting`（1842，只產問候）與 `/api/conversation/title`（1928，只產標題），**都不是通用聊天回覆**。
- 結論：**正式「文字聊天回覆」目前無後端 endpoint。** 要做真回覆，需 backend-agent **新增一支 chat adapter**（例如 `POST /api/companion/chat`，回 `{success, reply}`）；**Flutter 端不可放 OpenAI key**。打字聊天回覆無法靠現有 API 取代 mock。

**C. Realtime 本地指令用 MockAiService 罐頭，production 可接受嗎？**
- **不可接受。** 在 Realtime live 對話中，本應由 OpenAI Realtime 產生回覆；`_handleLocalRealtimeCommand` 對「穿透到 `_chat` 的罐頭句」做 `speakToolOutcome` 會疊念一段假罐頭。**裁決：Realtime 本地指令路徑只念「確定性工具結果」（簽到/購買/設定/查詢/陪伴內容），不念 `_chat` 罐頭**，聊天回覆交給 Realtime。

**D. STT：production 預設改 openAiProxy 是否足夠且安全？443/772 fallback 如何處理？**
- 預設改 `openAiProxy` **足夠且安全**：`OpenAiSpeechToTextService`（→ `/api/stt/transcribe`，server.js:1667，`gpt-4o-transcribe`）金鑰在後端，Flutter 不持 key。`OpenAiSpeechToTextService` 與 `MockSpeechToTextService` **皆 implements `SpeechToTextService`**（介面乾淨，可直接替換注入）。
- `conversation_controller` **443 / 772 兩處 `setSttMode(SttMode.mock)` 是 production fallback-to-mock**，且 774/439 對長者顯示「**已為你切換到 Mock STT**」工程字樣——**雙重違規**（production fallback mock + 工程字樣）。**裁決：production 移除這兩條 mock fallback，改長者友善錯誤訊息（不切 mock、不假成功）。**
- press-to-talk 音訊 STT 入口未接線（見 A），**production 無需隱藏額外 UI**；STT 替換實質只需 (1) 預設值 (2) 移除兩處 fallback (3) provider 注入正式 service。設定頁亦**無 user-facing STT mode 下拉**（settings 僅手動 ASR strategy 下拉，CR-0048 已處理），無「Mock STT」可見選項殘留。

#### 3. 五點裁決
1. **AI 路徑**：採 **(i)+(ii) 混合**——
   - **(i) 正式 chat adapter**：backend-agent 新增 `POST /api/companion/chat`（companion persona + 可選 memory context，回 `{success, reply}`；不破壞 `/api/companion/analyze` 契約；不碰 Realtime 路由）。Flutter 新增 `CompanionChatService`（HTTP，無 key）。`AiToolRouter._chat` 在 production 改用它；失敗 → **陪伴式白話錯誤**（不假 AI 成功、不 silent mock）。reply 組裝/persona/memory 由 companion-memory-agent 主導。
   - **(ii) Realtime 本地指令不念 `_chat` 罐頭**（見 C）：聊天回覆交 Realtime。
   - dev/test 仍可注入 `MockAiService` 作 `_chat` 後援。
2. **STT 路徑**：production 預設 `sttMode → openAiProxy`；移除 conversation_controller 443/772 的 mock fallback → 長者友善錯誤（不切 mock）；`ConversationController` 的 STT 欄位由具體 `MockSpeechToTextService` **泛化為 `SpeechToTextService` 介面**，production 注入 `OpenAiSpeechToTextService`，dev/test 注入 mock。press-to-talk 音訊入口維持未接線（不另開、不 mock）。
3. **拆 CR**：**是，拆三子 CR**（本案同動 AI + STT + 新後端 endpoint + Realtime 邊界，過大且風險不一）：
   - **CR-0049-A（STT 替換）**：medium-low。預設值 + 移除兩處 fallback + STT 介面注入 + 測試。**不動 AI、不動後端、可獨立驗證。先做。**
   - **CR-0049-B（AI 聊天回覆替換）**：high（跨 backend / companion-memory / 對話 / Realtime 邊界）。新增 `/api/companion/chat` + `CompanionChatService` + `_chat` rewire + Realtime 本地指令不念罐頭 + 測試。
   - **CR-0049-C（最終 gating）**：medium。app.dart 189-190 把兩 mock 注入收進 `if (AppConfig.mockServicesEnabled)`；測試斷言 production 樹無 mock。**須在 A、B 都落地後才做**（兩 consumer 在 production 都不再依賴 mock 才能安全 gating）。
   - 順序：**A → B →（兩者皆綠後）C**。A、B 檔案不重疊，可部分並行；C 必為最後。
4. **批次切分 + owner + 🔒/checkpoint**：見 §5。
5. **app.dart 189-190 gating 前置條件**：唯有當 (A) `ConversationController` 在 production 不再需要 mock STT（介面注入已切正式）**且** (B) `AiToolRouter._chat` 在 production 不再依賴 `MockAiService`（chat adapter 已接）後，才可把 189-190 改為 `if (AppConfig.mockServicesEnabled)`。同時 `AiToolRouter` / `ConversationController` 建構子須改成接受**正式 service**（不可仍 require mock 型別），否則 gating 後 production 缺 provider 會 crash。此即 CR-0049-C。

#### 4. 觸及 🔒 / 牽涉 agent
- 🔒：**CR-0049-B 觸及 `backend/stt_proxy/server.js`（新增 `/api/companion/chat`，須先更新 `PROJECT_ARCHITECTURE.md` 契約再放行，architecture checkpoint）**。`realtime_voice_service.dart` **全程不得碰**。app.dart（App root）+ conversation_controller STT 選用 + voice_agent 本地指令 = Realtime-adjacent，**均需 architecture read-only checkpoint**。
- agent：**conversation/Realtime owner**（A1 STT 選用、B4 本地指令念讀）、**companion-memory-agent**（B2/B3 回覆來源/persona/memory）、**backend-agent**（B1 新 endpoint）、**frontend-ux-agent**（A2/B2 wiring、C gating、settings/docs）。

#### 5. 批次切分（含 owner / 順序 / 🔒 / checkpoint / 允許檔案）

**CR-0049-A（STT 替換）— owner：conversation/Realtime owner（A1）+ frontend-ux-agent（A2/A3）**
- **A1**（medium-low，**checkpoint**；conversation_controller 屬 Realtime-adjacent）：`lib/controllers/conversation_controller.dart` 將 `mockSttService` 欄位泛化為 `SpeechToTextService sttService`（建構子注入），`_currentSttService()` 於 `openAiProxy` 回注入的正式 service；**移除 443、772 兩處 `setSttMode(SttMode.mock)` fallback**，改長者友善錯誤（不切 mock、不假成功、不顯示「Mock STT」）。**不得改 Realtime transcript 流程（`commit/updateRealtime*`）、不得改狀態機。**
- **A2**（low，**checkpoint**；app.dart App root）：`lib/models/user_profile.dart`（或 `profile_controller` 預設解析）production 預設 `sttMode → openAiProxy`（以 `AppConfig` 區分 dev/prod，避免硬切影響既有測試預期）；`lib/app.dart` STT provider 注入——production 注入 `OpenAiSpeechToTextService`，mock 僅 `if (AppConfig.mockServicesEnabled)`。**本批不動 189-190 的最終 gating 形態（留給 C），但須讓 ConversationController 改吃介面。**
- **A3**（low）：測試。production 預設非 mock；STT 失敗 → 友善錯誤、**不 fallback mock**；dev/test 可注入 mock；既有 conversation/Realtime 測試全綠。
- 允許檔案：`conversation_controller.dart`（STT 選用區，限 371-376 / 413-445 / 767-785）、`user_profile.dart` / `profile_controller.dart`（sttMode 預設）、`app.dart`（STT provider 注入）、`test/**`、本文件 / `FLUTTER_BUILD_FLAVORS.md` / `STORE_RELEASE_CHECKLIST.md`。

**CR-0049-B（AI 聊天回覆替換）— owner：backend-agent（B1）+ companion-memory-agent（B2/B3）+ conversation/Realtime owner（B4）+ frontend-ux-agent（wiring）**
- **B1**（high，🔒，**先更新 `PROJECT_ARCHITECTURE.md` 再放行 + checkpoint**）：`backend/stt_proxy/server.js` 新增 `POST /api/companion/chat`（companion persona + 可選 memory context，回 `{success, reply, ...}`）。**不得改 `/api/companion/analyze`、`/api/stt/transcribe`、任何 `/api/realtime/*` 契約；不得提交 `.env` / token / runtime `data/*.json`。**
- **B2**（medium，companion-memory-agent + frontend-ux-agent）：Flutter `CompanionChatService`（HTTP → `/api/companion/chat`，無 key）；persona/memory 組裝邏輯由 companion-memory-agent 定。
- **B3**（high，companion-memory-agent + conversation owner，**checkpoint**）：`ai_tool_router.dart` `_chat` production 改用 `CompanionChatService`；失敗 → 陪伴式白話錯誤（**不假成功、不 silent mock**）。**工具 flow（route 其餘分支）一字不動**；dev/test 仍可走 `MockAiService`。
- **B4**（medium，conversation/Realtime owner，**checkpoint**）：`voice_agent_controller._handleLocalRealtimeCommand` / `_routeToolsForTranscript`——Realtime 本地指令**只念確定性工具結果，不念 `_chat` 罐頭**（聊天交 Realtime）。**不得改語音狀態機、不得碰 `realtime_voice_service.dart`。**
- **B5**（low）：測試。`_chat` production 走正式 adapter；正式 AI 失敗不 fallback mock；Realtime 本地指令不念罐頭；既有 tool calling / Realtime 測試全綠；Care Alert notify auth 測試不受影響。
- 允許檔案：`server.js`（限新增 `/api/companion/chat`）、新增 `lib/services/companion_chat_service.dart`、`ai_tool_router.dart`（限 `_chat`）、`voice_agent_controller.dart`（限本地指令念讀）、companion reply 相關 service、`app.dart`（chat service provider）、`test/**`、`PROJECT_ARCHITECTURE.md`、本文件。

**CR-0049-C（最終 gating）— owner：frontend-ux-agent**
- **C1**（medium，**checkpoint**；App root）：`lib/app.dart` 189-190 → `if (AppConfig.mockServicesEnabled)` 包覆兩 mock 注入；確保 `AiToolRouter` / `ConversationController` 建構子已吃正式 service（A、B 完成後）。
- **C2**（low）：測試斷言 production provider 樹**不含** `MockAiService` / `MockSpeechToTextService`；`FLUTTER_BUILD_FLAVORS.md` §3 表格兩列 ⛔ → ✅、移除送審 blocker 註記；`STORE_RELEASE_CHECKLIST.md` 更新。
- **前置**：A、B 全綠且 checkpoint PASS 才可動 C（見 §3 裁決 5）。

#### 6. 風險
- CR-0049-A：**medium-low**（移除 fallback 與介面泛化牽動按住說話/打字 STT 錯誤路徑，但 press-to-talk 入口未接線、介面乾淨）。
- CR-0049-B：**high**（新後端 endpoint + `_chat` 回覆引擎更換 + Realtime 邊界；跨四 owner）。
- CR-0049-C：**medium**（App root wiring；但前置已讓 consumer 不依賴 mock，故為收尾）。

#### 7. 必守紅線（任務 §11，全子 CR 適用）
不破壞 Realtime WebRTC 主流程 / Care Alert notify auth / Memory API / Companion Engine；**Flutter 端不放 OpenAI key**；不用 fake response 取代正式 AI；不用 fake transcript 取代正式 STT；**production 不 fallback mock**；不硬刪 mock 害 dev/test 失效；不為過測試放寬 production guard；不提交 `.env` / token / runtime `data/*.json`；`realtime_voice_service.dart` 不得碰。

#### 8. 需使用者拍板的決策點（派工前）
- **CR-0049-B 的 AI 路徑成本/範圍**：principled 解法是 backend-agent 新增 `POST /api/companion/chat`（一支 LLM chat completion，含 persona + memory；有 token 成本與後端工作量）。**替代輕量方案**：production 打字輸入只路由「工具/指令/查詢/陪伴內容/Realtime」，純閒聊打字（offline）改顯示「我們用語音聊更自然喔」的引導，不產任何罐頭回覆——可不新增 LLM endpoint 即移除假回覆，但降級打字閒聊體驗。**此為產品/範圍取捨，建議由使用者拍板採『新增 chat endpoint』或『限制打字閒聊』後，再派 CR-0049-B。** CR-0049-A 與此決策無關，可立即派工。

#### 9. 裁決結論
- **✅ 核准 CR-0049 拆為 A / B / C 三子 CR**，順序 A → B →（皆綠後）C。
- **CR-0049-A 可立即派工**（owner：conversation/Realtime owner + frontend-ux-agent；A1 checkpoint）。
- **CR-0049-B 待 §8 產品決策拍板後派工**（owner：backend-agent + companion-memory-agent + conversation/Realtime owner + frontend-ux-agent；B1 🔒 須先更 `PROJECT_ARCHITECTURE.md`）。
- **CR-0049-C 為最後收尾**（owner：frontend-ux-agent），前置 = A、B 全綠 + checkpoint PASS。
- 本筆為 architecture 提案 + 裁決，**未執行任何程式改動、未跑測試**。

---

### CR-0049-A / CR-0049-B1 — Checkpoint Review（architecture-agent，read-only 覆驗）

**範圍**：CR-0049-A（Flutter STT 替換，frontend-ux + conversation owner）已落地；CR-0049-B1（後端 `POST /api/companion/chat`，backend-agent，🔒）已落地。本筆為實作後的 checkpoint 審查與裁決。

#### 執行進度

- **CR-0049-A**：✅ 已實作。
  - production 雙重守衛：`user_profile.dart` `UserProfile.initial()` `sttMode = AppConfig.isProduction ? 'openAiProxy' : 'mock'`；`profile_controller.sttMode` getter 於 `AppConfig.isProduction` 強制回 `SttMode.openAiProxy`（即使儲存值為舊 `'mock'`）。
  - `conversation_controller.dart` 欄位 `mockSttService` → `SpeechToTextService sttService`（介面注入）；`_currentSttService()` 回注入服務；`app.dart` 依 `AppConfig.mockServicesEnabled` 注入 `OpenAiSpeechToTextService(proxyUrl)` 或 mock。
  - 移除兩處 production mock fallback（`onPressToTalkEnd` / `_processSttResult`），改長者友善白話錯誤，dev/test 以 `AppConfig.mockServicesEnabled` 守衛保留 mock 備援。
  - `openai_speech_to_text_service.dart` 兩則訊息去「Mock 模式/STT」工程字樣。
  - 新增 `test/conversation_controller_stt_production_test.dart`；5 個既有測試建構子 `mockSttService` → `sttService`。
- **CR-0049-B1**：✅ 已實作。
  - 新增 `services/companionChatService.js`（純函式，OpenAI client / model / logger 由 deps 注入）+ `server.js` `POST /api/companion/chat`。
  - persona 重用 `buildRealtimeInstructions`（簽名相容：`(petName, [], memoryBlock, "", {languageHint, replyLanguage})`，memoryBlock 進 memoryContext 參數）；金鑰留後端。
  - 先更 `PROJECT_ARCHITECTURE.md` §4 契約再實作（契約與實作一致）。
  - 新增 `companionChatService.test.js` + `companionChatEndpoint.test.js`（8 案）；`package.json` check/test 已掛入。

#### Checkpoint 驗收（architecture-agent 獨立覆驗，非僅採信回報）

- 🔒 守線：`realtime_voice_service.dart` / `ai_tool_router.dart` / `mock_ai_service.dart` `git diff --quiet` = **UNTOUCHED**；`app.dart` 190-191 `MockAiService` / `MockSpeechToTextService` Provider 仍無條件宣告（C 範圍，未動）；line 223 `mockAiService` 仍接 `AiToolRouter`（_chat 路徑屬 B2/B3，未動）。
- A 驗收：(a) production 雙重守衛 → `openAiProxy` ✅；(b) 移除 mock fallback、改白話錯誤、無「Mock/STT」工程字樣 ✅（新測試斷言 `latestReply` 不含 `Mock`/`STT` 且 `sttMode` 仍 `openAiProxy`）；(c) dev/test mock 以 `mockServicesEnabled` 守衛仍可用 ✅；(d) 未碰 realtime/_chat/MockAiService/app.dart 190-191 ✅；(e) 既有測試綠 ✅。
- B1 驗收：(f) 失敗回 `{success:false,error}`（400 `invalid_input` / 503 `openai_unavailable`），不回 fake reply/stack ✅；(g) Flutter 不放 key、OpenAI 後端代理 ✅；(h) 未破壞 `/api/companion/analyze`（diff 僅在其後新增 route）、`/api/stt/transcribe`、Realtime、Memory、Care Alert notify 契約 ✅；(i) `PROJECT_ARCHITECTURE.md` §4 契約與實作一致 ✅；(j) log 經 `safeErrorMessage` redaction、成功路徑不呼叫 logError、不外洩 userText/reply/token ✅（測試覆蓋）。

#### 覆驗測試結果（architecture-agent 實跑）

- backend `npm test`：**446/446 pass（含新 8 案）**，0 fail。
- `node --test companionChatService.test.js companionChatEndpoint.test.js`：8/8 pass。
- `flutter analyze`（5 個觸及檔）：**No issues found**。
- `flutter test conversation_controller_stt_production + conversation_controller_ui_state + voice_agent_controller_realtime_lifecycle`：**54 passed**。

#### 裁決

- **PASS** — CR-0049-A 與 CR-0049-B1 通過 checkpoint，併入主線。🔒 `server.js` 路由新增經 architecture-agent 核准（契約先行、紅線未越）。

#### 待做 / follow-up（尚未實作）

- **CR-0049-B2**（frontend-ux + companion-memory）：Flutter `CompanionChatService`（HTTP → `/api/companion/chat`，前端不放 key）。
- **CR-0049-B3**（companion-memory + conversation owner，checkpoint）：`ai_tool_router.dart` `_chat` production 改用 `CompanionChatService`，失敗給陪伴式白話錯誤（不假成功、不 silent mock）；dev/test 仍走 `MockAiService`。
- **CR-0049-B4**（conversation/Realtime owner，checkpoint）：Realtime 本地指令只念確定性工具結果、不念 `_chat` 罐頭；不碰 `realtime_voice_service.dart` 與狀態機。
- **CR-0049-C**（frontend-ux，checkpoint）：`app.dart` 190-191 兩 mock Provider 以 `if (AppConfig.mockServicesEnabled)` 包覆 + 測試斷言 production provider 樹不含 mock；前置 = A、B 全綠 + checkpoint PASS。
- **persona follow-up**（companion-memory）：`buildRealtimeInstructions` persona 偏即時語音/工具化，打字閒聊建議後續細修 chat 變體，使打字回覆語氣更貼近陪伴而非工具化。

---

### CR-0049 B2 / B3 / B4 — 執行 micro-plan（architecture-agent 定案，可直接派工）

**前提**：CR-0049-A（commit c4fe416）+ B1（commit 3d20c7b, `POST /api/companion/chat`）已 PASS。後端契約已覆驗：無 auth；body `userText`(必填)/`petName`/`memoryContextSummary`/`languageHint?`/`replyLanguage?`；200 `{success:true,reply}`；400 `{success:false,error:'invalid_input'}`；503 `{success:false,error:'openai_unavailable'}`（`server.js:1680-1725`）。

**關鍵架構決定（B4）**：root cause 已覆驗 = `ai_tool_router.route()`（`ai_tool_router.dart:39-69`）無提醒分支；提醒建立邏輯只在 `conversation_controller._handleUserText`（`850-882`，typed 路徑、在 `route()` 之前 return）。Realtime 走 `voice_agent_controller._handleLocalRealtimeCommand`（`674-685`）直接呼 `toolRouter.route()` → 提醒命令穿透落 `_chat` → `speakToolOutcome` 念罐頭，且**提醒從未被建立**。
**裁決：B4 在 router 層解決，不碰任何 Realtime 檔**。把提醒分支加進 `route()`、`reminderController` 注入 `AiToolRouter`，回 `shouldSpeak:false`（Realtime 由寵物語音自然回應、不念罐頭；typed 路徑因 `850` 先 return 永不走到此分支 → 零重複建立）。`_handleLocalRealtimeCommand:681` 既有守衛 `result.shouldSpeak && message.isNotEmpty` 會自動因 `shouldSpeak:false` 不念。**無需 realtime-voice-agent，無需改 `voice_agent_controller`/`realtime_voice_service`。**

#### 批次 B2 — `CompanionChatService`（Flutter HTTP client）
- **owner**：frontend-ux-agent
- **允許檔**：新增 `lib/services/companion_chat_service.dart`；新增 `test/services/companion_chat_service_test.dart`
- **做法**（比照 `care_alert_notification_service.dart` 慣例，但**不吞失敗**）：
  - `CompanionChatService({http.Client? client})`，無 authTokenProvider（B1 路由無 auth）。
  - URL 組裝沿用 `AppConfig.apiBaseUrlForSttProxy(sttProxyUrl)` + path `'/companion/chat'`（同 care_alert 的 basePath 去尾斜線寫法）。
  - 方法簽名：
    `Future<String> reply({required String sttProxyUrl, required String userText, required String petName, String memoryContextSummary = '', String? languageHint, String? replyLanguage}) async`
  - 成功（200 + `success:true`）→ 回 `reply` 字串。
  - 失敗（非 200 / `success:false` / timeout / 網路錯誤 / `reply` 空）→ **throw `CompanionChatException`**（自訂，帶 `code`：`'invalid_input'|'openai_unavailable'|'network'`）。**不得回 mock、不得回假文案**——交由 B3 `_chat` 決定友善錯誤。
  - `.timeout(Duration(seconds: 8))`；body `jsonEncode`；header 僅 `Content-Type: application/json`；**不放任何 key**。
- **紅線**：不碰後端；不碰 Realtime；不吞成靜默成功；不放 key。
- **測試**：MockClient → (a) 200 success 回 reply；(b) 400 `invalid_input` → throw code=`invalid_input`；(c) 503 → throw code=`openai_unavailable`；(d) 網路 throw → code=`network`；(e) request body 不含任何 key 字樣。

#### 批次 B3 — `AiToolRouter._chat` production 化 + B4 提醒分支（**router 與 app.dart 須同一 checkpoint 落地**）
**B3a — router 邏輯**
- **owner**：companion-memory-agent
- **允許檔**：`lib/services/ai_tool_router.dart`
- **做法**：
  1. import `companion_chat_service.dart`、`../controllers/reminder_controller.dart`、`../config/app_config.dart`。
  2. 建構子（`14-37`）新增 `required this.companionChatService`、`required this.reminderController`，並加 `bool? useMockChat`，欄位 `late final bool useMockChat`（init list：`useMockChat ?? AppConfig.mockServicesEnabled`）。**保留 `mockAiService`**（dev/test 仍用，紅線：不可硬刪）。
  3. `route()`（`43-44` normalize 之後、`_isDailyCheckIn` 之前）插入提醒分支（B4）：
     `if (reminderController.isCreateReminderCommand(normalized)) return _createReminder(normalized);`
     `if (reminderController.isListReminderCommand(normalized)) return _listReminders();`
  4. 新增 `_createReminder`／`_listReminders`：呼 `reminderController.createFromVoice` / `listSummary()`；回 `toolName:'createReminder'|'listReminders'`、`shouldSpeak:false`、message 用既有 `850-882` 同款白話文案（建立失敗時友善提示時間沒聽清楚）。**`shouldSpeak:false` 是 B4 關鍵**。
  5. `_chat`（`476-502`）改 `Future<AiToolResult> _chat(...) async`；petMode 判斷邏輯原樣保留（可抽 `_chatPetMode(text)`）。分支：
     - `useMockChat == true` → `mockAiService.replyForChat(...)`（原行為，dev/test）。
     - 否則 → `await companionChatService.reply(sttProxyUrl: profileController.sttProxyUrl, userText: text, petName: profileController.petName, memoryContextSummary: memoryContextSummary)`；成功回 `success:true`。
     - `on CompanionChatException` → message = 陪伴式白話錯誤（**companion-memory 撰寫**，例如「我這邊有點不穩，等我一下再陪你聊好嗎？」），`success:false`、`shouldSpeak:true`。**不得 fallback mockAiService、不得假裝聽懂**。
  6. `route()` 已是 `Future<AiToolResult>`，`return _chat(...)`（async 回 Future）→ **route() caller 零 async ripple**（已覆驗：`home_screen:535`→quickAction、`task_screen:34`→quickAction、`conversation_controller:926`、`voice_agent_controller:677/744` 全部已 `await route()`）。
- **紅線**：不碰 Realtime/狀態機；不刪 `mockAiService`；production 不 fallback mock/不假回覆；提醒分支 `shouldSpeak:false`。

**B3b — DI 接線（與 B3a 同 PR / 同 checkpoint，否則 build 紅）**
- **owner**：frontend-ux-agent
- **允許檔**：`lib/app.dart`
- **做法**：(1) 新增 `Provider<CompanionChatService>(create: (_) => CompanionChatService())`（置於 `AiToolRouter` provider 之前）。(2) `AiToolRouter` create（`213-225`）新增 `companionChatService: context.read<CompanionChatService>()`、`reminderController: context.read<ReminderController>()`（`ReminderController` 已於 provider 樹存在，`274` 已 read，lazy create 順序安全）。**本批不動 `190-191`、不動 `223` mockAiService 接線（C 範圍）**。
- **紅線**：不改後端/Realtime；不改 STT 注入；不動 190-191/223。

#### owner 指派總表
| 批次 | owner | 檔案 |
|---|---|---|
| B2 | frontend-ux | `lib/services/companion_chat_service.dart`(+test) |
| B3a | companion-memory | `lib/services/ai_tool_router.dart` |
| B3b | frontend-ux | `lib/app.dart`（與 B3a 同 checkpoint） |
| B4 | （併入 B3a，companion-memory）| 同 `ai_tool_router.dart` |
- **realtime-voice-agent：不需出動**（B4 在 router 層解，Realtime 檔 untouched）。

#### 執行順序
1. B2（獨立、無依賴）→ commit。
2. B3a + B3b（建構子耦合，**同一 commit/checkpoint**，避免中途 build 紅）→ B4 提醒分支含於 B3a。
3. checkpoint 覆驗 → C。

#### 測試計畫（checkpoint 須全綠）
- B2：見上（`companion_chat_service_test.dart`）。
- B3/B4 `test/services/ai_tool_router_*`（新增或擴充）：
  - `useMockChat:false` + `CompanionChatService`(MockClient 200) → `_chat` 回後端 reply、`success:true`、`shouldSpeak:true`。
  - `useMockChat:false` + 後端失敗（throw）→ `_chat` 回友善錯誤、`success:false`、訊息**不等於** mock reply、**未呼叫** `mockAiService`（用會 throw 的 spy 斷言）。
  - `useMockChat:true` → 走 `mockAiService.replyForChat`（既有行為保留）。
  - `route('提醒我晚上八點吃藥')` → `toolName:'createReminder'`、`shouldSpeak:false`、`reminderController` 確有建立。
  - `route('我的提醒')` → `listReminders`、`shouldSpeak:false`。
- B4 回歸（既有 `voice_agent_controller_realtime_lifecycle_test` 或 `integration/agent_voice_turn_integration_test`，**不改 Realtime 檔**）：Realtime 提醒命令 → fake `realtimeVoiceService.speakToolOutcome` **未被呼叫**。
- 既有 `ai_tool_router` / `conversation_controller_*` / `voice_agent_controller_*` 全綠（route() 仍 async、caller 不變）。
- 指令：`flutter analyze`（觸及檔）+ `flutter test`（上列 + 既有相關）。**不需 .env / 不需 key**（MockClient）。

#### CR-0049-C 前置（B2/B3/B4 全綠 + checkpoint PASS 後才動）
- **owner**：frontend-ux，checkpoint。
- 收尾步驟：
  1. `ai_tool_router.dart`：`mockAiService` 改 nullable（僅 `useMockChat` 時使用），production 不再結構性依賴。
  2. `app.dart:190` `MockAiService` Provider 以 `if (AppConfig.mockServicesEnabled)` 包覆；`223` `mockAiService:` 改條件/可空注入。
  3. `app.dart:191` `MockSpeechToTextService` + `ConversationController` 的 `ChangeNotifierProxyProvider6`（`280-287` 第 5 泛型 `MockSpeechToTextService`、`296` 讀取）需改寫泛型/注入，使 production provider 樹**零 mock 實例化**（STT 已於 `295-297` 條件注入，僅剩 proxy 泛型結構待解）。
  4. 測試斷言：production build flag 下 provider 樹不含 `MockAiService`/`MockSpeechToTextService`。
- **紅線**：dev/test mock 不可硬刪，只可 gating。


---

### CR-0049 B2 / B3a / B3b / B4 — Checkpoint Review（architecture-agent，read-only 覆驗）

**範圍**：CR-0049-B 的 B2（`CompanionChatService`）+ B3a（`ai_tool_router` rewire）+ B4（router 提醒分支）+ B3b（`app.dart` 接線）已落地。B3a/B3b 依定案同一 checkpoint。本筆為實作後 read-only 覆驗與裁決。**CR-0049-C（gating）尚未做。**

#### 執行進度
- **B2** ✅ 新增 `lib/services/companion_chat_service.dart`：`reply({required userText, petName, memoryContextSummary, languageHint?, replyLanguage?})`，成功回非空 reply；失敗（非 200 / `success!=true` / `reply` 空 / JSON 壞 / 網路 / timeout 10s）一律 throw `CompanionChatException(code,message)`。不放 key（header 僅 `Content-Type`，body 僅脈絡欄位）、不吞錯、不回 fake/空。+ `test/services/companion_chat_service_test.dart`（13）。
- **B3a** ✅ `lib/services/ai_tool_router.dart`：建構子加 `companionChatService`/`reminderController`/`bool? useMockChat`（省略=`AppConfig.mockServicesEnabled`）；`_chat` 改 async——`useMockChat==true`→`mockAiService.replyForChat`（dev/test 既有行為）、否則 `await companionChatService.reply(...)`，`on CompanionChatException`→回陪伴式白話（`success:false`、`shouldSpeak:true`），**不 fallback mock、不假成功**。保留 `mockAiService`。
- **B4** ✅（併入 B3a）`route()` 於 normalize 後、`_isDailyCheckIn` 前加提醒分支：`_createReminder`（呼 `reminderController.createFromVoice`，`shouldSpeak:false`）/`_listReminders`（`listSummary()`，`shouldSpeak:false`）。Realtime 不念罐頭、交寵物語音自然回應。
- **B3b** ✅ `lib/app.dart`：新增 `Provider<CompanionChatService>`（line 189，置於 `AiToolRouter` provider 前）；`AiToolRouter` create 補 `companionChatService`/`reminderController`（`useMockChat` 省略）。**未動 194-195 mock Provider 宣告與 `mockAiService:` 接線（C 範圍）**。
- 測試：新增 `test/services/ai_tool_router_chat_test.dart`（5）；6 既有測試補新建構子參數（`useMockChat:true` 維持既有行為）：`care_alert_hook_test`、`conversation_controller_stt_production_test`、`conversation_controller_ui_state_test`、`home_screen_layout_test`、`integration/agent_voice_turn_integration_test`、`voice_agent_controller_realtime_lifecycle_test`。

#### architecture 獨立覆驗（read-only，全部親跑）
- (a) ✅ production `_chat`（`ai_tool_router.dart:574-597`）走 `companionChatService.reply`，`on CompanionChatException`→友善白話 `success:false`/`shouldSpeak:true`，**無 mockAiService fallback、無假成功**。
- (b) ✅ dev/test（`useMockChat==true`，`560-572`）走 `mockAiService.replyForChat`，既有行為不變。
- (c) ✅ B4 提醒分支 `_createReminder`/`_listReminders` 皆 `shouldSpeak:false`（`521`、`532`）。conversation_controller typed 路徑於 `850-870` 先建立提醒並 `return`，永不落到 `route()` → **零重複建立**確認。
- (d) ✅ `git diff --quiet HEAD -- lib/services/realtime_voice_service.dart lib/controllers/voice_agent_controller.dart` → UNTOUCHED。`conversation_controller.dart` 亦未碰。B4 純於 router 層解。
- (e) ✅ `CompanionChatService` 不放 key、失敗 throw `CompanionChatException`（不吞、不回 fake）。
- (f) ✅ `app.dart` 194-195 `MockAiService`/`MockSpeechToTextService` Provider 仍無條件、`mockAiService:` 接線未動（C 範圍）。
- (g) ✅ 既有 tool calling / route / Realtime / conversation 測試無回歸。

#### 驗收（architecture 親跑，非轉述）
- `flutter analyze`（觸及 3 檔 `companion_chat_service.dart` + `ai_tool_router.dart` + `app.dart`）→ **No issues found**。
- `flutter test`（companion_chat + ai_tool_router_chat + voice_agent realtime lifecycle）→ **41 passed**。
- `flutter test`（全量）→ **521 passed, All tests passed!**。
- 未碰 `.env`、未讀 key、MockClient 驅動，無外部相依。

#### follow-up（不阻擋本批）
- **base URL 解析一致性（low）**：B2 以 compile-time `AppConfig.apiBaseUrl` + `/api/companion/chat` 組 URL；sibling `care_alert_notification_service` 用 runtime 可覆寫的 `AppConfig.apiBaseUrlForSttProxy(profileController.sttProxyUrl)`。因 `apiBaseUrl`、`defaultSttProxyUrl` 同源 `backendBaseUrl` 且 `/api/companion/chat` 與 `/api/stt`、`/api/realtime` 同在 server.js，**production 預設兩者同 host、可正確命中**；唯一分歧情境＝使用者 runtime 把 `sttProxyUrl` 覆寫到與 `backendBaseUrl` 不同的 host。若該覆寫為支援情境，建議於 C 或後續對齊成 `sttProxyUrl` 解析。非 blocker。
- **persona follow-up（companion-memory，仍開）**：`buildRealtimeInstructions` persona 偏即時語音/工具化，打字閒聊回覆語氣建議後續細修 chat 變體。

#### 裁決
- **PASS** — B2 / B3a / B3b / B4 通過 checkpoint，併入主線。Realtime 主流程紅線未越（`realtime_voice_service.dart` / `voice_agent_controller` / `conversation_controller` 全 untouched），production 不 fallback mock、不假成功，前端不放 key。
- **CR-0049-C（最後一批，待做）**：`app.dart` 194-195 兩 mock Provider 以 `if (AppConfig.mockServicesEnabled)` 包覆 + `mockAiService:` 條件/可空注入 + `ai_tool_router` 把 `mockAiService` 改 nullable + 測試斷言 production provider 樹零 mock 實例。前置＝B 全綠 + 本 checkpoint PASS（已達成），可派工 frontend-ux-agent。

---

### CR-0049-C — Checkpoint Review + CR-0049 整體收尾（architecture-agent，read-only 覆驗）

**範圍**：CR-0049 最後一批 C（`app.dart` mock Provider gating + `ai_tool_router` `mockAiService` nullable）已落地。本筆為 read-only 覆驗、裁決，並收尾整個 CR-0049（A / B1 / B(B2/B3a/B3b/B4) / C 全部完成，audit **P2-5 mock 隔離完成**）。

#### 執行進度（C）
- ✅ `lib/services/ai_tool_router.dart`：`mockAiService` 改 `MockAiService?`（建構子去 `required`，`27`）；`_chat`（`565-578`）mock 分支 `final mock = mockAiService; if (useMockChat && mock != null)` 以區域非空變數呼叫；production 分支（`companionChatService` + B4 提醒分支）一字未動。
- ✅ `lib/app.dart`：`195-198` 兩個 mock Provider（`MockAiService`/`MockSpeechToTextService`）改 `if (AppConfig.mockServicesEnabled)`；`AiToolRouter` create（`232-234`）`mockAiService: AppConfig.mockServicesEnabled ? context.read<MockAiService>() : null`；`ConversationController` 由 `ChangeNotifierProxyProvider6<…MockSpeechToTextService…>` 改 `ProxyProvider5`（`296-355`，移除對 STT mock 的 proxy 型別依賴，避免 gating 後 production `ProviderNotFoundException`），STT 兩處 create/update 維持 `mockServicesEnabled ? mock : OpenAiSpeechToTextService(...)`（CR-0049-A 條件化）。
- ✅ 新增 `test/config/mock_service_provider_gating_test.dart`：鏡像 app wiring，production 斷言 `mockAiService==null` / `useMockChat==false` / STT 為 `OpenAiSpeechToTextService` / 後端失敗走白話錯誤不崩（null mock 不 NPE、不假成功）；dev/test 仍注入 mock。
- ✅ 文件：`docs/FLUTTER_BUILD_FLAVORS.md` §3 + `docs/STORE_RELEASE_CHECKLIST.md` 兩列翻 ✅ 已隔離（CR-0049）。

#### architecture 獨立覆驗（read-only，全部親跑）
- (a) ✅ production（`mockServicesEnabled==false`）provider 樹**零 mock 實例**：`app.dart` `MockShopService`(`181`)/`MockAiService`(`195`)/`MockSpeechToTextService`(`197`)/`MockTaigiAsrStrategy`(`213`) 皆 `if (AppConfig.mockServicesEnabled)` 才建構；唯二 runtime consumer——`AiToolRouter.mockAiService=null`（`232-234`）、`ConversationController` STT=`OpenAiSpeechToTextService`（`310-314`、`336-340`）——已條件化。
- (b) ✅ `ProxyProvider6→5`：移除第 5 泛型 `MockSpeechToTextService`，`ConversationController` create/update 依賴的 `ProfileController/PetController/AiToolRouter/TextToSpeechService/SearchService` 五者皆仍在泛型清單，STT 改由 `context.read` 條件選用而非 proxy 注入；既有依賴/行為不破壞。
- (c) ✅ dev/test mock 仍注入、既有降級行為不變；`MockAiService`/`MockSpeechToTextService` 檔案**未硬刪**（只 gating）。
- (d) ✅ production 不 fallback mock、不假回覆：`_chat` production 分支 `on CompanionChatException`→陪伴式白話 `success:false`/`shouldSpeak:true`，無 mock fallback；null mock 在 `useMockChat==false` 永不被解參考。
- (e) ✅ `git diff --stat HEAD -- realtime_voice_service.dart voice_agent_controller.dart conversation_controller.dart` → **三檔皆 UNTOUCHED**（C 的 proxy 改動全在 `app.dart`）。
- (f) ✅ 文件誠實翻 ✅：production 確實不注入（已由 production-flavor 測試實證，非僅文字宣稱）。
- (g) ✅ 全量無回歸（見下方驗收）。

#### 驗收（architecture 親跑，非轉述）
- `flutter analyze lib/app.dart lib/services/ai_tool_router.dart test/config/mock_service_provider_gating_test.dart` → **No issues found**。
- `flutter test test/config/mock_service_provider_gating_test.dart`（dev flavor）→ **4 passed**。
- `flutter test … --dart-define=APP_ENV=production --dart-define=API_BASE_URL=https://api.example.com`（production flavor）→ **4 passed**，實證 production 下 `mockAiService==null`、`useMockChat==false`、STT=`OpenAiSpeechToTextService`。
- 全量測試（frontend-ux 回報）：**flutter 525 passed** + production-flavor 隔離測試 + dev-flavor mock 測試皆綠。架構端親跑 analyze + 上述 dev/production 隔離測試覆驗無誤；全量 525 為 frontend 回報、與既有基線（B 時 521 + 本批新增測試）一致，未獨立重跑全量。

#### CR-0049 整體收尾
| 批次 | owner | 狀態 |
|---|---|---|
| A — STT consumer 切正式 `OpenAiSpeechToTextService`、`sttMode` production 預設 `openAiProxy` | frontend-ux | ✅ |
| B1 — 後端 `POST /api/companion/chat`（無 auth；200 `{success,reply}` / 400 `invalid_input` / 503 `openai_unavailable`） | backend | ✅ |
| B2 — `CompanionChatService`（失敗 throw `CompanionChatException`，不吞、不放 key） | frontend-ux | ✅ |
| B3a — `ai_tool_router._chat` production 化（後端引擎，不 fallback mock） | companion-memory | ✅ |
| B3b — `app.dart` DI 接線 | frontend-ux | ✅ |
| B4 — router 層提醒分支（`shouldSpeak:false`，零重複建立；Realtime 檔 untouched） | companion-memory | ✅ |
| C — mock Provider gating + `mockAiService` nullable + ProxyProvider6→5 | frontend-ux | ✅ |

- **audit P2-5（mock service build-flavor 隔離）完成**：`MockShopService`(CR-0034)/`MockTaigiAsrStrategy`(CR-0048)/`MockAiService`/`MockSpeechToTextService`(CR-0049) 四者 production provider 樹全部零實例。
- **紅線全程未越**：Realtime 主流程（`realtime_voice_service.dart` / `voice_agent_controller.dart` / `conversation_controller.dart`）整個 CR-0049 未碰；production 不 fallback mock、不假回覆、不假 transcript；前端不放 key；dev/test mock 只 gating 不硬刪。

#### 裁決
- **PASS** — CR-0049-C 通過 checkpoint，併入主線。**CR-0049（A/B1/B/C）整體完成**，audit P2-5 mock 隔離結案。

#### 殘留 / follow-up（不阻擋 CR-0049 結案）
- **persona follow-up（companion-memory，仍開）**：`buildRealtimeInstructions` persona 偏即時語音/工具化，打字閒聊回覆語氣建議後續細修 chat 變體，使打字降級回覆更貼近陪伴而非工具化。
- **P1-7「Mock STT」工程字樣移除**：屬 **CR-0039** 範圍（settings 手動 ASR 下拉等對使用者可見字樣），不在本案。
- **base URL 對齊（low FU）**：`CompanionChatService` 以 compile-time `AppConfig.apiBaseUrl` 組 URL，sibling `care_alert_notification_service` 用 runtime 可覆寫的 `sttProxyUrl`。production 預設同 host、可正確命中；唯一分歧＝使用者 runtime 覆寫 `sttProxyUrl` 至不同 host。若該覆寫為支援情境，建議後續對齊成 `sttProxyUrl` 解析。非 blocker。
- **release 裝置驗證**：production flavor 於 iOS/Android release build 的實機冒煙（聊天走後端、STT 走 proxy、無 mock）建議於送審前 device 驗證；單元/flavor 測試已綠但非裝置實測。

---

### CR-0050 — Companion Chat Persona Refinement for Production（打字聊天陪伴 persona）

**定位**：CR-0049 留下的「persona follow-up（仍開）」收尾。`POST /api/companion/chat` 原本借用 Realtime 語音 persona（`buildRealtimeInstructions` / `REALTIME_INSTRUCTIONS`），其內含大量「意義對照表」工具清單 + 「肯定回『好的，幫你打給X』」指示——那是語音路徑因為真的會 fire tool 才需要。打字聊天不觸發任何工具（Flutter `AiToolRouter.route()` 在 `_chat()` 之前已攔截所有工具意圖），沿用後讓文字聊天工具化、不像陪伴。

**owner**：companion-memory（persona 主體）+ backend co-touch（`server.js` rewire）；architecture-agent 規劃/核准 + checkpoint。

**改動（contract-preserving，🔒 server.js 加法式）**：
- ➕ 新增 `COMPANION_CHAT_PERSONA` 常數（接在 `REALTIME_INSTRUCTIONS` 之後）：陪伴型、先情緒後內容、簡短自然、無工具清單、不假裝執行 App 動作、記憶界線、健康/高風險求助界線。
- ➕ 新增 `buildCompanionChatInstructions(petName, memoryBlock, languageOptions)`（純組裝、不查記憶）：共用 `你的名字是 X。` header 與 `outputLanguageInstruction(...)`，persona 換成 `COMPANION_CHAT_PERSONA`。
- 🔁 `/api/companion/chat` 唯一 call-site 由 `buildRealtimeInstructions` 換成 `buildCompanionChatInstructions`；`{success,reply}` / `{success:false,error}` 契約**不變**、`generateCompanionReply` 呼叫不變、inline `memoryBlock` 建構不變。
- ➕ `module.exports.buildCompanionChatInstructions = ...`（供單元測試驗 persona，不打 OpenAI）。
- 🔒 `REALTIME_INSTRUCTIONS`（232–280）與 `buildRealtimeInstructions`（310–347）**byte-identical**（語音流程未碰，git diff 證明只有加法 + 單一 call-site swap + export）。

**architecture-agent 四道 guardrail（各有測試斷言）**：
- **G1 不假裝執行工具**：persona 無「意義對照表」/工具罐頭、不指示假裝已完成動作；對順口工具語句溫暖接住但不假執行、也不冷拒「我做不到」。
- **G2 高風險不淡化**：照護提醒非醫療診斷（不診斷/處方/劑量），但胸痛/呼吸困難/跌倒/嚴重不適/自傷意念仍明確建議立即聯絡照護人員或就醫。
- **G3 記憶界線**：無記憶不捏造家人/喜好/病史、不假裝「我記得」；有記憶可自然提及但不說「根據紀錄」。
- **G4 語音 byte-identical**：以 git diff 證明，非肉眼。

**Flutter（verify-only，CR-0049 已 production-correct）**：`AiToolRouter._chat` 成功顯示後端回覆、失敗走陪伴式白話（`CompanionChatException`→「我這邊有點不穩，先抱抱你…」）、不 fallback mock、不顯示工程訊息；`route()` 工具意圖全在 `_chat` 前攔截，chat 端點只收純閒聊文字。

**測試（親跑）**：
- ➕ `backend/stt_proxy/services/companionChatPersona.test.js`（10 斷言：petName/預設陪伴寶、G1 工具罐頭缺席 + 不假執行、G2 高風險求助語、G3 記憶界線兩態、emotion-first、台語語言指示、Mandarin 預設不強制台語）。
- 後端目標檔 `node --test companionChatPersona + companionChatEndpoint` → 10/10。
- 後端全量 `npm test` → **454 / 454**；`npm run check` → exit 0。
- Flutter `flutter analyze` → No issues；`flutter test` → **525 / 525**。

**文件**：➕ `docs/COMPANION_PERSONA.md`（兩路徑 persona 為何分開 + 陪伴原則）、➕ `docs/SAFETY_BOUNDARIES.md`（健康/記憶/高風險紅線）；🔁 `docs/STORE_RELEASE_CHECKLIST.md` §8 加列；🔁 `PROJECT_ARCHITECTURE.md` 註記 chat persona seam。

**裁決**：待 architecture-agent checkpoint。

**殘留 / follow-up**：
- **打字高風險未建 Care Alert（CR-0050 範圍外）**：`/api/companion/chat` 目前只用安全語氣回覆高風險文字，**不寫入 `care_alerts` / 不觸發通知**。建議後續 CR-0051 將打字文字接上情緒/風險分級 + Care Alert 建立（需先由 architecture-agent 確認權威 risk level 代碼，調和 runtime urgent/attention 與 low/medium/high/urgent 的差異）。語音 / Care Alert pipeline 不受本案影響。

---

### CR-0051 — Typed Companion Chat Risk Analysis & Care Alert Integration（架構前置裁決，coding 前記錄）

**定位**：收尾 CR-0050 殘留——讓打字聊天文字進入與語音相同的情緒/風險分析 → Care Alert → 通知流程，使語音/文字面對同一高風險訊號行為一致。task §4 要求 coding 前先由 architecture-agent 裁決並寫入本檔。

**盤點（已驗證）**：
- 風險腦可重用且已四級：`backend/companion/safety_guard.js` `classifySafety()` 直接輸出 `low/medium/high/urgent`（urgent=自傷/急性醫療/跌倒；high=強烈絕望/明顯無助；medium=低落/睡不好/食慾/孤單；low=catch-all）；`analyzeCompanionTurn()` 包進 emotion + `careAlertSummary`（`buildCareAlertSummary` 已截斷/去識別）。`normalizeRiskLevel`（companion_engine.js + careAlertStoreService.js）映射 legacy `normal→low`、`attention→medium`；`careAlertStoreService` 寫入時正規化 → 新資料永不含 `attention`。
- Care Alert pipeline 在 `/api/care-alerts/notify` handler（server.js ~412-575）：`saveCareAlert`（**persist-always，與通知解耦**）→ `shouldTelegramNotify`（`TELEGRAM_NOTIFY_LEVELS={high,urgent}`，low/medium 只進 store/caregiver_web）→ cooldown(`${source}::${riskLevel}`) → `recordNotificationLog` → `sendCareAlertNotification`。
- `/notify` 已由 `requireResidentCaller`（CR-0045）把關，server 由 idToken 權威推導 elderId、不信任 client。`/api/companion/chat` 目前**無 auth**，Flutter `companion_chat_service.dart`**不送 token**。語音 alert source=`companion_analysis`。

**裁決（APPROVE WITH ADJUSTMENTS，risk HIGH，逐項）**：
1. **Auth**：`/api/companion/chat` 加 **hard `requireResidentCaller`**（重用 CR-0045，不 fork residentCallerContext/adminAuthContext）。**身分/授權失敗 fail-CLOSED**（無/無效 token→401，跨住民/未綁定/inactive→403，無 reply 無 alert）；**alert 端失敗 fail-OPEN**（persist/Telegram 失敗仍回 200 reply，`careAlert.created=false`）。Guardrail：後端 hard-auth 與 Flutter 送 token **必須同一 release**；`resolveNotifyAuthToken` 在 prod demo 回 null→該情境 401（demo 無 token 失去 chat，視為可接受的 demo-fallback 移除）。
2. 重用 `requireResidentCaller`：是。
3. caregiver/super_admin 代送：**否**，resident-only。
4. risk 代碼僅 `low/medium/high/urgent`：是（已強制）。
5. legacy mapping：`attention→medium`、`normal→low` 走既有 `normalizeRiskLevel`；**另須在 seam 正規化引擎失敗 fallback 的 `"normal"`（server.js:1676）** 才能進 pipeline / 回應欄位；補回歸測試（attention→medium、normal→low、新寫入不含 attention/normal）。
6. alert 建立失敗 → chat 行為：reply 仍 200，alert best-effort，`careAlert.created=false`，所有 alert 端例外捕捉（§9.8 無 unhandled rejection）。
7. 向長者 UI 顯示 alert：**否**，無監控感文案；Flutter 可解析 optional `careAlert` 但不渲染新東西。
8. **【追加裁決 — trigger gate，本 CR crux】**：衝突釐清——語音前端 `voice_agent_controller.dart:871` `if (!needsHumanSupport) return` 把**整個 HTTP call** 擋在 high/urgent（needsHumanSupport 僅 high/urgent=true），但**後端 `/notify` 本來就 persist-always + notify-high/urgent**（兩個門檻已分離）。decision 8「與語音一致」綁的是**風險分類腦**，不是 send/persist 門檻。**Option A 裁定**：
   - 分類：打字聊天**原樣重用** `analyzeCompanionTurn`/`classifySafety`（§8.3：不另寫分類器/關鍵字/risk taxonomy）。
   - **打字 send predicate**：當 `normalizeRiskLevel(riskLevel) ∈ {medium, high, urgent}` 才送 Care Alert pipeline。**`low` 不送、不持久化**（low 是非匹配 catch-all，逐句寫入會洗版、違反「不存無意義語句」；§7.5「low 只記錄」指的是 low alert 若存在的通知政策，非要求為每個中性句造一列）。§12.1 #1 孤單→`safety_guard` 落在 **medium**，#1 文字本身是「low 或 medium」，故 `{medium,high,urgent}` 滿足 #1/#2/#3。
   - persist/notify 門檻：沿用既有（persist=收到就存、notify=high/urgent），**不新增 persist gate、不改 `/notify`、不改 schema**。
   - 接受 voice/typed 不一致（voice 僅 high/urgent 持久化、typed medium+），**記 follow-up CR-0052** 對齊語音（拆 `voice_agent_controller.dart:871` 的 send gate，notify 仍 high/urgent）——屬 realtime-voice/frontend，**out of CR-0051**。
   - 授權層級：屬架構守門人權限，**無需 user/product sign-off**（不新增資料類別/同意範圍，store/schema/caregiver_web 本就支援 medium/low）；惟錄製頻率上升，於隱私/資料治理文件加一行揭露。

**Seam 裁決**：**APPROVE 抽出共用 helper `processCareAlert(...)`**（拒絕在 /chat 複製 ~100 行旁路 §9）。條件（全 blocking）：helper 只含 orchestration（persist-decouple + cooldown + notif-log + Telegram），**不含 auth、不重推/不信任 client elderId**，收到的是已 server-authoritative 欄位；**Batch A 獨立 commit 純 refactor**，`/notify` 委派、**零行為變更**（既有 CR-0045/CR-0034 B2/notify 測試全綠、不改 /notify 行為測試），gatekeeper 先 re-review 該 diff 才接 typed-chat 邏輯；typed 用 **distinct cooldown source `companion_chat`**，與語音 `companion_analysis` 互不抑制。

**Response 契約**：`{success, reply, careAlert?:{created, riskLevel, id}}`；中性句**省略** `careAlert`；warranted 但 persist 失敗→`{created:false, riskLevel, id:null}`；`created` 反映**持久化**非通知（low 不會到此路徑）。禁洩：internal risk debug / system prompt / token / raw model payload / 完整敏感原文；`riskLevel` 是唯一暴露的風險欄位、回應不含 summary 原文。Flutter 既有 `reply` 解析不受影響、`careAlert` 嚴格 optional。

**Guardrails**：server-authoritative resident（若 body 帶 elderId 比照 /notify reconcile-或-403）；summary 走 `buildCareAlertSummary`、通知不含原文、log 不印 token/完整 chat/完整 summary；seam 正規化 legacy normal/attention；CR-0050 persona + 回覆生成路徑 byte-identical（風險分析側通道、不改 reply 文字）；`companionChatEndpoint.test.js` 無 token 改期望 401（同 CR-0045 對 /notify 的收緊，屬預期契約變更）。

**Scope 邊界**：Realtime WebRTC 未碰；`/notify` auth byte-identical（只委派）；CR-0050 persona 未碰；無 schema migration。

**批次**：A 後端純 refactor 抽 `processCareAlert`（先過 review）→ B 後端 typed-chat auth+風險分析+send predicate+careAlert 欄位+測試 → C Flutter token + 解析 optional careAlert（不渲染）+測試 → D 文件（+ `docs/TYPED_CHAT_CARE_ALERT_FLOW.md`）。

**裁決狀態**：架構前置裁決完成，依此實作；各 batch 後 architecture checkpoint。

#### 實作結果（CR-0051 完成）

- **Batch A（backend 純 refactor，gatekeeper re-review PASS）**：抽出 module-scope `async processCareAlert(body)`（persist-decouple + 通知稽核欄位 + cooldown + Telegram 編排），`/notify` 改委派 `const {response}=await processCareAlert(body)`、auth/reconciliation 與 500 catch 一字不動。helper 額外回 `{careAlert:{created,id,riskLevel}}`（`/notify` 忽略，供 B 用）。唯一結構位移：persist 區塊由原 try 之外移入 helper（在 handler 外層 try/catch 內）——因 `saveCareAlert` 自帶 inner try/catch、`recordNotificationLog` best-effort 不 throw，行為等價。notify 全測試未改全綠。
- **Batch B（backend，typed-chat 接線）**：`/api/companion/chat` 掛 `requireResidentCaller`（breaking：原無 auth）；reply 成功後純函式 `analyzeCompanionTurn({transcript:userText,petName,languageHint,retrievedMemories:[]})`（**不重查記憶/不查知識/不寫記憶**），seam `normalizeRiskLevel`，`riskLevel∈{medium,high,urgent}` 才組 server-authoritative body（`source:"companion_chat"`、`triggerSummary`=careAlertSummary 有 fallback、`transcriptSnippet` 截 200、`riskLevelLabel` 由 `RISK_LEVEL_LABELS`）呼叫共用 `processCareAlert`。fail-open（風險/alert 例外不阻擋 200 reply）。回應加 optional `careAlert`（low/中性省略，只暴露 riskLevel）。reply 生成路徑 + invalid_input(400)/openai_unavailable(503) byte-identical。`companionChatEndpoint.test.js` 無 token 改期望 401；新 `companionChatCareAlert.test.js`（孤單/睡不好/食慾→medium+skip、胸口痛/不想活→urgent+Telegram、中性→無 careAlert、no/forged token→401、跨住民→403、legacy 映射、不外洩）。
- **Batch C（Flutter）**：`companion_chat_service.dart` 注入 `AuthTokenProvider`（重用 `care_alert_notification_service` typedef），送 `Authorization: Bearer <idToken>`；無 token（production demo null / provider 例外）→ 白話 `CompanionChatException`（不送註定 401 的請求、不假成功）；401/403/非 200 → 白話例外；`reply()` 只取 `reply`、忽略 `careAlert` 等未知欄位（長者端零監控感文案）。`app.dart` 以 `AuthController.resolveNotifyAuthToken` closure 注入（與 CareAlertNotificationService 同源，置於 AuthController 後）。`_chat` 仍 `on CompanionChatException`→白話、**無 mock fallback**。

**驗證（orchestrator 親跑）**：backend `npm test` **468/468**、`npm run check` exit 0；`flutter analyze` clean、`flutter test` **533/533**。CR-0050 persona 測試 + CR-0045 notify auth 測試仍綠；Realtime（realtime_voice_service/voice_agent_controller）+ `/notify` + tool routing 未碰。

**正式版風險檢查**：未驗證 typed chat 不建 alert（401/403）✅；跨住民被擋（403）✅；high/urgent 通知（Telegram spy）✅；新資料無 `attention`（predicate 僅 medium+，seam 先映射）✅；persona 未破壞 ✅；Realtime/tool flow 未破壞 ✅；無監控感 UI（careAlert 不渲染）✅。

**殘留 / follow-up**：
- **CR-0052（voice persist-gate 對齊）**：語音 `voice_agent_controller.dart:871` `if(!needsHumanSupport)return` 只在 high/urgent 送 `/notify`，故語音僅持久化 high/urgent；打字已 medium+。拆語音 send gate 使其也持久化 medium+（notify 仍 high/urgent）——屬 realtime-voice/frontend，另案 review。
- **base URL（low FU，沿用 CR-0049）**：`CompanionChatService` 用 compile-time `AppConfig.apiBaseUrl`，`care_alert_notification_service` 用 runtime `sttProxyUrl`；production 同 host 可命中，唯使用者 runtime 覆寫 host 時分歧。
- 送審前：真 Postgres+Firebase 端到端（resident idToken→/chat→risk→care_alerts→Telegram）+ release 裝置實測。

**裁決**：CR-0051 各 batch architecture checkpoint PASS（A 已 re-review；B/C 依裁決實作、orchestrator 全量驗證綠）。併入主線。

---

## CR-0052 — Voice Care Alert Persist Gate Alignment for Medium Risk

### 審查者
架構守門人 agent

### 結論
核准（APPROVED）。Flutter-only 單批；不改後端；不觸及 🔒 檔案。

### 觸及 🔒 檔案
無。realtime_voice_service.dart / server.js 路由與 response 形狀 / DB schema /
CareAlertRiskLevel 欄位定義皆不變。僅變更 voice_agent_controller 建構 alert 時
傳入的 riskLevel 值（改為 canonical）與 persist gate 判斷依據。

### Ruling（對應 task §5）
1. 語音 medium 是否建立 Care Alert 紀錄：是。medium/high/urgent 皆 persist，
   與 typed chat /api/companion/chat（server.js:1754 gate {medium,high,urgent}）一致。
2. 語音 medium 是否通知 Telegram：否。由後端 TELEGRAM_NOTIFY_LEVELS={high,urgent}
   決定（telegramNotifyService.js:31）。Flutter 不得自行決定推播。
3. 語音 low 是否送 /notify：否。canonical ∈ {low}（含 legacy normal）在 gate 直接 return，
   不 addAlert、不 notify。
4. needsHumanSupport：語意維持「僅 high/urgent」，不得混入 medium。它不再作為 persist gate，
   僅保留為「是否需人為關懷」的語意旗標。
5. 新增獨立 predicate：核准新增 shouldPersistCareAlert（canonical-riskLevel-based）。
   不在 Flutter 端新增 shouldNotifyCaregiver；Telegram 推播權威唯一在後端，
   Flutter 端不得複製此決策，避免雙重真相來源。
6. risk level 權威值：維持 low / medium / high / urgent。

### 強制要求（非選用）
7. persist gate 與新 alert 建構必須以 canonical 為準（CareAlertRiskLevel.fromJson(...).canonical）。
   理由：safety_guard 仍可能輸出 legacy 'attention'（canonical=medium）。若以 raw
   字串 == 'medium' 比對，legacy 'attention' 會被漏判而丟失一筆 medium-equivalent alert。
   gate 必須先 canonical 再比 {medium,high,urgent}。
   新 alert 一律以 canonical 建構，避免新資料帶 legacy normal/attention（與 CR-0051 同向）。

### 後端
不改動。已驗證 processCareAlert persist-always（server.js:430-460）、
normalizeRiskLevel 已映射 attention→medium / normal→low（careAlertStoreService.js:74,85）、
Telegram 僅 high/urgent。task §7 四個「需改後端」條件皆不成立。

### UI / 監控感
無新風險。長者端 care_alert_screen.dart（route careAlerts）不顯示 riskLevel/label/JSON，
採「今日關心紀錄」柔和框架；high/urgent 既有就會本機 addAlert，medium 僅多一筆同類柔和紀錄，
不暴露分級、不產生監控感。frontend-ux-agent 須確保此畫面持續不顯示 raw risk level。

### 批次
單批可行（voice_agent_controller.dart gate + 建構 + care_alert_hook_test 參數化）。

### 測試指示
care_alert_hook_test.dart 需參數化 fake engine 的 riskLevel：
- 原 needsHumanSupport=true/urgent case → 保留（urgent 仍建 alert）。
- 原「needsHumanSupport=false 不建 alert」case → 改用 riskLevel='low'（或 'normal'）
  驗證不建 alert；不要再用 needsHumanSupport 控制 persist。
- 新增 riskLevel='medium' → 建立 1 筆 alert（persist 對齊）的 case。
- 確認 medium 不依賴 needsHumanSupport（needsHumanSupport=false 仍 persist）。

### 邊界警告（執行 agent 須遵守）
1. canonical 是強制（裁決 #7）：gate 與建構都要 canonical，raw 比對會漏接 legacy attention。
2. 不要在 Flutter 端複製通知決策（不新增 shouldNotifyCaregiver）；medium 仍送 /notify，由後端擋 Telegram。
3. needsHumanSupport 不改語意、不刪；本 CR 只是讓它不再當 persist gate。
4. source 維持 'companion_analysis'（後端 cooldown key = source::riskLevel）。
5. fire-and-forget 不變：notify 失敗（401/403/網路）不得阻斷 Realtime、不回滾本機 addAlert。
6. _lastAlertedTurnId 去重邏輯（872-873）保留。

---

## CR-0053 — Production End-to-End Smoke Test and Deployment Readiness

### 模式
**Plan-only**（docs-only，無程式碼變更、不觸 🔒 檔案）。

### 為何 Plan-only
執行環境（背景工程代理）不具備真 Firebase / 真 PostgreSQL / 真 OpenAI key / 真 Telegram Bot / 真 iOS·Android 實體裝置，且受紅線約束（不讀 `.env`、不貼 secret、不假裝通過，CR-0053 §5.1/§12）。故依任務 §5.1 走 Plan-only：建立可執行 smoke 計畫 + 誠實未執行報告 + 缺口/owner blocker。

### 產出
- 新增 `docs/E2E_SMOKE_TEST_PLAN.md`：可執行 checklist（模式判定、前置憑證/env 名稱、Backend B1–B13、caregiver_web W1–W12、Flutter F1–F15、ATS A1–A5、測試資料清理、最小通過集）。所有 env 只列**名稱**，紅線寫在文件頂。
- 新增 `docs/E2E_SMOKE_TEST_REPORT.md`：Run #0 = NOT EXECUTED，逐項 PENDING，列出靜態盤點已確認的程式基礎（fail-fast / health / migration 001–014 / Telegram 門檻 / AppConfig 守門）與 release blockers（未跑真 smoke、ATS 未收斂、HTTPS 網域未確認、Data Safety 表單）。
- 更新 `docs/STORE_RELEASE_CHECKLIST.md`（加 CR-0053 BLOCKER 行）、`docs/ENVIRONMENT_SETUP.md`（§5 相關文件指標）。

### 靜態盤點關鍵發現（非 smoke 通過）
- 後端 production fail-fast 已實作（`config/env.js`：缺 DATABASE_URL/OPENAI_API_KEY/CORS/Firebase/ADMIN_API_TOKEN 即 exit(1)；拒絕 ALLOW_JSON_FALLBACK/ALLOW_MOCK_SERVICES/REQUIRE_AUTH=false；啟動摘要全遮蔽）。
- `GET /health` 存在；`npm run db:migrate`（001–014 齊，含 013/014 + 單元測試）。
- Telegram `TELEGRAM_NOTIFY_LEVELS={high,urgent}`；語音+打字 persist 皆 medium+（CR-0051/0052）。
- Flutter `AppConfig` production 強制關 mock/demo/devpanel + `isApiBaseUrlProductionSafe` 守門。
- ⛔ iOS `NSAllowsArbitraryLoads=true`、Android `usesCleartextTraffic="true"` 仍未收斂 → ATS BLOCKER（CR-0046 B3）。

### 限制遵守
未連任何真服務、未污染資料、未產生需清理的測試資料、未提交任何 secret / service account / keystore。不改 CR-0039～CR-0052 任何主流程。

### 裁決
docs-only Plan-only，無 🔒 變更、無 API/schema/Realtime 改動，未跑測試（無程式碼可測）；併入主線。實際 Execute 一輪 smoke 為後續工作（需 owner 備齊真環境）。

---

## CR-0054 — HTTPS deployment + ATS/cleartext transport hardening (架構裁決)

決議者：architecture-gatekeeper
日期：2026-06-09
分支：feat/auth-admin-backend
模式：HYBRID — Thread 1 EXECUTE / Thread 2 PATCH-READY
整體風險：Thread 1 = medium；Thread 2(盲套) = high，(僅文件) = low

### A. 執行模式
核准 hybrid。Thread 1（CORS 收斂）EXECUTE now，可單元驗證、向後相容、不需裝置。
Thread 2（ATS/cleartext）一律 PATCH-READY，含 Android，不在本 CR 落地 runtime 變更。
理由：Thread 1 是純後端安全邊界修補，可離線驗證；Thread 2 同時觸及 iOS 實機可執行性
與 App↔後端資料路徑可達性，缺 HTTPS 後端 + 缺實體裝置 smoke（CR-0053 blocker）下落地
= 製造無法驗證的潛在破壞，違反 task §5.2「不要盲套」與 CLAUDE.md「不破壞 iOS 實機」。

### B. CORS 改動是否觸及 server.js API 契約 LOCK？
裁定：server.js 屬 LOCKED 檔，但「把 CORS middleware 來源從 ALLOWED_ORIGINS 改為
resolveCorsOrigins(process.env)」不更動任何路由、request/response 形狀，故不算「API 契約」
變更，而是「安全邊界修補」。核准 EXECUTE，毋須拆批。
硬性約束（backend-agent 實作時必守）：
1. 僅替換 server.js:166 為 resolveCorsOrigins(process.env) 並自 config/env.js 引入；
   166 之後的 split / origin 判斷不得改（.split(',') 必須保留）。
2. 保留 dev 空清單 → allow-all（本機開發）。production 因 fail-fast 保證非空 →
   line 172 自然不再 allow-all，缺口即閉合。
3. 必須保留「無 Origin header 一律放行」(line 171)——Flutter 原生 HTTP/WebRTC 不帶 Origin，
   動到這行會打斷長者端與 Realtime broker，絕對禁區。
4. 向後相容：resolveCorsOrigins 仍 fallback ALLOWED_ORIGINS，既有部署不回歸。
production allow-all 缺口：確認屬實，須修（task §8.3/§11.12 實質違反）。

### C. ATS/cleartext 模式
同意「不盲套、僅產 patch-ready」。Android 不核准「現在就套 dev/release 隔離」，與 iOS 一併
hold 到 smoke。release 禁 cleartext 的價值只在 HTTPS 後端切換時成立；現在落地 = 無 HTTPS 後端、
無裝置 smoke 下植入潛在資料路徑斷裂，tools:replace manifest 合併無 smoke 不得放行。

### D. iOS 例外策略
採 NSAllowsArbitraryLoads=false + NSAllowsLocalNetworking=true（靜態、單一 plist）。不採 xcconfig
驅動（避免結構性擴張）。NSAllowsLocalNetworking 已涵蓋 loopback / *.local / RFC1918 與 link-local，
dev LAN IP 後端無需列舉動態 IP，正式後端走 HTTPS 不需任何 arbitrary load。

### E. Thread 1 實作者
backend-agent（server.js 為其 ownership 且屬 LOCKED 檔），依 B 四條硬約束 + 補測試。diff 回 gatekeeper 審核後併。

### F. LOCK 邊界警告
- server.js LOCKED：Thread 1 限安全邊界修補，禁動路由/response 形狀、禁動 no-Origin 放行。
- Info.plist + AndroidManifest + 新增 network_security_config.xml：觸及 iOS 實機可執行性 + App↔後端
  可達性 → 僅 patch-ready，須 HTTPS 後端就緒 + 實體裝置 smoke（沿用 E2E_SMOKE A1-A5）後另開 CR 落地。
- realtime_voice_service.dart：本 CR 完全不得觸及。
- 禁讀/改任何 .env；patch 文件只列變數名與設定方式，不得含實值。
- 跨端契約：CORS 真實來源由 ALLOWED_ORIGINS 改為 CORS_ALLOWED_ORIGINS(優先)；caregiver_web 部署 origin
  必須在清單內 → 併 Thread 1 前須同步更新 PROJECT_ARCHITECTURE.md 環境章節。

### 批次切分
- Batch 1 (Thread 1, EXECUTE)：server.js CORS 來源收斂 + 測試 + PROJECT_ARCHITECTURE.md env 章節。owner=backend-agent。gate=測試綠 + gatekeeper diff 審核。
- Batch 2 (Thread 2, PATCH-READY)：新增 docs/TRANSPORT_SECURITY.md（Android network_security_config + manifest tools:replace、iOS NSAllowsLocalNetworking、smoke checklist、rollback）。不改 runtime。落地另開 CR 並要求裝置 smoke。

### 實作結果（CR-0054）
- **Batch 1（EXECUTE，backend-agent，gatekeeper diff 審核通過）**：`server.js` CORS middleware 來源由 `process.env.ALLOWED_ORIGINS` 改為 `resolveCorsOrigins(process.env)`（加 1 個 import），line 167 `.split(',')` 與 origin 判斷（168-177）一字未動、no-Origin 放行（171）未觸及。新增 `services/corsOrigin.test.js`（5 cases：CORS_ALLOWED_ORIGINS 優先/放行/擋、legacy 相容、兩者並存優先序、dev 空清單 allow-all、無 Origin 放行）+ package.json test/check 收錄。orchestrator 親跑 backend `npm test` **473/473**（+5）、`npm run check` exit 0。`PROJECT_ARCHITECTURE.md` env 章節 CORS 行同步更新（前置硬性要求達成）。
- **Batch 2（PATCH-READY，docs-only）**：新增 `docs/TRANSPORT_SECURITY.md`——Android `network_security_config.xml`（release 禁明文）+ debug 同名資源覆蓋（LAN/loopback/10.0.2.2）+ 主 manifest 移除 `usesCleartextTraffic` 改指 config；iOS `NSAllowsArbitraryLoads=false` + `NSAllowsLocalNetworking=true`；smoke checklist（T1-T9，沿用 A1-A5）+ rollback（一平台一 commit）。**不改 runtime**，落地依賴 HTTPS 後端 + 裝置 smoke，另開 CR。
- 文件更新：CHANGE_REVIEW（本段）、STORE_RELEASE_CHECKLIST（ATS/cleartext 行指向 TRANSPORT_SECURITY + CORS 已修 + CR-0054 BLOCKER 行）、E2E_SMOKE_TEST_REPORT（CORS 已修 + transport patch ready）、ENVIRONMENT_SETUP（§5 指標）、PROJECT_ARCHITECTURE（CORS 行）。
- **正式版風險**：production 仍允許 arbitrary loads？是（Batch 2 未落地，patch 就緒）。仍允許 cleartext？是（同上）。production 仍指向 localhost？否（AppConfig 守門）。CORS allow-all？否（已修）。破壞 Realtime？否（未碰 realtime_voice_service.dart / WebRTC）。破壞 Care Alert？否。假裝通過？否（ATS/cleartext 誠實標 PATCH-READY 未套用）。
- **裁決**：Batch 1 gatekeeper diff 審核 + 測試綠通過，併入主線；Batch 2 為 patch-ready 文件，transport 收斂落地另開 CR（依賴 CR-0053 HTTPS 後端 + 裝置 blocker）。

---

## CR-0055 — Apply Transport Security Patch and Run Device Smoke

### 模式
**BLOCKED（task §12.2）**——docs-only，無 runtime / 程式碼變更，不觸 🔒 檔案。

### 為何 Blocked（前置未齊，未盲套）
CR-0055 核心交付 = 套用 iOS/Android transport patch **並**跑 T1–T9 實機 smoke。task §2 列 8 項前置，末行明訂未齊則不套用、改更新 blocker 報告；§11.1 禁「沒 HTTPS 後端就硬關 HTTP 並假裝成功」。執行環境缺：正式 HTTPS 後端 + TLS 憑證（§2#1-2）、實體 iOS/Android 裝置（§2#4-5）、production 連線（§2#3）、Flutter prod HTTPS base URL（§2#6）、caregiver_web prod origin（§2#7）。且 T3/T5/T6（Realtime 語音 / 語音 Care Alert）本質需真機麥克風 + WebRTC，背景代理無法執行 → 無法達成 §12.1 裝置 smoke 通過。故 §12.2。

### 盤點（落地嘗試前確認，皆未動）
- iOS `Info.plist`：`NSAllowsArbitraryLoads=true`（未動）。
- Android `AndroidManifest.xml`：`usesCleartextTraffic="true"`（未動）。
- `res/xml/network_security_config.xml`：未建立。
- AppConfig 預設 base URL 仍 `http://127.0.0.1:3001`（dev；prod 由 build dart-define 指定，未提供正式網域）。
- caregiver_web 僅 `config.example.js`，無 prod `config.js`。
- ✅ CR-0054 Batch 1 CORS 修正保留，未受影響。

### 產出
- `docs/E2E_SMOKE_TEST_REPORT.md`：新增 Run #1（CR-0055 attempt = NOT EXECUTED/BLOCKED，§2 前置逐項狀態、T1–T9 全 BLOCKED、rollback 未啟用、owner action、下一次步驟）。
- 更新 `docs/TRANSPORT_SECURITY.md §7`（CR-0055 落地嘗試 = BLOCKED 註記）、`docs/STORE_RELEASE_CHECKLIST.md`（ATS/cleartext 行加 CR-0055 BLOCKED 狀態）、本檔。

### 限制遵守
未套用任何 transport patch、未動 Info.plist/AndroidManifest、未連任何真服務、未啟用 mock、未關 auth、未污染資料、未提交 secret/service account/keystore、未在文件貼 token/chat id/完整對話。未破壞 CR-0039～CR-0054 主流程。**未假裝通過**。

### 測試
無程式碼變更 → 無需重跑（baseline 維持：flutter 537/537、backend 473/473，CR-0054 時親跑）。release build / 裝置 smoke 因無裝置無法執行，誠實標示。

### 裁決
docs-only Blocked 報告，無 🔒 / API / schema / Realtime / runtime 變更；併入主線。transport 收斂落地仍待 owner 備齊 HTTPS 後端 + 實機後重跑（沿用 TRANSPORT_SECURITY §3 套用 + §5 smoke）。

---

## CR-0056 — Marketplace & DailyCareTask Production Data Decision

### 裁決（architecture gatekeeper）
- Marketplace = A2：本版 production 隱藏/停用，保留 development/test。內建交易 PG 化（金流 / App Store 3.1 / Play Payments / 財務合規）列 post-release。
- DailyCareTask = B2：本版 production 隱藏/停用，保留 development/test。PG 化（無 migration + AI Vision proof 落地）列 post-release。

### 現況事實
- 後端已 fail-closed：marketplaceStore / dailyCareTaskStore 在 production 經 isJsonFallbackAllowed 擋下，回 [] 或 FeatureUnavailableInProductionError；SEED 商品僅非 production 服務。production 不讀 JSON。
- 缺口僅在「Flutter 與 caregiver_web UI 入口在 production 仍可見」，長者點進去撞失敗/空白 → 本 CR 收斂。
- PG：marketplace migration 009 已建表但 store 未接；dailyCareTask 無 migration。本版均不走 PG。

### 本 CR 範圍（frontend-ux-agent，無 🔒）
- Flutter：AppConfig 新增 `marketplaceVisible`/`dailyCareTasksVisible` 衍生 getter（`showX && !isProduction`，能力不刪只隱藏），production 完全隱藏 shop_screen 長照商城卡與 settings_screen「今日任務」入口；補 widget test（production 隱藏 / dev 顯示）。
- caregiver_web：以 `config.js featureFlags`（預設關）隱藏商品/訂單管理與今日任務分頁；既有靜態結構測試語意不改，新增 flag gating 斷言。
- 文件：本檔 + STORE_RELEASE_CHECKLIST + GOOGLE_PLAY_DATA_SAFETY（移除 marketplace 金流、不申報財務）+ 新增 MARKETPLACE_PRODUCTION_DECISION / DAILY_CARE_TASK_PRODUCTION_DECISION。APP_STORE_METADATA 經查無商城/任務字樣需清理。

### 明確不做（邊界）
- 不動 server.js（🔒）、不改後端 API 契約 / response 形狀、不建 DB migration、不走 PG。
- 不顯示「功能準備中」死路頁（避免長者困惑 + App Store 2.1 placeholder 風險），改完全隱藏。
- 不破壞 Realtime / Care Alert / Memory / Auth scope；不啟用 mock；不提交 .env / secret / runtime data/*.json。
- 路由（AppRoute.marketplace / dailyCareTasks）保留註冊，不加 route guard（dev/test/deep-link 用；production 無入口即不可達）。

### 後續獨立 CR（backend-agent，非本 CR 阻擋）
1. 無 auth 的 /api/marketplace/products、/api/daily-care-tasks GET 補存取限制（defense-in-depth）。
2. POST /api/marketplace/orders 在 production 由 createOrder throw 映射為乾淨 not_enabled（目前落 500）。

### 驗證（orchestrator 親跑）
flutter analyze clean；flutter test **541/541**（+4 新 case：marketplaceVisible/dailyCareTasksVisible production 斷言 + shop/settings 環境分流）；caregiver_web `node --test` **90/90**。後端零改動（git diff backend/ = 0）→ backend baseline 維持 473/473。

### 裁決狀態
frontend-ux-agent 實作符合裁決（只隱藏不刪、未動後端、dev 不變），orchestrator 全量驗證綠。併入主線。

---

## CR-0057 — Marketplace & DailyCareTask 後端加固（production 停用路徑回應收斂）

### 裁決（architecture gatekeeper）
接 CR-0056 follow-up #1/#2。對 marketplace + daily-care 在 production 已 fail-closed 的
路徑，將「停用訊號」由現行誤映 500 收斂為語意正確的乾淨回應。defense-in-depth，
client 在 production 已無入口（CR-0056），本 CR 修後端 wire 契約一致性。

- Status code = 501 Not Implemented（統一）。
  - 退回 403：與 admin daily-care 既有 authz-forbidden(403) 同路由碰撞；403 是請求者
    權限語意，非「此部署未啟用功能」。
  - 退回 503：本 repo 503 已固定為上游暫時不可用 + 可重試（taigiAsr/health）；停用為
    永久決策、不可重試。
  - 501 未被使用、非 retryable、語意最貼切；本 CR 確立為「production 功能停用」新慣例。
- Response 形狀：保留各路由族 discriminator（marketplace `ok:false` / daily-care
  `success:false`）+ wire error 統一 `not_enabled` + 友善 `message`（無工程字眼/path/stack）。
  內部碼 `feature_unavailable_in_production` 不改，只在 HTTP 邊界映射。
- 不新增 auth：production 在資料讀取前已 fail-closed（store guard），501 不查資料、不洩漏，
  §7 最小限制滿足；既有 requireAdmin / resolveAdminAuthContext scope 保留不動。
- 不在 route 層加 isProduction：fail-closed 已在 store 資料邊界滿足（§7.4），route 只修
  500→501 映射，不搬守門位置、不雙重守門。停用路徑不 logError（非錯誤、避免假警報）。
- helper 放置：純判斷式 isFeatureUnavailableError() 放 config/env.js（與常數/錯誤類同檔、
  可單測）；Express 回應器 respondFeatureDisabled(res,{key}) 留 server.js（最小 🔒 侵入）。

### 批次（owner = backend-agent）
1. env.js 加 isFeatureUnavailableError + 單測（no route change）。
2. server.js marketplace 路由接 helper + route 測試（prod→501 not_enabled；dev/test 不變）。
3. server.js daily-care 路由接 helper（保留 authz 403 優先序）+ 測試（含 reminders 零變更斷言）。
4. PROJECT_ARCHITECTURE 契約段（須先/同 PR 更新）+ 本檔。

### 🔒 / 邊界
觸 🔒：server.js（route 映射）、config/env.js（additive export）。不改 store throw/return
語意、不動 reminders、Realtime、Care Alert、Memory、Auth scope、DB/migration；
不啟用 mock；不提交 .env / runtime data/*.json。

### 驗收門檻（backend-agent 須親跑、誠實標示）
- dev/test 既有 marketplace/dailyCareTask 路由測試保持綠且行為位元不變。
- production：各路由 → 501 + {discriminator:false, error:"not_enabled", message}，非 500、
  非 stack、非 demo/JSON、不讀檔。
- production+caregiver 跨住民 → 仍 403（authz 優先序未被 501 取代）。
- reminders 路由不受影響。

### 實作結果（CR-0057）
- **Batch 1（env.js additive）**：新增 `isFeatureUnavailableError(errOrResult)`（`x?.code === FEATURE_UNAVAILABLE_IN_PRODUCTION || x?.error === ...`，涵蓋 throw 型與 return 型、一般 error 不誤判）+ export；env.test.js 補 3 單測。
- **Batch 2（server.js marketplace）**：新增 `respondFeatureDisabled(res,{key})`（501 + `{[key]:false, error:"not_enabled", message}`）；接入 9 路由（read catch 內先判停用再 logError/500；mutation 在 false 分支先判）；停用路徑不 logError。新增 `marketplaceProductionEndpoint.test.js`（11）。
- **Batch 3（server.js daily-care）**：接入 6 路由（key="success"）；authz-403 優先序保留（caregiver 跨住民仍 403、super_admin 才 501、無 token 401）。新增 `dailyCareTaskProductionEndpoint.test.js`（8，含 reminders/health smoke）。
- **Batch 4（docs）**：PROJECT_ARCHITECTURE marketplace/dailyCareTask 契約段加註 CR-0057 wire 契約（501 not_enabled，保留 discriminator，authz 優先序）；MARKETPLACE/DAILY_CARE_TASK_PRODUCTION_DECISION 加 production direct API §；STORE_RELEASE_CHECKLIST + 本檔。
- **驗證（orchestrator 親跑）**：backend `npm test` **495/495**（+22）、`npm run check` exit 0。store 服務未改（git diff 確認）、reminders/Realtime/Care Alert/Memory/Auth/DB 未動、未啟用 mock、未讀 .env。
- **裁決**：符合 7 條規格 + 驗收門檻；store 語意不改、dev/test 位元不變、authz 優先序保留。併入主線。post-release：CR-0042 PG 化解除 501 停用。

---

## CR-0058 — Store Metadata / Legal / App Identity / Icon / Screenshots / Signing Readiness

### 模式
Readiness 整理：docs 為主 + **一處可離線安全 config 修正**（android:label）。owner 決策項一律列 blocker，不偽造、不擅改不可逆 ID。

### 盤點（18 點摘要）
- iOS Bundle ID `com.Andrew.petCompanionApp`、Android applicationId 同 → **個人名、非註冊網域、不可逆 → owner blocker**（不改）。
- Android namespace `com.example.pet_companion_app` → 內部 R/BuildConfig 套件名、非發布 ID、不影響送審；清理需移動 MainActivity，低優先不動。
- iOS CFBundleDisplayName `Pet Companion App`（interim）；**android:label 由 `pet_companion_app` 對齊為 `Pet Companion App`**（可逆、修跨平台不一致、非發明品牌）。最終品牌名 owner blocker。
- pubspec name `pet_companion_app`（套件名，改會破壞 import，維持）；description 良好；version 1.0.0+1。
- LegalConfig 4×`TODO_*`（privacy/terms/support URL + contactEmail）→ owner 真值 blocker；**已有 `isPlaceholder()` 防護**，UI 不會顯示壞連結，無需改 code。
- icon：iOS appiconset 齊（含 1024）需 owner 確認非預設；Android **缺 adaptive icon**（只有 legacy ic_launcher.png）→ asset blocker。
- screenshots 無 → asset blocker。
- release signing：Android release 仍用 **debug key**（build.gradle.kts），上架前須換正式 keystore → owner blocker。
- 無 user-facing demo/test/mock 字樣；store 草稿描述未宣稱停用之 marketplace/daily-care。

### 修改檔案
- `android/app/src/main/AndroidManifest.xml`（android:label 對齊 interim）
- `docs/APP_STORE_METADATA.md`（+§6 停用功能不得宣稱、+§7 app identity 現況/blocker）
- 新增 `docs/RELEASE_SIGNING.md`、`docs/STORE_ASSET_CHECKLIST.md`
- `docs/GOOGLE_PLAY_DATA_SAFETY.md`（CR-0058 對齊確認、財務=否）、`docs/STORE_RELEASE_CHECKLIST.md`、本檔

### 限制遵守
未偽造 URL、未擅改 Bundle ID/applicationId、未提交 keystore/credentials/.env、未用真個資、未宣稱醫療診斷、未宣稱停用功能可用、未重啟 production 隱藏功能、未碰 Realtime/Care Alert/Auth。

### 測試
android:label 為 Android native-only 變更，不影響 Dart → flutter analyze clean、flutter test 541/541（親跑確認無回歸）。未跑 release build（iOS/Android build 需 owner 環境/簽章；且 label 變更不需重 build 驗證契約）。

### Owner blockers（彙總）
1. Bundle ID / applicationId 正式化（不可逆，建議機構反向網域）。
2. 最終品牌名（中英）→ 同步 iOS display name / android:label / metadata。
3. Privacy/Terms/Support URL + 客服 email（填入 legal_config.dart + metadata）。
4. 正式 App icon（iOS 1024 + Android adaptive 前景/背景 + Play 512）+ 補 Android adaptive icon。
5. 5 組去識別化 screenshots + Android feature graphic。
6. Apple Developer 帳號 + iOS 憑證；Google Play Console + 正式 keystore + App Signing；release signingConfig 換正式 key。
7. 第三方登入 / Sign in with Apple 決策。
8. 內容分級問卷、開發者名稱。

### 裁決
docs-only + 一處可逆 label 修正，無 🔒（未動 server.js/Realtime/DB/Care Alert/deps），未跑破壞性變更；併入主線。實際填值 / 素材 / 簽章為 owner action。

---

## CR-0059 — Owner-Gated Release Blocker Handoff and Final Readiness Map

### 模式
**docs-only**，未改任何 runtime code / config（無 🔒）。

### 產出
- 新增 `docs/RELEASE_HANDOFF.md`：單一交接地圖。含 §2 已完成 hardening 表（CR-0033→CR-0058 + commit + 解決 blocker + 是否需真環境再驗證）；§3 剩餘 blocker 五分類（Owner Decision / Infrastructure / Device Smoke / Store Console / Post-release）；§4 20-area Final Readiness Matrix（status / owner needed / claude next / blocker? / evidence）；§5 Restart Map（環境齊後重啟 CR-0053 Execute / CR-0055 Execute / CR-0058 completion / CR-0059 refresh / CR-0060 RC regression）；§6 Owner Action Checklist；§7 不可假完成清單（12 條紅線）；§8 交接結論。
- 更新 `STORE_RELEASE_CHECKLIST`（指向 RELEASE_HANDOFF 為單一交接來源）+ 本檔。

### 盤點結論
- code-level P0/P1/P2 release blocker：**無剩餘**（agent 可做的程式硬化大致用盡）。
- 剩餘 blocker 全為 owner-gated：infra（HTTPS 後端/TLS/Firebase/PG/OpenAI/Telegram/CORS/hosting）、不可逆 identity（Bundle ID/applicationId 個人名）、法律 URL（legal_config TODO_*，有 isPlaceholder 防護）、簽章（release 仍 debug key）、素材（icon/adaptive/screenshots）、實機 smoke（CR-0053/0055）、商店後台。
- production hidden：marketplace / daily-care（CR-0056/57）；商店文案不得宣稱。
- patch-ready 未落地：transport（CR-0054/55）。
- 未執行：真環境 E2E smoke（CR-0053）、device smoke、release build。

### 限制遵守
未改 runtime、未偽造 owner 完成事項 / smoke 通過 / URL / 不可逆 ID、未宣稱 hidden 功能啟用 / 醫療診斷、未提交 secret、未擴大新功能 scope、未把 post-release 拉進 release blocker。

### 測試
docs-only → 不需跑單元測試（runtime 未改）。既有 baseline 維持（backend 495 / flutter 541 / caregiver_web 90）。

### 裁決
docs-only 交接地圖，無 🔒 / runtime 變更；併入主線。專案目前狀態可交接給組員 / 指導老師 / 後續開發者；下一步 owner action 與重啟 CR 已明確。

---

## CR-0061 — App Identity 定值接線（Bundle ID / applicationId / 品牌名 / 發行者，owner 拍板）

### 模式
Owner 拍板後的**不可逆 identity 接線**。對應 CR-0058 / RELEASE_HANDOFF §5 的「CR-0058 Owner completion」重啟點之 app identity 部分。owner 明確提供最終值，agent 僅照值接線，不發明、不擅改。

### 動機 / 問題
iOS Bundle ID / Android applicationId 先前為個人名 `com.Andrew.petCompanionApp`（CR-0058 列為不可逆 owner blocker）；品牌顯示名為 interim `Pet Companion App`；發行者未定。owner（國立嘉義大學資訊管理學系專題第四組）拍板正式值，需接線並收斂相關文件 blocker。

### Owner 拍板值
- iOS Bundle ID = Android applicationId = `tw.edu.ncyu.im.aicompanion`（嘉義大學反向網域，一致）。
- App 顯示名（英）：`AI Companion`；App 名稱（中）：`AI陪伴`。
- 開發者 / 發行者：國立嘉義大學資訊管理學系專題第四組。

### 修改檔案（runtime / build 設定）
- `ios/Runner.xcodeproj/project.pbxproj`：6× `PRODUCT_BUNDLE_IDENTIFIER` → app target 3× `tw.edu.ncyu.im.aicompanion`、RunnerTests 3× `tw.edu.ncyu.im.aicompanion.RunnerTests`（前綴替換，無殘留 `Andrew`）。
- `ios/Runner/Info.plist`：`CFBundleDisplayName` → `AI Companion`（`CFBundleName=pet_companion_app` 內部名維持不動）。
- `android/app/build.gradle.kts`：`applicationId` → `tw.edu.ncyu.im.aicompanion`，更新對齊註解。
- `android/app/src/main/AndroidManifest.xml`：`android:label` → `AI Companion`。

### owner 指定限制遵守
- **namespace 維持 `com.example.pet_companion_app` 不動**（owner 要求；與 applicationId 互相獨立，`MainActivity.kt` 套件路徑不受影響、未動）。
- iOS Bundle ID 與 Android applicationId 保持一致 ✅。
- 未提交 signing key / keystore / secret / `.env`（release signingConfig 仍 debug 佔位，屬另一 owner blocker，本 CR 不碰）。
- 未發明品牌、未捏造法律 URL（legal_config `TODO_*` 仍為待 owner 真值，屬 Step 7，未動）。

### 修改檔案（docs）
- `docs/APP_STORE_METADATA.md`：§1（App 正式名稱 / 發行者定值）、§2/§3（App 名稱 `AI陪伴`/`AI Companion`）、§7（identity 表 6 列改為 ✅ CR-0061 定值 + 註解）。
- `docs/STORE_RELEASE_CHECKLIST.md`：iOS Display name / Bundle ID、Android applicationId / label 由 ⛔ BLOCKER → ✅（CR-0061）；§5 owner-decision blockers #1/#2 標記已定值。
- `docs/RELEASE_HANDOFF.md`：§1 現況、§3.1 決策表 4 列、§4 matrix #13/#14（改為 ✅、blocker? = 否）、§6 checklist 兩項打勾。
- 本檔（CR-0061 紀錄）。

### 測試
identity / 品牌為 native + build 設定變更，不影響 Dart 契約。親跑確認無回歸：
- `flutter analyze` → **No issues found**。
- `flutter test` → **541/541 pass**。
- （回歸基線同步確認：backend `npm test` **495/495**、caregiver_web `node --test` **90/90**，於本批次起始時親跑為綠。）
- 未跑 iOS/Android release build（需 owner 簽章 / 環境；Bundle ID 變更不需重 build 驗證契約，且簽章為另一 blocker）。

### 殘留 / 下一步
- Firebase 正式專案須以 `tw.edu.ncyu.im.aicompanion` 建立 iOS/Android App；Apple 憑證 / provisioning / Sign in with Apple 設定須對應此 Bundle ID（owner，infra）。
- 剩餘 owner blocker 不變：HTTPS 後端 / 真憑證（Firebase/PG/OpenAI/Telegram）、法律 URL（legal_config）、icon / screenshots、release 簽章、實機 smoke（CR-0053/0055 Execute）、商店後台。

### 裁決
runtime 僅觸及 build identity 設定（非 🔒 server.js/Realtime/DB/Care Alert/deps 契約），owner 拍板、值由 owner 提供、限制全數遵守、測試綠無回歸；併入主線。剩餘為 owner infra / 素材 / 簽章 / 實機驗證。

---

## CR-0062 — Firebase 設定檔落地 + identity sanity check（owner 提供正式專案設定檔）

### 模式
Owner 提供之**正式 Firebase 設定檔落地 + 驗證**。對應 CR-0061 注意事項（Firebase 設定檔仍綁舊 Bundle ID）。owner 已於 Firebase Console 以正式 Bundle ID 新增 App 並下載設定檔；agent 僅將檔案搬入專案指定路徑並做 sanity check，**不改檔內任何值、不印 secret**。

### 動機 / 問題
CR-0061 將 Bundle ID/applicationId 改為 `tw.edu.ncyu.im.aicompanion`，但 `ios/Runner/GoogleService-Info.plist` / `android/app/google-services.json` 仍綁舊 `com.Andrew.petCompanionApp` → 真機 Firebase Auth 會不匹配。owner 於 Console 註冊新 App 後，需把新設定檔落地並驗證 identity 對齊與不進版控。

### 動作
- 將 owner 下載於 `~/Downloads/` 的兩個設定檔複製覆蓋至：
  - `ios/Runner/GoogleService-Info.plist`
  - `android/app/google-services.json`
- 未編輯檔內任何欄位（未捏造、未改值）。

### Sanity check 結果
1. **identity 對齊**：
   - iOS `GoogleService-Info.plist` → `BUNDLE_ID = tw.edu.ncyu.im.aicompanion` ✅。
   - Android `google-services.json` → 含 `package_name = tw.edu.ncyu.im.aicompanion` 的 client ✅（Gradle google-services plugin 以 applicationId 比對選用）。
   - 備註：`google-services.json` 另含兩個舊 `com.Andrew.petCompanionApp` client（Firebase 專案仍留舊 Android app）。功能無害（plugin 以 applicationId 比對），建議 owner 之後於 Console 移除舊 app 清理。
2. **不進版控**：兩檔由 `.gitignore:44`（GoogleService-Info.plist）/ `.gitignore:45`（google-services.json）命中；`git ls-files` 未追蹤、`git status` 不顯示 ✅。
3. **未印** API key / client id / project secret（僅抓 identity 行驗證）。
4. **未修改 Firebase Console 以外的假值**（未動其它檔案值）。

### 測試
設定檔為 native runtime 資產，不影響 Dart 契約。親跑確認無回歸：
- `flutter analyze` → **No issues found**。
- `flutter test` → **541/541 pass**。
- 未跑真機 Firebase Auth（需實體裝置 + 部署後端，屬 CR-0053 Execute 範圍）。

### 殘留 / 下一步
- 🟡 Firebase 真機 Auth smoke（idToken 簽發 / 驗證）待實體裝置 + 部署後端（CR-0053 Execute）。
- owner 可於 Firebase Console 移除舊 `com.Andrew.*` Android app（清理，非阻擋）。
- 其餘 infra blocker 不變：HTTPS 後端、PostgreSQL、OpenAI、Telegram、CORS origin。

### 限制遵守
未改設定檔內值、未印 secret、未提交設定檔（gitignored）、未碰 Realtime/Care Alert/Auth 程式契約、未發明假值。

### 裁決
僅落地 owner 提供之 gitignored runtime 設定檔 + 唯讀 sanity check，無 🔒 / 程式契約變更，測試綠無回歸；併入主線。Firebase identity 已對齊正式 Bundle ID，真機驗證待 CR-0053 Execute。

---

## CR-0063 — Production Backend Deployment Guide（Render / Railway，docs-only）

### 模式
**docs-only**。盤點 `backend/stt_proxy` 啟動與 env 契約後，新增一份 Render/Railway 部署指南；未改任何 runtime code / config（無 🔒）。對應 RELEASE_HANDOFF §6「部署正式 HTTPS 後端」owner action 的 How。

### 動機 / 問題
HTTPS 後端部署是 CR-0053/0055 Execute 與 caregiver_web 上線的前置 infra blocker，但先前只有 `ENVIRONMENT_SETUP §3` 的通用三環境說明，缺「具體 PaaS（Render/Railway）怎麼做 + 哪些 env + 怎麼跑 migration」的單一指南。

### 盤點（程式真相，未改 code）
- 啟動：`node server.js`（=`npm start`/`npm run dev`）；`server.js:23` 啟動即 `assertProductionEnvOrExit`。
- `PORT = process.env.PORT || 3001`（`server.js:133`）；`HOST = process.env.HOST || "127.0.0.1"`（`server.js:165`）→ **PaaS 需 `HOST=0.0.0.0`**。
- `GET /health`（`server.js:554`）回 `{status, hasOpenAiKey:<bool>, realtimeModel, time}`，**只回布林不回 key**。
- production fail-fast 必檢（`config/env.js validateProductionEnv`）：`DATABASE_URL`、`OPENAI_API_KEY`、`CORS_ALLOWED_ORIGINS`（別名 `ALLOWED_ORIGINS`）、Firebase 服務帳戶（`GOOGLE_APPLICATION_CREDENTIALS` 或 `FIREBASE_PROJECT_ID`+`FIREBASE_CLIENT_EMAIL`+`FIREBASE_PRIVATE_KEY`）、`ADMIN_API_TOKEN`；條件：`TELEGRAM_CARE_CHAT_ID` 設了則 `TELEGRAM_BOT_TOKEN` 必填；禁 `ALLOW_JSON_FALLBACK/ALLOW_MOCK_SERVICES=true`、`REQUIRE_AUTH=false`。
- **`PGVECTOR_ENABLED=true` 不在 fail-fast，但 runtime pool（`db/postgres.js:14`）沒它就回 null** → 文件標為「易漏雷區」。
- `db/pool.js` / `db/postgres.js` 直接把 `DATABASE_URL` 給 `pg`，**無顯式 ssl** → 雲端 PG 需在連線字串加 `?sslmode=require`（自簽 `no-verify`），不需改 code。
- `npm run db:migrate` = `node db/migrate.js`：`CREATE EXTENSION pgcrypto/vector` + 套用 `db/migrations/001…014`（14 檔）。
- `package.json` 無 `engines` → 建議平台指定 Node 20+。

### 產出
- 新增 `docs/BACKEND_DEPLOYMENT_GUIDE.md`：TL;DR 三雷區、啟動行為盤點表、production env 清單（只列名稱、不含值）、Render 步驟、Railway 步驟、`db:migrate` 執行、`/health` 驗證、下游串接、安全紅線。
- 更新 `docs/RELEASE_HANDOFF.md §6`（部署 item 加指南 How 指標）、`docs/STORE_RELEASE_CHECKLIST.md §5#6`（指向指南）、本檔。

### 限制遵守
未讀 `.env`、未印任何 secret / token / key 值（env 一律只列名稱）、未改 runtime code / config、未提交 secret、未碰 Realtime/Care Alert/Auth/DB schema 契約；env 名稱與 PORT/HOST/health/migration 行為皆對照實際程式確認。

### 測試
docs-only → 不需跑單元測試（runtime 未改）。既有 baseline 維持（backend 495 / flutter 541 / caregiver_web 90）。

### 裁決
docs-only 部署指南，無 🔒 / runtime 變更，內容與程式真相一致、未洩漏 secret；併入主線。實際部署 / 設值 / 跑 migration 為 owner action（infra blocker）。

---

## CR-0067 — 管理端「刪除訂單」功能（DELETE 端點 + 還原庫存 + 前端按鈕）

### 模式
小批次功能新增，觸及 🔒（`server.js` 新增路由 = API 契約、`PROJECT_ARCHITECTURE.md` API 表）。經 plan-mode 與使用者核准後實作；純新增，不改任何既有路由的路徑 / 方法 / response 形狀。

### 動機 / 問題
商城上線後，管理者網頁「訂單管理」只能改狀態（pending…cancelled）與配送備註，**無法刪除訂單**（`cancelled` 只改狀態、訂單仍留列表、且不還原庫存），後端也無 DELETE 端點。驗收時於 production 留下的測試訂單（`elder_name=驗收測試(可刪)`）無法從 UI 清除。使用者要求：管理端可刪除訂單，且刪除時把商品數量加回庫存。

### 變更（程式）
- **`services/marketplace/marketplaceStore.js`**：新增 `deleteOrder(id, options)`（DB-優先 + JSON 降級，比照 `updateOrderStatus` wrapper）。
  - `deleteOrderDb`：單一 transaction — `BEGIN` → `SELECT … FOR UPDATE`（無列→ROLLBACK+`not_found`）→ 逐項 `UPDATE marketplace_products SET stock = stock + qty`（商品不存在則略過）→ `DELETE` 訂單 → `COMMIT`，回 `rowToOrder`。
  - `deleteOrderJson`：讀單→還原 products 庫存→`writeAll`→`splice`+`writeAll` orders。
  - export `deleteOrder`。
- **`server.js`（🔒）**：新增 `app.delete("/api/admin/marketplace/orders/:id", requireAdmin, …)`，沿用既有 `requireAdmin`/`isFeatureUnavailableError`/`respondFeatureDisabled`；`not_found`→404、其他→500。不改既有路由。
- **`caregiver_web/app.js`**：訂單詳情新增 `#order-delete`（`btn btn-danger`「刪除訂單」）+ `deleteOrderFromDetail(id)`（`window.confirm` 二次確認 → `DELETE /admin/marketplace/orders/:id` 帶 Admin token → 成功關閉並 `loadOrders`）。
- **`caregiver_web/styles.css`**：新增 `.btn-danger` 紅色危險按鈕樣式（沿用 `.btn` 尺寸 / 圓角，長者友善）。

### 設計決策（與使用者確認）
刪除一律還原庫存。理由：訂單建立必扣庫存、`cancelled` 不還原，故刪除任何狀態的訂單時把庫存加回，剛好抵銷當初扣減一次，語意一致、不重複還原。

### DB schema
**無變更**（沿用 `marketplace_orders` / `marketplace_products`，實體刪除，無 soft-delete 欄）。部署不需 migration。

### 測試
- `marketplaceStore.test.js`（JSON）：刪單還原庫存 + 查不到、`not_found`、商品已下架仍可刪；production guard 加 `deleteOrder`。
- `marketplaceStore.db.test.js`（mock pg）：交易序列 `BEGIN→SELECT FOR UPDATE→逐項 stock+→DELETE→COMMIT`、`not_found` 走 ROLLBACK、production DB 例外回 `write_failed`。
- `marketplaceEndpoint.test.js`（真 Express）：缺 token→401、刪存在→200、再查→404、庫存還原 50、刪不存在→404。
- `caregiver_web/marketplace_admin.test.js`：刪除按鈕 / DELETE 呼叫 / `window.confirm` / `.btn-danger` 靜態結構。
- 全綠：backend `npm test` **531/531**、`npm run check` exit 0；caregiver_web `node --test` **94/94**。未刪任何既有測試。

### 限制遵守
未讀 / 改 `.env`；未提交 runtime `data/*.json`；未動 Realtime 主流程 / Care Alert 契約 / DB schema；純新增 API，既有路由形狀不變。

### 裁決
小範圍、純新增、契約已記錄於本檔與 `PROJECT_ARCHITECTURE.md §4`，測試齊備且全綠；併入主線。部署後以新按鈕清除 production 測試訂單。

---

## CR-0068 — 日常照護任務（Daily Care Task）JSON → PostgreSQL production 平移

### 模式
功能平移，觸及 🔒（新增 DB schema migration 016、`package.json` test/check 清單、`PROJECT_ARCHITECTURE.md` API 表）。比照已完成並上線的 marketplace CR-0066+ pattern；**保持 API response shape 不變**，不碰 Realtime / Auth / Marketplace。

### 動機 / 問題
daily-care-tasks 為 JSON-only store，production（ALLOW_JSON_FALLBACK=false）下一律回 501 not_enabled，App 端今日任務出現「伺服器忙線中」、caregiver_web 今日任務分頁被 featureFlags 關閉。需與 marketplace 同樣平移到 PostgreSQL 才能在正式環境使用。

### 變更（程式）
- **`db/migrations/016_create_daily_care_tasks.sql`（🔒 schema，新增）**：建 `daily_care_tasks` + `daily_care_task_submissions` 兩表。id / elder_id 用 TEXT（比照 015；不綁 elders FK，避免 demo id 違規）；submission 以 `task_id` FK 參照 tasks（ON DELETE CASCADE）；verification 整包存 `verification_json` JSONB。全冪等（CREATE/INDEX IF NOT EXISTS + ADD COLUMN IF NOT EXISTS），無破壞性操作、不灌種子（任務由 App runtime 建立）。
- **`services/dailyCareTask/dailyCareTaskStore.js`**：改 DB-優先 + JSON 降級（仿 marketplaceStore）。每個對外函式拆 `*Db` / `*Json`，wrapper 以 `isDbAvailable` 決策；production 無 DB → read 類 throw `FeatureUnavailableInProductionError`、envelope 類（updateTaskStatus）回 feature_unavailable / write_failed（行為與既有契約一致）。新增 `rowToTask` / `rowToSubmission`（snake_case row → 既有 camelCase 形狀）、`toIso` / `safeParseJson` / `setPgForTest`。`recordSubmissionDb` 用單一 transaction（SELECT FOR UPDATE → INSERT submission → UPDATE task → COMMIT）。**對外簽名 / 回傳形狀 / error 碼全不變。**
- **server.js / Flutter / vision service：未改**（路由、request/response 契約、AI 驗證邏輯不動）。

### API response shape
不變。store 對外仍回 camelCase（id, elderId, title, type, scheduledTime, dueAt, status, proofRequired, createdAt, updatedAt；submission: id, taskId, elderId, proofImagePath, submittedAt, status, verification{verificationStatus,confidence,reason,detectedObjects,reviewRequired}, note；admin 附 latestSubmission + submissionCount）。Flutter `DailyCareTask*` model 與 caregiver_web 解析欄位皆對齊，無需改前端解析。

### 前端
- `caregiver_web/index.html`：正式 APP_CONFIG `featureFlags.dailyCareTasks` `false → true`（後端已上線）；app.js cache-bust `?v=20260611-cr0067 → 20260611-cr0068`（避免快取舊檔，CR-0067 教訓）。
- Flutter 端無改動（端點 / 欄位不變）。

### 已知限制
完成證明圖片仍存於後端 runtime 檔系統（DB 只存 proof_image_path metadata）。Render Web Service 本機磁碟為 ephemeral，圖片不跨 redeploy 持久化——blob 物件儲存為後續獨立議題，不在本 CR 範圍。

### 測試
- 新增 `services/dailyCareTask/dailyCareTaskStore.db.test.js`（mock pg，13 例：CRUD/交易序列/task_not_found ROLLBACK/production 不降級）、`db/migration016.test.js`（靜態冪等審查，8 例）。
- 既有 `dailyCareTaskStore.test.js`（JSON）/ `dailyCareTaskProductionEndpoint.test.js`（production 無 DB → 501 防禦）/ `dailyCareTaskEndpoint.test.js` 維持綠（重構後行為不變）。
- `package.json` test/check 加入新檔（仿 marketplace.db.test 做法，未動依賴）。
- 全綠：backend `npm test` **552/552**、`npm run check` exit 0；caregiver_web `node --test` **94/94**。`marketplace_admin.test.js` index.html 斷言同步更新為兩旗標皆開啟。

### 限制遵守
未讀 / 改 `.env`；未提交 runtime `data/*.json`；未碰 Realtime / Auth / Marketplace 行為；未改既有 API 路由形狀；改功能補測試、未刪既有測試。

### 部署驗收（owner action）
Render Shell 跑 `npm run db:migrate`（套用到 016）→ App 端今日任務不再「伺服器忙線中」、長者能看任務 / 拍照完成、caregiver_web 今日任務分頁可看任務與 submission。

### 裁決
比照已上線的 marketplace 平移 pattern、契約不變、測試齊備且全綠、migration 冪等無破壞性；併入主線。實際 migrate / 部署為 owner action。

---

## CR-0069 — Production E2E Smoke Run #2（docs-only：驗收整理 + API 層自動 smoke）

### 模式
**docs-only**。不改任何功能程式碼；整理 `docs/E2E_SMOKE_TEST_REPORT.md` 的 Run #2 區塊為正式實機驗收步驟、驗收標準與填寫欄位，並把 Marketplace（CR-0067）與 Daily Care Tasks（CR-0068）已 production-enabled 納入 smoke 測項。無 🔒 runtime 變更。

### 動機
Marketplace 與 Daily Care Tasks 已先後平移 PostgreSQL 並在正式環境上線，需要一份涵蓋這兩塊的正式 E2E 驗收清單；同時把背景代理「能在 API 層實打驗證」的項目先跑出去敏佐證，把需真機 / 真帳號的項目明確標 PENDING 供人工執行。

### 環境確認（本輪實打）
- 後端：✅ `https://ai-companion-app-7mb8.onrender.com`（`GET /health` 200、hasOpenAiKey:true、realtimeModel:gpt-realtime）。
- caregiver_web：✅ `https://ai-companion-caregiver-web.onrender.com`（`/` 200、featureFlags `{marketplace:true, dailyCareTasks:true}`、`app.js?v=20260611-cr0068`）。

### 已自動驗證（A1–A7，唯讀 / 去敏；寫入報告）
- A1 /health 200 不洩 key；A2 marketplace 15 商品 200；A3 daily-care GET 200 `{success:true,tasks:[]}`（不再 501）；A4 DELETE 訂單無 token→401；A5 caregiver_web 旗標皆開 + 新版 app.js；A6 marketplace 下單扣庫存（CR-0067 已實打）；A7 daily-care 建立/列表/改狀態往返（CR-0068 已實打、測試資料已清）。

### 保留 PENDING（需真機 / 真帳號，人工執行）
- S1–S9（啟動 / 登入 / 語音含台語 / 打字 / 語音·打字 Care Alert / 管理端 scoped / 白話錯誤 / log 去敏）。
- M1–M4（商城長者端 UI / 購物車 / 下單 / caregiver_web 訂單管理含刪除）。
- D1–D5（今日任務 UI / 拍照上傳 + AI Vision 分支 / 證明照片管理端查看 / caregiver_web 今日任務分頁）。
- 原因：真機麥克風·相機 + WebRTC + AI Vision + 真登入帳號，背景代理無法執行；依 PLAN 紅線不假裝通過。

### 驗收標準
A1–A7 全 PASS（已達成，服務層就緒）；上架前最小通過集為 S1–S9 + M1–M4 + D1–D5 全 PASS（實機），任一 fail 記去敏摘要並開後續 CR。

### 限制遵守
未改功能程式碼；未讀 `.env`；報告未含 token / chat id / 完整對話 / 完整 email / `DATABASE_URL` 值（佐證皆去敏）；未產生需清理的測試資料（A 為唯讀；A6/A7 引用先前已清理的紀錄）。

### 裁決
docs-only 驗收整理 + API 層 smoke 佐證，無 🔒 / runtime 變更，與正式端點實況一致、未洩 secret；併入主線。實機 S/M/D 逐項為 owner action。

---

## CR-0070 — Release Build / 簽章 / Production Flags 檢查（docs-only）

### 模式
**docs-only**。不新增功能、不改 Realtime / Auth / Marketplace / Daily Care Tasks 行為、不改簽章 / 傳輸 runtime 設定。盤點 release build 設定與 production flags，產出檢查報告 `docs/RELEASE_BUILD_SIGNING_CHECK.md`。無 🔒 runtime 變更。

### 動機
正式展示 / 上架前確認 release build 設定完整，且 production build 不會用 localhost / 舊 Render URL / dev panel / mock / demo-only fallback；並把 CR-0067（marketplace）、CR-0068（daily care tasks）已 production-enabled 反映到正式 build 指令。

### 產出 / 確認
- **正式 build 指令**：`flutter run --release --dart-define=APP_ENV=production --dart-define=API_BASE_URL=https://ai-companion-app-7mb8.onrender.com --dart-define=ALLOW_MARKETPLACE_IN_PROD=true --dart-define=ALLOW_DAILY_CARE_TASKS_IN_PROD=true`。⚠️ 標記：今日任務入口在 production 預設隱藏，需 `ALLOW_DAILY_CARE_TASKS_IN_PROD=true` 才顯示（CR-0068 後端雖已上線，前端入口旗標獨立）。
- **Production flags 審查 P1–P8 全 PASS**（source = `lib/config/app_config.dart`，附 file:line）：API URL 守門擋 localhost、無寫死/殘留正式或舊 URL、mock / dev panel production 恆 false、demo·marketplace·今日任務入口由顯式旗標控制。
- **iOS / Android 就緒盤點**：bundle id / applicationId（`tw.edu.ncyu.im.aicompanion`）、display name、版本來源、權限、Firebase 設定檔皆就緒。
- **⛔ owner blockers（非本 CR 範圍，how-to 已在既有文件）**：Android release 仍用 debug 簽章（`RELEASE_SIGNING.md §2`）、iOS 無 distribution 簽章（§3）、ATS/cleartext 未收斂（`TRANSPORT_SECURITY.md §3`）、實機 E2E PENDING（`E2E_SMOKE_TEST_REPORT.md` Run #2）。

### 限制遵守
未改任何功能 / 簽章 / 傳輸 runtime 設定；未讀 `.env`；報告不含 keystore / 憑證 / 密碼 / key 值；未碰 Realtime / Auth / Marketplace / Daily Care Tasks 邏輯。

### 裁決
docs-only 檢查報告，無 🔒 / runtime 變更，與程式現況一致（app_config 行號、native 設定檔皆對照確認）、未洩 secret；併入主線。簽章 / 傳輸 / 實機 E2E 為既有 owner action。

---

## CR-0071 — Manual Production E2E Smoke Evidence Fill-in（docs-only）

### 模式
**docs-only**。不改任何功能程式碼。於 `docs/E2E_SMOKE_TEST_REPORT.md` Run #2 新增「C. 人工驗收佐證填寫表」——一份可逐項填寫的模板，供使用者依序補 S1–S9 / M1–M4 / D1–D5 的 pass/fail、裝置型號、OS 版本、build 指令、去敏佐證與 fail 後續 CR。無 🔒 / runtime 變更。

### 動機
B 段先前僅有使用者口頭「全數通過」摘要；需一份正式、結構化的佐證填寫格式，讓實機驗收結果有去敏證據可追溯，並明訂 fail 時的後續 CR 流程。

### 產出
- 執行資訊表（執行者 / 日期 / 裝置型號 / OS / build 指令 / app commit / URL，每輪填一次）。
- 逐項佐證表（17 項：S1–S9、M1–M4、D1–D5），欄位 = pass/fail｜去敏佐證｜fail→後續 CR，皆留 `（填）` 空格。
- 去敏紅線與 fail 處理規則：佐證不得含 token / chat id / 完整對話 / 完整 email / `DATABASE_URL`；fail → 開後續 CR 記去敏摘要，不在報告直接改功能。

### 後續維護約定
使用者貼回實機結果時，維護者**只整理成報告格式，不擅自改功能程式碼**；若有 fail 需修功能，另開對應 CR 經正常流程。

### 限制遵守
未改功能 / Realtime / Auth / Marketplace / Daily Care Tasks；未讀 `.env`；模板本身不含任何 secret；B 段既有 PASS 摘要保留，C 段為補充佐證層。

### 裁決
docs-only 模板，無 🔒 / runtime 變更；併入主線。實際填寫為 owner action。

---

## CR-0072 — 打字對話帶最近對話歷史（修「金魚腦 / 重複開場白 / 罐頭感」）

### 模式
小批次功能修正，觸及 🔒 `server.js` API 契約（`/api/companion/chat` 新增**選用** `history` 欄位，純 additive、向後相容）。經 plan-mode 與使用者核准。不改 Realtime / Auth / Marketplace / Daily Care Tasks；不改 persona（`buildCompanionChatInstructions`）。

### 動機 / 根因
正式 build（`-7mb8`，OpenAI key 已確認串接）下使用者回報「寵物不記得剛說的事 / 回覆罐頭感 / 一直重複開場白」。根因：打字對話 `companionChatService.generateCompanionReply` 送 OpenAI 的 `messages` 只有 `[system, user(這一句)]`，**沒有 session 內最近對話歷史** → 每則都是「全新對話」。

### 變更（程式）
- `services/companionChatService.js`：`generateCompanionReply` 多收選用 `history`；新增 `sanitizeHistory`（只留 role∈{user,assistant}、content 非空字串、截 1000 字、取最後 12 則）；組 `messages = [system?, ...cleanHistory, user]`。無 history → 與既有單則完全一致。export `sanitizeHistory` 供測試。
- `server.js` `/api/companion/chat`（🔒）：把 `req.body.history` 傳入 `generateCompanionReply`（清洗統一在 service）；response 形狀與風險側錄不變。
- Flutter：`companion_chat_service.reply` 加選用 `history`（非空才放入 payload）；`ai_tool_router.route/_chat` 透傳；`conversation_controller._recentChatHistory`（當前 session 最近 6 輪、user/assistant 交錯、oldest→newest）在 route() 前帶入。Realtime 語音（WebRTC）完全不經此路徑、零更動。

### API response shape
不變（`{success, reply, careAlert?}`）。request 僅新增**選用** `history`。

### 測試
- `companionChatService.test.js`：history 順序 system→history→user、髒值清洗、無 history 回歸、`sanitizeHistory`（非陣列/超量截 12/截長）。
- `companionChatEndpoint.test.js`：帶 history 仍正常（無 key→503、非 500）、history 壞值不報錯、缺 userText 仍 400。
- Flutter `companion_chat_service_test.dart`：帶 history → payload 含 history 陣列；空 history → 不帶 key。
- `ai_tool_router_chat_test.dart` 的 `_StubChatService.reply` 同步加 `history` 參數。
- 全綠：backend `npm test` **558/558**、`npm run check` exit 0；flutter 相關測試（companion service / router / conversation controller / 整合語音）全 passed。

### 限制遵守
未讀 `.env`；未改 Realtime / Auth / Marketplace / Daily Care / persona；既有 API 路由形狀不變、未刪既有測試。

### 範圍外（後續可選）
長期記憶寫入「射後不理 / 抽取門檻 / 檢索靜默失敗」改善（跨 session 記更牢）另開 CR。

### 裁決
最小、向後相容、契約已記錄、測試齊備且全綠、不碰受保護模組；併入主線。

---

## CR-0073 — 長期記憶層調校 + 可觀測性 + 修潛在 crash

### 模式
小批次調校，**僅改 `backend/stt_proxy/services/memory/*` 服務內部邏輯**（檢索/抽取門檻、防呆、去敏 log）。**不動 server.js 路由 / response 形狀 / DB schema / Realtime / Auth / Flutter / persona**，故非 🔒 API 契約變更。經 plan-mode 與使用者核准（範圍：調校 + 觀測 + 修 crash，不碰 Auth）。

### 動機 / 根因
正式環境（key + pgvector）記憶管線其實接好了（打字對話會抽取、會檢索、會注入，且寫入/檢索同一 userId），但「想不起使用者的事」源於：檢索門檻偏高（sim≥0.40、finalScore≥0.55、importance<3 排除、topK 3）+ 抽取缺自我介紹/家人分支 + 全程靜默無法診斷。

### 變更
- `memoryContextService.js`：檢索門檻改 env 可調並放寬預設 —— `MEMORY_MIN_SIMILARITY`(0.40→**0.30**)、`MEMORY_MIN_FINAL_SCORE`(0.55→**0.42**)、`MEMORY_MIN_IMPORTANCE`(3→**2**)、`MEMORY_CONTEXT_TOPK`(3→**5**)；不合法值回退預設。`buildMemoryContext` 加去敏觀測 log（候選數 / ranked 數 / 最高 similarity 數值 / provider / 門檻；**不記內容或 userId**），catch log 帶去敏 reason。
- `memoryExtractor.js`：放寬 <4 字硬擋白名單（+累/餓/怕/哭/名/叫）；**新增自我介紹（`personal_story`）與家人（`family`）rule 分支**（原本缺、production 只靠 AI 補）；加去敏決策 log（shouldRemember/type/reason/輸入長度，不記原文）。memoryType 皆為 005 CHECK + memoryStore 既有合法值。
- `memoryStore.js`：`createMemoryPostgres` dedupe 末段 `existing.rows[0]` 判空防呆（避免 `duplicate.id` TypeError 崩潰），為空回非崩潰 envelope。

### 測試
- 新增 `memoryContextService.test.js`（rankMemories 放寬後 sim 0.35/importance 2 通過、sim 0.1 仍擋、topK≤5、env 覆寫 fresh-require 驗證）、`memoryExtractor.test.js`（自我介紹→personal_story、家人→family、寒暄/天氣/敏感不退化、既有喜好分支仍正常）。
- 更新 `memoryStore.test.js` 兩個既有測試以反映放寬後門檻（用明確低於新門檻的值驗證排除，保留原意——CR 預期內的門檻變更，非為過測）。
- `package.json` test/check 納入兩個新測試檔。
- 全綠：backend `npm test` **571/571**、`npm run check` exit 0。

### 限制遵守
未讀 `.env`（新 env 變數只列名稱）；未碰 Auth / API 路由形狀 / DB schema / Realtime / Flutter / persona；log 全去敏（不含記憶內容 / userText / userId / token）。

### 範圍外（明確不做）
`/api/memories/*` 身分驗證（需同時接 Flutter idToken）→ 另開安全 CR。

### 裁決
服務內部調校 + 觀測 + 防呆，無 🔒 / schema / 契約變更、測試齊備且全綠、門檻 env 可調（production 可不重 build 微調）；併入主線。實機與 Render log 驗證為後續觀察。

---

## CR-0074 — Demo Script and Presentation Lock（docs-only）

### 模式
**docs-only**。不新增功能、不改後端 / Flutter / caregiver_web runtime、不改 API 契約 / schema。鎖定正式展示流程，產出可照做的 Demo Script 與展示前檢查清單。無 🔒 runtime 變更。

### 產出
- **改寫 `docs/DEMO_SCRIPT.md`** 為 production 版（取代 CR-0005 本機 localhost 版）：5–7 分鐘逐步流程（畫面 / 講稿 / 操作 / 測試句）、時間分配、全域備援、評審快答。鎖定 Render 正式 URL（`-7mb8` / `-caregiver-web`）與 production build 指令（含 marketplace / daily-care 旗標）。
- **測試句庫**：對照 `backend/companion/safety_guard.js` 設計，可可靠觸發對應分級且得體——medium（睡不好+沒胃口→只進 caregiver_web）、high（每天都好難過+沒有人需要我→推 Telegram）、長期記憶建立/回憶句、台語句；urgent 不建議現場觸發。明確標注「Telegram 只推 high/urgent，medium 只進管理端」。
- **`docs/E2E_SMOKE_TEST_REPORT.md`** 新增「Demo Readiness Checklist」小節：僅列展示前檢查項目，**不偽稱 smoke 全 PASS**（實機結果仍見 Run #2 / CR-0071）。

### 安全 / 紅線
腳本明訂展示時不得出現 OpenAI key / Firebase key / `DATABASE_URL` / Admin Token / 真實個資、不開 `.env` / 後台 log；Admin Token 事先貼好不當眾輸入。

### 測試 / 檢查
docs-only。`git status --short` 確認只動 `docs/`、`tasks/`，無任何 secret / `.env` / runtime data 檔被加入。未跑 backend/flutter test（無 runtime 變更）。

### 裁決
docs-only 展示腳本與檢查清單，與現行 production 行為一致（URL / 旗標 / 分級規則 / 分頁皆對照程式確認），未洩 secret；併入主線。

---

## CR-0075 — 記憶端點身分驗證強化（後端 auth + Flutter 帶 idToken）

### 模式
小批次安全強化，觸及 🔒 `server.js` API 契約（12 條記憶路由新增 auth）+ Auth + Flutter。經 plan-mode 與使用者核准。不改 persona / Realtime / Marketplace / Daily Care / DB schema / 記憶檢索門檻（CR-0073）。

### 動機 / 根因
`/api/memory/*` 與 `/api/memories/*`（extract/search/context/greeting/forget-recent/memories list·create/:id archive）原**完全無 auth**、userId 取自 client（任何人可讀寫他人記憶）。
關鍵正確性發現（已驗證）：Flutter 一直以 `currentElderId`（= `session.elderId` = `users.elder_id`）當記憶 userId；`requireResidentCaller.elderId` 亦為 `users.elder_id`。∴ 記憶 key 用 caller.elderId 與既有資料完全一致，**不孤立既有記憶**。

### 變更
- `server.js`（🔒）：全部 12 條記憶路由掛 `requireResidentCaller`；新增 `resolveMemoryCaller(req,res)` helper——記憶 key 取 `req.residentCaller.elderId`，client 帶 body/query `userId` 與其不符 → 403 `forbidden_resident`（reconcile-or-403，比照 companion/chat）。成功 response 形狀不變，只新增 401/403。
- `lib/services/memory_service.dart`：建構子加 `http.Client` + `AuthTokenProvider`；所有方法改用注入 client 並帶 `Authorization: Bearer <idToken>`；取不到 token 不掛 header、不 throw（記憶非關鍵，MemoryController 已靜默 catch）。
- `lib/app.dart`：`MemoryService` provider 移到 `AuthController` 之後（原在其前讀不到），注入 `authTokenProvider: () => AuthController.resolveNotifyAuthToken()`（同 CompanionChat / CareAlertNotify token 來源）。
- 不改 memory_controller 的 userId 傳遞（仍送 currentElderId；後端 reconcile 相符）。

### 測試
- 新增後端 `services/memory/memoryEndpointAuth.test.js`（真 Express + installResidentCallerStub）：無 token→401；有 token 通過；body/query userId 不符→403；相符→通過；archive/extract/forget-recent 同樣 gated。
- 新增 Flutter `test/services/memory_service_test.dart`：有 token→帶 Authorization；無 provider / null / 例外→不掛 header 且不 throw。
- 既有 memory_controller_test / memory_management_screen_test（fake service 繞過 http）不受影響；既有後端記憶 service 測試（非端點）不受 auth 影響。
- `package.json` test/check 納入新後端測試。
- 全綠：backend `npm test` **577/577**、`npm run check` exit 0；flutter memory 測試全 passed、analyze clean。

### 限制遵守
未讀 `.env`、未把 token 進 git；未改 persona/Realtime/Marketplace/Daily Care/schema/檢索門檻；既有成功 response 形狀不變。

### ⚠️ 部署順序
後端上線後，**舊 App（未帶 token）記憶呼叫會 401**（靜默降級、不崩潰）；需重 build + 重裝 iPhone App（含本 CR Flutter 版）記憶才恢復。建議合併後盡快重裝再驗收。

### 裁決
契約已記錄（本檔 + PROJECT_ARCHITECTURE）、測試齊備且全綠、key 與既有資料一致不需 migration；併入主線。

---

## CR-0079 — Elderly Friendly Error Message Polish（含 🔒 realtime_voice_service.dart 最小修改）

### 模式
小批次 UI 文字層修正，來源為 CR-0076 audit 的程式碼 P0。觸及 🔒 `lib/services/realtime_voice_service.dart`，**已先經 architecture-agent 審查核准（結論：核准 / 風險 low）**，由 realtime-voice-agent 依核准 diff 執行；其餘檔案為非鎖定檔。不改 Realtime 主流程、不改 API 契約、不改 Auth。

### 動機 / 根因
3 處將工程錯誤字串直接顯示給長者：agent_router_service 的 `error.toString()` / HTTP 狀態碼 / `agent route` 字眼；realtime data channel `error` 事件把 API 英文原文（或「Realtime API 發生錯誤」fallback）emit 給 UI（`voice_agent_controller._handleRealtimeFailure` 在 `lastFailureType == none` 時直接顯示 payload）；settings 診斷區顯示 enum 原名。

### 變更
- `agent_router_service.dart`：HTTP ≥400 / timeout / 例外三路徑改回白話 errorMessage，工程細節進 `debugPrint`。
- `realtime_voice_service.dart`（🔒）：error 事件分支只改 emit 字串——新增 top-level const `realtimeApiErrorUserMessage`（白話 + 引導打字），原始訊息只進 `_log`（空訊息印 `(no message)`）。`_isStopping` guard / `_isSpeaking` / `_recordFailure` 狀態機 / SDP/ICE/DataChannel 全未動；同檔 350、1124 行兩處 emit 經查無外漏路徑，不動。
- `settings_screen.dart`：診斷「最近錯誤」由 `lastFailure.name` 改用既有 `RealtimeFailureTypeLabel.message`。

### 測試
- 更新 `test/services/agent_router_service_test.dart`（timeout 斷言改白話文案）並新增 HTTP 500 / 網路例外 2 案例（斷言無狀態碼、無 exception 字串）→ 4/4 綠。
- 新增 `test/realtime_voice_service_test.dart`「error event surfaces plain-language message」→ 18/18 綠。
- 下游 `voice_agent_controller_realtime_lifecycle` + `realtime_timeout` → 30/30 綠。
- `flutter analyze`：本 CR 修改檔案 0 issue；既有無關 error（`mock_service_provider_gating_test.dart:160`，CR-0072 遺留 invalid_override）未處理、已記錄於 `docs/ERROR_MESSAGE_POLISH_CR0079.md` §5。

### 裁決
🔒 檔案僅 emit 字串內容變更，主流程與契約零影響、觀測性不變、測試齊備且全綠；併入主線。詳細文案對照見 `docs/ERROR_MESSAGE_POLISH_CR0079.md`。

---

## CR-0085 — Change Review Backfill and Final Feature Queue Alignment（docs-only）

### 模式
**docs-only / 整理型 CR。不改任何程式、不改後端 / Flutter / caregiver_web runtime、不改 API 契約 / DB schema / Realtime 主流程。** 僅補登先前已完成卻未登錄本檔的 CR，並重新對齊重複 / 缺漏的 CR 編號。不改寫 git 歷史、不更名既有 task 檔（保留 commit ↔ 檔名可追溯性）。規格見 `tasks/CR-0085-change-review-backfill-and-cr-number-alignment.md`。

### 動機 / 問題
盤點本檔、`tasks/`、git log 後發現：
- **編號重複**：`CR-0053`（既有 prod-e2e 已登錄 vs. 後來「雪貂」commit `65a4b8e` 誤用）、`CR-0075`（既有「記憶端點身分驗證」已登錄 vs.「寵物素材正規化」commit `2da9baa` 誤用）。
- **已完成但未登錄**：`CR-0064`、`CR-0065`、`CR-0080`、`CR-0080A`、`CR-0083`。
- **無 CR 編號**：「Demo 期間所有寵物外觀免費」commit `35e55f2`。

### 正式編號對齊（單一真相）
| 變更內容 | 來源 commit | 原始標示 | 正式編號 |
|---|---|---|---|
| 寵物素材尺寸 / 留白正規化（dog/fox/guinea_pig） | `2da9baa` | 「CR-0075」撞號 | **CR-0081** |
| 雪貂 ferret 去背 + 換皮 / 商店整合 | `65a4b8e` | 「CR-0053」撞號 | **CR-0082** |
| Realtime 語音工具呼叫 + 字幕 turn 整合 | `8e838a9` / `c1c52a6` | CR-0083（正確） | CR-0083 |
| Demo：所有寵物外觀免費直接可換 | `35e55f2` | （無編號） | **CR-0084** |
| 本整理型 CR | — | — | **CR-0085** |

- 保留不再重用的歷史缺號：`CR-0077`、`CR-0078`。
- **下一個可用的新 CR 編號：`CR-0086`**（往後一律遞增）。

### 補登紀錄（編號正確、僅先前漏登）
- **CR-0064 — Render 正式環境 caregiver_web CORS 修正**：單一 CORS middleware（白名單來源 `CORS_ALLOWED_ORIGINS`，逐一比對、fail-closed、不 allow-all）。落地：`backend/stt_proxy/server.js:166` 標記；commit `aff3027` 等。✅ 併入主線。
- **CR-0065 — caregiver_web 正式版分頁旗標**：依 `featureFlags` 在正式版隱藏 marketplace / 今日任務分頁入口（後端上線後又以 `15832a2` 重新開啟）。落地：`caregiver_web/app.js applyFeatureFlags`；commit `188db05`。✅ 併入主線。
- **CR-0080 — 語音字幕同步 + web-search 可靠性**：字幕分頁同步、放寬 web-search 意圖判斷（`shouldSearch` / `needsWebSearch` 對齊）。commit `c6f01ea`。✅ 併入主線。
- **CR-0080A — 測試替身簽章對齊**：`_ThrowingChatService.reply` 簽章對齊 `CompanionChatService`。commit `32a121e`。✅ 併入主線。
- **CR-0083 — Realtime 語音工具呼叫 + 字幕 turn 整合**：工具結果延後到語音結束才呈現，避免蓋掉字幕。commit `8e838a9` / `c1c52a6`。✅ 併入主線。

### 新編號變更摘要（補追溯）
- **CR-0081（原「CR-0075」）**：dog/fox/guinea_pig 共 51 張素材依統一規格重輸出（畫布 / 留白 / 主體位置一致）+ `scripts/normalize_pet_assets.sh`。commit `2da9baa`。✅ 併入主線。
- **CR-0082（原「CR-0053」）**：雪貂 18 張圖去背為透明 1024² RGBA、對齊 dog 畫布與腳底基準線；`PetSkin` 新增 `ferret`、`AssetPaths` 註冊、加入換皮 / 商店清單；含測試。commit `65a4b8e`。✅ 併入主線（flutter test 全綠）。
- **CR-0084 — Demo 全寵物免費**：`PetController` 新增 `freeAllSkins` 參數（預設 false，維持商店 / 解鎖流程）；`app.dart` 於 Demo 期間傳 `true`，價格仍保留於 `PetSkin.unlockCost`，Demo 後改回 `false` 即恢復付費。commit `35e55f2`。✅ 併入主線（600 測試全綠）。

### 限制遵守
未讀 `.env`、未把 token / runtime data 進 git；無 program code / API 契約 / schema / Realtime 變更；不改寫 git 歷史、不更名既有 task 檔；未偽稱測試結果（docs-only）。

### 裁決
docs-only 紀錄整理：補齊漏登 CR、消除 CR-0053 / CR-0075 重號歧義、宣告下一可用編號 CR-0086。與現行主線實況一致（逐筆對照 commit）、未洩 secret、無受保護模組變更；併入主線。

---

## CR-0086 — Caregiver Analytics Dashboard（長者狀態分析）

### 模式
小批次新增「長者狀態分析」後台頁 + 一條 caregiver-capable 分析 API。觸及 🔒 `server.js`（新增路由，不改既有路由形狀）。經本檔登錄。沿用既有授權模型（resolveAdminAuthContext + authorizationService），不改 Telegram / Realtime 語音主流程 / 長者端 Flutter UI / DB schema / 既有 API 形狀。詳見 `docs/CAREGIVER_ANALYTICS_DASHBOARD_CR0086.md`、規格 `tasks/CR-0086-caregiver-analytics-dashboard.md`。

### 動機
後台偏「事件列表」，缺「長期觀察」。新增分析頁讓照護者用近期趨勢（警示統計、任務完成、情緒、互動）掌握長者是否變差。

### 變更
- **後端**
  - 新增 `services/admin/caregiverAnalyticsService.js`：聚合單一長者近期狀態（純函式、資料可注入、可單元測試）。Care Alert / 任務為真實資料；情緒 / 遊戲沿用 `adminAnalysisService` 的 `dataSource`（measured / reference / insufficient）誠實標註；寵物無後端來源回空狀態。
  - `server.js`（🔒）新增 `GET /api/caregiver/analytics?elderId=&rangeDays=`，掛 `resolveAdminAuthContext`：super_admin 任一住民；caregiver 經 `assertCanAccessResident`，跨住民 403。缺 elderId → 400；rangeDays 預設 7、夾 1..90。回 `{ ok:true, summary, emotionTrend, careAlertStats, taskStats, gameMetrics, petStatus, ... }`。不改既有路由形狀。
- **前端（caregiver_web）**
  - `index.html`：導覽列新增「長者狀態分析」分頁 + `view-analytics` 區塊（非醫療 + 資料來源橫幅、長者選擇器、區間選擇、各統計區塊容器）。
  - `app.js`：新增 `elAN` 快取、`loadAnalyticsElders`（選擇器沿用 `/api/admin/elders` + `authHeaders`，依授權住民過濾）、`loadResidentAnalytics`、`renderAnalytics`；`showView` 納入 analytics + 懶載入；`currentViewName` 認得 analytics；init 綁定分頁 / 選擇 / 區間 / 重新整理。載入 / 空 / 401 / 403 / 一般錯誤皆白話，無 raw error。
  - `styles.css`：新增分析頁控制列 / 內容區樣式（其餘卡片 / 統計 / bar 沿用既有）。

### 資料真實性（誠實原則）
真實：`care_alerts`、`daily_care_tasks`(+submissions)。簽到狀態以任務提交推估（無獨立簽到表，已標註 proxy）。情緒 / 遊戲對真實長者目前回 `insufficient`（資料表存在但無真實寫入流程）；示範種子長者顯示 `reference` 標籤資料。寵物狀態後端無來源 → 空狀態。**不以假資料偽裝正式資料**。

### 測試
- 新增後端 `services/admin/caregiverAnalyticsService.test.js`（單元）+ `caregiverAnalyticsEndpoint.test.js`（真 HTTP：401 / 400 / caregiver 授權 200 / caregiver 跨住民 403 / super_admin 200 / 空狀態 / rangeDays 非法回 7），並登記於 `package.json` test / check。
- 新增前端 `caregiver_web/analytics_dashboard.test.js`（靜態檢查：分頁 / 橫幅 / API / caregiver-capable / 懶載入 / 空狀態白話 / 無敏感欄位）。
- 全綠：後端 `npm test` **592 passed**、`npm run check` exit 0；前端 `node --test caregiver_web/*.test.js` **108 passed**（既有 101 + 新 7）。

### 限制遵守
未讀 `.env`；未改 Telegram / Realtime 語音主流程 / 長者端 Flutter UI / DB schema / 既有 API 形狀；caregiver 不會看到未授權住民資料（沿用既有授權模型，fail-closed）；前端無 raw error / stack trace / 工程字。

### 已知限制
簽到為任務提交 proxy；情緒 / 遊戲對真實長者多為「資料不足」（無真實寫入流程）；寵物狀態後台未串接。詳見 `docs/CAREGIVER_ANALYTICS_DASHBOARD_CR0086.md` §7。

### 裁決
新增路由與既有授權模型一致、不改既有契約形狀、誠實標註資料來源、測試齊備且全綠、未碰受保護主流程；併入主線。下一個可用 CR 編號：**CR-0087**。

---

## CR-0087 — Pet Concern Push Notifications（寵物關心提醒）

### 模式
小批次 Flutter 端新增功能，**全為長者端本地推播**。擴充既有 `NotificationService`（不另寫一套通知系統），不觸及 🔒 Realtime 主流程 / 後端 API / DB schema，不改 Telegram / Care Alert / 管理端。詳見 `docs/PET_CONCERN_PUSH_NOTIFICATIONS_CR0087.md`、規格 `tasks/CR-0087-pet-concern-push-notifications.md`。

### 動機
讓 AI 寵物更像會關心人的夥伴：在寵物心情低落 / 飽足度低 / 親密度低 / 長者久未互動時，對**長者本人**發溫和的本地提醒，受 cooldown 限制不打擾。與通知照護者的 Care Alert（Telegram / 後端）本質不同，不可混接。

### 變更
- 新增 `lib/services/pet_concern_notification_policy.dart`：純 Dart 決策（門檻、優先序、cooldown、文案），可單元測試、不依賴 plugin。id 10002、獨立 channel，與簽到提醒（10001）區隔。
- 擴充 `lib/services/notification_service.dart`：`schedulePetConcernReminder` / `cancelPetConcernReminder` + 獨立 channel + tap 導回首頁。沿用既有 `zonedSchedule` 寫法，既有簽到方法不動。
- `lib/services/local_storage_service.dart`：新增 cooldown 紀錄（`concernNotifyTimestamps`）讀寫 + 開關欄位持久化，依帳號命名空間隔離。
- `lib/models/user_profile.dart` + `lib/controllers/profile_controller.dart`：新增 `concernRemindersEnabled`（預設開）+ setter。
- `lib/screens/settings_screen.dart`：「日常提醒」區新增「寵物關心提醒」`SwitchListTile`（關閉不影響必要提醒）。
- `lib/app.dart`：lifecycle `paused` 時依寵物與互動狀態評估並排「之後才跳」的關心提醒，`resumed` / 換帳號時取消；wire tap 導頁。每日簽到（10:00）邏輯保留不動。

### 資料來源（真實、不捏造）
寵物 mood/satiety/intimacy 取自長者端真實 `PetStats`（SharedPreferences）；情緒取自 `ConversationTurn.emotionTag`；inactivity 以「離開 App 當下最近一次對話 turn 時間」估算（無紀錄則不觸發）。缺資料一律不觸發對應提醒。

### 測試
- 新增 `test/services/pet_concern_notification_policy_test.dart`（純決策 14 案）、`notification_service_pet_concern_test.dart`（plugin mock 不 crash + 與簽到互不干擾）、`concern_notification_storage_test.dart`（開關 + cooldown round-trip + 帳號隔離）。
- 既有簽到提醒測試全綠（行為未變）。
- 全綠：`flutter analyze` No issues；`flutter test` 全部通過（619 tests）。

### 限制遵守
未讀 `.env`；未改 Telegram / Care Alert 通知規則 / Realtime 語音主流程 / 後端 / DB schema；未破壞每日簽到提醒；文案無工程字；推播有 cooldown 且可由設定開關關閉。

### 已知限制
每日簽到實際為 10:00（非規格假設 18:00），保留未動；inactivity 為前景最佳估計（無背景 isolate）；關心提醒採「離開時排未來、回來時取消」。詳見 `docs/PET_CONCERN_PUSH_NOTIFICATIONS_CR0087.md` §9。

### 裁決
擴充既有通知服務、純決策可測、不碰受保護主流程與後端契約、誠實處理缺資料、測試齊備且全綠；併入主線。**下一個可用 CR 編號：CR-0088。**

---

## CR-0088 — Mochi Pet Asset Integration and Pet State Trigger Expansion

### 模式
小批次 Flutter 端：(A) 新寵物 mochi 接入（同 CR-0082 ferret 模式）；(B) 寵物狀態顯示改由純函式選擇器決定。**未觸及 🔒 Realtime 主流程 / 後端 / DB**；首頁狀態選擇器為「消費既有訊號」的純函式，不改控制器內部與 Realtime。詳見 `docs/PET_ASSET_STATE_EXPANSION_CR0088.md`、規格 `tasks/CR-0088-mochi-pet-state-trigger-expansion.md`。

### 動機
(A) 新增「麻吉」貓寵物。(B) 先前首頁只讀 `petController.mode` 單一欄位，情緒狀態壽命極短、satiety/mood 等數值從未進顯示路徑 → 幾乎只在 talk/listening 間切換，其他 states 圖少有機會出現。

### 變更
- **素材**：18 張 `mochi_*.png` 去背為透明 1024² RGBA、對齊 dog 畫布與腳底基準線（原圖 738×1314 等白底 RGB）。ferret 覆查確認 CR-0082 去背仍乾淨，未更動。未建立 `assets/pets/mochi/`。
- **registry**：`PetSkin` 加 `mochi`（麻吉 / 120 點），`AssetPaths` 註冊 talk6/rest3/listening1/states8；換皮選單由 `PetSkin.values` 自動帶入（排 ferret 之後）。Demo 全寵物免費沿用 CR-0084。
- **狀態選擇器**：新增 `lib/utils/pet_state_selector.dart`（純函式）：listening(收音) > talking(播放) > transient(短暫情緒) > care state(satiety/mood/intimacy/深夜) > rest。`PetController` 新增 `showTransientState` 短暫情緒持有（擴充既有 idle 機制，到期自清）。`home_screen` 改以選擇器結果顯示寵物圖，並監聽對話在情緒對話結束後觸發 transient。
- **誠實缺資料**：thirsty 無 hydration 來源 → 不硬觸發；sleepy 由真實時鐘 / `tired` 觸發；缺數值不硬觸發。

### 測試
- 新增 `test/models/mochi_skin_test.dart`、`test/utils/pet_state_selector_test.dart`、`test/controllers/pet_controller_transient_test.dart`。
- 全寵物 8 狀態可解析、mochi 18 圖為 1024² RGBA、選擇器優先序與 mapping、transient 自清；既有寵物 / picker / avatar 測試全綠。
- `flutter analyze` No issues；`flutter test` **665 passed / 0 failed**。

### 限制遵守
未讀 `.env`；未改 Telegram / Care Alert 後端 / 管理端分析頁 / 推播通知（CR-0087）/ Realtime 主流程 / 字幕同步（留 CR-0089）；未動既有寵物素材與邏輯；未建立 mochi 子資料夾、正式 UI 不讀 `pets_raw/`。

### 已知限制
mochi rest_03 為趴睡姿（源圖）；thirsty 缺觸發來源、sleepy 僅時鐘 / tired；連續通話中 listening 穩定顯示；字幕對齊留 CR-0089。詳見 `docs/PET_ASSET_STATE_EXPANSION_CR0088.md` §11。

### 裁決
新寵物接入與既有模式一致、狀態選擇器為消費式純函式不碰受保護主流程、誠實處理缺資料、測試齊備且全綠；併入主線。**下一個可用 CR 編號：CR-0089。**

---

## CR-0089 — Voice Caption Synchronization Polish

### 模式
小批次修正字幕 / talk 與實際語音對齊。**觸及 🔒 `lib/services/realtime_voice_service.dart`，已先經 architecture-agent 審查核准（兩次：原案 + 修正案，皆 ✅ / 風險 LOW，核准紀錄見下）**，改動為純加法（不動 SDP / ICE / DataChannel / connect / response 生命週期）。其餘修正在 controller / 測試層。不改 persona（CR-0090）、不改寵物素材（CR-0088）、不改推播（CR-0087）。詳見 `docs/VOICE_CAPTION_SYNC_CR0089.md`、規格 `tasks/CR-0089-voice-caption-synchronization-polish.md`。

### 動機 / 根因
收 turn 綁在 `response.done`（生成結束）而非語音播完：service 在 response.done 即送 `assistantAudioEnd`，controller 隨即 `_finishPetTurn` 收掉 talk / 字幕，但語音可能還在播 → 字幕與正在播的語音對不上、下一段提前接手。真正「播完」訊號 `output_audio_buffer.stopped` 原本只在 service 內部用（CR-0083），未對外發出。

### 變更
- **🔒 `realtime_voice_service.dart`（純加法，經核准）**：新增兩個 event —— `assistantAudioPlaybackStarted`（真實語音開始、一輪一次，守 `!_sawOutputAudioBufferThisResponse`）與 `assistantAudioPlaybackStopped`（`output_audio_buffer.stopped`，於 CR-0083 flush 之後發）。保留 response.done 既有 `assistantAudioEnd`。
- **`voice_agent_controller.dart`**：`_currentTurnHadAudio`（只在 playback-started 設、每輪 response-start 重置）+ `_awaitingAudioStop` + 15s 保底計時器。response.done（done/audioEnd 兩路徑）改走 `_requestFinishPetTurn`：有真實語音 → 保留 speaking + 字幕、暫停麥克風，等 playback-stopped 才 `_finishPetTurn`（幂等）；純文字回覆 → 立即收。
- **測試**：service（started/stopped 條件、順序回歸）、controller（有語音延後 / 純文字立即 / 字幕保留）、既有 lifecycle + integration 改寫為新時序。

### architecture-agent 核准紀錄（🔒 realtime_voice_service.dart）
- **原案（assistantAudioPlaybackStopped）**：✅ APPROVE，風險 LOW。條件：service emit 與 controller case 同批次落地（switch 無 default）、新 emit 置於 `_flushPendingToolOutcome()` 之後、保留 response.done 的 assistantAudioEnd、`_finishPetTurn` 對兩路徑幂等 + 保留 4s/保底計時器、service 測試補齊、enum 加語意註解。
- **修正案（assistantAudioPlaybackStarted）**：🔁 MODIFY-then-approve，風險 LOW。修正要點：emit 必須守 `!_sawOutputAudioBufferThisResponse`（**非** `_isSpeaking`，否則文字先於語音的混合回覆會漏發、導致字幕提前被切）；controller `_currentTurnHadAudio` 須於 turn 起始重置；補 audio-only / text-only / text-then-audio 三路徑測試。
- 兩案要求皆已落實；合併後 `flutter analyze` 零警告、相關 service / controller / integration 測試全綠。

### 測試
`flutter analyze` No issues；`flutter test` **672 passed / 0 failed**（連續兩次穩定）。涵蓋 service 兩新事件條件 + 順序回歸、controller 有語音延後收 / 純文字立即收 / 字幕保留、既有時序測試更新。

### 限制遵守
未讀 `.env`；🔒 檔僅加事件、未動 SDP/ICE/DataChannel/連線/response 生命週期，且有 architecture-agent 核准紀錄；未改 persona / 寵物素材 / 推播 / Care Alert / Telegram / 後台 / 後端 / DB；未刪既有測試（行為時序變更處據實更新並註明 CR-0089）。

### 已知限制
依賴 `output_audio_buffer.stopped`（漏訊號由 15s 保底收尾）；純文字 Realtime 回覆沿用 response.done 立即收；playback-stopped 未帶 turn id（沿用既有 turn 守門）。詳見 `docs/VOICE_CAPTION_SYNC_CR0089.md` §6。

### 裁決
🔒 改動純加法且兩度經 architecture-agent 核准、收 turn 改以真實語音播完為準、測試齊備且全綠、不碰受保護連線主流程；併入主線。**下一個可用 CR 編號：CR-0090。**

---

## CR-0090 — Companion Conversation Naturalness Polish

### 模式
小批次 **後端 persona / instruction 字串** 調校，改善對話自然度。**未碰 🔒 `realtime_voice_service.dart`（理論成立，本 CR 不需該檔）**，亦未改 server.js 路由 / response 形狀（API 契約）—— 僅改 persona 常數字串 + 一個測試用純函式匯出，故非 🔒 API 契約變更。不改 persona 安全邊界、不降 Care Alert、不改字幕同步 / 寵物素材 / 推播 / Telegram / 後台 / DB。詳見 `docs/COMPANION_CONVERSATION_NATURALNESS_CR0090.md`、規格 `tasks/CR-0090-companion-conversation-naturalness-polish.md`。

### 動機
展示時最易感受到的問題：對話太罐頭、重複同句安慰、每次硬轉提醒 / 任務、安慰過度醫療化、台語每句硬翻成難懂純台語。

### 變更（皆 `backend/stt_proxy/server.js` persona 常數）
- **語音 `REALTIME_INSTRUCTIONS`**：新增「【陪伴優先 / 自然度】」（抗重複、不硬轉功能、先陪伴、不過度醫療化、不每句問句收尾）；工具「意義對照表」前加閘門「**只在長者明確要你做某件事時才套用**」——閒聊不套用、不硬轉功能。工具能力與高風險安全句**原樣保留**。
- **打字 `COMPANION_CHAT_PERSONA`**：新增「【自然陪伴】」（同段不重複開頭 / 安慰、不每次「聽起來…」開頭、不每次問句結尾、閒聊不硬轉任務、低落先陪伴後求助、一次一個溫和回應）。
- **台語 `outputLanguageInstruction`**：由「整段純台語、不可用標準中文」改為「自然口語、以台語為主、**長者聽得懂優先**、可國台語混用、不用生僻字」。
- `module.exports.buildRealtimeInstructions`：測試用純函式匯出。

### 安全
`safety_guard.js`、Care Alert 摘要、`next_strategy_planner.js` 安全分支、兩個 persona 的高風險安全句**完全未改**；既有安全 / Care Alert 斷言全綠（安全閂未動）。

### 測試
更新 / 新增 `companionChatPersona.test.js`：台語自然 guardrail（以台語為主 / 聽得懂優先 / 不每句硬翻純台語）、打字自然陪伴 guardrail、語音 persona guardrail（陪伴優先 + 抗重複 + 工具表只在明確需求套用 + 安全保留 + 無工程字眼）。`npm test` **595 passed**、`npm run check` exit 0。未改 Flutter，未跑 flutter test。

### 後續事項（交 realtime-voice-agent）
🔒 `realtime_voice_service.dart` `_instructionsWithCompanionContext`（L1279-1308）含一份**縮版語音 persona 副本**（mid-session `session.update` 用）+ 自帶台語指引 + 工具念稿包裝，不會反映本 CR persona / 台語措辭。建議 realtime-voice-agent 後續同步（屬 🔒 檔，須經其 owner / architecture-agent）。session 起始 instructions 來自後端 `/api/realtime/call`（已套用本 CR），影響有限。Flutter `companion_reply_strategy_service.dart` fallback 句庫亦列為後續可選。

### 限制遵守
未讀 `.env`；未碰 🔒 Realtime 檔與 server.js 路由 / response 契約；未弱化安全 / Care Alert；不讓 AI 做醫療診斷。

### 裁決
後端 persona 字串調校、安全邊界與工具能力原樣保留、抗重複 / 不硬轉任務 / 台語自然由 guardrail 測試把關、測試全綠、不碰受保護模組；併入主線。**下一個可用 CR 編號：CR-0091。**

---

## CR-0091 — Conversation History UX Polish

### 模式
**純前端 Flutter** 紀錄頁 UX：去工程化 + 本地搜尋。資料本地（`ConversationController.history` / `sessionSummaries`）、量不大 → 採前端本地搜尋，**未新增後端 API**（任務 D1）。不改 AI persona（CR-0090）/ Realtime / 字幕同步（CR-0089）/ 寵物素材（CR-0088）/ 推播（CR-0087）/ Care Alert / Telegram / 後台（CR-0086）/ DB。詳見 `docs/CONVERSATION_HISTORY_UX_CR0091.md`、規格 `tasks/CR-0091-conversation-history-ux-polish.md`。

### 動機
紀錄頁直接把 `emotionTag` / `petMood` 原值顯示給長者（「情緒：sad｜寵物心情：neutral」、卡片 chip 顯示 sad / neutral），且紀錄多了沒有搜尋。

### 變更
- 新增 `lib/utils/conversation_history_display.dart`（純函式）：`friendlyMoodLabel`（情緒→白話心情，neutral / raw key → null 不顯示）+ `filterConversationSessions`（本地搜尋：標題 / 預覽 / 長者話 / 寵物回覆，大小寫不敏感，中文 + 台語漢字）。
- `conversation_detail_screen.dart`：刪整段那行不再外漏 emotionTag / petMood，改友善心情 + 刪除提示（neutral 只剩刪除提示），長按刪整段保留。
- `conversation_session_tile.dart`：卡片 chip 改友善心情；neutral / 不認得不顯示 chip。
- `history_screen.dart`：新增搜尋框（放大鏡 + 清除 ✕、字級 18）、本地即時過濾；空狀態分「沒有紀錄」與「搜尋無結果」兩種白話提示。

### 不外漏 raw 欄位
全 app 掃描確認紀錄頁 Text() 不再渲染 emotionTag / petMood / riskLevel / 「情緒：」「寵物心情：」；home_screen / agent_confirmation 的 emotionTag / riskLevel 僅為邏輯用途（未顯示）。

### 測試
新增 `test/utils/conversation_history_display_test.dart`（friendlyMoodLabel + 搜尋：中文 / 台語 / 大小寫 / 無結果 / 空查詢）；`conversation_controller_ui_state_test.dart` 更新詳情刪整段文案 + 新增 HistoryScreen 搜尋 widget 測試（搜長者話 / 寵物回覆、清除恢復、畫面無 raw neutral / sad、無結果友善空狀態）。`flutter analyze` No issues；`flutter test` **684 passed / 0 failed**。

### 限制遵守
未讀 `.env`；純前端、未動後端 / API / DB / Realtime / persona / Care Alert / Telegram / 後台；不把 raw 情緒分析顯示給長者；錯誤 / 空狀態白話、不露 stack trace。

### 已知限制
搜尋為 substring（無模糊 / 拼音）；台語以漢字比對；日期文字搜尋未納入（可選）。詳見 `docs/CONVERSATION_HISTORY_UX_CR0091.md` §7。

### 裁決
純前端紀錄頁去工程化 + 本地搜尋、不外漏 raw 欄位、不新增後端、空 / 錯誤狀態白話、測試齊備且全綠、不碰受保護模組；併入主線。**下一個可用 CR 編號：CR-0092。**

---

## CR-0092 — Onboarding Navigation Flow Polish

### 模式
**純前端 Flutter** 新手導覽跨頁化。**沿用既有跨頁機制**（`CoachMarkStep.shellTabIndex` + `CoachMarkHost` 切分頁 + overlay 掛在 shell 之上 + 18-frame target 重試 + 置中降級），**未重構導航**。不改 Realtime / persona（CR-0090）/ 紀錄搜尋（CR-0091）/ 字幕（CR-0089）/ 寵物素材（CR-0088）/ 推播（CR-0087）/ 後台（CR-0086）/ App icon。詳見 `docs/ONBOARDING_NAVIGATION_FLOW_CR0092.md`、規格 `tasks/CR-0092-onboarding-navigation-flow-polish.md`。

### 動機
導覽大多停在首頁：商城/紀錄/設定步驟只亮底部分頁按鈕，使用者沒真的看到頁面。

### 變更
- `coach_mark_keys.dart`：新增 5 個 target key（`shopKey` / `historyTitleKey` / `historySearchKey` / `settingsAppearanceKey` / `settingsReplayKey`）；`buildHomeCoachMarkSteps` 由 13 步改 **16 步**——步驟 10/11/12 從「亮按鈕」改為帶 `shellTabIndex` 真正切到商城(1)/紀錄(2)/設定(3) 並高亮頁內目標，新增「搜尋紀錄」「重看導覽」步驟與「回首頁」收尾步。
- 三畫面用 `KeyedSubtree` 掛上對應 key：`shop_screen.dart`（商城標題）、`history_screen.dart`（標題 + CR-0091 搜尋框）、`settings_screen.dart`（換造型區 + 重看導覽鈕）。
- Controller / Host / overlay **未改**（機制已足夠）。

### target ready / fallback
切頁後 overlay 逐 frame 重試取 target（上限 18，無硬編延遲），取不到 / 元件隱藏 → 置中說明卡，不 crash、不黑屏、不露工程訊息。搜尋框在尚無紀錄時降級置中卡。

### 測試
更新 `coach_mark_steps_test.dart`（16 步、各步 shellTabIndex / target、四分頁覆蓋、無工程字）、`coach_mark_host_test.dart`（自動 16 步、逐步切 1→2→3→0、完成回首頁記已看過）；既有 HistoryScreen / ShopScreen widget 測試補 `CoachMarkKeys` provider。`flutter analyze` No issues；`flutter test` **685 passed / 0 failed**。

### 限制遵守
未讀 `.env`；純前端、未重構導航、未動受保護模組；GlobalKey 取不到安全降級不 crash；首次與重看共用同一套 controller。

### 已知限制
僅走底部分頁；若未來導覽要指向 pushed route（marketplace 內頁 / 提醒 / 記憶 / Care Alert / 拼圖）需調整 overlay 掛載層級 → 另開 CR 先回報。詳見 `docs/ONBOARDING_NAVIGATION_FLOW_CR0092.md` §7。

### 裁決
沿用既有跨頁機制做最小擴充、不重構導航、降級安全不 crash、測試齊備且全綠、不碰受保護模組；併入主線。**下一個可用 CR 編號：CR-0093。**

---

## CR-0093A — Realtime Mid-session Persona Alignment（CR-0090 後續小修）

> 用 **A 編號**避免打亂主線：**主線下一個 CR 仍為 CR-0093 — App Icon Replacement**，本 CR 不佔用該序號。

### 模式
CR-0090 後續小修，**觸及 🔒 `lib/services/realtime_voice_service.dart`，已先經 architecture-agent 審查核准（✅ / 風險 LOW，核准紀錄見下）**。僅同步該檔 mid-session `session.update` 縮版 persona 的**字串內容**，不改 SDP / ICE / DataChannel / 連線 / response lifecycle / 字幕同步 / 工具路由 / 狀態機 / 後端 persona / Care Alert / Telegram。詳見 `docs/REALTIME_MID_SESSION_PERSONA_ALIGNMENT_CR0093A.md`、規格 `tasks/CR-0093A-realtime-mid-session-persona-alignment.md`。

### 動機
CR-0090 已改後端語音 persona，但 `realtime_voice_service.dart` 內供 `session.update` 用的縮版 persona 副本（`_instructionsWithCompanionContext`）未同步 → 通話中 nextStrategy 變更時會回到舊版（較制式 / 易重複 / 硬轉任務）。

### 變更
- `_instructionsWithCompanionContext`（≈1279-1300）persona 字串加入 CR-0090 規則：陪伴優先不硬轉任務、避免重複罐頭 / 不每句問句收尾、低落先陪伴不過度醫療化，並**新增急性風險安全句**（胸痛 / 呼吸困難 / 跌倒 / 嚴重不適 / 自傷意念 → 提高安全提醒、建議聯絡家人或就醫；此縮版原本缺，屬加法強化）。
- `_outputLanguageGuidance`（≈1302-1310）台語措辭同步為「以台語為主、長者聽得懂優先、可國台語混用、不硬翻生僻字」；`replyLanguage=` regex 與 `mixed-zh-taigi`/`taigi`/default switch key 不變。
- payload 形狀不變、保留 nextStrategy 框架語、不外漏分析欄位名稱。

### architecture-agent 核准紀錄（🔒 realtime_voice_service.dart）
✅ APPROVED，風險 LOW。確認改動僅為兩私有字串建構器內容、`session.update` payload 形狀不變、未觸及連線 / lifecycle / CR-0089 audio 事件 / 佇列 / tool flush / 字幕 / 狀態機 / 簽章；安全句為加法強化。綁定條件（皆已遵守）：只改兩方法字串、不改名 / 簽章；保留 `$context` 注入與框架語；保留 `_outputLanguageGuidance` regex 與 switch key（僅措辭）；payload 精簡；安全句溫暖不重複；以 `eventSenderForTesting` 補測試、不弱化既有 realtime 測試。

### 測試
新增 `realtime_voice_service_test.dart`「CR-0093A …」：捕捉 `session.update` payload、解析 instructions、斷言含 CR-0090 guardrail（不硬轉任務 / 避免重複 / 不每句問句 / 低落先陪伴不過度醫療化 / 安全句 / 台語自然 / 保留 nextStrategy 框架語）。不影響既有 realtime / CR-0089 audio 事件測試。`flutter analyze` No issues；`flutter test` **686 passed / 0 failed**。

### 限制遵守
未讀 `.env`；🔒 檔僅改 persona 字串且經 architecture-agent 核准；未改後端 persona / 工具路由 / Care Alert / Telegram / 字幕同步 / App icon；未弱化安全。

### 裁決
🔒 改動經 architecture-agent 核准、僅同步 persona 文字、payload 形狀與狀態機不變、安全強化、測試齊備且全綠；併入主線。**主線下一個可用 CR 編號仍為：CR-0093（App Icon Replacement）。**

---

## CR-0093 — Pet Animation Pacing and Rest Ping-Pong Loop

> 註：原規劃 CR-0093 為 App Icon Replacement，本輪改先處理動畫節奏（App icon 先不做、延後）。CR-0093 編號用於本動畫 CR。

### 模式
**純前端 Flutter** 動畫節奏調整，只動 `lib/widgets/pet_avatar.dart`（+ 對應測試）。不改寵物素材檔、Realtime、字幕同步、AI persona、推播、後台、Care Alert、App icon。詳見 `docs/PET_ANIMATION_PACING_CR0093.md`、規格 `tasks/CR-0093-pet-animation-pacing-and-rest-ping-pong-loop.md`。

### 變更
- 放慢動畫：talk 220ms→320ms（`kTalkFrameDuration`）、rest→480ms（`kRestFrameDuration`）；其餘單張狀態不啟計時器。
- rest 改 ping-pong：新增純函式 `pingPongFrameIndex(counter, frameCount)`，通用支援 1~4 張（N=3 → 0,1,2,1,0…，尾張不直接跳回首張）；talk 維持線性。
- 與寵物種類無關（rest frames 來自 `AssetPaths.restFrames`）→ dog/fox/guinea_pig/ferret/mochi 全適用。

### 素材備註
發現工作區有 stray 未提交改動把 `assets/pets/rest/mochi_rest_03.png` 換成 428×761 WebP（.png 副檔名、非合法 PNG）；因本 CR 不改素材，已 `git checkout` 還原為 CR-0088 已提交的 1024² 透明 PNG。

### 測試
`test/widgets/pet_avatar_test.dart`：`pingPongFrameIndex`（N=1/2/3/4 序列、尾張不跳首張）、rest widget 動畫不 crash、talk 改用新節奏常數。`flutter analyze` No issues；`flutter test` **692 passed / 0 failed**。

### 限制遵守
未讀 `.env`；純前端 widget 動畫；未改素材檔（mochi_rest_03 還原為提交狀態）/ Realtime / 字幕 / persona / 推播 / 後台 / Care Alert / Telegram / App icon。

### 裁決
純前端動畫節奏 + rest ping-pong（通用 1~4 張）、不破壞其他狀態、不碰素材與受保護模組、測試齊備且全綠；併入主線。**下一個可用 CR 編號：CR-0094。**

---

## CR-0094 — Remove Time-Based Sleepy Idle State

### 模式
**純前端 Flutter** 小修：移除 CR-0088「深夜(22:00–06:00) → sleepy」時段規則（實機晚上測試時寵物閒置一直 sleepy）。只動 `lib/utils/pet_state_selector.dart`（移除 hour 參數 / sleepy 分支）+ `lib/screens/home_screen.dart`（移除傳 hour）+ 測試。不碰素材 / Realtime / 字幕 / persona / 推播 / 後台 / Care Alert / App icon。詳見 `docs/PET_IDLE_SLEEPY_REMOVAL_CR0094.md`。

### 變更
- `PetStateSelector.careStateFor` / `select`：移除 `hour` 參數與 `深夜 → sleepy` 分支。閒置一律回 rest；sleepy 改只由情緒 `tired` 的短暫情緒（`transientModeForEmotion`）觸發。
- `home_screen.dart`：移除 `hour: DateTime.now().hour`。
- 優先序不變：listening > talking > transient > care(hungry/sad/caring) > rest。

### 測試
`pet_state_selector_test.dart` 更新（移除深夜 sleepy 測試、改測閒置回 rest + sleepy 只由 tired 觸發）；`flutter analyze` No issues；`flutter test` **693 passed / 0 failed**。

### 裁決
純前端調整、移除時段 sleepy、sleepy 改由情緒觸發、不碰受保護模組與素材、測試齊備且全綠；併入主線。**下一個可用 CR 編號：CR-0095。**

---

## CR-0095 — Mochi rest_03 Asset Reprocess

### 模式
**純素材重做**（frontend-ux-agent 範圍）：使用者提供新的 mochi rest 圖（428×761 WebP、白底），用正式去背 / 1024² 流程重做 `assets/pets/rest/mochi_rest_03.png`。不改任何程式、Realtime、字幕、persona、推播、後台、Care Alert。詳見 `docs/MOCHI_REST03_REPROCESS_CR0095.md`。

### 變更
- `assets/pets/rest/mochi_rest_03.png`：428×761 WebP → **1024×1024 RGBA PNG**，content bbox `478×800+273+144`（腳底 y944、水平置中、底部留白 80px，對齊 mochi rest_01/02）。
- 去背：edge flood-fill **四角**、**fuzz 12%**（28% 會吃掉淺色貓的白胸/臉/腳掌，已用洋紅底目視驗證）。

### 測試
`flutter test test/models/mochi_skin_test.dart` **31 passed**（含「存在、1024² RGBA、透明背景」檢查）。

### 裁決
純素材重做、幾何對齊既有 rest 幀、真 PNG、不碰程式與受保護模組、素材測試全綠；併入主線。**下一個可用 CR 編號：CR-0096。**

---

## CR-0096 — Manual Voice Stop Submit and Noise Suppression

### 模式
**觸及 🔒** `lib/services/realtime_voice_service.dart`，已先送 **architecture-agent 審查並核准**（agentId a81bffb4145fbd32f，medium risk）。修正「聆聽中按停止，剛說的話沒送出、寵物不回覆」：把按鈕從「取消並斷線」改成「停止收音並送出本輪語音」，並加上噪音抑制。詳見 `docs/MANUAL_VOICE_STOP_SUBMIT_CR0096.md`。

> 任務檔內文沿用舊草稿編號 CR-0095（已用於 mochi 素材），本任務正式編號 CR-0096。

### 根因
`home_screen.dart` 在聆聽中呼叫 `stopRealtimeConversation()` → `realtimeVoiceService.stop()` + `clearRealtimeTranscriptState()` + 回 idle，等於取消並斷線、清掉 transcript，故寵物不回覆。

### 變更
- 🔒 service：`getUserMedia` 加 `echoCancellation/noiseSuppression/autoGainControl` + try/catch 降級；新增 `commitUserAudioAndRespond()`（pauseMicInput → `input_audio_buffer.commit` → 僅 `!_hasActiveAssistantResponse` 才 `response.create`）；`error` 事件白名單過濾良性碼 `input_audio_buffer_commit_empty` / `conversation_already_has_active_response`（只 log、不打斷對話）。
- controller：新增 `stopListeningAndSubmit()`（有語音才 commit、進 thinking、掛 responseTimeout、不清 transcript、不斷線）+ 新 getter `isCapturingUserSpeech`（ready/listening/transcribing）。
- home_screen：聆聽/轉錄中按鈕改呼叫 `stopListeningAndSubmit()`（原 `stopRealtimeConversation` 語意保留）。
- 文案：listening/ready/transcribing 改「正在聽你說，說完再按一下」。

### architecture-agent 裁決摘要
- 方案 **(a) 強化版** 核准；(b) 關 server_vad、(c) 只 commit 不送 response.create 駁回。
- 放行條件（全數已落實）：error 良性碼過濾 + controller 端有語音才 commit + thinking 掛 responseTimeout + getUserMedia try/catch 降級 + 補測試。
- 不動 SDP/ICE/DataChannel；CR-0089/CR-0083 字幕不受影響；無 API 契約 / DB / Care Alert 變更。
- owner：realtime-voice-agent 主導 🔒；frontend-ux-agent 改 home_screen 呼叫點。

### 測試
`flutter analyze` No issues；`flutter test` **699 passed / 0 failed**（新增 6 筆：service commit/error 過濾、controller stop-and-submit 有/無語音、presentation 文案）。

### 裁決
觸及 🔒 但已走核准流程並滿足全部放行條件、不破壞既有 Realtime 主流程與字幕、測試齊備且全綠；併入主線。**尚未實機驗收**（需 iPhone 跑情境 1–5）。**下一個可用 CR 編號：CR-0097。**

---

## CR-0097 — Pet Asset 去背 Audit + Mochi Reprocess

### 模式
**純素材重做 + 檢查**（frontend-ux-agent 範圍，寵物動畫軌道）：檢查 5 隻寵物 rest/states/talk 去背狀況，修復去背吃掉本體白毛與使用者新放的白底 WebP。不改 enum/resolver/動畫程式，不擴大成重做素材系統，不碰 persona/Realtime/字幕/推播/Care Alert/後台/App icon。詳見 `docs/PET_ASSET_CLEANUP_CR0097.md`。

### 關鍵釐清
「rest 多出難過/睡覺狀態」非程式 bug：`restFrames` 永遠只解析 `_rest_01/02/03`，問題在 `*_rest_03.png` 檔案內容本身；使用者已替換新 rest pose 圖。

### 變更（只動素材檔）
- guinea_pig_rest_03：白底 WebP → 1024² RGBA 去背 PNG（fuzz 12% 四角）。
- mochi 16 張從使用者乾淨原圖重做（rest_01/02、7 states、listening、talk×6；talk 用聯集 bbox 維持對位）。
- fox/guinea_pig 5 張白底 WebP states 去背（fox_hungry/thirsty、guinea_pig_excited/hungry/sleepy）。
- fox_rest_03：使用者新圖已合格，原樣納入。

### 已知限制（缺原圖、待補）
- mochi_normal：無乾淨原圖，維持現狀（仍合格 PNG、測試可過）。
- ferret_sad / ferret_caring：無 ferret 原圖、損傷輕微，依使用者決定先不動僅記錄。

### 測試
`flutter test` **699 passed / 0 failed**（mochi/ferret/pet skin tests 全綠）；素材內容以洋紅底目視驗證無破洞。

### 裁決
純素材去背修復、幾何對齊既有慣例（feet 944 / 1024² RGBA）、ping-pong 一致、不碰程式與受保護模組、測試全綠；併入主線。**mochi_normal / ferret 缺原圖部分待使用者補圖。下一個可用 CR 編號：CR-0098。**

---

## CR-0096 — 移除雪貂 ferret + 投資/股票回覆固定免責聲明 + 全功能回歸

> 註：CR 編號沿用任務檔名 `tasks/CR-0096-...md`（早於 CR-0097 開立、晚於它落地），非時間順序倒掛，僅編號早於前一筆。

### 模式
**跨邊界小批次**（touches frontend-ux / companion-memory(persona) / backend）：雪貂展示前下架避免品質不穩素材曝光；投資相關回覆補法定免責聲明。經 architecture-agent 視角確認：未動 Realtime 主流程 SDP/ICE、未改 server.js API 契約形狀、未改 DB schema、未改依賴版本。

### Part 1 — 移除雪貂（Flutter only；後端 / caregiver_web 本就無 ferret）
- `lib/models/pet_skin.dart`：`PetSkin.ferret` 自 enum 與所有 switch（storageId/assetPrefix/label/tagline/unlockCost）移除。
- `fromStorageId`：移除 `'ferret'` 對應 → 舊存檔 `ferret` 自動 fallback 成 `dog`（不 crash、不顯示雪貂名、不抓缺檔）。
- `lib/utils/asset_paths.dart`：移除 ferret 的 talk/rest frame count 與註解。
- `lib/onboarding/coach_mark_keys.dart`：新手導覽換造型文案由「狗狗、狐狸、雪貂、麻吉」改為「狗狗、天竺鼠、狐狸、麻吉」。
- 換皮彈窗 / 商店 / 解鎖清單皆走 `PetSkin.values`，enum 移除後自動不再出現雪貂（無額外硬寫入口）。
- 資源：刪除 `assets/pets/{listening,states,rest,talk}/ferret_*.png` 共 18 張（採任務 1.3 選項 A，避免正式 build 打包）。
- 測試：刪 `test/models/ferret_skin_test.dart`；`mochi_skin_test.dart` / `pet_controller_skin_test.dart` 去除 ferret 參照並新增「雪貂已下架 + 舊存檔 ferret→dog 防呆」測試。

### Part 2 — 投資 / 股票免責聲明
- 新增 `backend/stt_proxy/services/compliance/investmentDisclaimer.js`（純函式）：`isInvestmentRelatedText` / `appendInvestmentDisclaimerIfNeeded`，中英文 + 代號關鍵字；空 / 非字串不 crash；已含同句不重複；只附加不覆蓋。
- `/api/companion/chat`（typed chat）：成功回覆後依「使用者輸入」判斷意圖，命中即於結尾附固定提醒。
- Realtime 語音 persona（`REALTIME_INSTRUCTIONS`）與 chat persona（`COMPANION_CHAT_PERSONA`）：加入【投資/股票免責】指示，要求投資相關回覆結尾「原句」附上提醒，台語模式亦以繁體中文原樣講出，不報明牌、不保證獲利。
- 固定句：`投資一定有風險，基金投資有賺有賠，申購前應詳閱公開說明書`。

### 測試（全綠）
- 後端 `npm test`：**604 passed / 0 failed**（含新增 investmentDisclaimer 9 例）。
- Flutter `flutter test`：**671 passed / 0 failed**；`flutter analyze`（變更檔）：No issues。
- caregiver_web `node --test *.test.js`：**101 passed / 0 failed**（管理者網頁 smoke）。

### 裁決
雪貂下架乾淨（程式 / 素材 / 入口 / 文案皆無殘留，僅保留 fallback 防呆與下架測試）；投資免責以「後端決定性附加」+「persona 指示」雙保險覆蓋 typed / Realtime / 台語；未碰受保護主流程與 API 契約；三端測試全綠。併入主線。**下一個可用 CR 編號：CR-0098。**

---

## CR-0096S — Store Blocking Issues Cleanup Batch 1

### 模式
**production / store readiness 小批次**（Flutter config + app wiring + 測試）。先清掉明確不適合正式上架的 Demo-only 行為：App 啟動時硬把 `PetController.freeAllSkins` 設為 `true`，導致所有寵物外觀在正式版也會預設解鎖。此批次不碰 Realtime 主流程、後端 API 契約、DB schema、Care Alert 資料結構、依賴或 `.env`。

### 變更
- `AppConfig` 新增 `FREE_ALL_PET_SKINS` 原始旗標與 `freeAllPetSkinsEnabled` 實際守門。
- `freeAllPetSkinsEnabled` 在 production 一律 false，避免正式上架版因 Demo 設定外洩而繞過寵物解鎖 / 養成流程。
- `PetCompanionApp` 建立 `PetController` 時改讀 `AppConfig.freeAllPetSkinsEnabled`，移除硬編 `freeAllSkins: true` 與 Demo-only 註解。

### 測試
- `flutter test test/config/app_config_test.dart test/controllers/pet_controller_skin_test.dart`：**27 passed / 0 failed**。
- `flutter test --dart-define=APP_ENV=production --dart-define=FREE_ALL_PET_SKINS=true test/config/app_config_test.dart`：**10 passed / 0 failed**，確認 production 即使誤開 `FREE_ALL_PET_SKINS=true` 也仍強制關閉。

### 裁決
此批次屬 Store Blocking cleanup 的第一個低風險落點：保留內部展示旗標，但正式版強制關閉 Demo 全寵物免費。下一批應繼續清查登入 / debug 文案 / placeholder / privacy URL / release signing / cleartext traffic 等 store blockers。

---

## CR-0096S — Store Blocking Issues Cleanup Batch 2

### 模式
**Android transport security 小批次**（Android manifest/resource + Flutter config test）。清掉 Play Store production 風險：主 manifest 原本 `android:usesCleartextTraffic="true"`，會讓 release 也全域允許明文 HTTP。此批次不碰 Flutter API base URL、Realtime 主流程、後端 API 契約、DB schema、依賴或 `.env`。

### 變更
- `android/app/src/main/AndroidManifest.xml`：移除 `android:usesCleartextTraffic="true"`，改掛 `android:networkSecurityConfig="@xml/network_security_config"`。
- `android/app/src/main/res/xml/network_security_config.xml`：release/main 預設 `cleartextTrafficPermitted="false"`，正式版只允許 HTTPS。
- `android/app/src/debug/res/xml/network_security_config.xml` 與 `android/app/src/profile/res/xml/network_security_config.xml`：保留 `cleartextTrafficPermitted="true"`，避免本機 / LAN 開發流程被打斷。
- 新增 `test/config/android_transport_security_test.dart` 鎖住 release 不可回到全域明文。

### 測試
- `dart format test/config/android_transport_security_test.dart`：完成格式化。
- `flutter test test/config/android_transport_security_test.dart test/config/app_config_test.dart`：**13 passed / 0 failed**。
- `flutter analyze`：No issues found。
- `flutter build apk --debug`：成功產出 `build/app/outputs/flutter-apk/app-debug.apk`（Gradle 有既有 Java 8 / deprecated API warnings，非此批次錯誤）。

### 裁決
此批次把 Android release cleartext blocker 收斂為 production 禁明文、debug/profile 可開發的正式產品化設定。iOS ATS、Android release signing、正式 privacy/support URL 仍屬後續 store blocker。

---

## CR-0096S — Store Blocking Issues Cleanup Batch 3

### 模式
**iOS ATS 小批次**（iOS `Info.plist` + Flutter config test）。清掉 App Store production 風險：`NSAllowsArbitraryLoads=true` 會全域允許明文 HTTP。此批次不碰 Realtime WebRTC 主流程、Flutter API base URL、後端 API 契約、DB schema、簽章、依賴或 `.env`。

### 變更
- `ios/Runner/Info.plist`：`NSAllowsArbitraryLoads` 由 `true` 改為 `false`。
- `ios/Runner/Info.plist`：新增 `NSAllowsLocalNetworking=true`，保留 dev / 實機同網段 HTTP 後端能力；正式公網 API 仍必須走 HTTPS。
- 新增 `test/config/ios_transport_security_test.dart` 鎖住 ATS 不可回到全域 arbitrary loads，並檢查 iOS 權限文案不含 demo/debug/test/mock 工程字樣。

### 測試
- `dart format test/config/ios_transport_security_test.dart`：完成格式化。
- `plutil -lint ios/Runner/Info.plist`：OK。
- `flutter test test/config/ios_transport_security_test.dart test/config/android_transport_security_test.dart test/config/app_config_test.dart`：**16 passed / 0 failed**。
- `flutter analyze`：No issues found。
- `flutter build ios --release --no-codesign`：成功產出 `build/ios/iphoneos/Runner.app`（75.2MB）。

### 裁決
此批次把 iOS 全域 ATS 明文 blocker 收斂為「正式對外 HTTPS + local networking dev 例外」。仍需 owner 以正式 HTTPS 後端與 iOS 實機跑 Realtime / REST smoke；Android release signing、正式 privacy/support URL、正式 icon 仍屬後續 store blocker。

---

## CR-0096S — Store Blocking Issues Cleanup Batch 4

### 模式
**release signing / legal config readiness 小批次**（Android Gradle + Flutter config + 測試）。清掉兩個會讓正式上架流程假成功的風險：Android release 永遠用 debug key、法務 / 支援連結需改 code 才能填真值。此批次不提交任何 keystore、secret、`.env`、正式 URL 或客服信箱。

### 變更
- `.gitignore`：加入 `android/key.properties`、keystore / provisioning / 憑證副檔名，避免正式簽章資料被提交。
- `android/app/build.gradle.kts`：新增 release signing config，讀取 `android/key.properties`；真正跑 release / appbundle 時若缺 `storeFile` / `storePassword` / `keyAlias` / `keyPassword` 會 fail-fast，不再用 debug key 假裝可上架。debug/profile build 不需 keystore。
- `LegalConfig`：privacy / terms / support URL 與 contact email 改為 `--dart-define` 注入，預設仍是 TODO placeholder；新增 `areStoreLegalLinksConfigured` 集中判斷。
- 新增 `test/config/android_release_signing_test.dart`、`test/config/legal_config_test.dart` 鎖住 release 不可回 debug signing、法務連結可被 placeholder gate 辨識。

### 測試
- `dart format test/config/android_release_signing_test.dart test/config/legal_config_test.dart`：完成格式化。
- `flutter test test/config/android_release_signing_test.dart test/config/legal_config_test.dart test/config/app_config_test.dart`：**14 passed / 0 failed**。
- `flutter test --dart-define=PRIVACY_POLICY_URL=https://example.com/privacy --dart-define=TERMS_OF_SERVICE_URL=https://example.com/terms --dart-define=SUPPORT_URL=https://example.com/support --dart-define=CONTACT_EMAIL=support@example.com test/config/legal_config_test.dart`：**2 passed / 0 failed**。
- `flutter analyze`：No issues found。
- `flutter build apk --debug`：成功產出 `build/app/outputs/flutter-apk/app-debug.apk`。
- `flutter build appbundle --release`（未提供 `android/key.properties`）：**預期失敗**，fail-fast 訊息列出缺 `storeFile` / `storePassword` / `keyAlias` / `keyPassword`；確認不再用 debug key 產出假 release。

### 裁決
此批次把 repo 端上架接線補齊：正式 Android 簽章改為外部 keystore / CI secret 驅動，法務連結改為 build define 驅動。仍需要 owner 提供真實 `android/key.properties` 對應值、正式隱私 / 條款 / 支援 URL、客服信箱與商店後台資料；不可用佔位值送審。

---

## CR-0097 — Data Tracking Foundation / Admin Analytics Real Data

### 模式
**Architecture-scope data foundation**（Flutter event tracking + backend usage event API / store + DB migration + caregiver analytics）。目的：讓管理者網頁能看到 App 真實操作數據，而不是只有形式上的分析頁；同時首頁朝 voice-first、長者低文字操作調整。此批次不讀取 / 修改 `.env`，不新增 secret，不把 Realtime 主流程改成 mock。

### 變更
- 新增 `app_usage_events` migration，事件由長者端 Bearer token 上報，後端以 `requireResidentCaller` 權威推導 `elder_id`。
- 新增 `AppUsageEventStore`：production 走 Postgres；非 production 才允許 JSON fallback；事件 metadata 只保留 primitive 並截斷，避免把完整逐字稿或敏感資料寫入 analytics。
- 新增 `POST /api/app-usage/events`，Invalid event type 回 400；production 無 DB / fallback 不可用回既有 not-enabled 形狀。
- caregiver analytics 聚合加入 `usageStats`，寵物狀態改由真實 `app_usage_events` 產生；後台前端新增「App 使用狀況」區塊與 usage metrics。
- Flutter 新增 `AppUsageTrackingService`，使用既有 Auth token；沒有 token / 網路失敗 / 後端錯誤都不阻塞長者操作。
- 已接入事件：`app_open`、`app_background`、`voice_interaction_start/end`、`typed_chat_sent`、`pet_interaction`、`reminder_created`、`daily_task_completed`、`photo_verification_submitted`、`puzzle_started/completed`。
- 首頁初步 voice-first：常駐打字框收合為鍵盤圖示，保留大麥克風、寵物與寵物狀態作為主要操作焦點。

### 測試
- `node --test backend/stt_proxy/db/migration017.test.js backend/stt_proxy/services/appUsageEventStore.test.js backend/stt_proxy/services/admin/caregiverAnalyticsService.test.js`：**16 passed / 0 failed**。
- `node --test caregiver_web/analytics_dashboard.test.js`：**8 passed / 0 failed**。
- `flutter test test/services/app_usage_tracking_service_test.dart`：**3 passed / 0 failed**。
- `npm run check`（`backend/stt_proxy`）：通過。
- `npm test`（`backend/stt_proxy`，升權重跑，因 endpoint tests 需 listen `127.0.0.1`）：**614 passed / 0 failed**。
- `flutter analyze`：No issues found。
- `flutter test`：**690 passed / 0 failed**（保留一則既有 widget-test hit-test warning，非 failure）。

### 裁決
管理者網頁已具備接收與呈現真實 App 使用數據的基礎，不再只依賴 Care Alert / 任務或 placeholder 文案。仍需後續補完整視覺化、正式隱私揭露（資料收集項目）、以及以 production HTTPS backend / 真帳號做端到端 smoke。

---

## CR-0101A — Store Submission Smoke Runbook / Store Readiness Test

### 模式
**store readiness 文件 + 自動檢查小批次**。把 App Store / Google Play 送審前 smoke 收斂為單一 Runbook，並讓 repo 可自動檢查目前能檢查的上架條件。此批次不碰 Realtime 主流程、後端 API 契約、DB schema、依賴、簽章檔、`.env` 或正式 secret。

### 變更
- 新增 `docs/STORE_SUBMISSION_RUNBOOK.md`：整合 owner 輸入、repo 自動檢查、iOS/Android release build、實機 App smoke、後端 / 管理者後台 smoke、商店素材 / hosted legal URL blocker、商店後台 smoke、Run 記錄模板與 Go/No-Go gate。
- 新增 `test/config/store_readiness_test.dart`：檢查 Runbook 必備段落、store checklist 串接、production gating、hosted legal URL gate、ATS / Android cleartext release 預設、icon 現況與 Android adaptive icon blocker 文件化、store metadata 不宣稱 production 隱藏功能。
- `docs/STORE_RELEASE_CHECKLIST.md`：補 `docs/STORE_SUBMISSION_RUNBOOK.md` 作為上架 smoke 單一入口，並記錄 store readiness test。
- `docs/PRODUCTION_CONFIG_CHECKLIST.md`：補 Runbook 連結，讓 build/env checklist 導向同一 smoke 流程。
- `docs/STORE_ASSET_CHECKLIST.md`：補 Runbook 對應素材落點，明確列 iOS icon、Android legacy/adaptive icon、launch screen 檔位。

### Owner blockers（不可假完成）
- 正式 hosted privacy / terms / support URL 與客服信箱。
- Android adaptive icon、正式 icon、screenshots、feature graphic、launch screen 確認。
- Android release keystore / iOS distribution signing。
- 真 production HTTPS backend、Firebase、PostgreSQL migration、OpenAI Realtime、Telegram 與管理者 analytics smoke。

### 測試
- `dart format test/config/store_readiness_test.dart`：完成格式化（0 changed）。
- `flutter test test/config/store_readiness_test.dart test/config/legal_config_test.dart test/config/app_config_test.dart`：**21 passed / 0 failed**。
- `flutter test --dart-define=APP_ENV=production --dart-define=API_BASE_URL=https://api.example.com --dart-define=SHOW_DEMO_LOGIN=true --dart-define=SHOW_SOCIAL_SIGN_IN=true --dart-define=SHOW_MARKETPLACE=true --dart-define=SHOW_DAILY_CARE_TASKS=true test/config/app_config_test.dart test/config/legal_config_test.dart test/config/store_readiness_test.dart`：**21 passed / 0 failed**，確認 production 即使誤開 store-facing debug flags 仍強制關閉。
- `flutter analyze`：No issues found。
- `flutter test`：**700 passed / 0 failed**（保留一則既有 widget-test hit-test warning，非 failure）。

### 裁決
此批次讓上架 smoke 從「分散 checklist」變成可執行的單一 Runbook；repo 自動測試只能檢查程式與文件紅線，不能替代 owner 提供正式素材、URL、簽章與真環境實機 smoke。

---

## CR-0101A — Formal App Icon Output

### 模式
**store asset 小批次**。依 owner 指定的「老奶奶擁抱 AI 寵物、整體呈現愛心 / 陪伴感」方向，輸出正式候選 App icon 到 iOS / Android / Play listing 檔位。此批次不碰 Flutter 功能邏輯、後端 API、Realtime、DB schema、簽章或 `.env`。

### 變更
- iOS `AppIcon.appiconset` 全尺寸 icon 重新輸出，包含 App Store 1024×1024。
- Android legacy launcher icon 重新輸出：`mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png`。
- Android adaptive icon 補齊：
  - `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`
  - `android/app/src/main/res/mipmap-*/ic_launcher_foreground.png`
  - `android/app/src/main/res/values/colors.xml` 的 `ic_launcher_background`
- Play Console listing icon 補：`store_assets/play_store_icon_512.png`。
- `docs/STORE_ASSET_CHECKLIST.md` / `docs/STORE_RELEASE_CHECKLIST.md` 更新：icon / adaptive icon blocker 改為已輸出，screenshots、feature graphic、launch screen、hosted legal URL、簽章仍是 blocker。
- `test/config/store_readiness_test.dart` 強化：檢查 adaptive icon XML、foreground PNG、iOS 1024 PNG 尺寸、Play listing 512 PNG 尺寸。

### 測試
- `flutter test test/config/store_readiness_test.dart test/config/android_transport_security_test.dart test/config/ios_transport_security_test.dart`：**14 passed / 0 failed**。
- `flutter analyze`：No issues found。

### 裁決
正式候選 icon assets 已進 repo，可供 App Store / Google Play 預覽與實機檢查。仍需人工確認 Android launcher mask 裁切效果、launch screen、screenshots / feature graphic 與 hosted legal URL。

---

## CR-0101A — Hosted Legal Static Site Draft

### 模式
**store legal / support 靜態頁小批次**。依 owner 指示採純靜態網頁作為 App Store / Google Play 的隱私權政策、服務條款與支援頁來源。此批次不部署、不讀寫 `.env`、不填假網域；客服信箱由 owner 提供為 `aicompanion.support@gmail.com`。

### 變更
- 新增 `store_legal_site/`：
  - `index.html`
  - `privacy.html`
  - `terms.html`
  - `support.html`
  - `styles.css`
  - `assets/icon-512.png`
  - `README.md`
- 新增 `.github/workflows/legal-site-pages.yml`：push 到 `main` 或手動觸發時，把 `store_legal_site/` 部署到 GitHub Pages。部署不需要 `.env` 或 secret。
- 靜態頁內容對齊 App 內 legal 文案與 CR-0097 usage tracking disclosure，包含使用紀錄、OpenAI 第三方 AI、Care Alert 非醫療診斷、資料刪除與支援說明。
- 正式客服信箱已寫入 static legal site：`aicompanion.support@gmail.com`；App build / 商店後台需用同一值。
- `docs/STORE_RELEASE_CHECKLIST.md`、`docs/PRODUCTION_CONFIG_CHECKLIST.md`、`docs/APP_STORE_METADATA.md`、`docs/STORE_SUBMISSION_RUNBOOK.md` 更新：legal static site 草稿已存在；GitHub Pages 預期 URL 已文件化；客服信箱已定值；仍需 owner 在 GitHub repo Settings 啟用 Pages / GitHub Actions 並確認部署 URL 可開。
- `test/config/store_readiness_test.dart` 補檢查：靜態頁存在、icon 512×512、privacy/terms/support 必要內容存在、GitHub Pages workflow 存在且只部署 `store_legal_site/`，且正式客服 mailto 存在、不再顯示「上架前必填」客服信箱 blocker。

### 測試
- `dart format test/config/store_readiness_test.dart`：完成格式化（0 changed）。
- `flutter test test/config/store_readiness_test.dart test/config/legal_config_test.dart`：**11 passed / 0 failed**。
- `flutter analyze`：No issues found。

### 裁決
Legal/support 靜態頁已可透過 GitHub Pages Actions 部署，客服信箱 blocker 已解除。真正解除 hosted legal URL blocker 仍需要 owner 在 GitHub repo Settings 將 Pages Source 設成 GitHub Actions、確認 workflow 成功與三個 URL 可公開開啟，部署後再把 `PRIVACY_POLICY_URL` / `TERMS_OF_SERVICE_URL` / `SUPPORT_URL` / `CONTACT_EMAIL` 帶入 production build。

---

## CR-0101B — Google Play Feature Graphic Output

### 模式
**store asset 小批次**。從最簡單可離線處理的商店素材開始，先輸出 Google Play 1024×500 feature graphic。此批次不碰 release signing、`.env`、backend、Realtime 或 Flutter 功能行為。

### 變更
- 新增 `store_assets/play_feature_graphic_1024x500.png`（1024×500）：使用正式 icon、AI陪伴品牌字樣與非醫療陪伴文案。
- `docs/STORE_ASSET_CHECKLIST.md`：feature graphic 狀態改為已輸出；screenshots 仍待處理。
- `docs/STORE_RELEASE_CHECKLIST.md`：視覺素材狀態更新為 icon + feature graphic 已輸出，仍待 launch screen 確認與 screenshots。
- `test/config/store_readiness_test.dart`：新增 feature graphic 存在與 1024×500 PNG 尺寸檢查。

### 測試
- `dart format test/config/store_readiness_test.dart`：完成格式化（0 changed）。
- `flutter test test/config/store_readiness_test.dart`：**9 passed / 0 failed**。
- `flutter analyze`：No issues found。

### 裁決
Google Play feature graphic blocker 已可視為解除。下一個簡單項目可處理 screenshots 規劃/輸出；release signing 需要 owner 提供 Apple Developer / Play Console / keystore 流程，不能用假簽章替代。

---

## CR-0101B — Store Screenshot Output

### 模式
**store asset 小批次**。補齊 App Store / Google Play 送審候選 screenshots，先採去識別化靜態商店素材，不依賴真使用者資料、真照護紀錄、demo account 或本機後端。此批次不碰 Realtime、backend、DB schema、release signing、`.env` 或正式 secret。

### 變更
- 新增 `scripts/generate_store_screenshots.sh`：用既有正式候選 icon 產出去識別化商店截圖。
- 新增 Android phone screenshots：`store_assets/screenshots/android_phone/*.png`（5 張，1080×1920）。
- 新增 iPhone 6.7" screenshots：`store_assets/screenshots/ios_6_7/*.png`（5 張，1290×2796）。
- 截圖主題包含首頁語音入口、即時語音陪伴、長期記憶、Care Alert 非醫療診斷、隱私/支援/帳號刪除。
- `docs/STORE_ASSET_CHECKLIST.md`、`docs/STORE_RELEASE_CHECKLIST.md`、`docs/APP_STORE_METADATA.md` 更新：screenshots 與 hosted legal URL 狀態對齊目前可上架素材。
- `test/config/store_readiness_test.dart` 強化：檢查 screenshots 存在、PNG 尺寸正確，並確認產圖腳本未帶 `debug` / `demo` / `mock` 字樣且含非醫療診斷聲明。

### 測試
- `bash scripts/generate_store_screenshots.sh`：成功產出 10 張 PNG。
- `sips -g pixelWidth -g pixelHeight ...`：Android phone 5 張皆 1080×1920；iPhone 6.7" 5 張皆 1290×2796。
- `dart format test/config/store_readiness_test.dart`：完成格式化（0 changed）。
- `flutter test test/config/store_readiness_test.dart`：**9 passed / 0 failed**。
- `flutter analyze`：No issues found。

### 裁決
Screenshots 素材 blocker 可視為 repo 端解除；送審前仍需在 App Store Connect / Play Console 人工預覽裁切與可讀性。實機截圖目前因 iPhone 顯示 unpaired，需 owner 於 Xcode Devices 完成配對後再做真機補拍或確認。

---

## CR-0101B — Launch Screen Branding Output

### 模式
**store asset / launch readiness 小批次**。將 iOS / Android 啟動畫面從 Flutter 模板空白畫面收斂為正式品牌 icon + 溫暖底色。此批次不碰 Flutter runtime UI、Realtime、backend、DB schema、release signing、`.env` 或正式 secret。

### 變更
- iOS `LaunchImage.imageset` 由 1×1 空圖替換為正式候選 icon 圖資：
  - `LaunchImage.png`（168×168）
  - `LaunchImage@2x.png`（336×336）
  - `LaunchImage@3x.png`（504×504）
- Android 新增 `android/app/src/main/res/drawable-nodpi/launch_brand.png`（240×240）。
- Android `drawable/launch_background.xml` 與 `drawable-v21/launch_background.xml` 改為 `@color/launch_background` 底色 + `@drawable/launch_brand` 置中，不再保留 Flutter 模板白底空畫面。
- Android `values/colors.xml` 新增 `launch_background=#FFF8EA`。
- `docs/STORE_ASSET_CHECKLIST.md` / `docs/STORE_RELEASE_CHECKLIST.md` 更新 launch screen 狀態。
- `test/config/store_readiness_test.dart` 新增 launch screen / display name production branding 檢查。

### 測試
- `sips -g pixelWidth -g pixelHeight ...`：iOS launch images 為 168×168 / 336×336 / 504×504；Android launch brand 為 240×240。
- `dart format test/config/store_readiness_test.dart`：完成格式化。
- `flutter test test/config/store_readiness_test.dart`：**10 passed / 0 failed**。
- `flutter analyze`：No issues found。
- `git diff --check`：通過。

### 裁決
Launch screen repo 端 blocker 可視為解除；送審前仍需於 iOS / Android 實機確認啟動過場不閃白、不裁切、不出現舊圖。

---

## CR-0101B — Release Signing Runbook Executable Check

### 模式
**release signing 文件 / 自動檢查小批次**。把 Android upload keystore、iOS distribution signing、CI secret 命名與 No-Go 條件整理成可執行 runbook，並新增不讀 secret 內容的 readiness script。此批次不產生、不讀取、不提交任何 keystore、`android/key.properties`、Apple 憑證、`.p8`、`.mobileprovision`、`.env` 或正式 secret。

### 變更
- 新增 `scripts/check_release_signing_readiness.sh`：
  - 檢查 `android/key.properties` 是否被 gitignore。
  - 檢查 `.jks` / `.keystore` / `.p12` / `.p8` / `.cer` / `.mobileprovision` 未被 git 追蹤。
  - 檢查 Android release signing wiring 不是 debug signing，缺 key 時會 fail-fast。
  - 檢查 iOS Bundle ID / signing metadata 存在。
  - 若本機有 `android/key.properties`，只顯示存在，**不讀內容**。
- `docs/RELEASE_SIGNING.md`：升級成 iOS / Android 正式簽章 Runbook，包含 Android upload keystore、本機 `key.properties`、Play App Signing、iOS App Store Connect / Xcode Archive、CI secret 建議命名與 No-Go 條件。
- `docs/STORE_SUBMISSION_RUNBOOK.md`：加入 `bash scripts/check_release_signing_readiness.sh`，並把已完成的 hosted legal URL / store assets / launch screen 狀態對齊。
- `test/config/android_release_signing_test.dart`：新增 runbook / script regression checks，確保腳本不讀取 `android/key.properties` 內容、不含密碼範例值、且文件包含 release build 與 secret 邊界。

### 測試
- `bash scripts/check_release_signing_readiness.sh`：通過；提示本機尚無 `android/key.properties`，Android release build 會 fail-fast，符合預期。
- `dart format test/config/android_release_signing_test.dart`：完成格式化。
- `flutter test test/config/android_release_signing_test.dart test/config/store_readiness_test.dart`：**13 passed / 0 failed**。
- `flutter build appbundle --release ...`（未提供 `android/key.properties`）：**預期失敗**，fail-fast 訊息列出缺 `storeFile` / `storePassword` / `keyAlias` / `keyPassword`；確認不會用 debug key 產出假 release。
- `flutter analyze`：No issues found。
- `git diff --check`：通過。

### 裁決
Release signing 的 repo 端文件與自動檢查已可執行；真正送審仍需要 owner 完成 Android upload keystore / Play App Signing，以及 iOS Apple Developer / App Store Connect distribution signing。此批次沒有也不應該解除 owner signing blocker。

---

## CR-0101B — Internal Testing Smoke Runbook

### 模式
**TestFlight / Play Internal testing smoke 文件 + 自動檢查小批次**。把內測上架後必跑項目整理成單一 runbook，特別鎖住真機 Realtime、Care Alert、usage tracking、管理者 analytics、法律/支援入口、帳號刪除、Store Console 隱私申報與去敏紅線。此批次不讀 `.env`、不跑真服務、不產生簽章、不提交 secret。

### 變更
- 新增 `docs/INTERNAL_TESTING_SMOKE_RUNBOOK.md`：
  - Owner 需提供清單：production HTTPS API、Firebase 測試帳號、後端 env、Android upload keystore、Apple Developer / App Store Connect signing、iPhone pairing、Android 實機。
  - Repo gate：Flutter / backend / caregiver_web 測試、store readiness、release signing readiness。
  - iOS TestFlight 與 Google Play Internal testing build 指令。
  - 真機 App Smoke：安裝、首開、隱私同意、Email login、首頁易用性、Realtime 語音、打字聊天、後端失敗、法律/支援入口、帳號刪除。
  - Data / Admin Smoke：`app_usage_events`、voice start/end、typed chat、pet interaction、reminder、puzzle、管理者 analytics 真實彙整。
  - Care Alert Smoke：medium 持久化不推 Telegram；high/urgent 持久化並推測試 chat；長者端不顯示監控感。
  - Store Console Smoke：App Privacy / Data Safety / metadata / screenshots / legal URL 一致性。
- `docs/STORE_SUBMISSION_RUNBOOK.md`：連到 internal testing runbook，將 §4 定位為摘要。
- `test/config/store_readiness_test.dart`：新增 internal testing runbook regression checks，確保文件涵蓋 Realtime、Care Alert、usage tracking、管理者 analytics、帳號刪除、Data Safety、非醫療診斷、No-Go，且不建議 localhost / 127.0.0.1 / 10.0.2.2 / ngrok。

### 測試
- `dart format test/config/store_readiness_test.dart`：完成格式化。
- `flutter test test/config/store_readiness_test.dart`：**11 passed / 0 failed**。
- `flutter analyze`：No issues found。
- `git diff --check`：通過。

### 裁決
內測 smoke 現在有獨立可執行 Runbook；真正 PASS 仍需 owner 提供 production HTTPS API、測試帳號、簽章、TestFlight / Play Internal testing build 與真機執行結果。未跑前不得把 smoke 標示為通過。

---

## CR-0101B — Final Store Blocker Board

### 模式
**最後上架 Go / No-Go 文件 + 自動檢查小批次**。把剩餘上架事項收斂成單一 blocker board，區分 repo 已完成、owner 必須提供、必須真機驗證、商店後台必填與 No-Go 條件。此批次不讀 `.env`、不碰 signing secret、不跑真服務、不假裝真機 smoke 通過。

### 變更
- 新增 `docs/FINAL_STORE_BLOCKER_BOARD.md`：
  - 明列 repo 已完成：正式名稱、Bundle ID/applicationId、icon、screenshots、feature graphic、launch screen、GitHub Pages legal URL、support email、production gating、store readiness test、release signing readiness script、internal testing smoke runbook。
  - 明列 owner 必須提供：production HTTPS API、後端 env、production migrations、Firebase 測試帳號、Android upload keystore、iOS signing、iPhone pairing、Android 實機。
  - 明列必須真機驗證：TestFlight / Play Internal testing、Realtime、Care Alert、`app_usage_events`、caregiver_web analytics、法律/支援入口、帳號刪除。
  - 明列商店後台必填：App Store Privacy、Google Play Data Safety、metadata、screenshots preview、Play App Signing。
  - 明列最後執行順序與 No-Go 條件。
- `docs/STORE_SUBMISSION_RUNBOOK.md`、`docs/STORE_RELEASE_CHECKLIST.md`、`docs/PRODUCTION_CONFIG_CHECKLIST.md`：加入 final blocker board 入口。
- `docs/PRODUCTION_CONFIG_CHECKLIST.md`：把已部署 legal URL、正式 support email、icon / launch / 權限文案狀態對齊目前完成狀態。
- `docs/GOOGLE_PLAY_DATA_SAFETY.md`：把 hosted privacy URL 與資料刪除 / Care Alert 非醫療 / 權限用途同步狀態改為已完成。
- `test/config/store_readiness_test.dart`：新增 final blocker board regression checks，確保文件保留 owner-gated / device smoke / store console / Data Safety / Realtime / Care Alert / usage analytics / No-Go 關鍵項。

### 測試
- `dart format test/config/store_readiness_test.dart`：完成格式化（0 changed）。
- `flutter test test/config/store_readiness_test.dart`：**12 passed / 0 failed**。
- `flutter analyze`：No issues found。
- `git diff --check`：通過。

### 裁決
最後上架 blocker 已集中到 `docs/FINAL_STORE_BLOCKER_BOARD.md`。repo 能補的 store readiness 文件、素材與自動檢查已收斂；剩餘不可假完成的項目是 production HTTPS API、正式簽章、production env、測試帳號、真機 smoke 與商店後台隱私/資料安全表單。

---

## CR-0101B — Store Review Notes Template

### 模式
**商店審查備註 / App access template 小批次**。補齊 App Store Connect Review notes、Google Play App access instructions、Data Safety / App Privacy owner checklist 與審查帳號建立規則。此批次不放真帳號、不放密碼、不讀 `.env`、不接觸任何 secret。

### 變更
- 新增 `docs/STORE_REVIEW_NOTES_TEMPLATE.md`：
  - App Store Connect Review notes 可貼模板。
  - Google Play app access instructions 可貼模板。
  - Data Safety / App Privacy owner checklist。
  - 審查帳號建立規則：resident / caregiver / super_admin 分離，真帳密只填商店後台受保護欄位，不寫入 repo。
  - No-Go 條件：review notes 缺登入路徑、legal URL 不可開、Care Alert 寫成醫療診斷、審查帳號或後端 URL 寫入 repo 等。
- `docs/APP_STORE_METADATA.md`：Review notes / 測試帳號策略從「待定」改為模板已備妥，owner 仍需於商店後台填真帳號與正式 `API_BASE_URL`。
- `docs/FINAL_STORE_BLOCKER_BOARD.md`、`docs/STORE_SUBMISSION_RUNBOOK.md`、`docs/INTERNAL_TESTING_SMOKE_RUNBOOK.md`：加入 review notes template 入口。
- `test/config/store_readiness_test.dart`：新增 template regression checks，確保包含麥克風用途、Realtime、Care Alert 非醫療、Email login/register、帳號刪除、Data Safety / App Privacy、legal URL、support email，且不含常見 secret pattern。

### 測試
- `dart format test/config/store_readiness_test.dart`：完成格式化（0 changed）。
- `flutter test test/config/store_readiness_test.dart`：**13 passed / 0 failed**。
- `flutter analyze`：No issues found。
- `git diff --check`：通過。

### 裁決
商店審查文案 repo 端已可貼用；真正送審前仍需 owner 在 App Store Connect / Play Console 的受保護欄位填入審查專用帳號與正式 production HTTPS API 資訊，不能寫入 repo。
