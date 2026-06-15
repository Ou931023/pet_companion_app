# CR-0096 — Manual Voice Stop Submit and Noise Suppression

> 任務檔 `tasks/CR-0096-manual-voice-stop-submit-and-noise-suppression.md` 內文沿用舊草稿編號 CR-0095，但 CR-0095 已用於 mochi rest_03 素材重做，故本任務正式編號 **CR-0096**。

## 1. 問題描述

長者端語音對話：使用者正在說話時，如果再按一次語音按鈕（想「結束說話」），寵物**不會讀取剛剛說的話、也不會回覆**。在背景音很吵時，server VAD 偵測不到靜音、turn 一直不結束，使用者又沒有正確的手動結束入口。

## 2. 根因分析

- `lib/screens/home_screen.dart` 在 `isAwaitingUserSpeech`（ready / listening）分支呼叫 `voiceAgentController.stopRealtimeConversation()`。
- `stopRealtimeConversation()`（`voice_agent_controller.dart`）做的是「**結束整段對話**」：`realtimeVoiceService.stop()`（收掉連線資源）→ `conversationController.clearRealtimeTranscriptState()`（**清掉 transcript**）→ `_transition(idle)`。
- 等於把「停止說話」做成了「取消並斷線」：剛收的語音沒 commit、沒觸發 response，寵物自然不回覆。
- 另外 `getUserMedia({'audio': true})` 沒開噪音抑制，吵雜環境下 server VAD 更難判斷 end-of-speech。
- 補充缺口：使用者說話時 partial transcript 串流會把狀態帶到 `transcribing`，而 `isAwaitingUserSpeech` 不含 `transcribing`，導致這個區間按鈕會 no-op。本 CR 一併用新的 `isCapturingUserSpeech` 涵蓋。

## 3. 語音按鈕狀態機（本 CR 後）

| 狀態 | 按鈕語意 | 文案 |
|---|---|---|
| idle / error | 開始 / 重試一段語音 | 按住說話 / 再試一次 |
| connecting / recovering | 連線中，稍候 | 正在連線，馬上就好 / 正在重新連線 |
| ready / listening / transcribing（`isCapturingUserSpeech`） | **停止收音並送出本輪語音** | 正在聽你說，說完再按一下 |
| thinking / speaking（`isPetResponding`） | 不打斷，提醒先聽完 | 咕咕想一下 / 咕咕正在說話 |

「停止並送出」「取消本輪」「中斷寵物說話」三者明確區分：本 CR 的按鈕只做「停止並送出」；`stopRealtimeConversation()`（結束整段→idle、清 transcript）語意保留給其他入口；寵物回覆中一律不打斷（沿用既有 turn-based 規則）。

## 4. stop-and-submit 設計（architecture-agent 核准方案 a 強化版）

新增 controller `stopListeningAndSubmit()`：
1. 守門：非 `isCapturingUserSpeech` 直接 return。
2. 判斷本輪是否真的有語音（`_speechStartedAt != null` 或 `_partialTranscript` 非空）；**沒語音就不送 commit**（避免 `input_audio_buffer_commit_empty`），維持待命。
3. 呼叫 service `commitUserAudioAndRespond()`。
4. `_transition(thinking)`（UI 顯示「想一下」）+ `_startTimeout(responseTimeout)`（萬一沒回覆也不卡死）。
5. **不** clear transcript、**不** disconnect。

新增 🔒 service `commitUserAudioAndRespond()`：
1. `pauseMicInput()`：停止背景音續進 buffer；server 之後只收到靜音，不會再自動觸發第二輪 commit/response。
2. 送 `input_audio_buffer.commit`（server VAD 沒 fire 時唯一收尾來源）。
3. **僅當 `!_hasActiveAssistantResponse`** 才送 `response.create`（server VAD 若搶先建 response 就不重送，從源頭避免 double-response）。
4. 全程走既有 `_sendEventPayload`（data channel 未開排隊保護）；不碰 SDP / ICE / DataChannel、不 disconnect、不清 transcript。

### 良性錯誤過濾（放行必要條件）
service `error` 事件處理新增白名單：`input_audio_buffer_commit_empty`、`conversation_already_has_active_response` 只 log、不轉 `RealtimeEventType.error`、不打斷對話；其他錯誤（session、rate limit…）照常上報白話訊息。守住 CLAUDE.md「不要因為一個事件 parse 錯就讓整個對話壞掉」。

## 5. 噪音抑制（Part D）

`getUserMedia` 的 `'audio': true` 改為帶 constraints，並 try/catch 安全降級：
```dart
try {
  _localStream = await navigator.mediaDevices.getUserMedia({
    'audio': {'echoCancellation': true, 'noiseSuppression': true, 'autoGainControl': true},
    'video': false,
  });
} catch (_) {
  _localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
}
```
外層既有 `RealtimeFailure(microphonePermissionDenied)` 不動：真權限拒絕時降級呼叫仍會 throw 並由外層接住（只有一次權限決策）。

## 6. 是否修改鎖定檔與 architecture-agent 核准紀錄

- 觸及 🔒 `lib/services/realtime_voice_service.dart`：getUserMedia constraints、新 `commitUserAudioAndRespond`、`error` 良性碼過濾。
- **architecture-agent 已核准**（agentId a81bffb4145fbd32f，medium risk），方案 (a) 強化版；(b) 關 server_vad、(c) 只 commit 不送 response.create 皆被駁回。放行條件：error 白名單過濾 + controller 端有語音才 commit + thinking 掛 responseTimeout + getUserMedia try/catch 降級 + 補測試。全數已落實。
- 不改前後端 API 契約 / DB schema / Care Alert 資料結構 → 無須先更新 `PROJECT_ARCHITECTURE.md`。
- 對 CR-0089/CR-0083 字幕同步無破壞：手動 commit 仍走同一組 transcription / response / output_audio_buffer 事件與歸屬邏輯。

## 7. 測試結果

- `flutter analyze`：**No issues**。
- `flutter test`：**699 passed / 0 failed**（新增 6 筆）。
- service（`test/realtime_voice_service_test.dart`）：commit+response.create（無 active response）/ 只 commit（有 active response）；良性碼 commit_empty / already_has_active_response 不 emit error；非良性碼仍上報。
- controller（`test/voice_agent_controller_realtime_lifecycle_test.dart`）：聆聽中有語音按停止 → 送 commit+response.create、進 thinking、不清 partial transcript；還沒開口按停止 → 不送 commit、維持待命。
- presentation（`test/voice_button_presentation_test.dart`）：listening/ready/transcribing 文案改為「正在聽你說，說完再按一下」。

## 8. 已知限制

- 未實機驗收（需在 iPhone 跑任務檔的情境 1–5）。iOS 上 getUserMedia constraints 的實際生效程度與 disabled-track 是否傳靜音，需實機確認。
- `_hasActiveAssistantResponse` 在 `response.created` 設 true、`response.done` 設 false——本 CR 未動其時序。
- 未動 AI persona / 字幕同步主流程 / 寵物動畫（另一 CR 進行中）/ 推播 / Care Alert / Telegram / 後台 / App icon。
