<!--# CR-0019 Memory Greeting UX 任務檔

## SECTION 01/09：任務背景

目前首頁寵物開場問候會引用長期記憶，但實機畫面出現不自然的句子，例如：

> 我還記得使用者提到「所有的。」可能需要情緒支持。，今天也陪你慢慢聊。

這個句子有幾個問題：

1. 「使用者提到」不像寵物會說的話，太像系統摘要。
2. 「所有的。」是低品質、不完整片段，不應該被當成長期記憶引用。
3. 「可能需要情緒支持」像分類標籤，不適合直接顯示給長者。
4. 標點與語氣不自然。
5. 首頁一打開就硬翻記憶，容易讓使用者覺得怪或被監控。
6. 長期記憶應該默默輔助陪伴，而不是把後端摘要直接講出來。

本次目標是修正「首頁長期記憶問候」的 UX 與記憶品質篩選。

---

## SECTION 02/09：任務目標

請處理 CR-0019 memory greeting UX。

目標：

1. 長期記憶仍可用於首頁問候。
2. 但首頁問候必須先過濾低品質記憶。
3. 不可直接顯示後端記憶摘要或分類標籤。
4. 不可出現「使用者提到」「情緒支持」「記憶資料」「系統判斷」等工程感語句。
5. 問候要像寵物自然說話。
6. 沒有高品質記憶時，使用一般問候。
7. 情緒類記憶要溫柔處理，不要標籤化使用者。
8. 不要每次開 App 都硬引用記憶；只有高品質、適合開場的記憶才引用。
9. 保留既有長期記憶架構，不要另開新的記憶系統。
10. 不要改 pgvector / JSON fallback 主流程。

---

## SECTION 03/09：已完成背景

目前已完成並已 commit：

- CR-0012 pet skin
- CR-0013 voice turn control
- CR-0013b voice button wiring
- CR-0014 conversation strategy
- CR-0015a agent intent result model
- CR-0015b agent tool execution
- CR-0015c agent integration tests
- CR-0016 onboarding coach mark
- CR-0017 pet skin remaining UI wiring
- CR-0018 turn-based realtime conversation
- docs: pgvector demo setup guide

本次只處理 CR-0019 memory greeting UX。

---

## SECTION 04/09：禁止修改範圍

請不要混入以下內容：

