# 長期記憶展示驗證流程

這份文件用於畢業專題報告與現場展示「AI 老人陪伴寵物 App」的長期記憶系統。展示重點是：寵物能從對話中記住使用者明確提到、且有助於陪伴的內容，並在後續對話中自然使用，同時讓使用者可以在設定頁查看與刪除記憶。

## 一、長期記憶功能簡介

長期記憶分成四個階段完成：

Phase A 是記憶儲存基礎。後端使用 PostgreSQL 搭配 pgvector，建立 `companion_memories` 與 `memory_events`，保存記憶摘要、記憶類型、重要性、信心分數、embedding、使用次數與事件紀錄。若 PostgreSQL 無法使用，系統會自動切換到 JSON fallback，讓展示不會中斷。

Phase B 是 AI 自動抽取記憶。每輪對話後，後端會判斷使用者是否明確說出值得長期保存的資訊，例如偏好、生活習慣、睡眠狀態、提醒事項或照護需求。普通寒暄、太短的句子、AI 推測、醫療診斷與敏感身份推斷不會被保存。

Phase C 是記憶召回與 prompt 注入。當使用者下次送出訊息時，系統會產生該訊息的 embedding，搜尋語意相近的長期記憶，再根據相似度、重要性與近期性排序。只有相關度足夠的記憶會被放進 AI 回覆脈絡，讓寵物自然延續使用者的近況與偏好。

Phase D 是簡單記憶管理與隱私控制。使用者可以在 Flutter App 的設定頁進入「管理長期記憶」，查看目前寵物記得什麼，也可以按「忘記這筆」刪除不想保留的記憶。

## 二、系統如何從對話中抽取記憶

使用者完成一輪對話後，前端或後端會背景呼叫 `/api/memories/extract`。這個 API 會把 `userText`、`agentReply`、情緒、sessionId 與 turnId 送到 Memory Extractor。

Memory Extractor 會先判斷這句話是否值得記住。會保存的例子包含：

- 偏好：我喜歡聽台灣地方故事。
- 生活習慣：我每天早上會去散步。
- 情緒狀態：我最近常覺得孤單。
- 提醒事項：我明天要去醫院。
- 照護需求：我常常忘記喝水，可以提醒我嗎。
- 健康生活：我最近晚上都睡不好，白天很沒精神。

不會保存的例子包含：

- 普通寒暄：你好、哈哈、嗯嗯、謝謝。
- 一次性閒聊：今天天氣不錯。
- 使用者沒有明確說出口的 AI 推測。
- 醫療診斷或敏感身份推斷。

如果 `OPENAI_API_KEY` 可用，系統會優先使用 AI 做結構化判斷；如果 Key 不存在或 API 失敗，會改用 rule-based fallback，確保對話流程不會被記憶功能拖垮。

## 三、如何使用 embedding 與 pgvector 儲存

當某段對話被判定值得保存後，系統會產生一句 `memorySummary`，例如：

```text
使用者最近晚上睡不好，白天精神較差。
```

接著後端使用 `text-embedding-3-small` 將摘要轉成 1536 維 embedding，並寫入 PostgreSQL 的 `companion_memories.embedding` 欄位。pgvector 讓系統可以做語意相似搜尋，而不是只做關鍵字比對。

例如使用者下次問「給我一個睡眠健康小知識」，文字上不完全等於「晚上睡不好」，但 embedding 語意接近，因此可以召回睡眠相關記憶。

若 PostgreSQL 或 pgvector 不可用，系統會改用：

```text
backend/stt_proxy/data/companion_memories.json
backend/stt_proxy/data/memory_events.json
```

JSON fallback 僅供開發與展示備援使用，API 的 `provider` 會回傳 `json_fallback`。

## 四、如何在下次對話召回相關記憶

使用者送出新訊息時，系統會先呼叫 `/api/memories/context`：

1. 產生 userText embedding。
2. 用 pgvector 搜尋相似記憶。
3. 用 similarity、importance、recency 做混合排序。
4. 只保留達到門檻的記憶。
5. 組成短版 `memoryContext` 注入 AI prompt。
6. 更新 `use_count`、`last_used_at`，並記錄 `used_in_prompt` 事件。

排序概念：

```text
finalScore = similarity * 0.60
           + importanceScore * 0.25
           + recencyScore * 0.15
```

