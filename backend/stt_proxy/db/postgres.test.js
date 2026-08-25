const assert = require("node:assert/strict");
const test = require("node:test");

const postgres = require("./postgres");

test("getPool uses DATABASE_URL without requiring PGVECTOR_ENABLED", async () => {
  const oldDatabaseUrl = process.env.DATABASE_URL;
  const oldPgvectorEnabled = process.env.PGVECTOR_ENABLED;
  try {
    process.env.DATABASE_URL = "postgresql://user:pass@example.invalid:5432/app";
    process.env.PGVECTOR_ENABLED = "false";

    assert.ok(postgres.getPool());
  } finally {
    if (oldDatabaseUrl == null) delete process.env.DATABASE_URL;
    else process.env.DATABASE_URL = oldDatabaseUrl;
    if (oldPgvectorEnabled == null) delete process.env.PGVECTOR_ENABLED;
    else process.env.PGVECTOR_ENABLED = oldPgvectorEnabled;
    await postgres.closePool();
  }
});
