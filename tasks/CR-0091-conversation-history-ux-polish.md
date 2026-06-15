# CR-0091 — Conversation History UX Polish

## 目標

改善長者端「紀錄／對話紀錄」頁面的使用體驗，移除工程化欄位與技術字眼，並新增搜尋對話功能，讓長者或展示者可以更容易查看過去和寵物的互動內容。

本 CR 的重點是「紀錄頁 UX 與搜尋」，不處理 AI 對話自然度、字幕同步、寵物素材、推播、後台分析或 App icon。

---

## 背景

目前系統已完成：

```text
CR-0086 — Caregiver Analytics Dashboard
CR-0087 — Pet Concern Push Notifications
CR-0088 — Mochi Pet Asset Integration and Pet State Trigger Expansion
CR-0089 — Voice Caption Synchronization Polish
CR-0090 — Companion Conversation Naturalness Polish
```

接下來要處理長者端紀錄頁問題：

```text
1. 紀錄介面仍可能顯示「情緒」、「寵物心情」等偏工程或分析欄位。
2. 長者不需要看到 emotionTag、riskLevel、petMood 等技術資訊。
3. 紀錄多了之後不容易找過去講過的內容。
4. 需要新增搜尋對話功能，方便用關鍵字找過去的對話。
```

---

## 核心原則

紀錄頁應該像長者可以看懂的「陪伴紀錄」，不是工程除錯頁。

應該呈現：

```text
日期
時間
長者說了什麼
寵物回了什麼
簡短摘要或友善標籤
搜尋功能
空狀態提示
```

不應該直接呈現：

```text
emotionTag
petMood
riskLevel
JSON
debug
agent route
tool call
raw API response
confidence score
```

---

## 範圍

### 本 CR 要做

- 盤點目前紀錄頁顯示內容與資料來源。
- 移除或轉譯工程字眼。
- 新增對話搜尋功能。
- 支援搜尋空結果提示。
- 支援清除搜尋。
- 保留既有紀錄資料讀取流程。
- 補測試與文件。
- 更新 `docs/CHANGE_REVIEW.md`。

### 本 CR 不做

- 不改 AI persona；CR-0090 已處理。
- 不改語音字幕同步；CR-0089 已處理。
- 不改寵物素材與狀態；CR-0088 已處理。
- 不改推播通知；CR-0087 已處理。
- 不改後台分析頁；CR-0086 已處理。
- 不改 Care Alert / Telegram。
- 不新增 DB schema，除非現有資料完全無法搜尋且需先回報理由。
- 不讀 `.env`。
- 不把 raw 情緒分析 JSON 顯示給長者。

---

## 可能涉及檔案

請先盤點，實際檔名以專案為準。

可能涉及：

```text
lib/screens/history_screen.dart
lib/screens/record_screen.dart
lib/screens/conversation_history_screen.dart
lib/widgets/conversation_history_card.dart
lib/widgets/history_search_bar.dart
lib/controllers/conversation_controller.dart
lib/controllers/history_controller.dart
lib/services/conversation_history_service.dart
lib/models/conversation_turn.dart
lib/models/conversation_record.dart
lib/services/local_storage_service.dart
```

請以 grep / code search 確認實際檔案，不要硬建立重複頁面。

---

## Part A — 盤點紀錄頁現況

請先盤點目前紀錄頁：

```text
入口在哪裡
頁面檔案在哪裡
資料來源是本地還是後端
是否同時顯示語音與打字紀錄
是否顯示情緒 / 寵物心情 / 風險
是否顯示 raw enum / raw key
是否已有搜尋或篩選
```

並在文件中寫明。

---

## Part B — 移除工程字眼

### B1. 不要顯示 raw technical fields

請移除或轉譯以下字眼：

```text
emotionTag
emotion
petMood
riskLevel
risk_score
confidence
agent route
tool call
debug
JSON
API
null
undefined
```

如果目前 UI 有顯示：

```text
情緒：sad
寵物心情：low
風險：medium
```

請改成長者友善版本，或直接隱藏。

---

### B2. 建議轉譯方式

若仍需保留簡單狀態提示，可轉成友善文字。

範例：

```text
sad -> 那天心情有點低落
happy -> 那天心情不錯
neutral -> 那天狀態平穩
anxious -> 那天有些擔心
tired -> 那天比較累
```

寵物狀態可轉成：

```text
hungry -> 寵物想吃點東西
thirsty -> 寵物想喝水
caring -> 寵物正在關心你
happy -> 寵物很開心
sleepy -> 寵物有點想休息
```

但請注意：長者紀錄頁不一定需要顯示這些狀態。若顯示會讓畫面雜亂，建議隱藏，只保留對話內容。

---

### B3. 避免醫療化與警示化

紀錄頁不要把一般情緒顯示得像診斷。

避免：

```text
偵測到憂鬱風險
負面情緒指數
高風險心理狀態
```

較佳：

```text
那天聊到比較低落的心情
寵物有多陪你一下
```

Care Alert 相關嚴肅資訊應主要顯示在照護者後台，不要在長者紀錄頁造成壓力。

---

## Part C — 新增搜尋對話功能

### C1. 搜尋入口

請在紀錄頁上方新增搜尋框。

建議 placeholder：

```text
搜尋對話內容
```

或：

```text
搜尋和寵物聊過的內容
```

不要用：

```text
Search conversation JSON
Filter by emotionTag
```

---

### C2. 搜尋範圍

搜尋至少應涵蓋：

