# CR-0087 — Pet Concern Push Notifications

## 目標

新增「寵物關心提醒」推播機制，讓 App 除了既有每日 18:00 未簽到通知外，也能依照長者與寵物的互動狀況，主動以溫和、長者友善的方式提醒長者回到 App 與寵物互動。

本 CR 的核心不是 Care Alert，也不是通知照護者，而是「通知長者本人」的本地推播：

1. 心情低落時，寵物主動關心。
2. 飽足度太低時，提醒長者回來看看寵物。
3. 親密度太低或長時間未互動時，提醒長者與寵物互動。
4. 既有每日 18:00 未簽到通知維持，不得被破壞。
5. 推播頻率需有限制，避免打擾長者。
6. 推播文案需溫和、自然、長者友善，不顯示工程字眼。

---

## 背景

目前 App 已具備每日固定晚上 18:00 的未簽到通知。接下來要加入更像陪伴型寵物的「關心提醒」。

此類通知與 Care Alert 不同：

```text
Care Alert：
- 通知對象：照護者 / 管理端 / Telegram
- 目的：風險事件追蹤與照護介入
- 條件：medium / high / urgent 等風險

寵物關心提醒：
- 通知對象：長者本人
- 目的：陪伴、互動、溫和提醒
- 條件：心情低落、飽足度低、親密度低、長時間未互動
```

本 CR 不得把寵物關心提醒誤接成 Telegram 或 Care Alert。

---

## 範圍

### 本 CR 要做

- 保留既有每日 18:00 未簽到通知。
- 新增寵物關心提醒判斷邏輯。
- 新增本地推播排程／觸發機制。
- 新增頻率限制 cooldown。
- 新增長者友善推播文案。
- 更新或新增測試。
- 更新文件與 CHANGE_REVIEW。

### 本 CR 不做

- 不改 Telegram 通知規則。
- 不改 Care Alert 風險分級與後端通知流程。
- 不改 Realtime 語音主流程。
- 不改管理者後台分析頁。
- 不新增 DB schema，除非現有本地儲存完全不足且需先提出理由。
- 不讀 `.env`。
- 不使用 demo-only fake notification。

---

## 推播類型

### 1. 每日未簽到通知

既有功能，必須保留。

```text
類型：daily_check_in
觸發時間：每日 18:00
條件：當日尚未簽到
通知對象：長者本人
頻率：每日最多一次
```

文案可沿用既有文案，但不得顯示工程字。

---

### 2. 心情低落關心提醒

```text
類型：low_mood_care
觸發條件：
- 寵物心情值低於門檻，例如 mood < 30
或
- 最近一次情緒分析為 sad / anxious / lonely / tired 等低落狀態
或
- 近一段時間連續出現負向情緒，但未達 Care Alert 高風險
通知對象：長者本人
頻率限制：每 6 小時最多一次
```

建議文案：

```text
小夥伴有點擔心你，想陪你說說話。
聽起來你今天有點累，寵物想陪你一下。
如果你願意，可以回來和寵物聊聊。
```

避免文案：

```text
偵測到負面情緒
emotion = sad
risk level medium
你有憂鬱風險
```

---

### 3. 飽足度太低提醒

```text
類型：low_satiety
觸發條件：
- satiety < 30
通知對象：長者本人
頻率限制：每 4 小時最多一次
```

建議文案：

```text
你的寵物肚子有點餓了，回來看看牠吧！
小夥伴想吃點東西，也想看看你。
寵物在等你回來照顧牠。
```

---

### 4. 親密度太低提醒

```text
類型：low_intimacy
觸發條件：
- intimacy < 30
且
- 今日尚未與寵物互動
通知對象：長者本人
頻率限制：每日最多一次
```

建議文案：

```text
你的寵物好像有點想你了，來陪牠聊聊天吧。
今天還沒和寵物說說話，要不要回來看看牠？
小夥伴在等你，想和你聊幾句。
```

---

### 5. 長時間未互動提醒

```text
類型：inactive_interaction
觸發條件：
- 12 或 24 小時未開啟 App / 未與寵物互動
通知對象：長者本人
頻率限制：每日最多一次
```

建議文案：

```text
今天還沒看到你，寵物有點想你了。
要不要打開 App，和寵物說幾句話？
小夥伴在等你回來。
```

---

## 台語友善文案

若專案目前已有台語模式或語言設定，可依設定選擇文案。若尚未有穩定語系切換，本 CR 可先保留國語文案，不強制新增台語推播。

可備用台語風格文案：

```text
你的寵物有咧想你，欲毋欲來佮伊講幾句？
寵物看起來有淡薄仔餓，轉來看伊一下好無？
聽起來你今仔日有較累，寵物想欲陪你。
```

注意：台語文案若會造成長者看不懂，請優先使用國語白話文。

---

## 頻率限制與避免打擾

請建立明確 cooldown，避免推播過多。

建議規則：

```text
daily_check_in：每日最多一次
low_mood_care：每 6 小時最多一次
low_satiety：每 4 小時最多一次
low_intimacy：每日最多一次
inactive_interaction：每日最多一次
全體寵物關心提醒：每 2 小時最多一則
```

若同時符合多個條件，建議優先順序：

