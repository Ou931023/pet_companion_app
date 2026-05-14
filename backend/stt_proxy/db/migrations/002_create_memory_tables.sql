CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS memory_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  session_id TEXT,
  source_turn_id TEXT,

  memory_type TEXT NOT NULL CHECK (memory_type IN ('profile', 'episodic', 'emotional')),
  summary TEXT NOT NULL,
  original_user_text TEXT,
  ai_reply TEXT,
  emotion TEXT,

  importance REAL NOT NULL DEFAULT 0.5,
  tags TEXT[] NOT NULL DEFAULT '{}',

  embedding vector(1536) NOT NULL,

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_used_at TIMESTAMPTZ,
  deleted_at TIMESTAMPTZ
);

-- Ensure idempotency: add missing columns if migrations ran partially before
ALTER TABLE memory_items ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
ALTER TABLE memory_items ADD COLUMN IF NOT EXISTS last_used_at TIMESTAMPTZ;
ALTER TABLE memory_items ADD COLUMN IF NOT EXISTS tags TEXT[] DEFAULT '{}';

CREATE INDEX IF NOT EXISTS idx_memory_items_user_id
ON memory_items(user_id);

CREATE INDEX IF NOT EXISTS idx_memory_items_created_at
ON memory_items(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_memory_items_not_deleted
ON memory_items(user_id)
WHERE deleted_at IS NULL;

DO $$
BEGIN
  BEGIN
    EXECUTE '
      CREATE INDEX IF NOT EXISTS idx_memory_items_embedding_hnsw
      ON memory_items
      USING hnsw (embedding vector_cosine_ops)
    ';
  EXCEPTION WHEN OTHERS THEN
    EXECUTE '
      CREATE INDEX IF NOT EXISTS idx_memory_items_embedding_ivfflat
      ON memory_items
      USING ivfflat (embedding vector_cosine_ops)
      WITH (lists = 100)
    ';
  END;
END $$;
