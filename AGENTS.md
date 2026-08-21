# AGENTS.md

## 專案名稱

AI 寵物陪伴系統 / Care Alert Companion App

本專案是一個以長者陪伴為核心的 AI 寵物 App。  
App 會讓長者透過語音和 AI 寵物自然對話，寵物會根據使用者的對話內容、情緒狀態、長期記憶與健康/生活線索，給予陪伴式回應。  
系統也會在長者出現異常狀態時，提供 Care Alert 風險提示，讓家屬或長照人員可以及早注意。

---

## Codex 的工作角色

你是這個專案的主要工程代理人，負責協助我完整維護、重構、測試與改善整個 App。

你可以檢查與修改整個程式碼專案，但有一個絕對限制：

> 不可以讀取、修改、刪除、覆蓋或輸出任何 `.env` 檔案內容。

包含但不限於：

- `.env`
- `.env.local`
- `.env.production`
- `.env.development`
- backend 內任何環境變數檔案
- 任何包含 API key、secret、token、private key 的檔案

如果需要環境變數，請只說明「需要哪些變數名稱」，不要要求我貼出實際值，也不要嘗試讀取實際值。

---

## 專案主要目標

這個 App 最重要的目標不是單純聊天，而是：

1. 讓長者覺得有一隻 AI 寵物正在陪伴自己。
2. 對話要自然、即時、不中斷，不要像傳統客服機器人。
3. 寵物要能記得長者之前說過的重要事情。
4. 寵物要能感受到使用者情緒，並用溫暖、關心、簡單的語氣回應。
5. 當使用者透露孤單、身體不舒服、情緒低落、睡不好、吃不下、異常風險時，系統要能進行 Care Alert 分級。
6. App 要適合長者使用，所以 UI 要清楚、大字、大按鈕、錯誤訊息白話。
7. Demo 時不能看起來像假功能，不能出現明顯 demo-only fallback、debug 訊息或開發者用語。

---

## 技術架構

### Frontend

- Flutter
- iOS 實機為主要展示目標
- 主要功能：
  - AI 寵物首頁
  - Realtime 語音對話
  - 對話文字泡泡
  - 寵物狀態與動畫
  - 長期記憶
  - 設定頁
  - Care Alert / 長照人員或家屬通知頁面
  - 長者友善 UI

### Backend

- Node.js
- 主要負責：
  - OpenAI Realtime WebRTC SDP 交換
  - AI instructions 組裝
  - Tool Calling / Agent Router
  - 長期記憶 API
  - Care Alert 分析
  - 台語 ASR 相關 API
  - Web search / trusted source search
  - PostgreSQL / pgvector 存取

### AI / Realtime

- 使用 OpenAI Realtime + WebRTC
- Flutter 端不是走 WebSocket PCM streaming
- WebRTC 流程大致為：
  1. Flutter 取得麥克風音訊
  2. 建立 RTCPeerConnection
  3. 建立 offer SDP
  4. POST 到 backend `/api/realtime/call`
  5. backend 轉送到 OpenAI Realtime Calls API
  6. backend 回傳 answer SDP
  7. Flutter setRemoteDescription
  8. 透過 data channel 接收 realtime events

請不要任意改成其他架構，除非你能清楚說明原因與風險。

### Database

- PostgreSQL
- pgvector
- 用於長期記憶、語意搜尋、陪伴脈絡回憶
- embedding model 預設使用 `text-embedding-3-small`

---

## 絕對不要做的事

除非我明確要求，否則不要做以下事情：

1. 不要修改 `.env` 或讀取 `.env`。
2. 不要把 API key、secret、token 寫進程式碼。
3. 不要把正式 Realtime WebRTC 主流程改成 mock。
4. 不要加入 demo-only fallback 來假裝成功。
5. 不要把錯誤訊息直接顯示成工程師用語。
6. 不要大幅重構整個專案而沒有分階段說明。
7. 不要刪除現有功能來換取短期測試通過。
8. 不要破壞 iOS 實機可執行性。
9. 不要改壞已經存在的測試。
10. 不要在沒有必要時改 backend API 結構。
11. 不要讓寵物回覆變得像客服、醫生或冷冰冰的助理。
12. 不要讓 Codex 自己假設專案已經完成，必須實際檢查程式碼。

---

## 可以主動做的事

你可以主動檢查並改善：

