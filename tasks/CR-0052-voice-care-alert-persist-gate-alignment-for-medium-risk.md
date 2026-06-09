# CR-0052 — Voice Care Alert Persist Gate Alignment for Medium Risk

## 1. 任務定位

本任務接續 CR-0051。

CR-0051 已完成：

- 打字聊天 `/api/companion/chat` 接上情緒 / 風險分析
- typed chat medium/high/urgent 會進入 Care Alert 流程
- high/urgent 會依既有規則通知
- typed chat 使用正式四級 risk level：`low / medium / high / urgent`
- typed chat 不再產生 legacy `attention`
- 長者端不顯示監控感文案

目前殘留一致性問題：

> 語音端 `voice_agent_controller.dart:871` 目前只在 `needsHumanSupport == true` 時送 `/api/care-alerts/notify`，實際等同只送 high/urgent。  
> 這代表 medium 風險在打字聊天會持久化，但在語音聊天可能不會持久化，造成資料記錄與管理端分析不一致。

本 CR 目標是對齊語音與打字聊天的 Care Alert persist gate，使 medium 風險語音也會進入 Care Alert 紀錄，但維持通知規則不變。

---

## 2. 本次目標

完成 voice care alert persist gate alignment：

1. 語音路徑 medium/high/urgent 都應送 `/api/care-alerts/notify`。
2. low 仍不送 notify 或依既有規則處理。
3. high/urgent 繼續觸發通知。
4. medium 只建立 Care Alert 紀錄，不應造成 Telegram 洗版。
5. 不破壞 Realtime WebRTC。
6. 不破壞 CR-0045 `/notify` caller auth。
7. 不破壞 CR-0051 typed chat risk integration。
8. risk level 繼續使用正式四級：`low / medium / high / urgent`。
9. 補測試覆蓋語音 medium persist、high/urgent notify、low 不送。

---

## 3. 必讀文件

請先閱讀：

- `CLAUDE.md`
- `docs/CHANGE_REVIEW.md`
- `docs/TYPED_CHAT_CARE_ALERT_FLOW.md`
- `docs/COMPANION_PERSONA.md`
- `docs/SAFETY_BOUNDARIES.md`
- `lib/controllers/voice_agent_controller.dart`
- `lib/services/care_alert_notification_service.dart`
- `lib/services/realtime_voice_service.dart`
- `backend/stt_proxy/server.js`
- `backend/stt_proxy/services/careAlert*`
- CR-0045 `/api/care-alerts/notify` tests
- CR-0051 typed chat Care Alert tests
- voice_agent_controller 相關測試

---

## 4. 先盤點

修改前請先盤點並回報：

1. `voice_agent_controller.dart:871` 附近的 gate 條件。
2. `needsHumanSupport` 目前如何計算。
3. 語音風險資料中是否有 `riskLevel`。
4. 語音路徑是否仍有 legacy `attention`。
5. `CareAlertNotificationService.notify()` 目前 payload 需要哪些欄位。
6. Flutter 語音端是否已帶 Authorization Bearer idToken。
7. `/notify` backend 是否會 server-side 權威覆寫 elderId。
8. 後端 `/notify` 是否已 persist-always。
9. 後端 notification 是否只 high/urgent 推播。
10. 現有測試是否只覆蓋 high/urgent。

---

## 5. 架構裁決事項

請由 architecture-agent 或架構守門人先確認：

1. 語音端 medium 是否應建立 Care Alert 紀錄。
   - 建議：是。
2. 語音端 medium 是否應通知 Telegram。
   - 建議：否，除非後端現有規則另有設定。
3. 語音端 low 是否應送 `/notify`。
   - 建議：否。
4. `needsHumanSupport` 是否繼續只代表 high/urgent。
   - 建議：保留語意，不要把 medium 混進去。
5. 是否新增獨立 predicate，例如：
   - `shouldPersistCareAlert`
   - `shouldNotifyCaregiver`
6. risk level 權威值是否維持：
   - `low`
   - `medium`
   - `high`
   - `urgent`

裁決需寫入 `docs/CHANGE_REVIEW.md`。

---

## 6. Flutter 語音端需求

### 6.1 Gate 拆分

目前若只有：

```dart
if (!needsHumanSupport) return;
```

請改成語意更清楚的雙 gate：

- `shouldPersistCareAlert`
- `needsHumanSupport` 或 `shouldNotifyCaregiver`

建議方向：

```dart
final shouldPersistCareAlert = riskLevel == 'medium' || riskLevel == 'high' || riskLevel == 'urgent';

if (!shouldPersistCareAlert) return;

await careAlertNotificationService.notify(...);
```

注意：實際寫法請依現有型別與資料結構調整。

### 6.2 Notification 規則

Flutter 只負責送出 Care Alert 建立請求，不應自行決定 Telegram 推播細節。