```text
low_mood_care
low_satiety
inactive_interaction
low_intimacy
daily_check_in
```

但每日 18:00 未簽到通知若已存在固定排程，請不要破壞既有邏輯；只要避免同一時間重複跳太多通知。

---

## 建議實作位置

請依現有 Flutter 專案架構盤點後實作。可能涉及：

```text
lib/services/notification_service.dart
lib/services/local_notification_service.dart
lib/controllers/pet_controller.dart
lib/controllers/check_in_controller.dart
lib/controllers/conversation_controller.dart
lib/controllers/voice_agent_controller.dart
lib/models/pet_state.dart
lib/app_lifecycle 或 home_screen init
```

實際檔名以專案為準，不要硬建立重複服務。

若目前已經有通知服務，請優先擴充既有服務，不要另寫一套互相衝突的通知系統。

---

## 狀態資料來源

實作前請先盤點以下資料是否已存在：

```text
pet mood
pet satiety
pet intimacy
last interaction time
last app open time
today check-in status
latest emotion analysis
notification permission status
last notification sent timestamp
```

若某些資料目前只在 controller 內，請以最小變更方式暴露給通知判斷。

若資料不存在，請使用友善 fallback：

- 沒有 mood 資料 → 不觸發 low_mood_care。
- 沒有 satiety 資料 → 不觸發 low_satiety。
- 沒有 intimacy 資料 → 不觸發 low_intimacy。
- 沒有 last interaction → 可使用 App 最後開啟時間替代，但須在文件標註。

不要偽造狀態來硬觸發通知。

---

## 權限與平台要求

請確認：

```text
iOS notification permission
Android notification permission
Android 13+ POST_NOTIFICATIONS
本地推播初始化
使用者拒絕通知權限時的友善處理
```

如果既有通知功能已處理權限，本 CR 不需重寫，但需確認新增通知類型走相同權限機制。

---

## UI / 設定頁要求

若目前設定頁已有提醒或通知開關，請加入或沿用：

```text
寵物關心提醒
```

建議：

```text
開啟：允許寵物在你較少互動或狀態較低時提醒你
關閉：不發送寵物關心提醒，但不影響必要照護提醒
```

若沒有合適設定頁位置，可先採預設開啟，並在文件標註後續可新增開關。不過正式版建議有開關。

不要在 UI 顯示：

```text
low_mood_care
satiety < 30
cooldown
debug notification
```

---

## 測試要求

請依現有 Flutter 測試架構新增或更新測試。

至少涵蓋：

1. 每日 18:00 未簽到通知既有行為不變。
2. 心情低落時會產生 low_mood_care 通知候選。
3. 飽足度低於門檻時會產生 low_satiety 通知候選。
4. 親密度低且今日未互動時會產生 low_intimacy 通知候選。
5. 長時間未互動會產生 inactive_interaction 通知候選。
6. cooldown 內不重複通知。
7. 多條件同時成立時只選擇一則最合適通知。
8. 無資料時不崩潰，也不亂發通知。
9. 使用者關閉寵物關心提醒時不發送此類通知。
10. 不影響 Care Alert / Telegram / Realtime 測試。

若測試環境不方便直接測本地通知 plugin，請將判斷邏輯拆成純 Dart service，測「通知候選決策」，實際 plugin 呼叫只做薄封裝。

---

## 驗收標準

完成後需符合：

- 既有每日 18:00 未簽到通知仍可運作。
- 新增寵物關心提醒邏輯。
- 心情低落、飽足度低、親密度低、長時間未互動可觸發對應提醒。
- 通知有 cooldown，不會密集打擾。
- 通知文案自然、溫和、無工程字。
- 使用者可以關閉寵物關心提醒，或至少文件標明目前開關狀態。
- 不影響 Telegram / Care Alert。
- 不影響 Realtime 語音主流程。
- `flutter analyze` 通過。
- 相關 Flutter tests 通過。
- 新增文件 `docs/PET_CONCERN_PUSH_NOTIFICATIONS_CR0087.md`。
- 更新 `docs/CHANGE_REVIEW.md`，新增 CR-0087 條目，並宣告下一個可用 CR 為 CR-0088。

---

## 建議文件

請新增：

```text
docs/PET_CONCERN_PUSH_NOTIFICATIONS_CR0087.md
```

內容至少包含：

1. 功能目的。
2. 與 Care Alert 的差異。
3. 推播類型。
4. 觸發條件。
5. cooldown 規則。
6. 文案清單。
7. 設定頁開關。
8. 測試結果。
9. 已知限制。

---

## 建議執行指令

```bash
flutter analyze
flutter test
```

若本 CR 也觸及後端，才需要執行：

```bash
cd backend/stt_proxy
npm test
npm run check
```

---

## 注意事項

- 不要讀 `.env`。
- 不要改 Telegram。
- 不要改 Care Alert 通知規則。
- 不要改 Realtime 語音主流程。
- 不要用 demo-only fake notification。
- 不要顯示工程字眼給長者。
- 不要讓推播太頻繁。
- 不要破壞每日 18:00 未簽到通知。
- 若需觸及鎖定檔或 Realtime 相關檔案，請先停下並回報需 architecture-agent 審查。
