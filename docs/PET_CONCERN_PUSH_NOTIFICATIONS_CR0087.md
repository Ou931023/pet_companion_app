# CR-0087 — Pet Concern Push Notifications（寵物關心提醒）

App 在既有「每日簽到提醒」之外，新增一組「通知長者本人」的本地陪伴提醒：當寵物心情低落、肚子餓、親密度低或長者長時間未互動時，用溫和、長者友善的語氣提醒長者回來陪寵物。

---

## 1. 功能目的

讓 AI 寵物更像「會關心你的夥伴」：不只被動等長者開 App，也能在狀態較低或久未互動時，**對長者本人**發出溫和的本地推播。提醒頻率受 cooldown 限制，避免打擾。

---

## 2. 與 Care Alert 的差異（不可混淆）

| | Care Alert | 寵物關心提醒（本 CR） |
|---|---|---|
| 通知對象 | 照護者 / 管理端 / Telegram | **長者本人** |
| 目的 | 風險事件追蹤、照護介入 | 陪伴、溫和提醒回來互動 |
| 觸發 | medium / high / urgent 風險 | 心情低、飽足度低、親密度低、久未互動 |
| 通道 | 後端 + Telegram | **裝置本地推播**（flutter_local_notifications） |

本 CR **完全不碰** Telegram、Care Alert 風險分級與後端通知流程、Realtime 語音主流程。

---

## 3. 推播類型

| 類型 | 說明 | 既有/新增 |
|---|---|---|
| `daily_check_in` | 每日固定一則簽到提醒（**既有，保留不動**） | 既有（id 10001） |
| `low_mood_care` | 心情低落關心 | 新增 |
| `low_satiety` | 飽足度太低提醒 | 新增 |
| `low_intimacy` | 親密度太低提醒 | 新增 |
| `inactive_interaction` | 長時間未互動提醒 | 新增 |

> 說明：規格文件寫每日簽到為「18:00」，但專案既有實作的固定時間為**當地時間 10:00**（`CheckInReminderSchedule`，id 10001）。本 CR **保留既有行為、不更動時間**，四種新提醒走獨立 id 10002 與獨立通知 channel，與簽到提醒互不干擾。

---

## 4. 觸發條件

決策集中在純 Dart 服務 `lib/services/pet_concern_notification_policy.dart`（可單元測試、不依賴 plugin）。資料來源為長者端真實狀態 `PetStats`（`moodValue` / `fullness` / `intimacy`，0–100）與對話情緒標籤。

- **low_mood_care**：`moodValue < 30`，或最近一次情緒分析為 `sad / anxious / lonely / tired`。
- **low_satiety**：`fullness < 30`。
- **low_intimacy**：`intimacy < 30` **且**今日尚未與寵物互動。
- **inactive_interaction**：距最近一次互動 `>= 24` 小時。

**多條件同時成立時的優先序**：`low_mood_care → low_satiety → inactive_interaction → low_intimacy`（取第一個成立且未在 cooldown 內者，一次只發一則）。

**資料缺漏 → 不觸發（不捏造）**：mood/satiety/intimacy 為 null 時不觸發對應提醒；無對話紀錄時不觸發 inactive。

---

## 5. cooldown 規則

| 類型 | cooldown |
|---|---|
| `low_mood_care` | 每 6 小時最多一次 |
| `low_satiety` | 每 4 小時最多一次 |
| `low_intimacy` | 每日最多一次（24h） |
| `inactive_interaction` | 每日最多一次（24h） |
| **全體寵物關心提醒** | 每 2 小時最多一則 |

cooldown 時間戳記以 `LocalStorageService` 持久化（`concernNotifyTimestamps`，JSON `{類型 → ISO 時間, _any → ISO}`），並依帳號（elderId）命名空間隔離。

**觸發 / 排程機制**：App 進入背景（`paused`）時評估上述條件，若該發則排一則 `scheduleDelay`（預設 2 小時）後才跳的本地通知；回到 App（`resumed`）時取消它（人已回來、不需再提醒）。此為前景觸發（無背景 isolate），是本地通知在不依賴伺服器推播下的合理做法。

---

## 6. 文案清單（繁中、溫和、無工程字）

- **low_mood_care**（標題：小夥伴有點擔心你）
  - 小夥伴有點擔心你，想陪你說說話。
  - 聽起來你今天有點累，寵物想陪你一下。
  - 如果你願意，可以回來和寵物聊聊。
- **low_satiety**（標題：寵物肚子餓了）
  - 你的寵物肚子有點餓了，回來看看牠吧！
  - 小夥伴想吃點東西，也想看看你。
  - 寵物在等你回來照顧牠。
- **low_intimacy**（標題：寵物有點想你）
  - 你的寵物好像有點想你了，來陪牠聊聊天吧。
  - 今天還沒和寵物說說話，要不要回來看看牠？
  - 小夥伴在等你，想和你聊幾句。
- **inactive_interaction**（標題：今天還沒看到你）
  - 今天還沒看到你，寵物有點想你了。
  - 要不要打開 App，和寵物說幾句話？
  - 小夥伴在等你回來。

同一天固定一句、不同天輪替（`now.day % 3`），避免洗版又不重複。台語文案暫未強制（規格允許先用國語白話），列為後續可選。

---

## 7. 設定頁開關

設定頁「日常提醒」區新增 `SwitchListTile`「**寵物關心提醒**」，**預設開啟**：
- 開：在你較少互動，或寵物有點低落、肚子餓時，溫和提醒你回來陪牠。
- 關：不發送此類陪伴提醒，但**不影響每日簽到等必要提醒**。

開關狀態存於 `UserProfile.concernRemindersEnabled`（`LocalStorageService` 持久化、依帳號隔離），由 `ProfileController.setConcernRemindersEnabled` 切換。關閉時離開 App 不會排程關心提醒，並取消任何待發的。

---

## 8. 測試結果

- 新增 `test/services/pet_concern_notification_policy_test.dart`（純決策）：各類型觸發、情緒觸發、優先序、per-type cooldown、全體 cooldown、多條件擇一、無資料不亂發、缺資料不硬觸發、關閉不發。
- 新增 `test/services/notification_service_pet_concern_test.dart`（MethodChannel mock）：schedule/cancel 不 crash、與簽到提醒互不干擾。
- 新增 `test/services/concern_notification_storage_test.dart`：開關預設開啟可關閉存回、cooldown 紀錄空/round-trip、依帳號隔離。
- 既有 `notification_service_check_in_test.dart` / `check_in_reminder_schedule_test.dart` 全數通過（簽到提醒行為未變）。
- 結果：`flutter analyze` **No issues found**；`flutter test` **全部通過（619 tests）**。

---

## 9. 已知限制

- **每日簽到實際為 10:00**（非規格假設的 18:00），本 CR 未更動既有時間與邏輯。
- **inactivity 為前景最佳估計**：以「離開 App 當下、最近一次對話 turn 的時間」推估；無對話紀錄時不觸發 inactive（不以假資料硬觸發）。沒有背景 isolate，故無法在 App 完全未開啟時即時偵測，採「離開時排未來通知、回來時取消」模式。
- **關心提醒在離開 App 後 `scheduleDelay`（2h）才跳**：若長者很快回到 App 即被取消，屬預期（避免打擾）。
- 台語推播文案未強制新增（規格允許先用國語白話），列為後續可選。
- 未改 Telegram、Care Alert、Realtime 語音主流程、管理端分析頁、DB schema。
