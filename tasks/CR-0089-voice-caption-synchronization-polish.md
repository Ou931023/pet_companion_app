# CR-0089 — Voice Caption Synchronization Polish

## 目標

修正長者端語音對話中「寵物正在說話，但字幕內容對不上」的問題，讓字幕、寵物說話動畫、實際播放語音三者保持一致。

本 CR 的重點是字幕同步與語音輪次顯示，不處理 AI 對話自然度、不改 persona、不改工具功能、不重構 Realtime 主流程。

需要解決的現象包括：

1. 寵物正在播放上一句語音，但字幕已經被下一句覆蓋。
2. 寵物說話動畫還在播放，但字幕已經消失或切換。
3. filler、tool outcome、AI response 的字幕互相蓋掉。
4. `response.done` 發生時，語音可能尚未真正播完，導致字幕提前更新。
5. 工具回覆語音與一般 AI 語音的字幕來源不一致。
6. 一段對話中多個回覆排隊播放時，字幕與正在播放的那一段語音要對齊。

---

## 背景

目前專案已完成：

- Realtime 語音對話
- 寵物 talk / listening / rest / states 狀態切換
- tool outcome 語音播報
- CR-0088 已改善寵物狀態不再長時間卡在 talk/listening

但現在仍有字幕同步問題。使用者觀察到：

```text
寵物說話時，對話框字幕有時候和實際正在說的內容對不上。
```

此問題會直接影響 Demo 觀感，因此需要獨立 CR 處理。

---

## 重要界線

### 本 CR 要做

- 盤點字幕來源。
- 盤點語音播放狀態來源。
- 修正字幕更新時機。
- 避免下一句字幕提前覆蓋上一句。
- 讓字幕 owner / turn id / speech id 與實際播放語音一致。
- 修正 filler / tool outcome / AI response 之間的字幕競態。
- 補測試與文件。

### 本 CR 不做

- 不改 AI persona。
- 不處理對話內容重複或不自然問題，這留給 CR-0090。
- 不改寵物素材。
- 不改寵物狀態 mapping，除非字幕修正需要最小同步欄位。
- 不改 Care Alert。
- 不改 Telegram。
- 不改通知推播。
- 不改管理者後台。
- 不改工具功能本身。
- 不新增後端 DB schema。
- 不讀 `.env`。

---

## 鎖定檔案注意事項

若需要修改以下 Realtime 相關敏感檔案，請先停下並回報需要 architecture-agent 審查：

```text
lib/services/realtime_voice_service.dart
```

如果只是讀檔盤點，不需要審查。  
如果要修改該檔任何邏輯，必須先提出：

1. 需要修改的原因。
2. 預計修改區塊。
3. 是否影響 SDP / ICE / DataChannel / response lifecycle。
4. 是否有更小替代方案。

優先嘗試在 controller / caption state / UI 層修正，不要大改 Realtime service。

---

## 可能涉及檔案

請先盤點，實際檔名以專案為準。

可能涉及：

```text
lib/controllers/voice_agent_controller.dart
lib/services/realtime_voice_service.dart
lib/widgets/speech_bubble.dart
lib/widgets/pet_widget.dart
lib/screens/home_screen.dart
lib/models/conversation_turn.dart
lib/models/voice_turn.dart
lib/services/agent_tool_controller.dart
lib/services/ai_tool_router.dart
```

---

## Part A — 盤點字幕與語音來源

### A1. 字幕來源

請找出目前字幕文字來自哪些地方，例如：

```text
Realtime partial transcript
Realtime final transcript
assistant response text
tool filler text
tool outcome text
typed chat response
error fallback message
```

請標明哪些字幕是：

```text
長者說的話
寵物說的話
工具補充語音
錯誤提示
```

不要讓長者字幕與寵物字幕共用同一個無 owner 的欄位而互相覆蓋。

### A2. 語音播放來源

請找出目前寵物語音播放來源，例如：

```text
Realtime output audio
TTS tool outcome speech
filler speech
local fallback TTS
typed chat TTS（若有）
```

請確認各來源是否有：