```text
長者說的話
寵物回覆
對話摘要（若有）
日期文字（可選）
```

如果資料結構支援，也可涵蓋：

```text
提醒文字
任務文字
```

但不要搜尋或顯示 raw JSON technical fields。

---

### C3. 搜尋行為

建議：

```text
即時搜尋或按 Enter 搜尋皆可，依現有 UI 風格決定。
大小寫不敏感。
支援中文關鍵字。
支援台語文字關鍵字。
搜尋結果高亮可選，不強制。
```

基本互動：

```text
輸入關鍵字 → 顯示符合紀錄
清除搜尋 → 回到全部紀錄
沒有結果 → 顯示友善空狀態
```

---

### C4. 空狀態

沒有紀錄時：

```text
還沒有對話紀錄，之後和寵物聊天會出現在這裡。
```

搜尋沒有結果時：

```text
找不到相關對話，換個關鍵字試試看。
```

錯誤時：

```text
紀錄暫時載入失敗，稍後再試一次。
```

不要顯示 raw exception 或 stack trace。

---

## Part D — 搜尋實作策略

### D1. 若紀錄目前在前端本地

若對話紀錄已載入到前端 list，資料量不大，請優先使用本地搜尋。

優點：

```text
改動小
不需改後端
不需改 API
測試容易
```

---

### D2. 若紀錄來自後端且資料量大

若目前紀錄是分頁後端查詢，請評估是否新增 query 參數。

例如：

```text
GET /api/conversations?query=...
```

但本 CR 優先避免擴大後端 API。若必須改 API，請說明原因並補測試。

---

### D3. 避免影響既有紀錄載入

搜尋不應破壞：

```text
原本紀錄排序
日期分組
載入更多
刪除紀錄
點進紀錄詳情
語音 / 打字紀錄區分
```

若目前沒有這些功能，則不需新增。

---

## Part E — UI 建議

紀錄卡片建議呈現：

```text
日期 / 時間
你說：......
寵物說：......
```

或更自然：

```text
你和寵物聊到：
「我今天有點累」
寵物回你：
「先慢慢來，我陪你一下。」
```

如果空間有限，顯示摘要即可，點擊後看完整內容。

搜尋框建議：

```text
左側放搜尋 icon
右側有清除 x
文字大小長者友善
觸控區域足夠
```

---

## Part F — 測試要求

請依現有 Flutter 測試架構新增或更新測試。

至少涵蓋：

1. 紀錄頁不顯示 raw engineering fields。
2. `emotionTag` / `riskLevel` / `petMood` 不會直接出現在 UI。
3. 有紀錄時可正常顯示對話內容。
4. 輸入關鍵字可搜尋長者文字。
5. 輸入關鍵字可搜尋寵物回覆。
6. 搜尋無結果時顯示友善空狀態。
7. 清除搜尋後恢復全部紀錄。
8. 中文關鍵字可搜尋。
9. 台語文字關鍵字可搜尋（若資料存在）。
10. 不影響既有紀錄載入測試。
11. 錯誤狀態不顯示 raw exception / stack trace。

如果目前沒有 widget test，請至少抽出搜尋 filter 純函式測試。

---

## 手動驗收

請在模擬器或實機確認：

```text
打開紀錄頁
確認沒有工程字眼
確認看得懂每筆紀錄
搜尋「累」
搜尋「吃藥」
搜尋「寵物」
搜尋不存在的字
清除搜尋
切換頁面再回來
```

確認：

```text
搜尋結果正確
空狀態友善
畫面不 overflow
文字不太小
長者看得懂
```

---

## 文件要求

請新增：

```text
docs/CONVERSATION_HISTORY_UX_CR0091.md
```

內容至少包含：

1. 問題盤點。
2. 紀錄頁資料來源。
3. 移除 / 轉譯的工程字眼。
4. 搜尋功能設計。
5. 空狀態與錯誤狀態。
6. 測試結果。
7. 已知限制。

請更新：

```text
docs/CHANGE_REVIEW.md
```

新增：

```text
## CR-0091 — Conversation History UX Polish
```

並宣告下一個可用 CR：

```text
CR-0092
```

---

## 建議執行指令

如果只改 Flutter：

```bash
flutter analyze
flutter test
```

若有改後端 API，才需要：

```bash
cd backend/stt_proxy
npm test
npm run check
```

---

## 驗收標準

完成後需符合：

- 紀錄頁不再顯示工程字眼。
- 情緒、寵物心情、風險等 raw key 不直接顯示給長者。
- 紀錄頁可搜尋對話。
- 中文與台語文字搜尋可正常處理。
- 搜尋無結果有友善提示。
- 清除搜尋可恢復全部紀錄。
- 不影響既有紀錄載入與刪除功能。
- Flutter analyze 通過。
- 相關 Flutter tests 通過。
- 新增文件 `docs/CONVERSATION_HISTORY_UX_CR0091.md`。
- 更新 `docs/CHANGE_REVIEW.md` 並宣告 CR-0092。

---

## 注意事項

- 不要讀 `.env`。
- 不要改 AI persona；CR-0090 已處理。
- 不要改 Realtime / 字幕同步；CR-0089 已處理。
- 不要改寵物素材；CR-0088 已處理。
- 不要改推播；CR-0087 已處理。
- 不要改後台分析頁；CR-0086 已處理。
- 不要把 raw 情緒分析 JSON 顯示給長者。
- 不要讓紀錄頁變成除錯頁。
- 如果必須新增後端搜尋 API，請先說明原因並補 API 測試。
