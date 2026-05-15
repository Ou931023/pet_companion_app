CREATE EXTENSION IF NOT EXISTS vector;

ALTER TABLE companion_memories
DROP CONSTRAINT IF EXISTS chk_companion_memories_memory_type;

ALTER TABLE companion_memories
ADD CONSTRAINT chk_companion_memories_memory_type
  CHECK (memory_type IN (
    'preference',
    'emotion_event',
    'routine',
    'family',
    'health_note',
    'reminder_context',
    'personal_story',
    'other',
    'emotion',
    'reminder',
    'care_need',
    'story_preference',
    'health_lifestyle',
    'reminiscence'
  ));

CREATE OR REPLACE VIEW memories AS
SELECT
  id,
  user_id,
  memory_summary AS content,
  memory_type AS type,
  importance,
  source_turn_id,
  source_session_id AS session_id,
  embedding,
  NOT is_active AS archived,
  created_at,
  updated_at
FROM companion_memories;
