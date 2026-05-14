# Long-term Memory Phase B

Phase B adds automatic memory extraction and server-side embeddings on top of Phase A. It does not add memory recall, prompt injection, Tavily/search changes, or Flutter UI changes.

## What Phase B Added

- `POST /api/memories/extract` for one-turn memory extraction and storage.
- Server-side memory embedding via OpenAI embeddings.
- AI-first memory extraction with rule-based fallback.
- Deduplication before storage.
- Non-blocking Flutter integration after each completed conversation turn.

## Extraction Rules

The extractor only saves information the user explicitly said. It can save:

- `preference`: likes or dislikes, such as quiet music.
- `routine`: repeated habits, such as morning walks.
- `emotion`: recent emotional state, such as loneliness.
- `reminder`: future events, such as a hospital visit tomorrow.
- `care_need`: care reminders, such as drinking water or taking medicine.
- `story_preference`: preferred story style or topic.
- `health_lifestyle`: sleep, energy, and lifestyle state.

It does not save:

- Ordinary greetings or chatter such as `哈哈`, `嗯`, `謝謝`.
- Very short text without clear meaning.
- One-off small talk such as `今天天氣不錯`.
- AI guesses or inferred personal facts.
- Medical diagnoses.
- Political, religious, or sensitive identity inferences.
- Personal information the user did not clearly say.

## Embeddings

Embeddings are created server-side only:

```env
EMBEDDING_MODEL=text-embedding-3-small
OPENAI_API_KEY=...
```

The expected vector length is 1536 dimensions. API keys stay in backend `.env`; Flutter never receives them.

## Fallback Behavior

If `OPENAI_API_KEY` is missing:

- Memory extraction uses rule-based fallback.
- Embedding returns `provider = none`.
- The memory can still be stored with `embedding = null`.

If OpenAI extraction or embedding fails, the API logs a warning and continues without breaking the conversation flow.

## Deduplication

Before storage, the backend avoids duplicates using:

- Existing `sourceTurnId`, handled by Phase A unique source-turn behavior.
- Exact same `memorySummary` for the same `userId`.
- When PostgreSQL + pgvector and an embedding are available, nearest memory with similarity greater than `0.92`.

Deduplicated attempts record a `memory_events` row with `event_type = deduplicated` when possible.

## API Test

Start backend:

```bash
npm run dev
```

Extract and store a memory:

```bash
curl -X POST http://127.0.0.1:3001/api/memories/extract \
  -H 'Content-Type: application/json' \
  -d '{
    "userId": "default_user",
    "userText": "我最近晚上都睡不好，白天很沒精神。",
    "agentReply": "我陪你一起慢慢調整，也可以幫你找睡眠小知識。",
    "emotion": "tired",
    "sessionId": "session_001",
    "turnId": "turn_001"
  }'
```

Possible stored response:

```json
{
  "shouldRemember": true,
  "memory": {
    "memoryType": "health_lifestyle",
    "memorySummary": "使用者近期睡眠或精神狀態：我最近晚上都睡不好，白天很沒精神。",
    "importance": 4,
    "emotionLabel": "tired"
  },
  "embeddingProvider": "openai",
  "storeProvider": "postgres_pgvector"
}
```

When no memory should be stored:

```json
{
  "shouldRemember": false,
  "reason": "普通寒暄，不需保存"
}
```

## Flutter Integration

After a turn is saved to local conversation history, `ConversationController` calls `MemoryController.extractMemory(...)` in the background. It is intentionally non-blocking. Realtime voice already had this pattern and now uses the same new `/api/memories/extract` endpoint through `MemoryService`.

Short user texts are skipped before calling the backend.

## Tests

Run:

```bash
npm run check
npm run test:memory
npm test
```

The memory tests cover rule-based extraction, chatter rejection, weather small talk rejection, duplicate source turns, duplicate summaries, JSON fallback, and missing `OPENAI_API_KEY`.

## Phase C

Next step: memory recall and prompt injection. Phase C should retrieve relevant active memories, rank by similarity/importance/recency, and inject a compact memory block into prompts without exposing internal storage language to the user.
