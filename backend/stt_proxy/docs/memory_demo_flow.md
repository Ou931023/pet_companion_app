# 長期記憶展示驗證流程

這份文件用於畢業專題展示與驗證「AI 老人陪伴寵物 App」的長期記憶系統。展示重點是：系統能記住使用者明確說出的偏好或近況，並在後續對話中自然、適度地使用。

## 一、長期記憶功能簡介

長期記憶系統分成三個階段完成。

Phase A 建立記憶儲存基礎。後端使用 PostgreSQL 搭配 pgvector，建立 `companion_memories` 與 `memory_events` 資料表，用來保存長期記憶、embedding 向量、重要性、信心分數、使用次數與事件紀錄。若 PostgreSQL 無法使用，系統會自動切換到 JSON fallback，確保展示與開發時不會中斷。

Phase B 加入 AI 自動抽取記憶。每輪對話結束後，後端會判斷使用者是否明確說出值得長期保存的資訊，例如睡眠狀態、生活習慣、故事偏好或照護需求。普通寒暄、太短的句子、AI 推測、醫療診斷或敏感身份推斷不會被保存。值得保存的內容會產生摘要與 embedding，再寫入 Memory Store。

Phase C 加入記憶召回與 prompt 注入。當使用者送出新訊息時，後端會產生該訊息的 embedding，搜尋相似記憶，並用 similarity、importance、recency 混合排序。只有相關且分數足夠的記憶會被組成 `memoryContext`，注入 Realtime instructions 或供 mock 回覆使用，讓寵物自然延續使用者的長期偏好與近況。

## 二、展示前準備

1. 進入後端資料夾：

```bash
cd backend/stt_proxy
```

2. 確認 `.env` 至少包含：

```env
OPENAI_API_KEY=你的 OpenAI API Key
DATABASE_URL=postgres://USER:PASSWORD@localhost:5432/DATABASE_NAME
PGVECTOR_ENABLED=true
EMBEDDING_MODEL=text-embedding-3-small
```

3. 啟動 PostgreSQL + pgvector 後執行 migration：

```bash
npm run db:migrate
```

4. 啟動後端：

```bash
npm run dev
```

5. 如果 PostgreSQL 不可用：

系統會改用 JSON fallback：

```text
backend/stt_proxy/data/companion_memories.json
backend/stt_proxy/data/memory_events.json
```

API 回傳中的 `provider` 會顯示 `json_fallback`。這代表功能仍可展示，但向量搜尋會使用簡化的 cosine similarity 或最近重要記憶排序。

6. 確認 API 可用：

```bash
curl http://127.0.0.1:3001/api/memories
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

## 三、固定 Demo 腳本

### Demo 1：睡眠記憶

第一句：

```text
我最近晚上都睡不好，白天很沒精神。
```

預期：Phase B 會在對話後自動抽取並保存睡眠與精神狀態相關記憶。

第二句：

```text
給我一個睡眠健康小知識。
```

預期：Phase C 會召回睡眠相關記憶。AI 回覆可以自然提到「你之前有提到最近晚上比較睡不好」，並給出溫和的生活建議，但不能做醫療診斷。

### Demo 2：故事偏好

第一句：

```text
我喜歡聽台灣地方故事。
```

預期：Phase B 會保存使用者的故事偏好。

第二句：

```text
說一個故事給我聽。
```

預期：Phase C 會召回故事偏好，寵物回覆會偏向台灣地方故事，而不是隨機一般故事。

### Demo 3：不相關記憶不硬用

前提：系統已存在睡眠記憶。

提問：

```text
查一下最近科技新聞。
```

預期：系統不應硬提睡眠記憶。記憶只作為陪伴脈絡，若和目前問題無關，AI 應忽略。

## 四、API 測試方式

### 1. POST /api/memories/extract

手動測試記憶抽取與儲存：

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

### 2. GET /api/memories

查看目前 active memories：

```bash
curl 'http://127.0.0.1:3001/api/memories?userId=default_user'
```

### 3. POST /api/memories/context

測試記憶召回：

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
  "memoryContextSummary": "使用了 1 筆長期記憶：...",
  "usedMemoryIds": [1],
  "provider": "postgres_pgvector"
}
```

無可用記憶時，預期看到：

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

## 五、展示時可講的說明詞

為什麼要做長期記憶：

長者陪伴 App 如果每次都像第一次見面，陪伴感會很弱。長期記憶讓 AI 寵物能記住使用者明確說過的偏好、習慣與近況，例如喜歡的故事類型或最近睡眠狀態，讓後續回覆更有連續性與溫度。

為什麼使用 pgvector：

使用者下一次說的話不一定和原本記憶文字完全相同。pgvector 可以用 embedding 做語意相似搜尋，例如「睡眠健康小知識」可以召回「最近晚上睡不好」這類語意相關的記憶。

如何避免 AI 亂記：

系統只保存使用者明確說出口的資訊，不保存普通寒暄、太短文字、AI 推測、醫療診斷或敏感身份推斷。記憶抽取同時有 AI 判斷與 rule-based fallback，並會記錄信心分數與重要性。

如何避免記憶被過度使用：

Phase C 不只看相似度，也看重要性與近期性。只有 similarity、importance、finalScore 達到門檻的記憶才會使用，最多只注入 3 筆。prompt 也明確要求：如果記憶和目前問題無關，請忽略。

如何保護使用者隱私：

API Key 只存在後端 `.env`，不放進 Flutter。記憶不會直接顯示給使用者，也不會暴露資料庫、embedding、pgvector 或 memory id 等技術細節。敏感內容與診斷類文字不會自動保存或用於問候。

## 六、展示風險與 fallback

1. PostgreSQL 沒開時：

系統會使用 JSON fallback，回傳 `provider = json_fallback`。展示仍可進行。

2. OPENAI_API_KEY 失敗或不存在時：

記憶抽取會使用 rule-based fallback。embedding 會回傳 `provider = none`，不會讓 server crash。

3. Embedding 失敗時：

記憶仍可保存，embedding 會是 `null`。原本對話不受影響。

4. memoryContext 失敗時：

`/api/memories/context` 會回傳 `memoryUsed = false`，原對話流程仍可繼續。

5. Realtime 無法展示時：

可以使用 curl 展示：

```bash
curl -X POST http://127.0.0.1:3001/api/memories/extract ...
curl -X POST http://127.0.0.1:3001/api/memories/context ...
```

這可以直接證明記憶抽取、儲存、召回與 ranking 都有運作。
