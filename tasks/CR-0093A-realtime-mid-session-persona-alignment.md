# CR-0093A — Realtime Mid-session Persona Alignment

## 目標

同步 `lib/services/realtime_voice_service.dart` 內的 mid-session / session.update 縮版語音 persona，讓它與 CR-0090 已完成的後端語音 persona 自然度規則一致。

本 CR 是 CR-0090 的後續小修，目標是避免 Realtime session 中途更新時，使用到舊版、較制式、較容易重複或較硬轉任務的縮版 persona。

---

## 背景

CR-0090 已完成：

```text
Companion Conversation Naturalness Polish
```

主要改動集中於後端：

```text
backend/stt_proxy/server.js
COMPANION_CHAT_PERSONA
REALTIME_INSTRUCTIONS
outputLanguageInstruction
```

已加入：

```text
陪伴優先
避免重複
不要每次硬轉提醒 / 喝水 / 吃藥 / 任務
低落時先陪伴、不過度醫療化
台語以自然口語、長者聽得懂為主
```

但 CR-0090 回報中有一項後續事項：

```text
lib/services/realtime_voice_service.dart 內仍有一份 mid-session persona 縮版副本，僅供 session.update 使用，尚未同步 CR-0090 的自然度措辭。
```

因為 `realtime_voice_service.dart` 是 🔒 鎖定檔，所以 CR-0090 依規定未碰。本 CR 專門處理這個小範圍同步。

---

## 重要限制

`lib/services/realtime_voice_service.dart` 是 🔒 鎖定檔。

本 CR 必須先走 architecture-agent 審查，取得核准後才能修改。

請先提交審查內容，包含：

1. 需要修改的原因。
2. 預計修改的常數 / 字串 / 區塊。
3. 確認不修改 SDP / ICE / DataChannel / WebRTC 連線 / response lifecycle。
4. 確認不修改 tool calling / tool routing / audio playback / caption sync。
5. 確認只是同步 persona 文字，不改 API 契約與狀態機。

未取得核准前，不得直接修改 `realtime_voice_service.dart`。

---

## 範圍

### 本 CR 要做

- 盤點 `realtime_voice_service.dart` 內 mid-session / session.update 使用的 persona 或 instruction 字串。
- 將該縮版 persona 與 CR-0090 的自然度規則對齊。
- 保留現有語音功能、台語模式、安全邊界與工具能力。
- 新增或更新測試。
- 新增文件並更新 `docs/CHANGE_REVIEW.md`。
- 宣告下一個可用 CR 仍依主線遞增，建議為 `CR-0093` 或依 CHANGE_REVIEW 目前狀態決定。

### 本 CR 不做

- 不改後端 persona；CR-0090 已完成。
- 不改 Realtime 連線主流程。
- 不改 SDP / ICE / DataChannel。
- 不改字幕同步；CR-0089 已完成。
- 不改寵物素材；CR-0088 已完成。
- 不改推播；CR-0087 已完成。
- 不改紀錄頁；CR-0091 已完成。
- 不改新手導覽；CR-0092 已完成。
- 不改 Care Alert / Telegram。
- 不改工具功能。
- 不改 App icon。
- 不讀 `.env`。

---

## 可能涉及檔案

預期只需要小範圍修改：

```text
lib/services/realtime_voice_service.dart
test/realtime_voice_service_test.dart
docs/REALTIME_MID_SESSION_PERSONA_ALIGNMENT_CR0093A.md
docs/CHANGE_REVIEW.md
```

若需要修改更多檔案，請先說明原因，不要擴大範圍。

---

## Part A — 盤點現有 mid-session persona

請先找出 `realtime_voice_service.dart` 中 session.update 使用的 persona / instructions。

可能關鍵字：

```text
session.update
instructions
persona
Taigi
台語
Realtime
companion
```

請在文件中寫明：

```text
該字串目前用途
何時會被送出
是否只影響 mid-session update
是否與後端起始 session instructions 不同
```

---

## Part B — 同步 CR-0090 自然度規則

請將縮版 persona 補上 CR-0090 的關鍵規則，但保持簡短，避免 session.update payload 過長。

