# CR-0030 條件式每日簽到通知

## 任務目標

請新增「條件式每日簽到通知」。

採用做法 B：

> 不是每天 10:00 才即時檢查是否簽到，而是每天預先排程一則 10:00 的本機通知；如果使用者在 10:00 前已完成今日簽到，就取消今天的簽到通知。

請採用最小可行修改，不要重構整個每日獎勵系統，也不要重寫任務系統。  
這次只做：

1. 每日 10:00 簽到通知排程
2. 已簽到取消今日通知
3. App 啟動時同步排程
4. 必要測試與文件補充

請不要破壞既有功能：

- OpenAI Realtime
- Care Alert
- 登入／註冊
- 長期記憶
- 寵物狀態
- 每日獎勵
- 任務系統
- 管理者端 API

---

## 一、功能需求

### 1. 每日簽到通知

每天早上 10:00 排程一則本機通知。

通知標題：

```text
早安，今天也來看看你的 AI 寵物吧
```

通知內容：

```text
記得完成今日簽到，領取陪伴獎勵！
```

通知 payload：

```text
check_in_reminder
```

notification id 固定使用：

```text
10001
```

---

### 2. 條件式取消通知

如果使用者今天已經簽到，今天的 10:00 通知要被取消。

如果使用者在 10:00 前完成簽到，今天的 10:00 通知要立即取消。

如果使用者在 10:00 後才簽到，今天通知可能已經發出，不需要補救，只要確保明天通知正常排程。

---

### 3. App 啟動同步邏輯

App 每次啟動後，要同步簽到通知狀態。

邏輯如下：

```text
App 啟動
↓
初始化 NotificationService
↓
讀取今天是否已簽到
↓
如果今天已簽到：
    取消今天通知
    排程下一次 10:00 通知，通常是明天 10:00
如果今天未簽到：
    如果現在時間早於今天 10:00：
        排程今天 10:00 通知
    如果現在時間已晚於今天 10:00：
        排程明天 10:00 通知
```

---

### 4. 簽到成功後同步邏輯

簽到成功時：

```text
使用者完成簽到
↓
寫入今日簽到紀錄
↓
發放獎勵
↓
取消今天 10:00 通知
↓
排程下一次 10:00 通知
```

請確保：

- 只有簽到成功才取消通知
- 簽到失敗不要取消通知
- 重複簽到不要造成通知排程錯亂

---

## 二、技術要求

請使用 Flutter 本機通知。

優先使用：

- flutter_local_notifications
- timezone

如果專案已經有 `flutter_local_notifications`，請沿用現有架構，不要建立第二套通知系統。

如果尚未有通知服務，請新增：

```text
lib/services/notification_service.dart
```

必要時可新增：

```text
lib/controllers/notification_controller.dart
```

---

## 三、NotificationService 需求

請實作或補齊以下方法：

```dart
initialize()
requestPermissions()
scheduleDailyCheckInReminder()
cancelTodayCheckInReminder()
rescheduleNextCheckInReminder()
syncCheckInReminder({required bool hasCheckedInToday})
cancelAllNotifications()
```

---

### 1. initialize()

需求：

- 初始化 `flutter_local_notifications`
- 初始化 `timezone`
- 建立 Android notification channel
- 設定 iOS 權限
- 設定通知點擊 callback
- 初始化失敗不得造成 App crash

---

### 2. requestPermissions()

需求：

- iOS 請求 alert / badge / sound 權限
- Android 13+ 請求通知權限
- 權限被拒絕時回傳 false
- 不要把工程錯誤顯示給使用者

---

### 3. scheduleDailyCheckInReminder()

需求：

- 排程下一次 10:00 簽到通知
- 使用手機當地時間
- 如果現在時間早於今天 10:00，排程今天 10:00
- 如果現在時間已晚於今天 10:00，排程明天 10:00
- notification id 固定使用 10001
- 避免重複排程造成通知洗版

---

### 4. cancelTodayCheckInReminder()

需求：

- 取消 notification id 10001
- 用於使用者完成今日簽到後
- 用於 App 啟動時發現今天已簽到

