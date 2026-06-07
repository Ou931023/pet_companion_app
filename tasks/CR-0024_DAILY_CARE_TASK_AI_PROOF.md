<!--# CR-0024 Daily Care Task AI Proof Verification 任務檔

## SECTION 01/10：任務背景

目前 App 裡有「日常提醒」入口，但日常照護任務功能尚未完整。

我們需要讓長者可以完成日常照護任務，例如：

- 吃藥
- 喝水
- 運動
- 散步

長者完成任務後，可以拍照或從圖庫選照片上傳。系統需要使用 AI 影像辨識自動檢查照片是否符合該任務類型，例如：

- 吃藥任務：照片中是否有藥包、藥盒、藥丸、藥袋等藥品相關物件。
- 喝水任務：照片中是否有水杯、水瓶、飲水相關畫面。
- 運動任務：照片中是否像散步、戶外活動、運動器材或運動場景。

AI 判斷通過後，任務可自動標記完成。AI 不確定時，任務要進入 needs_review，讓管理者端 / 長照人員人工查看。

本功能是長者端與管理者端的重要閉環：

長者端提醒任務 → 長者拍照上傳 → AI 影像辨識 → 任務狀態更新 → 管理者端查看狀態。

---

## SECTION 02/10：任務目標

請處理 CR-0024 daily care task AI proof verification。

目標：

1. 長者端 App 有清楚的「今日任務 / 日常任務」功能。
2. 任務至少支援吃藥、喝水、運動三類。
3. 長者完成任務後，可以拍照或從圖庫選照片。
4. 照片送到後端後，後端使用 AI Vision 進行任務類型確認。
5. AI 判斷通過後，自動標記任務 completed。
6. AI 判斷不確定時，標記 needs_review，管理者端可查看。
7. AI 判斷不符合時，標記 rejected 或 needs_review，避免誤判。
8. 管理者端可以看到任務狀態、照片、AI 判斷結果、信心分數與原因。
9. 不要假裝 AI 能確認使用者真的吃下藥，只能確認照片中是否有相關物件或場景。
10. 不要把日常任務塞進長期記憶頁。
11. 不要破壞現有 Reminder / Memory / Care Alert / Agent 架構。

---

## SECTION 03/10：重要安全限制

AI 影像辨識只能作為照護任務輔助確認，不能做醫療診斷或藥物正確性判斷。

### 吃藥任務禁止說法

不要顯示：

- AI 已確認你真的吃藥成功。
- AI 已確認藥物正確。
- AI 已確認劑量正確。
- 這就是你的藥，請放心服用。

可以顯示：

- 照片看起來有藥品相關物品，我先幫你記錄完成。
- 這張照片看起來像是吃藥任務的完成證明。
- 這張照片我看不太清楚，先送給照護人員確認。

### 喝水任務禁止說法

不要顯示：

- AI 已確認你喝了多少水。
- AI 已確認你喝完水。

可以顯示：

- 照片看起來有水杯或水瓶，我先幫你記錄。
- 這張照片看起來像是喝水任務的完成證明。

### 運動任務禁止說法

不要顯示：

- AI 已確認你完成足夠運動量。
- AI 已確認你運動達標。

可以顯示：

- 照片看起來像有活動一下，我先幫你記錄。
- 這張照片我看不太清楚，先送給照護人員確認。

---

## SECTION 04/10：已完成背景

目前已完成：

- Realtime 一人一句語音
- 對話策略
- AI Agent 工具
- 長期記憶問候 UX
- 13 步導覽
- 寵物換皮
- 回憶拼圖
- Care Alert / Telegram
- 管理者端基礎 Care Alert
- pgvector Demo setup 文件

本次只處理「日常照護任務 + 拍照上傳 + AI 影像辨識確認 + 管理者端任務狀態」。

---

## SECTION 05/10：禁止修改範圍

不要混入以下內容：