至少包含：

```text
陪伴優先，先接住情緒。
回覆簡短自然，通常 1～3 句。
避免重複同一句開頭或罐頭安慰。
不要每次都以「聽起來...」開頭。
不要每次都結尾問問題。
不要硬轉提醒、喝水、吃藥或任務，除非長者明確提出或情境明確需要。
低落、孤單、疲倦時先陪伴，不急著解決。
不要做醫療診斷或保證療效。
高風險內容仍遵守安全邊界。
台語模式以自然口語、長者聽得懂為主，可國台語混用，不硬翻生僻字。
```

---

## Part C — 保留既有功能

同步 persona 時必須確認不破壞：

```text
台語模式
語音回覆
工具路由
提醒工具
Care Alert 風險處理
字幕同步
audio playback stopped / started 事件
session.update 發送流程
```

本 CR 只能改 persona 文字或最小必要匯出測試輔助，不應改狀態機。

---

## Part D — 測試要求

請依現有 Flutter 測試架構補測。

至少涵蓋：

1. mid-session persona 包含「避免重複」規則。
2. mid-session persona 包含「不硬轉提醒 / 任務」規則。
3. mid-session persona 包含「低落先陪伴、不過度醫療化」規則。
4. 台語 session.update persona 包含「自然口語、長者聽得懂、可國台語混用」規則。
5. 不影響既有 `realtime_voice_service_test.dart`。
6. 不影響 CR-0089 新增的 audio started / stopped 事件測試。
7. `flutter analyze` 通過。
8. `flutter test` 通過。

若該 persona 目前無法被測試取到，請用最小方式抽出 helper 或 const 供測試，不要大改服務流程。

---

## 手動驗收建議

實機測試：

```text
進入語音模式
切換台語 / 國語模式
連續問：
- 我今天有點累
- 我昨晚睡不好
- 我覺得有點孤單
- 今天天氣不錯
- 等一下提醒我吃藥
```

觀察：

```text
回覆是否更自然
是否不再硬轉任務
是否不一直重複同一句
提醒需求仍能正常使用工具
字幕同步仍正常
語音連線仍正常
```

---

## 文件要求

請新增：

```text
docs/REALTIME_MID_SESSION_PERSONA_ALIGNMENT_CR0093A.md
```

內容至少包含：

1. 修改動機。
2. 鎖定檔審查紀錄。
3. 修改位置。
4. 同步的 CR-0090 規則。
5. 測試結果。
6. 已知限制。

請更新：

```text
docs/CHANGE_REVIEW.md
```

新增：

```text
## CR-0093A — Realtime Mid-session Persona Alignment
```

並說明：

```text
此 CR 是 CR-0090 後續小修，使用 A 編號避免打亂主線 CR-0093。
```

下一個主線 CR 仍建議為：

```text
CR-0093 — App Icon Replacement
```

除非 CHANGE_REVIEW 已另行宣告不同編號。

---

## 建議執行指令

```bash
flutter analyze
flutter test
```

若未改後端，不需要跑 backend npm 測試。

---

## 驗收標準

完成後需符合：

- architecture-agent 已核准修改 `realtime_voice_service.dart`。
- mid-session persona 與 CR-0090 自然度規則一致。
- 不修改 Realtime 連線主流程。
- 不修改 SDP / ICE / DataChannel / response lifecycle。
- 不影響 CR-0089 字幕同步。
- 不影響工具與提醒功能。
- 不降低安全邊界。
- 台語模式語氣更自然、長者聽得懂。
- Flutter analyze 通過。
- Flutter tests 通過。
- 文件與 CHANGE_REVIEW 更新完成。

---

## 注意事項

- 不要讀 `.env`。
- 不要改後端 persona，除非發現 CR-0090 遺漏且需先回報。
- 不要改 tool routing。
- 不要改 Care Alert / Telegram。
- 不要改字幕同步。
- 不要更換 App icon。
- 不要把 session.update persona 寫得過長。
- 不要移除安全規則。
- 未經 architecture-agent 核准，不得修改鎖定檔。
