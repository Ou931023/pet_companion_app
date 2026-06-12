# CR-0083：Realtime 工具呼叫盤點 + 工具字幕回合完整性

> 任務檔 `tasks/CR-0083-...md` 為空檔；範圍依指示界定為兩件事：
> （1）盤點 Realtime 是否有「真正的 tool calling」；
> （2）最小修正「工具結果蓋掉語音字幕」的問題。
> 不做假搜尋、不硬編即時資訊、不加 secrets、不改 Realtime 主流程的狀態機。

---

## 1. 盤點結果：Realtime 沒有原生 tool calling

**結論：目前 OpenAI Realtime session 沒有掛任何 tools，工具是「前端關鍵字攔截 + 補一句語音」的 client-side 補償機制。**

證據：

- `backend/stt_proxy/server.js`（`/api/realtime/call`，約 line 2772）送給 OpenAI
  `/v1/realtime/calls` 的 `sessionConfig` 只有 `type` / `model` / `audio`（input 轉錄 +
  `server_vad`、output voice）/ `instructions`，**沒有 `tools` 或 `tool_choice` 欄位**。
  → 模型不會真的 function call；`server_vad` 的 `create_response: true` 讓模型對每句使用者
  發話都自動產生一則回覆。
- 工具實際上是在 **Flutter 端** 補的：
  `voice_agent_controller._routeToolsForTranscript()` →
  - 本地指令（簽到 / 設定 / 找新聞 / 查資訊…）：`AiToolRouter.route()`；或
  - 後端 agent（播音樂 / 打電話…）：`agentToolController.routeFromUserText()` → `/api/agent/route`。
  - 執行完再用 `realtimeVoiceService.speakToolOutcome()` 送一則一次性 `response.create`，
    把結果當 `instructions` 讓寵物用語音念出來。
- 後端雖有 `/api/agent/tools`、`/api/agent/route`（`tool_intent_builder`），但**沒有**被當成
  OpenAI Realtime 的 tools 注入 session，是另一套 client 驅動的 router。

**影響**：因為模型本身無法呼叫工具，「即時查詢」完全依賴前端關鍵字命中（CR-0080 已擴充過
關鍵字）。本 CR 不改這個架構（屬於較大的架構決策），僅修字幕回合問題；後續若要做真正的
Realtime function calling，需另開 CR 並經 architecture-agent 規劃（會動到 `sessionConfig` 與
`realtime_voice_service.dart` 主流程）。

---

## 2. 問題根因：工具結果在語音播完前就蓋掉字幕

語音模式下使用者問「幫我查天氣」時：

1. `server_vad` 自動讓模型先回 filler（response 1，例如「好的，幫你查」）。
   它的文字在 `response.done` 以 `assistantText` 送出 → `setMessage`（設字幕），語音開始播。
2. 真正的工具結果在 response 1 還 active 時送達 → 被排進 `_pendingToolOutcomeLine`。
3. **舊行為**：在 `response.done` handler 立刻把排隊的工具念稿送出（response 2），
   其 `assistantText` → `setMessage` 把字幕換成查詢結果。
4. **Bug**：`response.done` 只代表「生成結束」，**不是語音播完**。
   `output_audio_buffer.stopped`（真正的播放結束）原本**完全沒有處理**（只處理 `.started`）。
   所以 response 2 的字幕會在 response 1 的語音還在播時就把字幕蓋掉
   → 「第一句還沒念完，字幕就跳到查詢結果」。

---

## 3. 最小修正（只動 `lib/services/realtime_voice_service.dart`）

把「排隊工具念稿的送出時機」從 `response.done` 移到 **語音真的播完**：

- 新增 `_sawOutputAudioBufferThisResponse`：在 `output_audio_buffer.started` /
  `response.output_audio.delta` / `response.audio.delta` 設為 true；`response.created` 時重置。
- 新增 `output_audio_buffer.stopped` 處理：若有排隊念稿 → 此時才送出（`_flushPendingToolOutcome`）。
- `response.done`：
  - 若這輪**有**語音 buffer 事件 → 不立刻送，改為等 `.stopped`（並啟動保底計時器）。
  - 若這輪**沒有**語音 buffer（純文字回覆）→ 沿用舊行為，立刻送（fallback 不漏「後續」）。
- 保底計時器 `toolOutcomeFlushFallback`（預設 4 秒）：萬一 `.stopped` 沒到也會送出念稿，
  確保不會永遠卡住而「沒有後續」。任何一次 flush、`stop()`、重連、`dispose` 都會取消計時器。

**刻意不動**：`assistantText` / `assistantAudioEnd` 的發出時機、`_finishPetTurn`、turn-based
狀態機（這些是承重邏輯）。`output_audio_buffer.stopped` 分支只負責 flush 念稿，不發任何
state / audio 事件。

---

## 4. 測試與驗收

`test/realtime_voice_service_test.dart` 新增 3 個測試：

1. 語音 session 中排隊的工具念稿在 `output_audio_buffer.stopped` 才送、`response.done` 不送。
2. 純文字 session（無 audio buffer 事件）仍在 `response.done` flush（fallback 保留）。
3. `.stopped` 一直沒到時，保底計時器仍會送出念稿。

結果：

- `flutter test test/realtime_voice_service_test.dart test/realtime_turn_coordinator_test.dart test/realtime_timeout_test.dart` → 32 passed。
- 全套 `flutter test` → **563 passed, 0 failed**。
- `flutter analyze`（變更檔）→ No issues found。

### 建議實機驗收

1. 語音問「今天嘉義天氣如何？」→ 寵物先說 filler、**filler 語音念完後**字幕才換成查詢結果，
   兩句語音不重疊、字幕不提前翻。
2. 觀察 log 是否常出現「output_audio_buffer.stopped not received in time」；若頻繁，
   再評估 4 秒保底是否需調整。

---

## 5. 沒有改動（刻意）

- Realtime `sessionConfig`（不在本 CR 加 native tools）、SDP / WebRTC 主流程。
- Auth、Care Alert、Marketplace、Daily Care Tasks。
- 任何 `.env` / secret。