```text
開始播放事件
播放結束事件
response.done
audio done
queue done
speaking flag
turn id / request id
```

### A3. 現有競態問題

請特別找出以下情境：

```text
response.done 先於音訊真正播完
tool outcome 排隊時提前更新字幕
filler 還在播，但 AI 回覆字幕已出現
AI 回覆還在播，但下一輪聆聽字幕已覆蓋
語音播放停止後字幕沒有清掉或沒有淡出
```

---

## Part B — 設計字幕 owner / turn id

請建立一套最小但明確的字幕歸屬機制。

建議概念：

```text
captionOwner:
- user
- pet
- tool
- system

captionSource:
- realtime
- tool_outcome
- filler
- typed_chat
- error

captionTurnId:
- 每一段要顯示在寵物對話框的語音，都有唯一 id
```

若目前專案已有類似欄位，請沿用，不要重建。

---

## Part C — 字幕更新規則

### C1. 正在播放的語音擁有字幕

當寵物正在播放某段語音時：

```text
字幕 = 該段語音對應文字
寵物狀態 = talk
不得被下一段已產生但尚未播放的文字覆蓋
```

### C2. 語音排隊時不要提前換字幕

如果有多段語音排隊：

```text
第一段播放中 → 顯示第一段字幕
第二段等待中 → 不顯示第二段字幕
第二段開始播放 → 才切第二段字幕
```

### C3. response.done 不等於 audio done

不得再用單純 `response.done` 當成字幕可切換或語音已結束的唯一依據。

若目前沒有明確 audio done 事件，請採取安全策略：

```text
以 speaking flag / output_audio done / local playback completion / queue drain 為準
```

如果缺乏可靠事件，請先提出最小可行修正，不要亂猜時間。

### C4. filler / tool outcome / AI response 不能互相蓋

請分清楚：

```text
filler speech
tool outcome speech
AI assistant response
```

例如：

```text
filler 正在播：「我幫你看一下喔」
→ 字幕顯示 filler

tool outcome 開始播：「已經幫你記下提醒」
→ 字幕切 tool outcome

AI response 開始播
→ 字幕切 AI response
```

不得在 filler 尚未播放完時提前顯示 tool outcome 或 AI response。

### C5. 使用者字幕與寵物字幕不要互蓋

長者正在說話時可以顯示使用者語音辨識字幕；寵物正在說話時顯示寵物字幕。

若 UI 只有一個對話框，請至少確保：

```text
使用者收音中 → 顯示「正在聽您說...」或使用者字幕
寵物播放中 → 顯示寵物正在說的內容
```

不要讓 user transcript 在寵物播放中覆蓋 pet caption。

---

## Part D — 寵物 talk 狀態與字幕同步

CR-0088 已處理狀態觸發，但本 CR 需要確認：

```text
字幕顯示某段寵物語音時，pet visual state 應為 talk。
語音播放結束後，talk 結束，字幕可保留短暫時間後淡出或轉 transient state。
```

若目前 pet talk 狀態由 `isSpeaking` 控制，請確認 `isSpeaking` 的更新時機與字幕相同來源。

---

## Part E — 建議實作策略

優先採取「最小風險」方案：

1. 抽出 caption state model，例如：
   ```text
   CaptionState(text, owner, source, turnId, isActive)
   ```
2. 每段 TTS / Realtime audio / tool speech 進入播放 queue 時，帶上 caption text。
3. 只有「開始播放」時才 set caption。
4. 只有「該 turnId 播放結束」時才 clear / fade / allow next caption。
5. 若收到過期 turnId 的事件，不得覆蓋當前字幕。
6. 測試 response.done 早到時字幕不被提前切走。

若現有架構不適合新增 model，可用既有 controller state 增加最小欄位，但要有測試覆蓋。

---

## Part F — 測試要求

請依現有 Flutter 測試架構補測。

至少新增或更新以下測試：

### F1. 一般 AI 語音字幕

```text
寵物開始播放 AI 回覆 → 顯示該回覆字幕
AI 回覆播放中 → 下一段已準備好也不得覆蓋
AI 回覆播放結束 → 字幕可清除或保留短暫時間
```

