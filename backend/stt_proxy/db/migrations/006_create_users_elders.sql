-- CR-0006 Batch 1：身份與綁定模型（users / elders）
-- 契約見 PROJECT_ARCHITECTURE.md §10.3。
-- 沿用既有 migrations（002/004）的 pgcrypto + gen_random_uuid() 慣例與 IF NOT EXISTS 冪等寫法。

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- elders：每位長者的基本資料。先建（users.elder_id 會 FK 到這裡）。
CREATE TABLE IF NOT EXISTS elders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  display_name TEXT,
  birth_year INTEGER,
  gender TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- users：登入帳號，對應一位長者（elder_id）。firebase_uid 唯一。
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  firebase_uid TEXT UNIQUE,
  elder_id UUID REFERENCES elders(id),
  role TEXT NOT NULL DEFAULT 'elder',
  email TEXT,
  email_verified BOOLEAN NOT NULL DEFAULT FALSE,
  display_name TEXT,
  auth_provider TEXT,
  provider_user_id TEXT,
  binding_status TEXT NOT NULL DEFAULT 'pending',
  binding_deadline TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  verified_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
);

-- 冪等補欄位：若 users 曾以較少欄位建立過，補上缺漏欄位。
ALTER TABLE users ADD COLUMN IF NOT EXISTS firebase_uid TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS elder_id UUID REFERENCES elders(id);
ALTER TABLE users ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT 'elder';
ALTER TABLE users ADD COLUMN IF NOT EXISTS email TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS email_verified BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS display_name TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS auth_provider TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS provider_user_id TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS binding_status TEXT NOT NULL DEFAULT 'pending';
ALTER TABLE users ADD COLUMN IF NOT EXISTS binding_deadline TIMESTAMPTZ;
ALTER TABLE users ADD COLUMN IF NOT EXISTS verified_at TIMESTAMPTZ;
ALTER TABLE users ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ;

-- firebase_uid 唯一性（建表時的 UNIQUE 在既有表上不會自動補，這裡以唯一索引補強）。
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_firebase_uid_unique
ON users (firebase_uid)
WHERE firebase_uid IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_users_elder_id
ON users (elder_id);
