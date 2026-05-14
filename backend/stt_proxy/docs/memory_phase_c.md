# Long-term Memory Phase C

Phase C adds memory recall, relevance ranking, prompt context creation, and lightweight prompt injection for realtime companion replies. It does not change Tavily/search, does not add large UI, and does not force memories into every response.

## What Phase C Added

- `services/memory/memoryContextService.js`
- `POST /api/memories/context`
- Mixed relevance ranking using similarity, importance, and recency.
- Prompt-safe `memoryContext` text block.
- `last_used_at` / `use_count` updates.
- `memory_events` entries with `event_type = used_in_prompt`.
- Realtime prompt injection using `companion_memories`.
- Homepage greeting now uses the new Phase C memory context path before falling back.
- ConversationTurn fields for `memoryUsed`, `usedMemoryIds`, and `memoryContextSummary`.

## Recall Flow

1. Receive `userText`.
2. Skip if text is too short or meaningless.
3. Create a server-side embedding for `userText`.
4. Search `companion_memories` through PostgreSQL + pgvector or JSON fallback.
5. Rank memories.
6. Build a short prompt block.
7. Mark selected memories as used.
8. Return `memoryUsed`, `usedMemoryIds`, `memoryContext`, and `memoryContextSummary`.

If embedding or memory lookup fails, the service returns an empty context and does not interrupt chat.

## Ranking

The final score is:

```text
finalScore =
similarity * 0.60
+ importanceScore * 0.25
+ recencyScore * 0.15
```

Where:

- `importanceScore = importance / 5`
- 7 days: `1.0`
- 30 days: `0.8`
- 90 days: `0.5`
- Older: `0.2`

Filters:

- `similarity >= 0.72`
- `importance >= 3`
- `isActive = true`
- `finalScore >= 0.65`
- Maximum 3 memories

For JSON fallback records without similarity, recent active memories are ranked by importance and recency.

## Prompt Context

The generated context is intentionally short:

```text
可參考的使用者長期記憶：
1. 使用者最近晚上睡不好，白天精神較差。
2. 使用者喜歡聽台灣地方故事。

使用規則：
- 這些記憶只作為陪伴脈絡。
- 可以自然延續相關話題，但不要硬提。
- 不要說「我查到你的記憶」或「資料庫顯示」。
- 健康相關內容不可做醫療診斷。
- 如果和目前問題無關，請忽略。
```

The assistant should never expose memory IDs, pgvector, embeddings, or database language to the user.

## API Test

Build memory context:

```bash
curl -X POST http://127.0.0.1:3001/api/memories/context \
  -H 'Content-Type: application/json' \
  -d '{
    "userId": "default_user",
    "userText": "今天想聽一個台灣故事",
    "limit": 5
  }'
```

Example response:

```json
{
  "memoryUsed": true,
  "usedMemoryIds": [1],
  "memoryContext": "可參考的使用者長期記憶：...",
  "memoryContextSummary": "使用了 1 筆長期記憶：使用者喜歡聽台灣地方故事。",
  "provider": "postgres_pgvector"
}
```

If no relevant memory is found:

```json
{
  "memoryUsed": false,
  "usedMemoryIds": [],
  "memoryContext": "",
  "memoryContextSummary": "",
  "usedMemoryIds": [],
  "provider": "none",
  "reason": "no_relevant_memory"
}
```

## Prompt Injection

Realtime calls now build memory context before creating the realtime session configuration. If relevant memories exist, the context is appended to the realtime instructions. If not, the normal companion prompt is used unchanged.

This keeps memory use natural and optional.

## Homepage Greeting

`GET /api/memories/greeting?userId=default_user` returns a short 1-2 sentence greeting from the single most recent important non-sensitive memory. If no memory is available, the Flutter controller falls back to the existing time-based greeting.

Example:

```json
{
  "greeting": "最近睡眠比較辛苦的話，我今天也會陪你慢慢放鬆。",
  "memoryUsed": true,
  "memoryId": 1,
  "provider": "postgres_pgvector"
}
```

Health memories are phrased gently and never as diagnosis. Story preferences can produce a greeting such as:

```text
你之前喜歡台灣地方故事，等等我也可以說一個給你聽。
```

## Demo Flow

1. User says: `我最近晚上都睡不好，白天很沒精神。`
2. Phase B extracts and stores a `health_lifestyle` memory after the reply.
3. User later says: `給我一個睡眠健康小知識。`
4. Phase C recalls the sleep memory and mock/realtime replies can naturally say: `你之前有提到最近晚上比較睡不好...`
5. User says: `我喜歡聽台灣地方故事。`
6. Phase B stores a `story_preference` memory.
7. User later says: `說一個故事給我聽。`
8. Phase C recalls the story preference, and mock/realtime replies can steer toward a Taiwan local story.

## Tests

Run:

```bash
npm run check
npm run test:memory
npm test
```

Memory tests cover ranking thresholds, prompt block safety, embedding failure fallback, JSON fallback recall, and marking memories as used.

## Phase D Ideas

- Add user-visible memory management controls.
- Add consent and privacy copy.
- Improve prompt injection for non-realtime backend chat if a backend chat endpoint is introduced.
- Add memory decay or archival suggestions.
- Add evaluation cases for overuse and unsafe medical personalization.
