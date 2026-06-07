<!--# CR-0026 Conversation Record Title and Delete 任務檔

## SECTION 01/08：任務背景

目前「對話紀錄」頁顯示的每則紀錄沒有清楚標題，看起來像直接把對話內容塞進卡片。使用者希望每次對話都像 ChatGPT 新聊天一樣，有一個簡短的聊天標題。

另外，前一次 Claude 誤解需求，以為是「點進對話後刪除整段或刪除某一句」。這次請注意：需求是「在對話紀錄列表中，長按某一則對話卡片，可以刪除該則對話紀錄」。

本次只處理：

1. 對話紀錄列表每則對話要有標題。
2. 長按列表中的某則對話紀錄，可以刪除該則紀錄。
3. 不處理詳細頁刪單句。
4. 不刪長期記憶。
5. 不碰 Realtime 主流程。

---

## SECTION 02/08：任務目標

請處理 CR-0026 conversation record title and delete。

目標：

1. 對話紀錄列表每則紀錄都有 title。
2. title 風格像 ChatGPT 的聊天標題，簡短、自然、可辨識。
3. title 不要直接顯示太長的原句。
4. 若沒有 title，依第一則使用者訊息產生 fallback title。
5. 若內容不足，顯示「未命名對話」。
6. 長按某則對話紀錄卡片時，顯示刪除確認視窗。
7. 點「刪除」後，只刪除該則對話紀錄。
8. 點「取消」不刪除。
9. 刪除後列表立即更新。
10. 不刪除長期記憶 MemoryService。
11. 不處理詳細頁單句刪除。

---

## SECTION 03/08：禁止修改範圍

不要混入以下內容：

1. RealtimeVoiceService 主流程
2. VoiceAgentController 狀態機
3. Agent tools
4. MemoryService 長期記憶刪除
5. DailyCareTask / 日常照護任務
6. 回憶拼圖
7. onboarding coach mark
8. pet skin
9. auth / admin
10. Care Alert / Telegram
11. pgvector / database migration
12. runtime data/*.json
13. raw assets
14. unrelated UI cleanup

不要 push。  
完成前不要 commit。  
測試通過後，只 commit CR-0026 相關檔案。

---

## SECTION 04/08：需要檢查的檔案範圍

請先找出對話紀錄相關程式：

可能包含：

- conversation history screen
- conversation record screen
- conversation detail screen
- conversation model
- conversation controller
- conversation local storage / API service
- records tab / bottom nav record page
- 相關測試

請先確認：

1. 對話紀錄列表資料從哪裡來。
2. 每一則紀錄目前的 id 是什麼。
3. 每一則紀錄目前是否已有 title 欄位。
4. 若沒有 title，是否可以新增 title。
5. 是否有 conversation session / thread / record 的概念。
6. 刪除一則紀錄應該刪哪個資料。
7. 刪除是否只影響對話紀錄，不影響長期記憶。

---

## SECTION 05/08：對話標題規則

每則對話紀錄需要顯示 title。

### A. title 優先順序

請依序使用：

1. 若 record.title 存在且非空，使用 record.title。
2. 若沒有 title，根據第一則使用者訊息產生簡短標題。
3. 若沒有使用者訊息，根據第一則訊息產生。
4. 若仍無法產生，使用「未命名對話」。

### B. title 生成規則

title 要簡短自然，像 ChatGPT 對話標題。

規則：

1. 建議 6～14 個中文字。
2. 不要太長。
3. 不要包含完整長句。
4. 不要包含標籤感英文，例如 lonely / neutral。
5. 不要包含工程字。
6. 不要包含「情緒：」「寵物心情：」這類 metadata。
7. 可以根據關鍵內容整理。

範例：

原句：

我覺得很累，又睡不著，怎麼辦？常常一個人。

title：

睡不好與孤單感

原句：

你會做什麼事？

title：

功能詢問

原句：

我今天想聽音樂。

title：

想聽音樂

原句：

提醒我晚上八點吃藥。

title：

吃藥提醒

若無法判斷：

未命名對話

### C. 顯示方式

對話紀錄列表卡片建議顯示：

1. title：較大、較粗
2. preview：一小段最近訊息或摘要
3. emotion / mood badge：若已有可保留
4. time：若已有可保留

不要讓英文 mood badge 變成主要 title。

---

## SECTION 06/08：長按刪除行為

在對話紀錄列表中，使用者長按某一則對話卡片時：

1. 顯示確認視窗。
2. 標題：刪除這則對話？
3. 內容：刪除後，這則對話紀錄會從列表中移除。
4. 按鈕：取消 / 刪除。
5. 點取消：不刪除。
6. 點刪除：刪除該則對話紀錄。
7. 刪除後列表立即更新。
8. 只刪除被長按的那一則。
9. 不刪除其他紀錄。
10. 不刪除長期記憶。
11. 不刪除 Care Alert。
12. 不刪除 DailyCareTask。

如果目前儲存層不支援 hard delete，請用 archive / hide 方式，讓列表不再顯示該紀錄。

### 重要釐清

本次不是：

- 不是點進對話詳細頁後刪整段。
- 不是刪除某一句訊息。
- 不是刪除 MemoryService 長期記憶。
- 不是清空所有對話紀錄。

本次是：

- 在對話紀錄列表中，長按某一則對話卡片，刪除該則紀錄。

---

## SECTION 07/08：測試要求

請加入或更新測試，至少覆蓋：

1. 對話紀錄有 title 時，列表顯示 title。
2. 對話紀錄沒有 title 時，會從第一則使用者訊息產生 fallback title。
3. 長句會被整理成短 title。
4. 無法產生 title 時顯示「未命名對話」。
5. title 不會顯示 lonely / neutral 這類 mood label。
6. title 不會顯示「情緒：」「寵物心情：」metadata。
7. 長按某一則對話卡片會顯示確認視窗。
8. 點取消不刪除。
9. 點刪除後只移除該則紀錄。
10. 刪除後其他紀錄仍存在。
11. 刪除對話紀錄不會刪除長期記憶。
12. flutter analyze 通過。
13. flutter test 通過。

如果有後端或 local storage 測試，也請補上。

---

## SECTION 08/08：Commit 與回報格式

通過後 commit，commit message 使用：

CR-0026 conversation record title and delete

不要 push。

完成後請回報：

完成內容
- 對話紀錄列表資料原本在哪裡
- title 如何產生
- 沒有 title 時如何 fallback
- 長按刪除如何實作
- 是否有確認視窗
- 是否只刪除該則紀錄
- 是否不影響長期記憶

修改檔案
- 檔案路徑與用途

測試結果
- flutter analyze
- flutter test
- 單檔測試

Commit
- commit hash
- commit message
- 是否 push：否

注意事項
- 是否需要實機確認
- 是否有任何和 Realtime / Memory / Agent / DailyCareTask / onboarding / pet skin 糾纏的檔案

---

## 完整性檢查要求

開始修改程式前，請先停止並回報：

1. 你是否讀到 SECTION 01/08 到 SECTION 08/08。
2. 你理解本次不是刪除詳細頁單句，而是長按列表卡片刪除該則對話紀錄。
3. 對話標題要如何產生。
4. 沒有 title 時如何 fallback。
5. 禁止修改範圍。
6. 預計檢查檔案。
7. 預計不碰哪些檔案。

如果缺任何 SECTION，請不要開始修改。-->