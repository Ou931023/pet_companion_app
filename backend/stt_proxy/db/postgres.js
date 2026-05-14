const dotenv = require("dotenv");
const { Pool } = require("pg");

dotenv.config();

let pool;
let availability;

function pgvectorEnabled() {
  return String(process.env.PGVECTOR_ENABLED || "").toLowerCase() === "true";
}

function getPool() {
  if (!process.env.DATABASE_URL || !pgvectorEnabled()) {
    return null;
  }
  if (!pool) {
    pool = new Pool({
      connectionString: process.env.DATABASE_URL,
      max: Number(process.env.PG_POOL_MAX || 10),
      idleTimeoutMillis: Number(process.env.PG_IDLE_TIMEOUT_MS || 30000),
      connectionTimeoutMillis: Number(process.env.PG_CONNECTION_TIMEOUT_MS || 2000),
    });
    pool.on("error", (error) => {
      availability = false;
      console.error("[postgres] idle client error", error?.message || error);
    });
  }
  return pool;
}

async function query(text, params = []) {
  const activePool = getPool();
  if (!activePool) {
    const error = new Error("PostgreSQL is not configured");
    error.code = "POSTGRES_NOT_CONFIGURED";
    throw error;
  }
  return activePool.query(text, params);
}

async function isPostgresAvailable() {
  if (!process.env.DATABASE_URL || !pgvectorEnabled()) return false;
  if (availability === true) return true;
  try {
    await query("SELECT 1");
    availability = true;
    return true;
  } catch (error) {
    availability = false;
    console.error("[postgres] unavailable, using JSON fallback", error?.message || error);
    return false;
  }
}

async function closePool() {
  availability = undefined;
  if (!pool) return;
  const activePool = pool;
  pool = undefined;
  await activePool.end();
}

module.exports = {
  getPool,
  query,
  isPostgresAvailable,
  closePool,
};