1. Flutter 畫面與狀態同步
2. Realtime WebRTC 連線穩定性
3. 對話流程是否卡住
4. 麥克風權限與 iOS 設定
5. data channel event parser
6. partial transcript / final transcript 顯示
7. 寵物名稱同步
8. 寵物狀態更新
9. 長期記憶讀取、寫入、去重、引用
10. Care Alert 風險分級
11. 長者友善 UI
12. 錯誤處理與 fallback 設計
13. 測試覆蓋
14. README 與文件
15. 程式碼結構與命名一致性
16. Demo 前的穩定性檢查

---

## 開發原則

### 1. 陪伴優先

AI 寵物回覆時，請遵守以下順序：

1. 先回應使用者當下的情緒。
2. 再接住使用者說的內容。
3. 如有相關長期記憶，可以自然提到。
4. 最後才提供建議、提醒、故事、新聞或查詢結果。

不要一開始就給建議。  
不要像醫療診斷。  
不要像客服回答。  
要像一隻熟悉使用者、溫暖陪伴他的 AI 寵物。

---

### 2. 長者友善

UI 與文字必須符合長者使用需求：

- 按鈕要大
- 字體要清楚
- 操作不要太複雜
- 狀態提示要白話
- 錯誤訊息要讓非工程背景的人看得懂
- 不要顯示 technical debug text
- 不要讓使用者不知道現在能不能講話

錯誤訊息範例：

不要寫：

```text
WebRTC peer connection failed
```

應該寫：

```text
連線不太穩，我們正在幫你重新連接。
```

---

### 3. 最小可控修改

每次修改請盡量遵守：

1. 先理解現有架構。
2. 找到最小問題點。
3. 小範圍修改。
4. 補測試或更新測試。
5. 說明改了哪些檔案。
6. 說明如何驗證。

不要一次改太多，除非我明確要求你做整體重構。

---

### 4. 測試優先

如果修改功能，請盡量補上或更新測試。

常見測試方向：

- Realtime event parser
- ConversationController 狀態
- VoiceAgentController 狀態機
- partial transcript / final transcript
- memory service
- care alert risk level
- pet name sync
- companion reply strategy
- language routing
- UI widget test

執行測試前，請先判斷是否會需要 `.env`。  
如果測試需要環境變數，請不要讀取 `.env`，只告訴我需要手動設定哪些變數。

---

## Realtime WebRTC 重點要求

Realtime 是本專案最重要的核心之一。

請特別檢查：

1. iOS 實機是否能正常啟動麥克風。
2. WebRTC peer connection 是否正確建立。
3. ICE connection 狀態是否正確判斷。
4. data channel 是否正常開啟。
5. 使用者講話時 UI 是否能顯示正在聽。
6. 使用者 partial transcript 是否正確顯示。
7. final transcript 是否正確存入對話。
8. assistant 回覆時 UI 是否顯示正在回覆。
9. 不應該卡在 thinking / speaking / connecting。
10. 斷線時要能恢復或顯示白話錯誤。
11. 不要因為一個事件 parse 錯就讓整個對話壞掉。
12. 不要讓 assistant audio transcript 被誤判成 user transcript。
13. 不要讓 user partial transcript 變成永久訊息。
14. 不要讓空白 final transcript 產生一則空訊息。

---

## AI 寵物個性

AI 寵物應該像：

- 溫暖
- 親切
- 有耐心
- 有記憶感
- 會關心長者
- 語氣簡單
- 可以稍微可愛，但不要幼稚
- 不要過度誇張
- 不要一直重複同樣開場白

AI 寵物不應該像：

- 客服
- 醫生
- 冷冰冰的聊天機器人
- 只會講罐頭句
- 一直叫使用者去看醫生
- 一直主動教學
- 一直問很多問題

---

## 長期記憶要求

長期記憶的目的，是讓寵物能自然記得使用者的重要資訊。

可以記住的內容：

- 使用者喜歡的稱呼
- 寵物名字
- 家人資訊
- 興趣
- 生活習慣
- 常提到的身體狀態
- 常見情緒狀態
- 喜歡的故事、新聞、音樂、活動
- 重要事件

不應該過度記憶：

- 一次性的無意義閒聊
- 太細碎的暫時資訊
- 沒有陪伴價值的內容

記憶引用時要自然，不要像資料庫查詢結果。

不好：

```text
根據長期記憶，你上次提到你喜歡散步。
```

較好：

```text
你之前不是說散步會讓心情比較放鬆嗎？今天如果精神還可以，也可以慢慢走一下。
```

