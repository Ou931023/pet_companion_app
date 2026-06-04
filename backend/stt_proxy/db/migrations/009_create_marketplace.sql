-- CR-0032 長照商品商城平台 MVP：商品 / 訂單資料表。
--
-- MVP 階段 runtime 以 JSON store（data/marketplace_products.json /
-- data/marketplace_orders.json）為主，這份 schema 是「正式 PostgreSQL 方向」
-- 的對照，欄位與 JSON store 一致。可冪等重複執行（IF NOT EXISTS）。

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 商品
CREATE TABLE IF NOT EXISTS marketplace_products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  center_id TEXT,
  center_name TEXT,
  name TEXT NOT NULL,
  description TEXT,
  category TEXT,
  price INTEGER NOT NULL DEFAULT 0,
  stock INTEGER NOT NULL DEFAULT 0,
  image_url TEXT,
  status TEXT NOT NULL DEFAULT 'active',
  commission_rate NUMERIC(4, 3) NOT NULL DEFAULT 0.100,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_marketplace_products_status
ON marketplace_products (status);

CREATE INDEX IF NOT EXISTS idx_marketplace_products_center
ON marketplace_products (center_id);

-- 訂單（items 以 JSONB 保存明細，MVP 一張訂單僅含同一長照中心商品）
CREATE TABLE IF NOT EXISTS marketplace_orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT,
  elder_name TEXT,
  center_id TEXT,
  center_name TEXT,
  items_json JSONB NOT NULL DEFAULT '[]'::jsonb,
  total_amount INTEGER NOT NULL DEFAULT 0,
  commission_rate NUMERIC(4, 3) NOT NULL DEFAULT 0.100,
  commission_amount INTEGER NOT NULL DEFAULT 0,
  center_revenue INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'pending',
  delivery_note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_marketplace_orders_status
ON marketplace_orders (status);

CREATE INDEX IF NOT EXISTS idx_marketplace_orders_user
ON marketplace_orders (user_id);
