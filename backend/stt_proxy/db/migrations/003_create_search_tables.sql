CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS crawled_documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  url TEXT NOT NULL UNIQUE,
  site_name TEXT,
  domain TEXT,
  published_at TEXT,
  crawled_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  content TEXT NOT NULL,
  summary TEXT,
  category TEXT NOT NULL DEFAULT 'general_web_search',
  source_type TEXT NOT NULL DEFAULT 'trusted_crawl',
  is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS search_queries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_query TEXT NOT NULL,
  query_mode TEXT NOT NULL,
  used_provider TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS search_results (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  query_id UUID REFERENCES search_queries(id) ON DELETE CASCADE,
  document_id UUID REFERENCES crawled_documents(id) ON DELETE SET NULL,
  title TEXT NOT NULL,
  url TEXT NOT NULL,
  snippet TEXT,
  rank INTEGER NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_crawled_documents_category
  ON crawled_documents(category)
  WHERE is_active = TRUE;

CREATE INDEX IF NOT EXISTS idx_search_queries_created_at
  ON search_queries(created_at DESC);