### F2. response.done 早於 audio done

```text
收到 response.done
但 audio 尚未完成
→ 字幕仍保留目前正在播放的文字
```

### F3. filler 與 tool outcome

```text
filler 播放中 → 顯示 filler 字幕
tool outcome 尚未開始 → 不得提前覆蓋
tool outcome 開始播放 → 才顯示 tool outcome 字幕
```

### F4. 多段排隊語音

```text
speech A 播放中，speech B 等待
→ 顯示 A

speech A 結束，speech B 開始
→ 顯示 B
```

### F5. 過期事件不覆蓋

```text
turnId 舊的 done / error / transcript event 到達
→ 不得覆蓋目前新的字幕
```

### F6. user transcript 與 pet caption

```text
使用者收音時顯示 user caption
寵物播放時顯示 pet caption
pet speaking 時 user partial 不應覆蓋 pet caption
```

### F7. 不影響 Realtime lifecycle

若本 CR 觸及語音 controller，請至少跑現有：

```text
voice_agent_controller_realtime_lifecycle
realtime_timeout
realtime_voice_service_test
```

實際測試名稱以專案為準。

---

## 手動驗收

請在 iPhone 實機測試：

1. 一般語音對話：
   ```text
   長者說一句
   寵物回覆
   檢查寵物嘴巴動畫、字幕、實際語音是否一致
   ```

2. 連續問兩句：
   ```text
   不得出現上一句語音播著下一句字幕
   ```

3. 觸發工具功能：
   ```text
   例如提醒 / 任務 / 查狀態
   filler 與 tool outcome 字幕要跟語音一致
   ```

4. 中途停頓：
   ```text
   字幕不要突然被空白或下一段覆蓋
   ```

5. 台語語音模式：
   ```text
   若有台語回覆，字幕至少不應錯位或被提前覆蓋
   ```

---

## 文件要求

請新增：

```text
docs/VOICE_CAPTION_SYNC_CR0089.md
```

內容至少包含：

1. 問題原因盤點。
2. 字幕來源與語音來源。
3. 新的 caption owner / turn id 規則。
4. 修正內容。
5. 測試結果。
6. 已知限制。

請更新：

```text
docs/CHANGE_REVIEW.md
```

新增：

```text
## CR-0089 — Voice Caption Synchronization Polish
```

並宣告下一個可用 CR：

```text
CR-0090
```

---

## 建議執行指令

```bash
flutter analyze
flutter test
```

若只改 Flutter，不需要跑後端 npm 測試。

若觸及後端或 caregiver_web，才需要跑：

```bash
cd backend/stt_proxy
npm test
npm run check
```

---

## 驗收標準

完成後需符合：

- 寵物正在說哪一句，字幕就顯示哪一句。
- 下一段語音未開始前，不得提前顯示下一段字幕。
- filler / tool outcome / AI response 不互相提前覆蓋。
- response.done 不會讓字幕提前清除或切換。
- 使用者字幕不會在寵物播放中覆蓋寵物字幕。
- 寵物 talk 狀態與正在播放的語音一致。
- Flutter analyze 通過。
- 相關 Flutter tests 通過。
- 若修改鎖定檔 `realtime_voice_service.dart`，需有 architecture-agent 核准紀錄。
- 更新 `docs/VOICE_CAPTION_SYNC_CR0089.md` 與 `docs/CHANGE_REVIEW.md`。

---

## 注意事項

- 不要讀 `.env`。
- 不要修改 AI persona；對話自然度留給 CR-0090。
- 不要修改寵物素材；素材已由 CR-0088 處理。
- 不要修改推播；推播已由 CR-0087 處理。
- 不要修改 Care Alert / Telegram。
- 不要修改後台分析頁。
- 不要用固定秒數硬猜所有音訊長度，除非沒有更可靠事件且有清楚註解與測試。
- 不要大改 Realtime 主流程。
- 若必須修改鎖定檔 `realtime_voice_service.dart`，請先停下並回報需 architecture-agent 審查。
