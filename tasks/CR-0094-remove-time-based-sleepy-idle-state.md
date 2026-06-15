# CR-0094 — Remove Time-Based Sleepy Idle State

> 由實機測試回饋產生：晚上（22:41）寵物閒置一直顯示 sleepy。使用者選擇「移除時段 sleepy」。

## 任務重點

1. 移除 CR-0088 的「深夜（22:00–06:00）→ sleepy」時段規則，避免整晚閒置都顯示 sleepy。
2. 閒置（狀態正常）一律回 rest 待機。
3. sleepy 改為只由對話情緒分析為 `tired` 的短暫情緒（transient）短暫觸發。
4. 不破壞 listening / talking / hungry / sad / caring / 短暫情緒 的既有優先序。
5. 不碰寵物素材、Realtime、字幕、AI persona、推播、後台、Care Alert、App icon。
6. 新增 `docs/PET_IDLE_SLEEPY_REMOVAL_CR0094.md`、更新 `docs/CHANGE_REVIEW.md`，宣告下一個 CR 為 CR-0095。
7. 跑 `flutter analyze` 與 `flutter test`。

## 實作摘要

`lib/utils/pet_state_selector.dart`：`select` / `careStateFor` 移除 `hour` 參數與深夜 sleepy 分支；`lib/screens/home_screen.dart` 移除傳入 `hour`。見 `docs/PET_IDLE_SLEEPY_REMOVAL_CR0094.md`。
