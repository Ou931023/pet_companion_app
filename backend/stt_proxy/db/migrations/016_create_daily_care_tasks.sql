-- CR-0068：日常照護任務（Daily Care Task）JSON → PostgreSQL 平移。
-- 對映 services/dailyCareTask/dailyCareTaskStore.js 的 normalizeTask() /
-- recordSubmission() 既有對外形狀（store 對外用 camelCase，DB 欄位用 snake_case，
-- 由 rowToTask / rowToSubmission 映射回 camelCase，API response shape 不變）。
--
-- 冪等：migrate.js 啟動時 glob migrations/*.sql 依檔名排序重跑、無 schema_migrations 追蹤，
-- 故本檔必須完全冪等：CREATE TABLE/INDEX IF NOT EXISTS + ADD COLUMN IF NOT EXISTS，
-- 無破壞性操作（無 DROP / TRUNCATE）。本批次只建表，不灌種子（任務由 App 端 runtime 建立）。
--
-- id / elder_id 用 TEXT（比照 marketplace migration 015 放寬為 TEXT 的決策）：
--   - store 端 id 為 randomUUID() 字串並帶入 INSERT；elder_id 可能是 demo 字串而非
--     elders 表的 UUID，故不加 elders FK，避免 demo / 跨環境 id 造成 FK 違規。
-- status / type / verificationStatus 不加 CHECK：寫入層已用 VALID_* 集合收斂，
--   schema 不加 CHECK 以免擋既有 JSON 舊值或日後狀態擴充。

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- daily_care_tasks：每一筆日常照護任務（對映 normalizeTask 形狀）。
CREATE TABLE IF NOT EXISTS daily_care_tasks (
  id TEXT PRIMARY KEY,
  elder_id TEXT,
  title TEXT NOT NULL DEFAULT '',
  type TEXT NOT NULL DEFAULT 'medication',
  description TEXT NOT NULL DEFAULT '',
  scheduled_time TEXT NOT NULL DEFAULT '',
  due_at TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'pending',
  proof_required BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 冪等補欄位：若曾以較少欄位建立過，補上缺漏欄位。
ALTER TABLE daily_care_tasks ADD COLUMN IF NOT EXISTS elder_id TEXT;
ALTER TABLE daily_care_tasks ADD COLUMN IF NOT EXISTS title TEXT NOT NULL DEFAULT '';
ALTER TABLE daily_care_tasks ADD COLUMN IF NOT EXISTS type TEXT NOT NULL DEFAULT 'medication';
ALTER TABLE daily_care_tasks ADD COLUMN IF NOT EXISTS description TEXT NOT NULL DEFAULT '';
ALTER TABLE daily_care_tasks ADD COLUMN IF NOT EXISTS scheduled_time TEXT NOT NULL DEFAULT '';
ALTER TABLE daily_care_tasks ADD COLUMN IF NOT EXISTS due_at TIMESTAMPTZ;
ALTER TABLE daily_care_tasks ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'pending';
ALTER TABLE daily_care_tasks ADD COLUMN IF NOT EXISTS proof_required BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE daily_care_tasks ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE daily_care_tasks ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

CREATE INDEX IF NOT EXISTS idx_daily_care_tasks_elder
ON daily_care_tasks (elder_id);

CREATE INDEX IF NOT EXISTS idx_daily_care_tasks_status
ON daily_care_tasks (status);

CREATE INDEX IF NOT EXISTS idx_daily_care_tasks_scheduled
ON daily_care_tasks (scheduled_time);

-- daily_care_task_submissions：每次拍照完成證明 + AI 影像驗證結果。
-- verification 結構（verificationStatus / confidence / reason / detectedObjects /
-- reviewRequired）整包存 JSONB，由 rowToSubmission 經 normalizeVerification 還原。
-- proof_image_path 為本機檔路徑 metadata（實體圖片仍存於 runtime 檔系統，不入 DB）。
CREATE TABLE IF NOT EXISTS daily_care_task_submissions (
  id TEXT PRIMARY KEY,
  task_id TEXT NOT NULL REFERENCES daily_care_tasks(id) ON DELETE CASCADE,
  elder_id TEXT,
  proof_image_path TEXT,
  submitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  status TEXT NOT NULL DEFAULT 'needs_review',
  verification_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  note TEXT NOT NULL DEFAULT ''
);

-- 冪等補欄位。
ALTER TABLE daily_care_task_submissions ADD COLUMN IF NOT EXISTS task_id TEXT REFERENCES daily_care_tasks(id) ON DELETE CASCADE;
ALTER TABLE daily_care_task_submissions ADD COLUMN IF NOT EXISTS elder_id TEXT;
ALTER TABLE daily_care_task_submissions ADD COLUMN IF NOT EXISTS proof_image_path TEXT;
ALTER TABLE daily_care_task_submissions ADD COLUMN IF NOT EXISTS submitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE daily_care_task_submissions ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'needs_review';
ALTER TABLE daily_care_task_submissions ADD COLUMN IF NOT EXISTS verification_json JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE daily_care_task_submissions ADD COLUMN IF NOT EXISTS note TEXT NOT NULL DEFAULT '';

CREATE INDEX IF NOT EXISTS idx_daily_care_task_submissions_task
ON daily_care_task_submissions (task_id);

CREATE INDEX IF NOT EXISTS idx_daily_care_task_submissions_submitted
ON daily_care_task_submissions (submitted_at DESC);
