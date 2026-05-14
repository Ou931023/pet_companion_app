const fs = require('fs');
const path = require('path');
const dotenv = require('dotenv');
dotenv.config();

const pool = require('./pool');

const extensionSql = `
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS vector;
`;

const tableSql = `
-- create memory_items table (fallback when migrations/ not present)
CREATE TABLE IF NOT EXISTS memory_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id text NOT NULL,
  session_id text,
  source_turn_id text,
  memory_type text NOT NULL CHECK (memory_type IN ('profile','episodic','emotional')),
  summary text NOT NULL,
  original_user_text text,
  ai_reply text,
  emotion text,
  importance real NOT NULL DEFAULT 0.5,
  tags text[] NOT NULL DEFAULT '{}',
  embedding vector(1536) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  last_used_at timestamptz,
  deleted_at timestamptz
);
`;

async function applyExtensions(client) {
  console.log('Applying extensions...');
  await client.query(extensionSql);
  console.log('Extensions applied.');
}

async function applySqlFiles(client) {
  const migrationsDir = path.join(__dirname, 'migrations');
  if (!fs.existsSync(migrationsDir)) return;

  const files = fs
    .readdirSync(migrationsDir)
    .filter((name) => name.endsWith('.sql'))
    .sort();

  for (const file of files) {
    const sql = fs.readFileSync(path.join(migrationsDir, file), 'utf8');
    console.log(`Applying migration file ${file}`);
    await client.query(sql);
  }
}

async function migrate() {
  const client = await pool.connect();
  try {
    console.log('Running migrations...');
    // Always ensure extensions exist
    await applyExtensions(client);

    const migrationsDir = path.join(__dirname, 'migrations');
    if (fs.existsSync(migrationsDir)) {
      // Apply ordered migration files
      await applySqlFiles(client);
    } else {
      // No migrations present, apply fallback table creation
      console.log('No migrations directory; applying fallback table creation');
      await client.query(tableSql);
    }

    console.log('[DB] migrations completed');
  } catch (err) {
    console.error('[DB] migration failed:', err);
    process.exitCode = 1;
  } finally {
    client.release();
    await pool.end();
  }
}

migrate();
