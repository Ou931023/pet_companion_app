# CR-0089 — Voice Caption Synchronization Polish

修正「寵物正在播放上一句語音，字幕卻已切到 / 清掉下一句」的問題，讓字幕、talk 動畫、實際播放語音三者一致。

---

## 1. 問題原因盤點

盤點後確認根因：**收 turn 的時機綁在 `response.done`（生成結束），而不是語音真正播完**。

- `realtime_voice_service.dart` 在 `response.done` 同時送出 `assistantAudioEnd`，但**語音可能還在播**（註解原本就寫明這點）。
- `VoiceAgentController` 收到 `assistantResponseDone` / `assistantAudioEnd` 就 `_finishPetTurn` → 把寵物從 `speaking` 收回 `idle`，talk 動畫停、字幕可被下一段內容接手。
- 真正「語音播完」的事件 `output_audio_buffer.stopped` 原本**只在 service 內部處理**（CR-0083 用它送排隊的工具念稿），**沒有對外發出**，所以 controller 看不到「語音真的停了」這個時間點。

結果：`response.done` 一到，talk / 字幕就提前收掉，與還在播的語音對不上。

---

## 2. 字幕來源與語音來源

### 字幕（caption）來源（皆經 `ConversationController`）
| 類型 | 欄位 | 來源事件 |
|---|---|---|
| 寵物即時字幕 | `liveRealtimeReply`（`isRealtimeStreaming`） | `assistantPartialText`（逐字 delta） |
| 寵物最終字幕 | `latestReply` | `assistantText`（response.done 的最終文字） |
| 寵物 filler / 狀態 | `latestReply` | `showPetBubbleMessage`（連線 / 逾時 / 重連 / 錯誤） |
| 工具念稿 | 同上（走同一條 assistant 文字路徑） | CR-0083 排隊後送出的額外 response |
| 使用者即時字幕 | `temporaryUserBubbleText` | ASR partial |
| 使用者最終字幕 | `latestUserText` | ASR final |

首頁 `_resolvePetText` 以 `liveRealtimeReply > latestReply > (使用者說話中→空) > 寵物預設訊息` 取一條顯示；寵物字幕優先於使用者字幕。

### 語音播放事件來源（`realtime_voice_service.dart` → events stream）
- `assistantAudioStart`：第一筆 delta（**含純文字回覆**）→ 進 speaking。
- `assistantAudioEnd`：`response.done` 時發出（**生成結束，語音可能還在播**）。
- **（本 CR 新增）** `assistantAudioPlaybackStarted`：**真實語音** buffer 開始（一輪一次）。
- **（本 CR 新增）** `assistantAudioPlaybackStopped`：`output_audio_buffer.stopped`，**語音真的播完**。

---

## 3. caption owner / turn 規則（沿用既有，未重建）

本 CR 不新增獨立 caption model，而是沿用既有歸屬機制 + 新的播放邊界訊號：

- **使用者 vs 寵物**：分屬不同欄位（user → `temporaryUserBubbleText` / `latestUserText`；pet → `liveRealtimeReply` / `latestReply`），`_resolvePetText` 寵物優先。**寵物 talk 期間麥克風關閉**（turn-based），使用者無法插話，故 user partial 不會蓋掉 pet caption。
- **turn id 守門**：`assistantResponseDone` 既有 `_isActiveTurn(_responseTurnId)` 過期守門保留 → 過期 turn 的結束事件不收掉新 turn。
- **播放邊界**：以 `assistantAudioPlaybackStarted` / `assistantAudioPlaybackStopped` 界定「這一段語音的字幕生命週期」——語音開始才算有語音、語音真的停才收 turn。

---

## 4. 修正內容

### 🔒 `lib/services/realtime_voice_service.dart`（經 architecture-agent 審查核准，見 CHANGE_REVIEW CR-0089）
**純加法**，未動 SDP / ICE / DataChannel / connect / response 生命週期：
1. 新增 enum `assistantAudioPlaybackStarted`：在既有 `output_audio_buffer.started` / `response.output_audio.delta` / `response.audio.delta` 分支，守 `!_sawOutputAudioBufferThisResponse` 一輪發一次（**真實語音**才發；純文字不發；文字先於語音的混合回覆也正確發一次）。
2. 新增 enum `assistantAudioPlaybackStopped`：在既有 `output_audio_buffer.stopped` 分支、`_flushPendingToolOutcome()` **之後**發出（保留 CR-0083 工具念稿 flush 順序）。
3. `response.done` 仍照常發 `assistantAudioEnd`（未移除）。

