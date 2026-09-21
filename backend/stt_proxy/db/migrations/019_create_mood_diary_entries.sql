CREATE TABLE IF NOT EXISTS mood_diary_entries (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  elder_id UUID NOT NULL REFERENCES elders(id) ON DELETE CASCADE,
  mood TEXT NOT NULL CHECK (mood IN ('happy', 'okay', 'low', 'worried')),
  content TEXT NOT NULL CHECK (char_length(content) BETWEEN 1 AND 1000),
  shared_with_caregiver BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_mood_diary_resident_created
  ON mood_diary_entries (elder_id, created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_mood_diary_shared_resident_created
  ON mood_diary_entries (elder_id, created_at DESC, id DESC)
  WHERE shared_with_caregiver = TRUE;
