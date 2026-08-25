"use strict";

const fs = require("fs");
const path = require("path");
const { Pool } = require("pg");

const extensionSql = `
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS vector;
`;

function shouldRunStartupMigrations(env = process.env) {
  if (!env.DATABASE_URL) return false;
  if (env.NODE_ENV === "test") return false;
  return String(env.AUTO_MIGRATE_ON_START || "false").toLowerCase() === "true";
}

async function applySqlFiles(client, migrationsDir) {
  if (!fs.existsSync(migrationsDir)) return [];
  const files = fs
    .readdirSync(migrationsDir)
    .filter((name) => name.endsWith(".sql"))
    .sort();

  for (const file of files) {
    const sql = fs.readFileSync(path.join(migrationsDir, file), "utf8");
    await client.query(sql);
  }
  return files;
}

async function runStartupMigrations({
  env = process.env,
  logger = console,
  migrationsDir = path.join(__dirname, "migrations"),
} = {}) {
  if (!shouldRunStartupMigrations(env)) {
    return { skipped: true, appliedFiles: [] };
  }

  const pool = new Pool({
    connectionString: env.DATABASE_URL,
    max: 1,
    idleTimeoutMillis: Number(env.PG_IDLE_TIMEOUT_MS || 30000),
    connectionTimeoutMillis: Number(env.PG_CONNECTION_TIMEOUT_MS || 5000),
  });

  const client = await pool.connect();
  try {
    logger.log("[DB] startup migrations begin");
    await client.query(extensionSql);
    const appliedFiles = await applySqlFiles(client, migrationsDir);
    logger.log("[DB] startup migrations completed", {
      migrationCount: appliedFiles.length,
    });
    return { skipped: false, appliedFiles };
  } finally {
    client.release();
    await pool.end();
  }
}

module.exports = {
  runStartupMigrations,
  shouldRunStartupMigrations,
};
