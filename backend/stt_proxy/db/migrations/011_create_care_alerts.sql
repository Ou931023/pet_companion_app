-- CR-P2A Batch 1：Care Alert 改 PostgreSQL 持久化（care_alerts + care_alert_status_events）
-- 契約見 docs/CHANGE_REVIEW.md CR-P2A（§ 欄位）與 pet_companion_app/CLAUDE.md §3.3（核心表）。
-- 欄位對映 careAlertStoreService.js 的 normalizeAlert() 既有 JSON 形狀，沿用既有 migrations
-- （006/008/009/010）的 pgcrypto + gen_random_uuid() 慣例與 IF NOT EXISTS /
-- ADD COLUMN IF NOT EXISTS / CREATE INDEX IF NOT EXISTS 冪等寫法。
-- migrate.js 啟動時 glob migrations/*.sql 依檔名排序重跑、無 schema_migrations 追蹤，
-- 故本檔必須完全冪等：重複執行不可報錯、不可造成副作用。
--
-- 本批次 migration only：只建表，不接任何 store / 路由 / 寫入邏輯（Batch 2/3 才接）。
--
-- risk_level 用 TEXT 不加 CHECK：寫入層以 normalizeRiskLevel() 收斂為四級
-- （low/medium/high/urgent），legacy（normal/attention）相容由讀取層處理，
-- schema 不加 CHECK 以免擋既有 care_alerts.json 舊值。

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- care_alerts：每一筆 Care Alert（對映 normalizeAlert 形狀）。
-- id 由 service 端產生（randomUUID）並帶入 INSERT，與既有 JSON 形狀一致，
-- 避免 DB 與 JSON 兩路徑 id 來源不同；建表仍給 DEFAULT 以利手動/冪等補欄位。
CREATE TABLE IF NOT EXISTS care_alerts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  -- 綁定哪位長者；未帶入為 NULL（向下相容，舊資料缺欄位視為 NULL）。
  elder_id UUID REFERENCES elders(id),
  received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  status TEXT NOT NULL DEFAULT 'new' CHECK (status IN ('new', 'acknowledged', 'resolved')),
  -- 寫入前以 normalizeRiskLevel() 收斂為四級；TEXT 不加 CHECK 容 legacy 值。
  risk_level TEXT NOT NULL DEFAULT 'low',
  risk_level_label TEXT,
  category TEXT,
  category_label TEXT,
  trigger_summary TEXT,
  transcript_snippet TEXT,
  -- payload 來源時間（normalizeAlert.createdAt），可空。
  created_at TIMESTAMPTZ,
  source TEXT,
  status_updated_at TIMESTAMPTZ,
  acknowledged_at TIMESTAMPTZ,
  resolved_at TIMESTAMPTZ
);

-- 冪等補欄位：若 care_alerts 曾以較少欄位建立過，補上缺漏欄位。
ALTER TABLE care_alerts ADD COLUMN IF NOT EXISTS elder_id UUID REFERENCES elders(id);
ALTER TABLE care_alerts ADD COLUMN IF NOT EXISTS received_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE care_alerts ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'new';
ALTER TABLE care_alerts ADD COLUMN IF NOT EXISTS risk_level TEXT NOT NULL DEFAULT 'low';
ALTER TABLE care_alerts ADD COLUMN IF NOT EXISTS risk_level_label TEXT;
ALTER TABLE care_alerts ADD COLUMN IF NOT EXISTS category TEXT;
ALTER TABLE care_alerts ADD COLUMN IF NOT EXISTS category_label TEXT;
ALTER TABLE care_alerts ADD COLUMN IF NOT EXISTS trigger_summary TEXT;
ALTER TABLE care_alerts ADD COLUMN IF NOT EXISTS transcript_snippet TEXT;
ALTER TABLE care_alerts ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ;
ALTER TABLE care_alerts ADD COLUMN IF NOT EXISTS source TEXT;
ALTER TABLE care_alerts ADD COLUMN IF NOT EXISTS status_updated_at TIMESTAMPTZ;
ALTER TABLE care_alerts ADD COLUMN IF NOT EXISTS acknowledged_at TIMESTAMPTZ;
ALTER TABLE care_alerts ADD COLUMN IF NOT EXISTS resolved_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_care_alerts_elder
ON care_alerts (elder_id);

CREATE INDEX IF NOT EXISTS idx_care_alerts_risk
ON care_alerts (risk_level);

CREATE INDEX IF NOT EXISTS idx_care_alerts_status
ON care_alerts (status);

CREATE INDEX IF NOT EXISTS idx_care_alerts_received
ON care_alerts (received_at DESC);

-- care_alert_status_events：狀態變更軌跡（append-only）。
-- 每次 status 變更 append 一列，保留 new → acknowledged → resolved 完整軌跡。
CREATE TABLE IF NOT EXISTS care_alert_status_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  alert_id UUID NOT NULL REFERENCES care_alerts(id) ON DELETE CASCADE,
  from_status TEXT,
  to_status TEXT NOT NULL,
  changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- 誰改：caregiver_web / system（actor 來源，非 PII 明碼）。
  source TEXT
);

-- 冪等補欄位：若 care_alert_status_events 曾以較少欄位建立過，補上缺漏欄位。
ALTER TABLE care_alert_status_events ADD COLUMN IF NOT EXISTS alert_id UUID REFERENCES care_alerts(id) ON DELETE CASCADE;
ALTER TABLE care_alert_status_events ADD COLUMN IF NOT EXISTS from_status TEXT;
ALTER TABLE care_alert_status_events ADD COLUMN IF NOT EXISTS to_status TEXT NOT NULL DEFAULT '';
ALTER TABLE care_alert_status_events ADD COLUMN IF NOT EXISTS changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE care_alert_status_events ADD COLUMN IF NOT EXISTS source TEXT;

CREATE INDEX IF NOT EXISTS idx_alert_status_events_alert
ON care_alert_status_events (alert_id);
