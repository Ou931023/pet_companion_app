-- CR-0040 Batch A：resident-caregiver 授權關聯表（resident_caregiver_links）。
-- 契約見 docs/CHANGE_REVIEW.md CR-0040 §5 與 pet_companion_app/CLAUDE.md §3.3（核心表）。
--
-- 命名橋接（CR-0040 §5 裁決）：
--   - 表名保留 `resident_caregiver_links`（對齊 CLAUDE.md §3.3 核心表清單）。
--   - 欄位用 `elder_id`（對齊真實 elders 表與既有 care_alerts.elder_id FK 慣例）。
--     「resident」概念即本專案 elder。
--   - caregiver_id FK 至 users(id)：caregiver 將是 users.role='caregiver'（§12 #5 落位）。
--
-- migrate.js 啟動時 glob migrations/*.sql 依檔名排序重跑、無 schema_migrations 追蹤，
-- 故本檔必須完全冪等：每個 CREATE / ALTER / INDEX 皆 IF NOT EXISTS，重複執行不報錯、不副作用。
-- 沿用既有 migrations（006/011）的 pgcrypto + gen_random_uuid() 慣例。
--
-- 本批次 migration only：只建表，不接任何 service / 路由（Batch B/C 才接）。
-- 純新增表，不改 elders / users / care_alerts 既有欄位 → 對既有資料零破壞。

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- resident_caregiver_links：哪位 caregiver 被授權存取哪位 elder（resident）。
CREATE TABLE IF NOT EXISTS resident_caregiver_links (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  -- resident = elder：被照護的長者。
  elder_id UUID NOT NULL REFERENCES elders(id),
  -- caregiver 身分錨於 users（users.role='caregiver'，§12 #5 建立帳號時落位）。
  caregiver_id UUID NOT NULL REFERENCES users(id),
  -- 授權角色：primary | secondary | viewer。
  role TEXT NOT NULL DEFAULT 'primary',
  -- 關聯狀態：active | revoked。授權過濾只取 active。
  status TEXT NOT NULL DEFAULT 'active',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ
);

-- 冪等補欄位：若 resident_caregiver_links 曾以較少欄位建立過，補上缺漏欄位。
ALTER TABLE resident_caregiver_links ADD COLUMN IF NOT EXISTS elder_id UUID REFERENCES elders(id);
ALTER TABLE resident_caregiver_links ADD COLUMN IF NOT EXISTS caregiver_id UUID REFERENCES users(id);
ALTER TABLE resident_caregiver_links ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT 'primary';
ALTER TABLE resident_caregiver_links ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'active';
ALTER TABLE resident_caregiver_links ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE resident_caregiver_links ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ;
ALTER TABLE resident_caregiver_links ADD COLUMN IF NOT EXISTS revoked_at TIMESTAMPTZ;

-- 查詢索引：以 caregiver 取授權 elder 集合（只取 active）。
CREATE INDEX IF NOT EXISTS idx_rcl_caregiver_active
ON resident_caregiver_links (caregiver_id)
WHERE status = 'active';

-- 查詢索引：以 elder 反查 caregiver。
CREATE INDEX IF NOT EXISTS idx_rcl_elder
ON resident_caregiver_links (elder_id);

-- 唯一鍵：同一 elder + caregiver 只允許一筆 active 關聯（避免重複授權）。
CREATE UNIQUE INDEX IF NOT EXISTS idx_rcl_unique_active
ON resident_caregiver_links (elder_id, caregiver_id)
WHERE status = 'active';
