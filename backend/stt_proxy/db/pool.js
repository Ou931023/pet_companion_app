const { Pool } = require('pg');

// 正式與開發環境都只接受標準 PostgreSQL 環境設定；不得在原始碼提供
// 本機帳號、密碼或資料庫名稱 fallback。production 缺 DATABASE_URL 會由
// config/env.js 在 server 啟動時 fail-fast。
const pool = new Pool({
  connectionString: process.env.DATABASE_URL || undefined,
});

module.exports = pool;