1. RealtimeVoiceService 主流程
2. turn-based realtime conversation
3. voice button wiring
4. Agent tools
5. onboarding / coach mark
6. pet skin ownership / purchase
7. auth / OAuth / login backend
8. admin backend
9. Care Alert / Telegram API
10. pgvector / database migration / database env 設定
11. runtime data/*.json
12. raw assets
13. docs noise
14. shop UI
15. pet status panel UI
16. unrelated home_screen WIP

不要 push。

完成前不要 commit。  
等測試確認後，最後只 commit CR-0019 memory greeting UX 相關檔案。

---

## SECTION 05/09：需要檢查的檔案範圍

請先檢查和首頁問候、長期記憶引用相關的程式碼。

可能包含：

- `lib/screens/home_screen.dart`
- `lib/controllers/memory_controller.dart`
- `lib/controllers/conversation_controller.dart`
- `lib/controllers/voice_agent_controller.dart`
- `lib/services/memory_service.dart`
- `backend/stt_proxy/services/memory/*`
- `backend/companion/*`
- companion greeting / prompt builder 相關檔案
- 任何產生首頁 greeting bubble / pet greeting / opening message 的程式
- 相關測試

請先找出：

1. 首頁寵物問候文字在哪裡產生。
2. 首頁問候是否直接引用 MemoryService 回傳內容。
3. 是否有 memory summary / care summary / emotion summary 被直接放進 UI。
4. 哪裡產生「我還記得使用者提到……」這種句子。
5. 哪裡產生「可能需要情緒支持」這種分類語句。
6. 哪裡決定 App 開啟時顯示哪一句 greeting。
7. 是否已有 memory confidence / importance / category / archived 欄位可用於篩選。
8. 是否已有 fallback greeting。

---

## SECTION 06/09：記憶問候規則

### A. 不可直接引用低品質記憶

首頁問候不可引用以下記憶：

1. 太短的內容。
2. 只有一兩個詞。
3. 只有語助詞或無意義片段。
4. 沒有主詞、事件或可理解語意。
5. ASR 誤辨內容。
6. 只有「好的」「嗯」「所有的」「不知道」「可以」「那個」等片段。
7. 只有分類標籤，例如「需要情緒支持」。
8. 內容像 metadata，例如 riskLevel、emotion、category、summary。
9. 已 archived 的記憶。
10. 信心分數過低的記憶。
11. 內容含工程字或內部欄位。
12. 內容會讓使用者覺得被監控或不舒服。

低品質例子：

- 所有的。
- 好的。
- 嗯。
- 不知道。
- 需要情緒支持。
- 使用者有負面情緒。
- riskLevel high。
- emotion sadness。
- 可能需要照護。
- 使用者提到某事。
- transcript unclear。

這些都不應出現在首頁問候中。

---

### B. 可用於首頁問候的高品質記憶

可以引用以下類型：

1. 家人與人際關係  
   例：女兒週末會回來、兒子住台北、孫子喜歡打籃球。

2. 喜好  
   例：喜歡老歌、不喜歡太甜、喜歡狐狸。

3. 日常習慣  
   例：每天晚上八點吃藥、早上會去公園散步、睡前喜歡聽故事。

4. 近期重要事件  
   例：最近要去醫院、女兒要來看他、最近想整理照片。

5. 溫和情緒脈絡  
   例：最近有點孤單、晚上睡不好、想念朋友。  
   但首頁問候不能直接揭露或貼標籤。

---

### C. 首頁問候語氣規則

問候必須像寵物自然說話。

禁止出現：

- 使用者提到
- 根據記憶
- 記憶資料
- 系統
- 分析
- 情緒支持
- 風險
- 標籤
- metadata
- API
- JSON
- database
- payload
- toolName
- pgvector
- fallback

不要說：

> 我還記得使用者提到「……」

應改成：

> 你之前說……

或更自然：

> 今天也想陪你慢慢聊聊。

---

### D. 情緒類記憶的處理

情緒類記憶要特別保守。

不要說：

- 你之前很孤單。
- 你需要情緒支持。
- 我知道你最近狀態不好。
- 系統判斷你需要陪伴。
- 你有負面情緒。

可以說：

- 今天也想陪你慢慢聊聊。你現在心情還好嗎？
- 我在這裡陪你，今天想先聊聊什麼？
- 今天想輕鬆聊聊，還是先休息一下？

情緒記憶可以影響語氣，但不要直接暴露成標籤。

---

### E. 沒有高品質記憶時

如果沒有可用記憶，使用一般問候。

建議 fallback 問候：

- 準備好開始今天的陪伴了嗎？
- 今天想先跟我聊聊什麼？
- 我在這裡，今天也陪你慢慢聊。
- 今天想聊天、聽故事，還是設定提醒呢？

不要為了使用長期記憶而硬引用低品質片段。

---

## SECTION 07/09：問候範例

### A. 沒有可用記憶

輸出：

> 準備好開始今天的陪伴了嗎？

或：

> 今天想先跟我聊聊什麼？

---

### B. 喜好記憶

記憶：

> 使用者喜歡聽老歌。

首頁問候：

> 你之前說喜歡聽老歌，今天想聽一點輕鬆的嗎？

---

### C. 家人記憶

記憶：

> 女兒週末會回來看他。

首頁問候：

> 你之前說女兒週末會回來，今天有想跟她聊聊嗎？

---

### D. 日常習慣

記憶：

> 使用者每天晚上八點吃藥。

首頁問候：

> 晚上吃藥的提醒我會幫你記著，今天也慢慢來。

若提醒系統還沒有接好，不要假裝已設定提醒。可以改成：

> 你之前提過晚上要吃藥，今天需要我晚點提醒你嗎？

---

### E. 情緒記憶

記憶：

> 使用者最近常覺得孤單。

首頁問候：

> 今天也想陪你慢慢聊聊。你現在心情還好嗎？

不要輸出：

> 我記得你最近很孤單。

---

### F. 低品質記憶

記憶：

> 所有的。

首頁問候：

> 準備好開始今天的陪伴了嗎？

不要輸出：

> 我還記得你提到「所有的」。

---

## SECTION 08/09：實作要求

請完成：

1. 找出首頁 greeting 產生邏輯。
2. 新增或強化 memory greeting filter。
3. 低品質記憶不可進入首頁 greeting。
4. archived memory 不可進入首頁 greeting。
5. 若有 confidence / score / importance 欄位，低於安全門檻不可用於 greeting。
6. 若無品質欄位，請用內容規則做基本過濾。
7. 新增或強化 memory-to-greeting formatter。
8. formatter 要把記憶轉成自然寵物語氣。
9. 不可直接把 memory summary 原文塞進 UI。
10. 情緒記憶只能產生溫和問候。
11. 沒有合格記憶時使用 fallback greeting。
12. 不要另開新的 memory store。
13. save_memory / recall_memory 仍沿用既有 MemoryService。
14. 不要改 pgvector / JSON fallback 主流程。
15. 不要修改 runtime data/*.json。
16. 如果有後端與前端兩處都可能產生 greeting，請避免重複產生或彼此矛盾。
17. 若首頁 greeting 是由後端產生，請在後端修；若是前端組字，請在前端修；若兩邊都有，請優先維持架構一致。

---

## SECTION 09/09：測試、Commit 與回報格式

請加入或更新測試，至少覆蓋：

1. 低品質記憶「所有的。」不會出現在首頁問候。
2. 低品質記憶「嗯」「好的」「不知道」不會出現在首頁問候。
3. 問候不會出現「使用者提到」。
4. 問候不會出現「情緒支持」。
5. 問候不會出現「記憶資料」「系統」「分析」等工程字。
6. 有高品質家人記憶時，可以自然引用。
7. 有高品質喜好記憶時，可以自然引用。
8. 有高品質日常習慣記憶時，可以自然引用，但不可假裝已設定提醒。
9. 情緒記憶只用溫和問候，不直接標籤使用者。
10. archived memory 不會被引用。
11. 沒有可用記憶時，使用一般 fallback 問候。
12. 首頁 greeting 不會直接顯示 raw memory summary。
13. flutter analyze 通過。
14. flutter test 通過。
15. 若改 backend，請跑相關 node test 或 npm test。

通過後 commit，commit message 使用：

CR-0019 memory greeting UX

不要 push。

回報格式：

完成內容
- 首頁 greeting 原本在哪裡產生
- 低品質記憶如何過濾
- 高品質記憶如何轉成自然問候
- 情緒記憶如何避免標籤化
- 沒有可用記憶時如何 fallback
- 是否有改後端 / 前端 / 兩者都有

修改檔案
- 檔案路徑與用途

測試結果
- flutter analyze
- flutter test
- backend memory / companion 測試或單檔測試

Commit
- commit hash
- commit message
- 是否 push：否

注意事項
- 是否需要實機確認
- 是否有任何和 Realtime / Agent / onboarding / pet skin / auth-admin 糾纏的檔案

---

## 完整性檢查要求

開始修改程式前，請先停止並回報：

1. 你是否讀到 SECTION 01/09 到 SECTION 09/09。
2. 你理解目前錯誤句子的問題。
3. 禁止出現在首頁 greeting 的詞語。
4. 低品質記憶判斷規則。
5. 高品質記憶可引用類型。
6. 情緒記憶的保守處理方式。
7. 預計檢查的檔案。
8. 預計不碰哪些檔案。

如果缺任何 SECTION，請不要開始修改。-->