# CR-0095 — Manual Voice Stop Submit and Noise Suppression

## 目標

修正長者端語音對話的「手動停止說話」行為。

目前問題：

```text
使用者正在說話時，如果再按一次停止說話按鈕，寵物不會讀取使用者剛剛說的話，也不會回覆。
```

預期行為：

```text
使用者按下語音按鈕開始說話。
使用者說完一段話後，再按一次停止說話。
App 應停止收音，並把剛剛那段語音送出給 Realtime / AI。
寵物應根據剛剛那段話回覆。
```

這個 CR 也要加強麥克風收音的噪音抑制，讓使用者在旁邊環境音很多時，可以自己決定什麼時候結束說話，避免一直被背景雜音拖住。

---

## 編號說明

原本曾暫時規劃為 CR-0093，但使用者表示：

```text
寵物動畫已經做一半。
接下來這個手動停止語音問題改成 CR-0095。
```

因此本任務正式編號為：

```text
CR-0095 — Manual Voice Stop Submit and Noise Suppression
```

請不要覆蓋目前進行中的寵物動畫 CR。  
若 `docs/CHANGE_REVIEW.md` 目前已宣告 CR-0094 或其他主線事項，請依實際狀態補登，但本任務本身使用 CR-0095。

---

## 背景

使用者回報：

```text
目前發現一個問題，就是使用者說話時如果再按一次停止說話按鈕，
那麼寵物就不會讀取使用者說的話。
這樣如果旁邊音訊很雜很多的時候，使用者不能決定什麼時候講話停止，
我們希望要達到抑制雜訊的效果，而且當使用者說一段話按停止鍵寵物仍要可以回覆。
```

此問題會直接影響實機展示，優先度高。

---

## 重要判斷

這不是單純 UI 問題，而是語音回合控制問題。

目前停止按鈕可能只是：

```text
暫停麥克風
取消 listening 狀態
關閉 local capture
清掉 UI 狀態
```

但沒有做：

```text
明確結束使用者這一輪語音
保留已收音內容
通知 Realtime 產生回覆
等待 transcript / response
```

所以按停止後，剛剛說的話被視為取消或未完成，而不是送出。

---

## 範圍

### 本 CR 要做

- 盤點語音按鈕目前的 start / stop 行為。
- 修正「停止說話」：從取消收音改成「結束並送出本輪語音」。
- 保留使用者已說的內容，不得因 stop 清空。
- 手動 stop 後，寵物必須進入處理中並產生回覆。
- 加強麥克風 noise suppression / echo cancellation / auto gain control。
- 明確區分：
  ```text
  停止並送出
  取消本輪
  中斷寵物說話
  ```
- 補測試與文件。
- 更新 `docs/CHANGE_REVIEW.md`。

### 本 CR 不做

- 不改 AI persona；CR-0090 / CR-0093A 已處理。
- 不改字幕同步；CR-0089 已處理。
- 不改寵物素材。
- 不改寵物動畫速度或 rest ping-pong；此項已有其他 CR 進行中。
- 不改推播。
- 不改後台。
- 不改 Care Alert / Telegram。
- 不改 App icon。
- 不讀 `.env`。

---

## 🔒 鎖定檔注意事項

本 CR 很可能需要盤點或修改：

```text
lib/services/realtime_voice_service.dart
```

這是 🔒 鎖定檔。

如果只是讀檔盤點，不需審查。  
如果要修改任何邏輯，必須先停下並送 architecture-agent 審查。

審查內容至少包含：

1. 現在 stop button 為何沒有送出使用者語音。
2. 預計修改哪些 function / event。
3. 是否需要送出 Realtime client event，例如：
   ```text
   input_audio_buffer.commit
   response.create
   ```
   或專案既有等價事件。
4. 是否影響 SDP / ICE / DataChannel / WebRTC 連線。
5. 是否影響 CR-0089 的 audio started / stopped 字幕同步。
6. 是否影響工具流程。
7. 是否有 controller 層解法可避免大改 service。

未核准前不得修改鎖定檔。

---

## 可能涉及檔案

請先盤點，實際檔名以專案為準。

可能涉及：

```text
lib/controllers/voice_agent_controller.dart
lib/services/realtime_voice_service.dart
lib/widgets/voice_button.dart
lib/screens/home_screen.dart
lib/services/audio_input_service.dart
lib/services/microphone_permission_service.dart
test/voice_agent_controller_realtime_lifecycle_test.dart
test/realtime_voice_service_test.dart
test/integration/agent_voice_turn_integration_test.dart
docs/CHANGE_REVIEW.md
```

請用 grep / code search 確認實際檔案。

---

## Part A — 盤點目前語音按鈕狀態機

請先找出語音按鈕目前有哪些狀態。

例如：

```text
idle
connecting
listening
processing
speaking
error
```

請盤點：

```text
按第一次語音按鈕會呼叫什麼
listening 中再按一次會呼叫什麼
目前 stop 是 pause / cancel / dispose / mute 哪一種
stop 後是否有送出 user turn
stop 後是否有等待 transcript
stop 後是否有觸發 response
server_vad 是否仍在等待 silence
雜音環境下是否可能永遠不觸發 turn end
```

請在文件中寫明根因。

---

## Part B — 定義按鈕語意

請把語音按鈕語意定清楚。

### B1. idle → start listening

```text
使用者按下按鈕
開始收音
UI 顯示正在聽
寵物顯示 listening
```

### B2. listening → stop and submit

```text
使用者正在說話時再按一次
不是取消
不是丟棄
而是「停止並送出」
```

停止並送出應做到：

```text
停止或暫停麥克風輸入，避免背景雜音繼續進來
明確結束本輪使用者語音
保留已收音內容
通知 Realtime / AI 產生回覆
UI 進入 processing
寵物之後進入 talk
```