後端應維持：

- medium：persist，不推播或依既有規則
- high：persist + notify
- urgent：persist + notify

### 6.3 Auth

確認語音端送 `/notify` 時仍帶 Bearer idToken。

不得：

- 使用 hardcoded token
- 使用 fake token
- 信任 client elderId
- 略過 CR-0045 auth

---

## 7. Backend 需求

理想上本 CR 不需要改後端，除非發現：

1. `/notify` 不接受 medium。
2. `/notify` 把 medium 錯誤 mapping 成 low / attention。
3. `/notify` medium 會錯誤觸發 Telegram。
4. backend tests 未覆蓋 medium persist。

若需後端改動：

- 必須不破壞 CR-0045 auth。
- 必須不破壞 CR-0051 typed chat flow。
- 必須補測試。

---

## 8. UI / UX 要求

不得在長者端顯示：

- 「已建立警示」
- 「系統已通知照護人員」
- 「你被記錄了」
- raw risk level
- Care Alert JSON

除非現有產品已有溫和設計。

建議維持零監控感；Care Alert 是照護端流程。

---

## 9. 測試需求

### 9.1 Flutter Tests

至少新增或更新：

1. 語音 medium risk 會呼叫 `CareAlertNotificationService.notify()`。
2. 語音 high risk 仍會呼叫 notify。
3. 語音 urgent risk 仍會呼叫 notify。
4. 語音 low risk 不呼叫 notify。
5. `needsHumanSupport` 語意不被混淆。
6. medium 不顯示監控感 UI 文案。
7. notify request 仍帶 auth token。
8. notify 401/403 不阻斷 Realtime 對話。
9. Realtime 相關既有測試仍通過。
10. CR-0051 typed chat tests 不受影響。

### 9.2 Backend Tests

若改後端，至少確認：

1. `/notify` medium 授權請求會建立 alert。
2. `/notify` medium 不觸發 Telegram。
3. `/notify` high/urgent 仍觸發 Telegram。
4. `/notify` low 行為符合既有規則。
5. `/notify` auth 仍有效。
6. 新資料 risk level 不出現 `attention`。

---

## 10. 文件需求

請更新：

- `docs/CHANGE_REVIEW.md`
- `docs/TYPED_CHAT_CARE_ALERT_FLOW.md`
- `docs/SAFETY_BOUNDARIES.md`
- `docs/STORE_RELEASE_CHECKLIST.md`

如需要，新增：

- `docs/VOICE_CARE_ALERT_FLOW.md`

文件需說明：

1. 語音與打字聊天的 Care Alert 一致性。
2. medium 會持久化但不推播的設計原因。
3. high/urgent 通知規則。
4. 為何長者端不顯示監控感文案。
5. `needsHumanSupport` 與 `shouldPersistCareAlert` 的差異。

---

## 11. 限制

本 CR 不得：

1. 破壞 Realtime WebRTC。
2. 破壞 CR-0045 `/notify` caller auth。
3. 破壞 CR-0051 typed chat risk integration。
4. 把 medium 直接當 high/urgent 推播。
5. 讓 low 大量建立 alert 造成噪音。
6. 使用 legacy `attention` 作為新 alert level。
7. 使用 fake token / hardcoded elderId。
8. 在長者端顯示監控感文案。
9. 為了通過測試關閉通知。
10. 大量重寫 voice controller unrelated code。

---

## 12. 驗收標準

完成後必須符合：

1. 語音 medium 會建立 Care Alert。
2. 語音 medium 不會造成 Telegram 洗版。
3. 語音 high/urgent 仍通知。
4. 語音 low 不送 notify 或符合既有規則。
5. `/notify` auth 不被破壞。
6. typed chat flow 不被破壞。
7. risk level 仍為 `low / medium / high / urgent`。
8. 長者端無監控感 UI。
9. Flutter analyze 通過。
10. Flutter 相關測試通過。
11. 後端若改動則 backend tests 全綠。
12. CHANGE_REVIEW 已更新。

---

## 13. 完成回報格式

請用以下格式回報：

```md
## CR-0052 完成回報

### 1. 本次目標
-

### 2. 修改檔案
-

### 3. 架構裁決
-

### 4. 語音現有 gate 盤點
-

### 5. Flutter gate 改動
-

### 6. Backend 行為確認 / 改動
-

### 7. UI / UX 結果
-

### 8. 測試結果
-

### 9. 正式版風險檢查
- 語音 medium 是否持久化：
- medium 是否誤推播：
- high/urgent 是否仍通知：
- low 是否仍安靜：
- /notify auth 是否未破壞：
- typed chat 是否未破壞：
- 是否有監控感 UI：
- 是否仍出現 attention：

### 10. 殘留風險
-

### 11. 下一個建議 CR
-
```
