-- CR-0036 Batch 1：知情同意稽核軌跡（consent_records）
-- 契約見 docs/CHANGE_REVIEW.md CR-0036 與 PROJECT_ARCHITECTURE.md §3.3（核心表）。
-- 沿用既有 migrations（006/008/009）的 pgcrypto + gen_random_uuid() 慣例與
-- IF NOT EXISTS / ADD COLUMN IF NOT EXISTS / CREATE INDEX IF NOT EXISTS 冪等寫法。
-- migrate.js 啟動時 glob migrations/*.sql 依檔名排序重跑、無 schema_migrations 追蹤，
-- 故本檔必須完全冪等：重複執行不可報錯、不可造成副作用。
--
-- 撤回不刪舊列：以 action='withdrawn' 寫新列，保留完整稽核軌跡。

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- consent_records：每一次「授予 / 撤回」同意都新增一列（append-only 稽核）。
-- user_id / elder_id 皆 nullable：同意可能在後端尚未建立 user 前發生
-- （有 firebaseUid / idToken 時於 service 層解析回填）。
CREATE TABLE IF NOT EXISTS consent_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id),
  elder_id UUID REFERENCES elders(id),
  consent_type TEXT NOT NULL,
  consent_version TEXT NOT NULL,
  action TEXT NOT NULL DEFAULT 'granted',
  source TEXT,
  agreed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  withdrawn_at TIMESTAMPTZ,
  app_version TEXT,
  platform TEXT,
  -- PII（可選、nullable）：依 §9，僅落 DB 供稽核，
  -- server log 與 API response 絕不回顯。蒐集前需於隱私政策揭露。
  ip TEXT,
  user_agent TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 冪等補欄位：若 consent_records 曾以較少欄位建立過，補上缺漏欄位。
ALTER TABLE consent_records ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES users(id);
ALTER TABLE consent_records ADD COLUMN IF NOT EXISTS elder_id UUID REFERENCES elders(id);
ALTER TABLE consent_records ADD COLUMN IF NOT EXISTS consent_type TEXT NOT NULL DEFAULT '';
ALTER TABLE consent_records ADD COLUMN IF NOT EXISTS consent_version TEXT NOT NULL DEFAULT '';
ALTER TABLE consent_records ADD COLUMN IF NOT EXISTS action TEXT NOT NULL DEFAULT 'granted';
ALTER TABLE consent_records ADD COLUMN IF NOT EXISTS source TEXT;
ALTER TABLE consent_records ADD COLUMN IF NOT EXISTS agreed_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE consent_records ADD COLUMN IF NOT EXISTS withdrawn_at TIMESTAMPTZ;
ALTER TABLE consent_records ADD COLUMN IF NOT EXISTS app_version TEXT;
ALTER TABLE consent_records ADD COLUMN IF NOT EXISTS platform TEXT;
ALTER TABLE consent_records ADD COLUMN IF NOT EXISTS ip TEXT;
ALTER TABLE consent_records ADD COLUMN IF NOT EXISTS user_agent TEXT;
ALTER TABLE consent_records ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

CREATE INDEX IF NOT EXISTS idx_consent_user_id
ON consent_records (user_id);

CREATE INDEX IF NOT EXISTS idx_consent_elder_id
ON consent_records (elder_id);

CREATE INDEX IF NOT EXISTS idx_consent_type
ON consent_records (consent_type);

CREATE INDEX IF NOT EXISTS idx_consent_type_version
ON consent_records (consent_type, consent_version);