1. RealtimeVoiceService 主流程
2. 對話策略核心 prompt
3. Agent intent 主架構
4. 長期記憶儲存主流程
5. pgvector / database migration 無關部分
6. 寵物換皮購買流程
7. 回憶拼圖
8. onboarding coach mark
9. auth / OAuth 主流程
10. Care Alert / Telegram 主流程
11. runtime data/*.json
12. raw assets
13. .env

不要 push。

完成前不要 commit。  
通過測試後，最後只 commit CR-0024 相關檔案。

---

## SECTION 06/10：長者端 App 功能要求

請建立或補完整長者端「今日任務 / 日常任務」功能。

### A. 任務列表

長者端需要能看到今日任務，例如：

- 吃藥
- 喝水
- 運動

每張任務卡片顯示：

1. 任務名稱
2. 任務類型
3. 預定時間
4. 狀態
5. 完成按鈕
6. 若需要照片證明，顯示「拍照完成」

狀態顯示文案：

- 待完成
- 已送出
- 已完成
- 等待照護人員查看
- 未通過
- 已逾時

### B. 拍照或選照片

長者點擊「拍照完成」後：

1. 可使用相機拍照，或從圖庫選照片。
2. 顯示照片預覽。
3. 使用者按「送出」。
4. 上傳照片到後端。
5. 後端 AI Vision 回傳確認結果。
6. App 依結果更新任務狀態。

若使用者取消選圖：

- 不要 crash。
- 回到任務頁。

若權限不足：

- 顯示白話提示：需要相機或照片權限，才能上傳完成照片。

### C. AI 結果顯示

AI 判斷通過：

- 任務狀態：已完成
- 寵物文案：做得很好，我幫你記錄完成了。

AI 不確定：

- 任務狀態：等待照護人員查看
- 寵物文案：這張照片我看不太清楚，先送給照護人員確認。

AI 判斷不符合：

- 任務狀態：等待照護人員查看或未通過
- 寵物文案：這張照片好像不太符合任務，我們再確認一下。

---

## SECTION 07/10：後端 AI Vision 要求

請檢查現有 backend 是否已有 care task / reminder / task store。

如果已有，請沿用。  
如果沒有，請建立最小可用資料結構與 API。

### A. 建議資料模型

CareTask:

- id
- elderId
- title
- type
- description
- scheduledTime
- dueAt
- status
- proofRequired
- createdAt
- updatedAt

TaskSubmission:

- id
- taskId
- elderId
- proofImageUrl 或 safe local path
- submittedAt
- status
- aiVerificationStatus
- aiConfidence
- aiReason
- detectedObjects
- reviewRequired
- note

任務狀態：

- pending
- submitted
- completed
- needs_review
- rejected
- missed

AI 驗證狀態：

- passed
- uncertain
- failed

### B. API 建議

1. GET /api/care-tasks?elderId=...
   - 取得長者任務列表

2. POST /api/care-tasks
   - 建立任務

3. POST /api/care-tasks/:id/submit
   - 上傳完成照片並觸發 AI Vision

4. PATCH /api/care-tasks/:id/status
   - 管理者或系統更新任務狀態

5. GET /api/admin/care-tasks
   - 管理者端查看所有任務狀態

### C. AI Vision 行為

請新增 AI Vision 驗證服務，例如：

careTaskVisionService

輸入：

- taskType: medication / hydration / exercise
- image
- elderId
- taskId

輸出：

- verificationStatus: passed / uncertain / failed
- confidence: number
- reason: string
- detectedObjects: string[]
- reviewRequired: boolean

### D. AI 判斷規則

#### medication / 吃藥

應尋找：

- 藥包
- 藥盒
- 藥丸
- 藥袋
- 藥杯
- 服藥相關物件

判斷通過條件：

- 照片明確包含藥品相關物件
- confidence >= 建議門檻，例如 0.7

#### hydration / 喝水

應尋找：

- 水杯
- 水瓶
- 飲水容器
- 飲用水相關畫面

判斷通過條件：

- 照片明確包含水杯或水瓶
- confidence >= 建議門檻，例如 0.7

#### exercise / 運動

應尋找：

- 散步場景
- 運動器材
- 戶外活動
- 運動姿勢
- 健走、活動相關畫面

判斷通過條件：

- 照片明確符合活動或運動任務
- confidence >= 建議門檻，例如 0.65

### E. 不確定處理

若 AI 回傳不確定：

- 不要直接完成任務。
- status = needs_review。
- reviewRequired = true。
- 管理者端可以查看照片與 AI 原因。

### F. 沒有 AI key 或 AI 失敗

如果缺少 AI key 或 AI Vision 呼叫失敗：

- 不要 crash。
- status = needs_review。
- reviewRequired = true。
- reason = 影像確認暫時無法完成，已送照護人員查看。
- 不要標記 completed。

不要使用會誤導的 demo-only fake passed。

---

## SECTION 08/10：管理者端功能要求

管理者端 / caregiver_web 需要看到任務進行狀態。

請新增或補完整「日常任務追蹤」區塊。

管理者可看到：

1. 長者姓名 / elderId
2. 今日任務數量
3. 已完成數
4. 未完成數
5. 逾時數
6. 等待查看數
7. 任務類型：吃藥、喝水、運動
8. 任務狀態
9. 完成時間
10. AI 判斷狀態
11. AI 信心分數
12. AI 原因
13. 照片證明縮圖或查看入口

篩選建議：

- 全部
- 待完成
- 已完成
- 等待查看
- 已逾時
- 未通過

若 caregiver_web 目前是靜態前端，請以最小破壞方式接 API 或 mock-safe fallback。  
不要假裝後端不存在。

---

## SECTION 09/10：和現有功能的關係

### A. 與長期記憶

日常任務不是長期記憶。

不要把每次喝水、吃藥照片都存成長期記憶。  
只有重要習慣或偏好才可能進 MemoryService，例如：

- 使用者每天晚上八點吃藥。
- 使用者喜歡飯後散步。

### B. 與提醒

日常任務可以和 Reminder 系統整合。

若已有提醒功能，請讓任務顯示提醒時間或建立提醒。  
不要另開完全重複的提醒系統。

### C. 與 AI Agent

Agent 可以建立任務，例如：

- 晚上八點提醒我吃藥。
- 每天早上提醒我喝水。

但本次不要重寫 Agent intent 架構，只接必要工具或資料流。

### D. 與 Care Alert

任務長期未完成可以在未來作為風險指標。  
本次可先記錄狀態，不一定要直接觸發 Care Alert。  
若已有安全規則，請沿用，不要亂觸發 Telegram。

---

## SECTION 10/10：測試、Commit 與回報格式

請加入或更新測試，至少覆蓋：

1. 長者端可取得今日任務列表。
2. 任務卡片顯示名稱、時間、狀態。
3. 使用者可拍照或選擇照片作為完成證明。
4. 取消選圖不 crash。
5. 上傳後觸發 AI Vision 驗證。
6. 吃藥照片含藥品相關物件時可 passed。
7. 喝水照片含水杯或水瓶時可 passed。
8. 運動照片含活動場景時可 passed。
9. AI 不確定時 status = needs_review。
10. AI 失敗或缺 key 時 status = needs_review，不 crash。
11. 不會假裝藥物正確或劑量正確。
12. 管理者端可看到任務狀態。
13. 管理者端可看到 AI 判斷結果與信心分數。
14. 管理者端可看到 completed / pending / needs_review / missed 分類。
15. 日常任務不會被直接存成長期記憶。
16. 照片完成證明不會被 commit 成 raw asset。
17. flutter analyze 通過。
18. flutter test 通過。
19. 後端相關 node test 通過。
20. caregiver_web 若有測試，也要通過。

通過後 commit，commit message：

CR-0024 daily care task AI proof verification

不要 push。

回報格式：

完成內容
- 長者端日常任務如何實作
- 拍照 / 圖庫上傳如何處理
- AI Vision 如何確認吃藥 / 喝水 / 運動
- AI 不確定或失敗時如何處理
- 任務狀態如何更新
- 後端 API / store 如何設計
- 管理者端如何查看任務狀態與 AI 結果
- 是否有和 Reminder / Memory / Agent / Care Alert 串接

修改檔案
- 檔案路徑與用途

測試結果
- flutter analyze
- flutter test
- backend test
- caregiver_web test

Commit
- commit hash
- commit message
- 是否 push：否

注意事項
- 是否需要實機確認相機 / 照片權限
- 是否需要實機確認 AI Vision API
- 是否有任何和 Realtime / Agent / onboarding / pet skin / auth-admin 糾纏的檔案

---

## 完整性檢查要求

開始修改程式前，請先停止並回報：

1. 你是否讀到 SECTION 01/10 到 SECTION 10/10。
2. 你理解本次功能是日常照護任務，不是長期記憶。
3. 長者端任務流程。
4. 拍照完成證明流程。
5. AI Vision 對吃藥 / 喝水 / 運動分別要確認什麼。
6. AI 不確定或失敗時如何處理。
7. 管理者端要看到哪些任務狀態與 AI 結果。
8. 不可假裝 AI 已確認藥物正確或劑量正確。
9. 禁止修改範圍。
10. 預計檢查檔案。
11. 預計不碰哪些檔案。

如果缺任何 SECTION，請不要開始修改。-->