---

### 5. rescheduleNextCheckInReminder()

需求：

- 先取消舊的 10001
- 再排程下一次 10:00 簽到通知

---

### 6. syncCheckInReminder()

這是最重要的方法。

方法：

```dart
syncCheckInReminder({required bool hasCheckedInToday})
```

邏輯：

```text
如果 hasCheckedInToday == true：
    取消今天簽到通知
    排程下一次 10:00 通知，通常是明天 10:00

如果 hasCheckedInToday == false：
    如果現在時間早於今天 10:00：
        排程今天 10:00 通知
    如果現在時間已晚於今天 10:00：
        排程明天 10:00 通知
```

---

## 四、整合位置

請先盤點目前專案中與以下功能相關的檔案：

- 每日簽到
- 每日獎勵
- 任務
- App 初始化
- Provider 初始化
- 設定頁
- 現有通知功能

可能檔名包含：

```text
daily_reward
check_in
reward
task
home
pet_controller
wallet_controller
profile_controller
main.dart
app.dart
```

---

### 1. App 啟動整合

請選擇目前專案最合適的位置整合，例如：

- `main.dart`
- `app.dart`
- bootstrap/init service
- Provider 初始化處
- DailyRewardController 初始化處

流程：

```text
App 啟動
↓
NotificationService.initialize()
↓
讀取今日是否已簽到
↓
NotificationService.syncCheckInReminder(hasCheckedInToday: ...)
```

請避免把大量通知邏輯塞進 UI widget。

---

### 2. 簽到成功整合

請找出目前每日簽到或每日獎勵完成的位置。

在使用者成功完成今日簽到後呼叫：

```dart
NotificationService.syncCheckInReminder(hasCheckedInToday: true);
```

或等價流程：

```dart
await NotificationService.cancelTodayCheckInReminder();
await NotificationService.rescheduleNextCheckInReminder();
```

---

## 五、時區要求

請使用 `timezone` 套件處理 `zonedSchedule`。

每日 10:00 應該是手機當地時間，不要用 UTC。

請避免以下錯誤：

- 用 `DateTime.now().toUtc()` 排本地通知
- 日期跨日時排錯
- 今天已超過 10:00 還排今天的過去時間
- App 重開後重複排程多則通知

---

## 六、通知點擊行為

如果目前專案路由容易處理，點擊通知後導向：

- 首頁
或
- 每日簽到／每日獎勵頁

如果目前路由不方便，至少點擊通知後能打開 App，不要為了導頁大改路由架構。

---

## 七、設定頁

如果目前設定頁已有提醒相關區塊，請新增或預留「每日簽到提醒」開關。

如果會牽涉太大，請先保留 TODO，不要大改 UI。

最低限度要完成：

- 通知服務功能
- 簽到後取消通知
- App 啟動同步排程

---

## 八、測試需求

請新增或更新測試，至少覆蓋：

1. 現在時間早於 10:00 且未簽到，會排程今天 10:00。
2. 現在時間晚於 10:00 且未簽到，會排程明天 10:00。
3. 今天已簽到，會取消今日通知並排程下一次通知。
4. 簽到成功後會呼叫 `syncCheckInReminder(hasCheckedInToday: true)` 或等價方法。
5. notification id 固定為 10001。
6. 權限被拒絕時不會 crash。
7. 不影響既有每日獎勵、任務、寵物狀態流程。

如果 `flutter_local_notifications` 不容易直接單元測試，請把時間計算與 notification id 產生邏輯拆成純 Dart helper，優先測 helper。

---

## 九、通知文案規範

請使用繁體中文。  
語氣要溫暖、簡單、長者友善。

不要出現：

```text
API error
exception
null
debug
token
stack trace
failed
```

---

## 十、完成後請回報

請用以下格式回報：

```text
CR-0030 完成回報

一、完成內容

二、修改檔案

三、新增檔案

四、App 啟動時如何同步簽到通知

五、簽到成功後如何取消通知

六、iPhone 實機測試方式

七、Android 測試注意事項

八、已執行測試與結果

九、尚未完成或保留 TODO
```