系統不會每次都硬用記憶。若相似度太低、重要性不足，或問題和記憶無關，`memoryUsed` 會是 `false`，原本對話照常進行。

## 五、使用者如何在設定頁管理與刪除記憶

Phase D 提供簡單的 Flutter 記憶管理頁，不顯示 embedding、pgvector、memoryContext 等技術細節。

展示路徑：

```text
設定頁 -> 管理長期記憶
```

頁面會顯示目前保存的記憶，每筆包含：

- 記憶摘要
- 記憶類型
- 重要性
- 建立時間
- 使用次數

使用者點選「忘記這筆」後，App 會呼叫：

```text
POST /api/memories/:id/archive
```

後端會將該記憶標記為 `is_active = false`，並記錄 `archived` 事件。成功後，該筆記憶會從列表移除。

空狀態文字：

```text
目前還沒有長期記憶，和寵物多聊聊後，牠會慢慢更了解你。
```

## 六、展示前準備

後端 `.env` 建議包含：

```env
OPENAI_API_KEY=你的 OpenAI API Key
DATABASE_URL=postgres://USER:PASSWORD@localhost:5432/DATABASE_NAME
PGVECTOR_ENABLED=true
EMBEDDING_MODEL=text-embedding-3-small
PORT=3001
```

注意事項：

- API Key 只放在 `backend/stt_proxy/.env`。
- 不要把 API Key 放進 Flutter。
- `.env` 已加入 `.gitignore`，不要提交到 GitHub。
- PostgreSQL 沒開時，記憶功能會走 JSON fallback。

確認 API 可用：

```bash
curl 'http://127.0.0.1:3001/api/memories?userId=default_user'
```

```bash
curl -X POST http://127.0.0.1:3001/api/memories/context \
  -H 'Content-Type: application/json' \
  -d '{
    "userId": "default_user",
    "userText": "給我一個睡眠健康小知識",
    "limit": 5
  }'
```

## 七、後端啟動方式

進入後端資料夾：

```bash
cd backend/stt_proxy
```

安裝套件：

```bash
npm install
```

執行 migration：

```bash
npm run db:migrate
```

啟動後端：

```bash
npm run dev
```

或使用一般啟動：

```bash
npm start
```

健康檢查：

```bash
curl http://127.0.0.1:3001/health
```

## 八、Flutter run 指令

回到專案根目錄：

```bash
cd ../..
```

安裝 Flutter 套件：

```bash
flutter pub get
```

啟動 App：

```bash
flutter run
```

如果要指定 Chrome：

```bash
flutter run -d chrome
```

如果使用 Android 模擬器連本機後端，後端 URL 通常要使用：

```text
http://10.0.2.2:3001
```

桌面或 Chrome 可使用：

```text
http://localhost:3001
```

## 九、必測 Demo 腳本

### Demo 1：睡眠記憶

第一句：

```text
我最近晚上都睡不好，白天很沒精神。
```

預期：系統在對話後自動保存睡眠與精神狀態相關記憶。

第二句：

```text
給我一個睡眠健康小知識。
```

預期：系統會召回睡眠相關記憶，寵物自然提到之前睡不好，例如「你之前有提到最近晚上比較睡不好」，並提供溫和的生活建議，但不做醫療診斷。

### Demo 2：故事偏好

第一句：

```text
我喜歡聽台灣地方故事。
```

預期：系統保存使用者的故事偏好。

第二句：

```text
說一個故事給我聽。
```

預期：系統會召回故事偏好，寵物回覆偏向台灣地方故事，而不是隨機一般故事。

### Demo 3：記憶管理

操作流程：

```text
進入設定頁 -> 管理長期記憶 -> 顯示已保存記憶 -> 點選忘記這筆 -> 確認該筆從列表移除
```

預期：使用者可以看見目前寵物記得什麼，也可以主動刪除某筆記憶。刪除後，該筆記憶不再出現在列表，也不再參與後續召回。

### Demo 4：不相關記憶不硬用

前提：系統已存在睡眠記憶。

提問：

```text
查一下最近科技新聞。
```

預期：系統不應硬提睡眠記憶。記憶只作為陪伴脈絡，若和目前問題無關，AI 應忽略。

## 十、API 測試範例

### POST /api/memories/extract

