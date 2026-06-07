-- CR-P2B Batch 1：通知與敏感操作稽核（notification_logs + audit_logs）
-- 契約見 docs/CHANGE_REVIEW.md CR-P2B（§ 欄位）與 pet_companion_app/CLAUDE.md
-- §8.7（每次通知必須寫入 notification log）、§9.13（所有敏感操作需寫 audit log）。
-- 沿用既有 migrations（006/008/009/010/011）的 pgcrypto + gen_random_uuid() 慣例與
-- IF NOT EXISTS / ADD COLUMN IF NOT EXISTS / CREATE INDEX IF NOT EXISTS 冪等寫法。
-- migrate.js 啟動時 glob migrations/*.sql 依檔名排序重跑、無 schema_migrations 追蹤，
-- 故本檔必須完全冪等：重複執行不可報錯、不可造成副作用。
-- 排序在 011 之後 → alert_id FK 可安全指向 011 建立的 care_alerts(id)。
--
-- 本批次 migration only：只建表，不接任何寫入點（Batch 2/3 才接 service + server.js）。
--
-- PII 紅線（§8.8 / §9.14）：兩表皆「結構化、不含原文 / PII / token」。
--  notification_logs 不得有：完整對話原文、transcriptSnippet、chat_id、bot token、URL、email、ip。
--  audit_logs.metadata 僅放結構化非敏感欄位（如 from/to status、刪除計數）；禁放原文 / email / ip / token。

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- notification_logs：Care Alert 通知三結局（sent / failed / skipped_*）每次寫一列。
-- 只存結構化、非敏感欄位，絕不存對話原文 / snippet / chat_id / bot token / URL。
CREATE TABLE IF NOT EXISTS notification_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  -- 對應的 Care Alert（可空：少數情境可能無 alert id）。
  alert_id UUID REFERENCES care_alerts(id),
  elder_id UUID,
  channel TEXT NOT NULL DEFAULT 'telegram',
  risk_level TEXT,
  -- sent | failed | skipped_low_risk | skipped_cooldown
  outcome TEXT NOT NULL,
  -- 失敗時的 error code（如 telegram_send_failed）；不存原文 / URL / token。
  error_code TEXT,
  http_status INT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 冪等補欄位：若 notification_logs 曾以較少欄位建立過，補上缺漏欄位。
ALTER TABLE notification_logs ADD COLUMN IF NOT EXISTS alert_id UUID REFERENCES care_alerts(id);
ALTER TABLE notification_logs ADD COLUMN IF NOT EXISTS elder_id UUID;
ALTER TABLE notification_logs ADD COLUMN IF NOT EXISTS channel TEXT NOT NULL DEFAULT 'telegram';
ALTER TABLE notification_logs ADD COLUMN IF NOT EXISTS risk_level TEXT;
ALTER TABLE notification_logs ADD COLUMN IF NOT EXISTS outcome TEXT NOT NULL DEFAULT '';
ALTER TABLE notification_logs ADD COLUMN IF NOT EXISTS error_code TEXT;
ALTER TABLE notification_logs ADD COLUMN IF NOT EXISTS http_status INT;
ALTER TABLE notification_logs ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

CREATE INDEX IF NOT EXISTS idx_notif_log_alert
ON notification_logs (alert_id);

CREATE INDEX IF NOT EXISTS idx_notif_log_created
ON notification_logs (created_at DESC);

-- audit_logs：敏感操作稽核（帳號刪除 / Care Alert 狀態變更 / consent 寫入 …）。
-- metadata 僅結構化非敏感欄位；絕不存 PII（email / ip）/ 原文 / token。
CREATE TABLE IF NOT EXISTS audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  -- elder | caregiver | system
  actor_type TEXT,
  -- user_id / 識別（非 PII 明碼），可空。
  actor_id TEXT,
  -- account_delete | care_alert_status_change | consent_record …
  action TEXT NOT NULL,
  target_type TEXT,
  target_id TEXT,
  -- success | failed
  outcome TEXT,
  -- 僅結構化非敏感欄位（如 from/to status、刪除計數）；禁放原文 / email / ip / token。
  metadata JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 冪等補欄位：若 audit_logs 曾以較少欄位建立過，補上缺漏欄位。
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS actor_type TEXT;
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS actor_id TEXT;
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS action TEXT NOT NULL DEFAULT '';
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS target_type TEXT;
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS target_id TEXT;
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS outcome TEXT;
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS metadata JSONB;
ALTER TABLE audit_logs ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

CREATE INDEX IF NOT EXISTS idx_audit_action
ON audit_logs (action);

CREATE INDEX IF NOT EXISTS idx_audit_actor
ON audit_logs (actor_id);

CREATE INDEX IF NOT EXISTS idx_audit_created
ON audit_logs (created_at DESC);