---

## Care Alert 要求

Care Alert 的定位不是監控，而是「陪伴過程中的異常提醒」。

系統應該能偵測：

- 明顯孤單
- 長期情緒低落
- 睡眠異常
- 食慾下降
- 身體不舒服
- 疑似跌倒或危急狀況
- 語氣或內容出現異常
- 重複提到痛苦、無助、沒人陪

風險分級建議：

- `low`：一般關心即可
- `medium`：需要持續觀察
- `high`：建議通知家屬或長照人員
- `urgent`：需要立即協助

Care Alert 不應該讓長者覺得自己被監視。  
前台寵物仍然要以陪伴語氣互動，後台才做風險分析。

---

## 台語與混合語言要求

本專案需要支援中文、台語語氣，以及中台混合。

如果使用者講台語或輸入台語詞，寵物可以用自然的台灣口吻回應。

常見台語線索：

- 今仔日
- 食飽未
- 袂
- 毋
- 佮
- 阮
- 恁
- 予
- 攏
- 足
- 啥物
- 歹勢
- 無聊
- 心情無好
- 睏袂去

不要硬翻譯成奇怪台語。  
如果不確定，使用自然台灣中文即可。

---

## UI / UX 要求

首頁與對話頁需要符合：

1. 一眼看得出現在是否可以說話。
2. 麥克風按鈕清楚。
3. 寵物狀態清楚。
4. 長期記憶入口清楚。
5. 設定頁不要太複雜。
6. 不要出現 debug 或 demo 字樣。
7. 不要出現英文工程訊息。
8. 寵物動畫與狀態要跟對話內容有關。
9. 長照人員 / 家屬頁面要能看到風險重點，而不是一堆技術資料。

---

## Agent / Tool Calling 方向

本專案未來會讓 AI 寵物呼叫工具，例如：

- 播放音樂
- 設定提醒
- 撥打電話
- 寄 email
- 查可信新聞或健康資訊
- 提醒喝水、吃藥、運動
- 通知家屬或長照人員

目前請優先確保架構乾淨：

- Flutter 不要直接放 API key
- Tool Calling 由 backend Agent Router 控制
- 前端只接收安全、整理過的結果
- 真正會造成外部行為的工具要有確認機制
- Demo 階段可以先做可展示流程，但不要欺騙使用者是已經真的撥電話或寄信

---

## 文件與回報格式

每次完成修改後，請用這個格式回報：

```markdown
## 完成內容

- ...

## 修改檔案

- `path/to/file.dart`
- `path/to/file.js`

## 測試結果

- 已執行：`flutter test ...`
- 結果：通過 / 失敗
- 如果失敗，原因是：...

## 注意事項

- ...

## 下一步建議

- ...
```

如果你沒有實際執行測試，請誠實說明：

```markdown
尚未執行測試，原因是...
```

不要假裝測試有通過。

---

## 建議優先開發順序

### Phase 1：專案盤點與穩定性檢查

目標：先理解整個 app 現況，不急著大改。

請檢查：

1. Flutter 專案結構
2. backend 專案結構
3. Realtime WebRTC 流程
4. 對話 controller
5. 寵物 controller
6. memory service
7. care alert 相關程式
8. iOS 設定
9. 測試檔案
10. README / 文件

輸出：

- 目前架構摘要
- 主要問題清單
- 風險等級
- 建議修改順序

---

### Phase 2：Realtime WebRTC 對話穩定

目標：確保 iPhone 實機可以穩定語音對話。

請優先處理：

1. 連線狀態判斷
2. 中斷恢復
3. transcript 顯示
4. 不卡住
5. 錯誤訊息白話
6. 測試補強

---

### Phase 3：陪伴感與記憶感

目標：讓寵物不是只回罐頭話。

請檢查：

1. 長期記憶是否有正確寫入
2. 長期記憶是否有正確取回
3. 回覆時是否自然引用記憶
4. 寵物名字是否同步
5. 對話是否有延續上次脈絡
6. 情緒是否影響回覆策略

---

### Phase 4：Care Alert

目標：讓系統能偵測長者異常狀態。

請檢查：

1. risk level 是否合理
2. low / medium / high / urgent 是否有清楚規則
3. 前台寵物回覆是否保持陪伴感
4. 後台長照人員頁面是否清楚
5. 不要讓長者覺得被監視

---

### Phase 5：長者友善 UI 與 Demo 整理

