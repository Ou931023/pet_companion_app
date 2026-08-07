-- CR-0097 Data Tracking Foundation：App 使用事件持久化。
-- 事件由長者端以 Bearer idToken 上報；server 以 requireResidentCaller 權威推導 elder_id。

CREATE TABLE IF NOT EXISTS app_usage_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  elder_id TEXT NOT NULL,
  user_id TEXT,
  event_type TEXT NOT NULL,
  event_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  session_id TEXT,
  duration_ms INTEGER,
  metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE app_usage_events ADD COLUMN IF NOT EXISTS elder_id TEXT NOT NULL DEFAULT '';
ALTER TABLE app_usage_events ADD COLUMN IF NOT EXISTS user_id TEXT;
ALTER TABLE app_usage_events ADD COLUMN IF NOT EXISTS event_type TEXT NOT NULL DEFAULT '';
ALTER TABLE app_usage_events ADD COLUMN IF NOT EXISTS event_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE app_usage_events ADD COLUMN IF NOT EXISTS session_id TEXT;
ALTER TABLE app_usage_events ADD COLUMN IF NOT EXISTS duration_ms INTEGER;
ALTER TABLE app_usage_events ADD COLUMN IF NOT EXISTS metadata_json JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE app_usage_events ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

CREATE INDEX IF NOT EXISTS idx_app_usage_events_elder_time
ON app_usage_events (elder_id, event_at DESC);

CREATE INDEX IF NOT EXISTS idx_app_usage_events_type_time
ON app_usage_events (event_type, event_at DESC);