```bash
curl -X POST http://127.0.0.1:3001/api/memories/extract \
  -H 'Content-Type: application/json' \
  -d '{
    "userId": "default_user",
    "userText": "我最近晚上都睡不好，白天很沒精神。",
    "agentReply": "我陪你一起慢慢調整，也可以幫你找睡眠小知識。",
    "emotion": "tired",
    "sessionId": "demo_session_sleep",
    "turnId": "demo_turn_sleep_001"
  }'
```

### GET /api/memories

```bash
curl 'http://127.0.0.1:3001/api/memories?userId=default_user'
```

### POST /api/memories/context

```bash
curl -X POST http://127.0.0.1:3001/api/memories/context \
  -H 'Content-Type: application/json' \
  -d '{
    "userId": "default_user",
    "userText": "給我一個睡眠健康小知識",
    "limit": 5
  }'
```

有召回時，預期看到：

```json
{
  "memoryUsed": true,
  "memoryContext": "可參考的使用者長期記憶：...",
  "memoryContextSummary": "使用了 1 筆長期記憶：睡眠狀態。",
  "usedMemoryIds": [1],
  "provider": "postgres_pgvector"
}
```

沒有可用記憶時，預期看到：

```json
{
  "memoryUsed": false,
  "memoryContext": "",
  "memoryContextSummary": "",
  "usedMemoryIds": [],
  "provider": "none",
  "reason": "no_relevant_memory"
}
```

## 十一、報告可用說明詞

為什麼做長期記憶：

長者陪伴 App 如果每次對話都像第一次見面，陪伴感會很弱。長期記憶讓 AI 寵物能記住使用者明確說過的偏好、習慣與近況，例如喜歡的故事類型或最近睡眠狀態，讓後續回覆更有連續性與溫度。

為什麼使用 pgvector：

使用者下一次說的話不一定會和原本記憶使用完全相同的字。pgvector 可以用 embedding 做語意相似搜尋，例如「睡眠健康小知識」可以召回「最近晚上睡不好」這類語意相關的記憶，比單純關鍵字搜尋更適合自然對話。

如何避免 AI 亂記：

系統只保存使用者明確說出口、且有助於陪伴的內容。普通寒暄、太短文字、一次性閒聊、AI 自己推測、醫療診斷與敏感身份推斷都不會保存。記憶抽取也會產生 importance 與 confidence，並用 sourceTurnId 與摘要比對避免重複保存。

如何避免記憶被過度使用：

召回時不只看相似度，也會看重要性與近期性。只有 similarity、importance、finalScore 達到門檻時才會使用，且最多只注入少量記憶。prompt 也明確要求 AI：如果記憶和目前問題無關，就忽略。

如何讓使用者控制記憶：

Phase D 在設定頁提供「管理長期記憶」。使用者可以看見目前寵物記得的內容，也可以隨時按「忘記這筆」刪除單筆記憶。刪除後該記憶會被 archive，不再出現在列表，也不再參與後續個人化回覆。

## 十二、展示失敗時的 fallback 說法

PostgreSQL 沒開時：

```text
系統偵測到 PostgreSQL 不可用，所以自動切換到 JSON fallback。這是展示與開發用的備援機制，仍能展示建立、列表、刪除與基本召回。
```

OPENAI_API_KEY 失敗或不存在時：

```text
AI 抽取與 embedding 失敗不會影響主對話。系統會改用 rule-based fallback 判斷是否值得記住，或在沒有 embedding 時略過語意召回。
```

embedding 失敗時：

```text
記憶功能設計成非阻塞。embedding 失敗時，對話仍會正常回覆；記憶可以先保存為沒有向量的資料，等服務恢復後再處理。
```

memoryContext 失敗時：

```text
記憶召回只是輔助陪伴脈絡，不是主對話依賴。召回失敗時，系統會回到原本 AI 對話流程，使用者不會感覺 App 壞掉。
```

Realtime 無法展示時：

```text
如果現場 Realtime 連線不穩，可以直接用 curl 展示 /api/memories/extract 與 /api/memories/context，證明記憶抽取、儲存、召回與隱私控制都有運作。
```

記憶管理頁沒有資料時：

```text
目前沒有長期記憶是正常狀態。先完成睡眠或故事偏好的 Demo 對話，等系統保存記憶後，再回到設定頁查看。
```
