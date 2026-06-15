# CR-0094 — Remove Time-Based Sleepy Idle State

移除 CR-0088 的「深夜（22:00–06:00）→ sleepy」時段規則。實機測試在晚上時，寵物閒置會「一直」顯示 sleepy；改為閒置一律回 rest 待機，sleepy 只在對話情緒分析為 `tired` 時由短暫情緒（transient）短暫出現。

---

## 問題

CR-0088 的 `PetStateSelector.careStateFor` 有一條 `hour >= 22 || hour < 6 → sleepy`。實機在 22:41 測試時，寵物大多時間閒置（沒收音、沒播語音、沒短暫情緒、且 satiety/mood/intimacy 正常）→ 落到時段 sleepy → 看起來整晚都 sleepy。

## 變更（`lib/utils/pet_state_selector.dart`）

- `careStateFor`：移除 `hour` 參數與 `深夜 → sleepy` 分支。care state 只剩 satiety<30→hungry、mood<30→sad、intimacy<30→caring。
- `select`：移除 `hour` 參數（不再傳給 careStateFor）。
- `lib/screens/home_screen.dart`：移除呼叫端的 `hour: DateTime.now().hour`。
- sleepy 仍可出現：`transientModeForEmotion('tired') → sleepy`（聊到累時短暫顯示），與 ping-pong rest（CR-0093）並存。

## 效果

- 閒置（白天 / 晚上皆同）→ rest 待機輪播（不再因時段變 sleepy）。
- hungry / sad / caring 仍由真實數值觸發；happy / excited / caring / sleepy 仍由互動後短暫情緒觸發。
- 優先序不變：listening > talking > transient > care(hungry/sad/caring) > rest。

## 測試

- `test/utils/pet_state_selector_test.dart`：移除「深夜→sleepy」測試，改測「閒置狀態正常 → rest（不再因時段 sleepy）」、「sleepy 只由 tired 短暫情緒觸發、careState 不自產 sleepy」；移除 sel() 的 hour 參數。
- `flutter analyze` **No issues**；`flutter test` **693 passed / 0 failed**。

## 已知限制

- thirsty 仍無自動觸發來源（無 hydration 資料，沿用 CR-0088 決定）。
- 未動 Realtime / 字幕 / persona / 推播 / 後台 / Care Alert / 寵物素材 / App icon。
