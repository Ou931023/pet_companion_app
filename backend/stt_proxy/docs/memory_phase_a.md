# Long-term Memory Phase A

Phase A adds the database and service foundation for companion memories. It does not perform AI memory extraction, OpenAI embedding generation, or prompt injection.

## Completed Scope

- Added `companion_memories` and `memory_events` PostgreSQL tables.
- Added pgvector-ready SQL migration with indexes and an `updated_at` trigger.
- Added a safe PostgreSQL helper that does not crash the server when the database is unavailable.
- Added a Memory Store with create, list, vector search, archive, and event logging.
- Added JSON fallback files for development and demos.
- Added `/api/memories` endpoints for manual testing.
- Added memory store tests.

## SQL Migration

Migration file:

```text
db/migrations/004_create_companion_memories.sql
```

The migration:

- Enables `CREATE EXTENSION IF NOT EXISTS vector`.
- Creates `companion_memories`.
- Creates `memory_events`.
- Adds CHECK constraints for memory type, emotion label, importance, confidence, use count, and event type.
- Adds indexes for active user/type queries, duplicate source turn prevention, created time, memory events, and vector search.
- Creates `update_updated_at_column()` with `CREATE OR REPLACE FUNCTION`.
- Recreates the `trg_companion_memories_updated_at` trigger.

The vector index first attempts partial HNSW:

```sql
CREATE INDEX IF NOT EXISTS idx_companion_memories_embedding_hnsw
ON companion_memories
USING hnsw (embedding vector_cosine_ops)
WHERE embedding IS NOT NULL;
```

If that fails because the local PostgreSQL/pgvector version does not support it, the migration falls back to non-partial HNSW, then IVFFlat.

## PostgreSQL + pgvector Setup

Install or run PostgreSQL with pgvector available, then create a database.

Example `.env`:

```env
DATABASE_URL=postgres://USER:PASSWORD@localhost:5432/DATABASE_NAME
PGVECTOR_ENABLED=true
```

Run migrations from `backend/stt_proxy`:

```bash
npm run db:migrate
```

The existing migration runner applies SQL files in `db/migrations` in filename order.

## API Testing

Start the backend:

```bash
npm run dev
```

Create a manual memory:

```bash
curl -X POST http://127.0.0.1:3001/api/memories \
  -H 'Content-Type: application/json' \
  -d '{
    "userId": "default_user",
    "memoryType": "preference",
    "memoryText": "使用者喜歡聽台灣地方故事。",
    "memorySummary": "使用者喜歡聽台灣地方故事。",
    "emotionLabel": "happy",
    "importance": 4,
    "confidence": 0.9,
    "sourceTurnId": "manual_test_001",
    "sourceSessionId": "manual_session"
  }'
```

List memories:

```bash
curl 'http://127.0.0.1:3001/api/memories?userId=default_user'
```

Search by embedding:

```bash
curl -X POST http://127.0.0.1:3001/api/memories/search \
  -H 'Content-Type: application/json' \
  -d '{
    "userId": "default_user",
    "embedding": [0.01, 0.02, 0.03],
    "limit": 5
  }'
```

For PostgreSQL vector search, embeddings should match the table dimension: `VECTOR(1536)`. Short vectors are mainly useful for JSON fallback demos.

Archive a memory:

```bash
curl -X POST http://127.0.0.1:3001/api/memories/1/archive \
  -H 'Content-Type: application/json' \
  -d '{ "userId": "default_user" }'
```

## JSON Fallback

Fallback files:

```text
data/companion_memories.json
data/memory_events.json
```

The Memory Store uses JSON fallback when:

- `DATABASE_URL` is missing.
- `PGVECTOR_ENABLED` is not `true`.
- PostgreSQL connection fails.
- A PostgreSQL memory operation fails.

JSON fallback supports create, list, archive, event logging, and simplified vector search. If stored memories have embeddings, it uses cosine similarity. If not, it returns recent active memories.

Fallback responses include:

```json
{ "provider": "json_fallback" }
```

PostgreSQL responses include:

```json
{ "provider": "postgres_pgvector" }
```

## Tests

Run only memory tests:

```bash
npm run test:memory
```

Run the backend test suite:

```bash
npm test
```

The memory tests force JSON fallback using a temporary data directory, so they do not require a running PostgreSQL instance.

## Phase B

Recommended next steps:

- Add AI-assisted memory extraction behind a feature flag.
- Generate embeddings server-side only.
- Add deduplication and memory update rules.
- Add retrieval thresholds and recency/importance ranking.
- Inject selected memories into conversation prompts carefully.
- Add privacy controls for viewing and deleting memories.