### B3. speaking → optional interrupt

若寵物正在說話時按按鈕，請依現有規則處理。

本 CR 不強制新增 interrupt 功能，但不得破壞既有行為。

### B4. cancel 若需要，必須另有明確入口

如果產品需要「取消本輪不送出」，不應和「停止說話」混在同一個按鈕。

目前展示需求是：

```text
按停止 = 送出並讓寵物回覆
```

---

## Part C — Realtime turn finalization

請依專案目前 Realtime 架構，找出最小且正確的 turn finalization 方法。

可能方法包括但不限於：

```text
input_audio_buffer.commit
response.create
server_vad forced turn end
client event through data channel
existing finishUserTurn / stopListeningAndSubmit function
```

請不要盲目新增事件。先看現有 service 是否已有類似 function。

正確行為：

```text
stop listening
commit current audio buffer / finalize current user turn
request assistant response if needed
do not clear transcript before response starts
do not close session
do not disconnect WebRTC
```

如果目前使用 `server_vad` + `create_response:true`，請確認手動 stop 是否仍需要 explicit commit / response.create，或是否已有專案包裝事件。  
若需修改 Realtime service，請先走 architecture-agent 審查。

---

## Part D — 噪音抑制

請檢查 WebRTC / getUserMedia audio constraints。

若尚未啟用，請加入或確認：

```text
echoCancellation: true
noiseSuppression: true
autoGainControl: true
```

若 Flutter / plugin / platform 不支援某些 constraint，請安全降級，不得 crash。

目標：

```text
降低背景音拖住 VAD 的機率
讓使用者可以靠手動停止結束本輪
不影響正常說話辨識
```

請不要為了噪音抑制大改音訊 pipeline。

---

## Part E — UI / 文案

按鈕狀態建議：

```text
未說話：按一下開始說話
聽您說話中：按一下送出
處理中：寵物想一想
寵物說話中：顯示寵物正在回覆
```

避免：

```text
停止說話 = 取消
停止 = 清除
debug stop
VAD timeout
commit buffer
```

長者友善文案可用：

```text
正在聽您說，說完再按一下
我聽到了，正在想怎麼回你
```

---

## Part F — 測試要求

請依現有 Flutter 測試架構新增或更新測試。

至少涵蓋：

1. listening 中按 stop 會呼叫 stop-and-submit，而不是 cancel。
2. stop-and-submit 會保留本輪已收音 / transcript 狀態。
3. stop-and-submit 會觸發 assistant response request 或等價流程。
4. stop 後 UI 進入 processing，而不是 idle。
5. stop 後寵物不會卡在 listening。
6. noisy / no server_vad end 情境下，手動 stop 仍可 finalize turn。
7. stop 不會 disconnect Realtime session。
8. stop 不會破壞 CR-0089 字幕同步。
9. audio constraints 包含 noise suppression / echo cancellation / auto gain control，或有安全降級測試。
10. flutter analyze 通過。
11. flutter test 通過。

若 Realtime service 需新增測試 helper，請保持純測試用途，不改 production API shape 過大。

---

## 手動驗收

請在 iPhone 實機測試：

### 情境 1：正常環境

```text
按語音按鈕
說：我今天有點累
立刻再按一次停止
預期：寵物仍會回覆「累」這件事
```

### 情境 2：有背景音

```text
旁邊播放音樂或讓環境有雜音
按語音按鈕
說一句完整話
按停止
預期：App 停止收音並送出，不會一直等背景音安靜
```

### 情境 3：短句

```text
說：你好
按停止
預期：寵物回覆
```

### 情境 4：停頓後停止

```text
說一句話
停 1 秒
按停止
預期：仍送出，不丟失
```

### 情境 5：寵物正在說話

```text
寵物 talk 中按按鈕
確認既有行為不壞
```

---

## 文件要求

請新增：

```text
docs/MANUAL_VOICE_STOP_SUBMIT_CR0095.md
```

內容至少包含：

1. 問題描述。
2. 根因分析。
3. 語音按鈕狀態機。
4. stop-and-submit 設計。
5. 噪音抑制處理。
6. 是否修改鎖定檔與 architecture-agent 核准紀錄。
7. 測試結果。
8. 已知限制。

請更新：

```text
docs/CHANGE_REVIEW.md
```

新增：

```text
## CR-0095 — Manual Voice Stop Submit and Noise Suppression
```

並依實際狀態宣告下一個可用 CR。

---

## 建議執行指令

若只改 Flutter：

```bash
flutter analyze
flutter test
```

若沒有改後端，不需要跑 backend npm 測試。

---

## 驗收標準

完成後需符合：

- 使用者 listening 中按停止，不會丟掉剛剛說的話。
- 手動停止會送出本輪語音並讓寵物回覆。
- 背景雜音環境下，使用者可手動結束說話。
- 麥克風啟用 noise suppression / echo cancellation / auto gain control，或有安全降級。
- 不 disconnect Realtime session。
- 不破壞 CR-0089 字幕同步。
- 不破壞工具 / Care Alert / Telegram。
- Flutter analyze 通過。
- Flutter tests 通過。
- 文件與 CHANGE_REVIEW 更新完成。

---

## 注意事項

- 不要讀 `.env`。
- 不要把「停止說話」做成取消。
- 不要清空已收音內容。
- 不要用 disconnect session 的方式停止收音。
- 不要大改 Realtime 連線。
- 不要改 AI persona。
- 不要改寵物動畫；動畫 CR 已在進行中。
- 不要改 App icon。
- 若要改 `realtime_voice_service.dart`，一定要先 architecture-agent 核准。
