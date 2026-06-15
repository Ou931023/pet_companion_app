# CR-0091 — Conversation History UX Polish

長者端「對話紀錄」頁去工程化 + 新增本地搜尋：移除直接顯示的 `emotionTag` / `petMood` 等 raw key，改成長者友善的心情描述；新增可搜尋長者話與寵物回覆的搜尋框，含友善空狀態。純前端、未動後端 / Realtime / persona。

---

## 1. 問題盤點

| 問題 | 位置 |
|---|---|
| 對話詳情每則下方直接顯示 `情緒：${emotionTag}｜寵物心情：${petMood}`（如「情緒：sad｜寵物心情：neutral」） | `lib/screens/conversation_detail_screen.dart` |
| 紀錄列表每張卡片右側用 `Chip` 直接顯示 `emotionTag` 原值（sad / neutral…） | `lib/widgets/conversation_session_tile.dart` |
| 紀錄多了不好找過去講過的內容（無搜尋） | `lib/screens/history_screen.dart` |

其餘 `emotionTag` / `riskLevel` 參照（`home_screen.dart`、`agent_confirmation_sheet.dart`）皆為**邏輯用途**（CR-0088 短暫狀態觸發、工具風險樣式 switch），未顯示給長者，本 CR 不動。

---

## 2. 紀錄頁資料來源

- **入口**：底部分頁「對話紀錄」→ `HistoryScreen`（列表）→ 點一則進 `ConversationDetailScreen`（詳情）。
- **資料來源**：**本地**。`ConversationController.sessionSummaries`（每則對話摘要）與 `history`（所有 turn，含 `userText` / `petReply` / `emotionTag` / `sessionId` / `timestamp`），由 `LocalStorageService`（SharedPreferences）讀取，**同步、無後端 API**。
- 同時涵蓋語音與打字紀錄（都進同一個 `_history`）。
- 因資料在前端本地且量不大 → 依任務 D1 採**前端本地搜尋，未新增後端 API**。

---

## 3. 移除 / 轉譯的工程字眼

新增純函式 `lib/utils/conversation_history_display.dart` `friendlyMoodLabel(emotionTag)`：

| emotionTag | 顯示 |
|---|---|
| happy | 心情不錯 |
| sad | 有點低落 |
| lonely | 有點孤單 |
| anxious | 有些擔心 |
| tired | 比較累 |
| angry | 有些不開心 |
| neutral / 空 / 不認得（含 riskLevel、petMood 等 raw key） | **null → 不顯示** |

- **對話詳情**：刪整段那行由「情緒：sad｜寵物心情：neutral　·　長按這行刪整段」改為「那天有點低落　·　長按這行可刪整段」；neutral 時只剩「長按這行可刪整段」。刪整段的長按操作保留。
- **紀錄卡片**：右側 chip 改顯示友善心情（如「有點低落」）；neutral / 不認得時**不顯示 chip**（畫面更乾淨）。
- **不醫療化 / 不警示化**（B3）：只用「有點低落 / 比較累」這類白話，不出現「負面情緒指數 / 高風險心理狀態」等字眼；Care Alert 嚴肅資訊仍只在照護者後台。

---

## 4. 搜尋功能設計（本地）

- **入口**：紀錄頁標題下方搜尋框，placeholder「搜尋和寵物聊過的內容」，左側放大鏡 icon、右側清除 ✕（有輸入才出現），字級 18 長者友善。
- **搜尋邏輯**：`filterConversationSessions(sessions, allTurns, query)`（純函式）——比對 session 標題、最後預覽，以及該 session 內每一則的**長者說的話**與**寵物回覆**。
  - 大小寫不敏感（英文）；中文與**台語漢字**皆為純文字 substring 比對 → 中文 / 台語關鍵字都可搜。
  - query 去空白後為空 → 回全部（維持原排序）。
- **互動**：輸入即時過濾；清除 ✕ → 回到全部；不破壞既有排序、刪除、點進詳情、語音 / 打字混合紀錄。
- 不搜尋、不顯示任何 raw JSON / technical field。

---

## 5. 空狀態與錯誤狀態

| 狀態 | 文案 |
|---|---|
| 沒有任何紀錄 | 「還沒有對話紀錄」＋「之後和寵物聊天，內容會出現在這裡。」（不顯示搜尋框） |
| 搜尋無結果 | 「找不到相關對話」＋「換個關鍵字試試看。」 |
| 詳情整段被刪光 | 「這段對話的紀錄都刪完了。」 |

**錯誤狀態**：紀錄為本地同步讀取（`sessionSummaries` / `history` getter 不丟例外）→ 無 async 載入失敗路徑，畫面不會出現 raw exception / stack trace。刪除失敗則以白話 SnackBar 提示（既有行為）。

---

## 6. 測試結果

- 新增 `test/utils/conversation_history_display_test.dart`：`friendlyMoodLabel`（情緒轉白話、neutral / raw key → null、回傳值絕不等於原 enum）；`filterConversationSessions`（空查詢回全部、搜長者話、搜寵物回覆、搜標題 / 預覽、**台語漢字**、英文大小寫不敏感、無結果空清單）。
- 更新 / 新增 `test/conversation_controller_ui_state_test.dart`：詳情刪整段測試改用新友善文案；新增 HistoryScreen 搜尋 widget 測試（搜長者話 / 寵物回覆、清除恢復全部、**畫面無 raw `neutral` / `sad`**、搜尋無結果 → 友善空狀態）。
- 結果：`flutter analyze` **No issues**；`flutter test` **684 passed / 0 failed**。

---

## 7. 已知限制

- 搜尋為 substring 比對，無模糊比對 / 注音 / 拼音；台語以**漢字文字**比對（與資料儲存一致），不做台羅 / 拼音轉換。
- 日期文字搜尋未納入（任務列為可選）；提醒 / 任務文字若已存在於 turn 的 `userText` / `petReply` 即可被搜到，未額外抓工具 metadata。
- 紀錄卡片心情 chip 取 session 摘要的 `emotionTag`（既有計算），neutral 時不顯示；本 CR 未改該摘要的情緒計算邏輯。
- 未動 AI persona（CR-0090）、Realtime / 字幕同步（CR-0089）、寵物素材 / 狀態（CR-0088）、推播（CR-0087）、Care Alert / Telegram、後台分析頁（CR-0086）、後端 / DB。