### `lib/controllers/voice_agent_controller.dart`
- 新增 `_currentTurnHadAudio`（只在 `assistantAudioPlaybackStarted` 設 true，每輪 `assistantResponseStart` 重置）、`_awaitingAudioStop`、`_audioStopFallbackTimer`。
- `assistantResponseDone` / `assistantAudioEnd`（皆在 response.done）改走 `_requestFinishPetTurn`：
  - **本輪有真實語音** → 不立即收 turn，**保留 speaking + 字幕**，並暫停麥克風（語音尾段不被插話蓋字幕），等 `assistantAudioPlaybackStopped` 才收。
  - **純文字回覆** → 沿用舊行為，response.done 立即收 idle（不卡等）。
- 新增 `assistantAudioPlaybackStopped` 分支：語音真的播完 → `_finishPetTurn`（對兩條結束路徑幂等）。
- 安全保底：`_audioStopFallback`（15s）—— 若 `output_audio_buffer.stopped` 罕見漏訊號，仍把 turn 收掉，避免永遠卡 speaking（非「用秒數猜音長」，是漏訊號上限）。

### 效果對應驗收標準
- 寵物正在說哪一句，字幕就顯示哪一句：talk / 字幕保留到語音真的播完。
- response.done 不會讓字幕提前清除 / 切換：收 turn 延後到 playback-stopped。
- filler / tool outcome / AI response 不互相提前覆蓋：CR-0083 工具念稿延到 playback-stopped 送出 + 本 CR 的 talk 保留。
- 使用者字幕不在寵物播放中覆蓋寵物字幕：寵物 turn 期間麥克風關閉。
- 寵物 talk 狀態與正在播放的語音一致：speaking 與字幕同步收於 playback-stopped。

---

## 5. 測試結果
- **service**（`realtime_voice_service_test.dart`）：`output_audio_buffer.stopped` 發出且僅一次 `assistantAudioPlaybackStopped`；`response.done` 仍發 `assistantAudioEnd`；pending tool outcome 時 flush 先於 playback-stopped（順序回歸）；`assistantAudioPlaybackStarted` 在 audio-only=1 / text-only=0 / text-then-audio=1。
- **controller**（`voice_agent_controller_realtime_lifecycle_test.dart`）：有語音時 response.done 仍 speaking + 字幕保留、playback-stopped 才 idle；純文字 response.done 立即 idle；既有「冪等收斂 idle」「下一句不重連」等改寫為新時序。
- **integration**（`agent_voice_turn_integration_test.dart`）：同步更新為 playback-stopped 才 idle。
- 結果：`flutter analyze` **No issues**；`flutter test` **672 passed / 0 failed**（連續兩次穩定）。

---

## 6. 已知限制
- **依賴 `output_audio_buffer.stopped`**：此事件由 OpenAI Realtime 在語音播完時送出（CR-0083 已依賴）。極少數漏訊號情境由 15s 保底計時器收尾（談話回覆通常數秒，保底幾乎不會觸發）。
- **純文字 Realtime 回覆**：無語音 buffer → 沿用 response.done 立即收（無法、也不需要等播完）。
- **過期 playback-stopped**：`assistantAudioPlaybackStopped` 未帶 turn id（事件 payload 僅字串）；目前以「對應當前語音段」處理，跨輪錯置為極端邊界，未額外加 turn 標記（沿用既有 turn 守門，避免擴大 🔒 改動）。
- **未動範圍**：AI persona / 對話自然度（CR-0090）、寵物素材（CR-0088）、推播（CR-0087）、Care Alert / Telegram / 後台分析頁、後端 / DB。
- 字幕分頁節奏（`PetSubtitleText`，CR-0080/0084）未變更，本 CR 只處理「字幕該屬於哪一段語音、何時可切換」。
