-- CR-0007 Batch 2：健康分析後台資料表（情緒 / 生理 / 遊戲認知）
-- 契約見 PROJECT_ARCHITECTURE.md §10.3。
-- 沿用 006 的 pgcrypto + gen_random_uuid() 慣例與 IF NOT EXISTS 冪等寫法，FK 到 elders.id。

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- emotion_history：每位長者的情緒歷史紀錄（來源預設為陪伴分析）。
CREATE TABLE IF NOT EXISTS emotion_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  elder_id UUID REFERENCES elders(id),
  emotion TEXT,
  score NUMERIC,
  source TEXT NOT NULL DEFAULT 'companion_analysis',
  summary TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- elder_health_metrics：生理 / 生活指標（demo 階段以確定性產生器供給）。
CREATE TABLE IF NOT EXISTS elder_health_metrics (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  elder_id UUID REFERENCES elders(id),
  metric_date DATE,
  daily_interaction_minutes INTEGER,
  reminder_completion_rate NUMERIC,
  medication_completion_rate NUMERIC,
  water_completion_rate NUMERIC,
  exercise_completion_rate NUMERIC,
  sleep_hours NUMERIC,
  sleep_quality TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- game_cognitive_metrics：遊戲認知退化指標序列。
CREATE TABLE IF NOT EXISTS game_cognitive_metrics (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  elder_id UUID REFERENCES elders(id),
  game_type TEXT,
  played_at TIMESTAMPTZ,
  moves INTEGER,
  duration_seconds INTEGER,
  completion_rate NUMERIC,
  difficulty TEXT,
  cognitive_score NUMERIC,
  regression_flag BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_emotion_history_elder_id
ON emotion_history (elder_id);

CREATE INDEX IF NOT EXISTS idx_elder_health_metrics_elder_id
ON elder_health_metrics (elder_id);

CREATE INDEX IF NOT EXISTS idx_game_cognitive_metrics_elder_id
ON game_cognitive_metrics (elder_id);