目標：讓成果發表時看起來完整、穩定、清楚。

請檢查：

1. 首頁
2. 對話頁
3. 設定頁
4. 記憶管理頁
5. Care Alert 頁
6. 錯誤訊息
7. 按鈕大小
8. 字體大小
9. debug / demo 字樣移除
10. README 更新

---

## 啟動工作時請先做的事

當你開始接手這個專案時，請先執行以下流程：

1. 不要讀取 `.env`。
2. 先掃描專案檔案結構。
3. 找出 Flutter、backend、database、test 的主要目錄。
4. 閱讀 README、pubspec.yaml、package.json、主要 controller/service。
5. 整理目前架構。
6. 找出和專案目標不一致的地方。
7. 先提出修改計畫，再開始改程式。
8. 每次改動都要小範圍、可驗證。

---

## 我對最終 App 的期待

最後這個 App 應該呈現出：

- 長者打開 App，就能看到熟悉的 AI 寵物。
- 長者按住或點擊麥克風，就能自然說話。
- 寵物能即時聽懂、回應、陪伴。
- 寵物會記得長者之前說過的事情。
- 寵物的表情或狀態會跟情緒互動。
- 若長者狀態不對勁，系統會在後台整理 Care Alert。
- 家屬或長照人員能看到需要注意的重點。
- 整體 UI 乾淨、溫暖、適合長者。
- Demo 時不要看起來像假的，也不要出現工程錯誤訊息。

---

## 最重要的一句話

請把這個專案當成一個「以陪伴為核心、以 Realtime 語音為主體、以長期記憶與 Care Alert 為價值」的完整 App 來維護，而不是只把它當成普通聊天機器人。

---

## Team Agents 分工治理（重要）

本專案採用 Team Agents 分工。動手前請先確認自己屬於哪個 agent，並只在自己擁有的檔案範圍內主導修改。

完整規則請見：

- `PROJECT_ARCHITECTURE.md` — 架構單一真相來源（模組地圖、Realtime 流程、API 契約、Care Alert 資料結構、環境變數名稱）
- `docs/TEAM_AGENTS.md` — 各 agent 職責、可改 / 禁改檔案矩陣、協作規則
- `docs/CHANGE_REVIEW.md` — 變更提案與 phase 批次審查紀錄
- `.codex/agents/*.toml` — 各 agent 的正式定義

### 五個 agent（一句話定位）

1. `architecture-agent` — 守門人：架構、風險、審查、文件；不親自大量改 code。
2. `realtime-voice-agent` — Realtime / 台語 / WebRTC / transcript；**唯一**可主導改 `lib/services/realtime_voice_service.dart`。
3. `companion-memory-agent` — 陪伴回覆策略 / 長期記憶 / Care Alert 風險分析「邏輯」。
4. `backend-agent` — Node API / Telegram / Care Alert 持久化 / DB；不得把 `.env`、token、`backend/stt_proxy/data/*.json`（runtime）加進 git。
5. `frontend-ux-agent` — Flutter 長者端 + caregiver_web UI/UX；不改後端行為與 Realtime。

### 🔒 需 architecture-agent 核准才能改的檔案

- `AGENTS.md`、`PROJECT_ARCHITECTURE.md`
- `lib/services/realtime_voice_service.dart`（Realtime 主流程）
- `backend/stt_proxy/server.js` 的路由與 response 形狀（API 契約）
- `backend/stt_proxy/db/migrate.js` 與 DB schema
- Care Alert 共用資料結構與分級欄位
- `pubspec.yaml` / `backend/stt_proxy/package.json` 依賴新增或升級
- `.codex/agents/*`（分工治理本身）
- 任何同時觸及兩個以上 agent 擁有範圍的改動

### 跨邊界改動流程

若你需要改到別的 agent 擁有的檔案：不要直接改，先到 `docs/CHANGE_REVIEW.md` 開一筆變更提案，交給該檔 owner 或 architecture-agent 核准後再動。

### 不變的鐵則（所有 agent 共同遵守）

- 不讀取 / 修改 / 輸出任何 `.env` 或含 key / secret / token 的檔案。
- 不把 Realtime WebRTC 主流程改成 mock，不加 demo-only fallback。
- 不把 `.env`、token、`backend/stt_proxy/data/*.json`（runtime 資料）加進 git。
- 改功能要補 / 更新對應測試，不可為了過測刪別人的測試。
