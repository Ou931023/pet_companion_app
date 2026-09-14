"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const originalDatabaseUrl = process.env.DATABASE_URL;
const originalTimeout = process.env.PG_CONNECTION_TIMEOUT_MS;
const originalPgvectorEnabled = process.env.PGVECTOR_ENABLED;

function restoreEnv() {
  if (originalDatabaseUrl === undefined) delete process.env.DATABASE_URL;
  else process.env.DATABASE_URL = originalDatabaseUrl;
  if (originalTimeout === undefined) delete process.env.PG_CONNECTION_TIMEOUT_MS;
  else process.env.PG_CONNECTION_TIMEOUT_MS = originalTimeout;
  if (originalPgvectorEnabled === undefined) delete process.env.PGVECTOR_ENABLED;
  else process.env.PGVECTOR_ENABLED = originalPgvectorEnabled;
}

test.afterEach(async () => {
  const postgres = require("./postgres");
  await postgres.closePool();
  restoreEnv();
});

test("runtime pool allows ten seconds for managed PostgreSQL cold resume", () => {
  process.env.DATABASE_URL = "postgresql://user:password@example.invalid/app";
  delete process.env.PG_CONNECTION_TIMEOUT_MS;
  const postgres = require("./postgres");

  expectPoolTimeout(postgres, 10000);
});

test("getPool uses DATABASE_URL without requiring PGVECTOR_ENABLED", () => {
  process.env.DATABASE_URL = "postgresql://user:password@example.invalid/app";
  process.env.PGVECTOR_ENABLED = "false";
  const postgres = require("./postgres");

  assert.ok(postgres.getPool());
});

test("PG_CONNECTION_TIMEOUT_MS still overrides the production default", () => {
  process.env.DATABASE_URL = "postgresql://user:password@example.invalid/app";
  process.env.PG_CONNECTION_TIMEOUT_MS = "15000";
  const postgres = require("./postgres");

  expectPoolTimeout(postgres, 15000);
});

test("availability check retries after a transient connection failure", async () => {
  process.env.DATABASE_URL = "postgresql://user:password@example.invalid/app";
  const postgres = require("./postgres");
  const pool = postgres.getPool();
  let attempts = 0;
  pool.query = async () => {
    attempts += 1;
    if (attempts === 1) throw new Error("temporary connection timeout");
    return { rows: [{ value: 1 }] };
  };

  const originalConsoleError = console.error;
  console.error = () => {};
  try {
    assert.equal(await postgres.isPostgresAvailable(), false);
    assert.equal(await postgres.isPostgresAvailable(), true);
    assert.equal(attempts, 2);
  } finally {
    console.error = originalConsoleError;
  }
});

function expectPoolTimeout(postgres, expected) {
  const pool = postgres.getPool();
  assert.ok(pool);
  assert.equal(pool.options.connectionTimeoutMillis, expected);
}
