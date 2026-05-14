CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS companion_memories (
  id BIGSERIAL PRIMARY KEY,
  user_id TEXT NOT NULL DEFAULT 'default_user',
  memory_type TEXT NOT NULL,
  memory_text TEXT NOT NULL,
  memory_summary TEXT NOT NULL,
  emotion_label TEXT,
  importance INTEGER NOT NULL DEFAULT 3,
  confidence NUMERIC(4,3) NOT NULL DEFAULT 0.800,
  source_turn_id TEXT,
  source_session_id TEXT,
  embedding VECTOR(1536),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_used_at TIMESTAMPTZ,
  use_count INTEGER NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  CONSTRAINT chk_companion_memories_importance
    CHECK (importance BETWEEN 1 AND 5),
  CONSTRAINT chk_companion_memories_confidence
    CHECK (confidence >= 0 AND confidence <= 1),
  CONSTRAINT chk_companion_memories_use_count
    CHECK (use_count >= 0),
  CONSTRAINT chk_companion_memories_memory_type
    CHECK (memory_type IN (
      'preference',
      'routine',
      'emotion',
      'reminder',
      'care_need',
      'story_preference',
      'health_lifestyle',
      'other'
    )),
  CONSTRAINT chk_companion_memories_emotion_label
    CHECK (
      emotion_label IS NULL OR emotion_label IN (
        'happy',
        'neutral',
        'sad',
        'lonely',
        'anxious',
        'tired',
        'angry',
        'unknown'
      )
    )
);

CREATE TABLE IF NOT EXISTS memory_events (
  id BIGSERIAL PRIMARY KEY,
  memory_id BIGINT REFERENCES companion_memories(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL,
  detail TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_memory_events_event_type
    CHECK (event_type IN (
      'created',
      'retrieved',
      'used_in_prompt',
      'updated',
      'archived',
      'deduplicated',
      'error'
    ))
);

CREATE INDEX IF NOT EXISTS idx_companion_memories_user_active_type
ON companion_memories (user_id, is_active, memory_type);

CREATE UNIQUE INDEX IF NOT EXISTS idx_companion_memories_source_turn_unique
ON companion_memories (user_id, source_turn_id)
WHERE source_turn_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_companion_memories_created_at
ON companion_memories (created_at DESC);

CREATE INDEX IF NOT EXISTS idx_memory_events_memory_id
ON memory_events (memory_id);

DO $$
BEGIN
  BEGIN
    EXECUTE '
      CREATE INDEX IF NOT EXISTS idx_companion_memories_embedding_hnsw
      ON companion_memories
      USING hnsw (embedding vector_cosine_ops)
      WHERE embedding IS NOT NULL
    ';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Partial HNSW index creation failed, trying non-partial HNSW index: %', SQLERRM;
    BEGIN
      EXECUTE '
        CREATE INDEX IF NOT EXISTS idx_companion_memories_embedding_hnsw
        ON companion_memories
        USING hnsw (embedding vector_cosine_ops)
      ';
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'HNSW index creation failed, trying IVFFlat fallback: %', SQLERRM;
      EXECUTE '
        CREATE INDEX IF NOT EXISTS idx_companion_memories_embedding_ivfflat
        ON companion_memories
        USING ivfflat (embedding vector_cosine_ops)
        WITH (lists = 100)
      ';
    END;
  END;
END $$;

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_companion_memories_updated_at ON companion_memories;

CREATE TRIGGER trg_companion_memories_updated_at
BEFORE UPDATE ON companion_memories
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();
