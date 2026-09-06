const assert = require("node:assert/strict");
const test = require("node:test");

const {
  deleteAccountData,
  deleteAccountDataPostgres,
} = require("./sessionService");

function normalizeSql(sql) {
  return String(sql).replace(/\s+/g, " ").trim();
}

function createTransactionDb({ found = true, failPattern = null } = {}) {
  const statements = [];
  let released = false;
  const client = {
    async query(sql) {
      const normalized = normalizeSql(sql);
      statements.push(normalized);
      if (failPattern && failPattern.test(normalized)) {
        throw new Error("injected transaction failure");
      }
      if (normalized.startsWith("SELECT id, elder_id FROM users")) {
        return found
          ? { rows: [{ id: "user-1", elder_id: "elder-1" }], rowCount: 1 }
          : { rows: [], rowCount: 0 };
      }
      return { rows: [], rowCount: /^DELETE FROM /.test(normalized) ? 1 : 0 };
    },
    release() {
      released = true;
    },
  };
  return {
    db: {
      async isPostgresAvailable() {
        return true;
      },
      getPool() {
        return { connect: async () => client };
      },
    },
    statements,
    wasReleased: () => released,
  };
}

test("production account deletion removes all resident data in one transaction", async () => {
  const fake = createTransactionDb();
  const result = await deleteAccountDataPostgres("firebase-uid", fake.db);

  assert.equal(fake.statements[0], "BEGIN");
  assert.equal(fake.statements.at(-1), "COMMIT");
  assert.ok(!fake.statements.includes("ROLLBACK"));
  assert.equal(fake.wasReleased(), true);
  assert.deepEqual(
    {
      provider: result.provider,
      user: result.user,
      elder: result.elder,
      memories: result.memories,
      careAlerts: result.careAlerts,
    },
    { provider: "postgres", user: 1, elder: 1, memories: 2, careAlerts: 1 },
  );

  const sql = fake.statements.join("\n");
  for (const table of [
    "notification_logs",
    "consent_records",
    "resident_caregiver_links",
    "emotion_history",
    "elder_health_metrics",
    "game_cognitive_metrics",
    "daily_care_task_submissions",
    "daily_care_tasks",
    "app_usage_events",
    "care_alerts",
    "marketplace_orders",
    "memory_items",
    "companion_memories",
    "audit_logs",
    "users",
    "elders",
  ]) {
    assert.match(sql, new RegExp(`DELETE FROM ${table}\\b`), `${table} must be deleted`);
  }
  assert.ok(
    fake.statements.findIndex((statement) => statement.startsWith("DELETE FROM users")) >
      fake.statements.findIndex((statement) => statement.startsWith("DELETE FROM companion_memories")),
    "identity rows must be deleted only after dependent data",
  );
});

test("any account deletion failure rolls back before identity rows are removed", async () => {
  const fake = createTransactionDb({ failPattern: /^DELETE FROM emotion_history/ });

  await assert.rejects(
    () => deleteAccountDataPostgres("firebase-uid", fake.db),
    /injected transaction failure/,
  );

  assert.ok(fake.statements.includes("ROLLBACK"));
  assert.ok(!fake.statements.includes("COMMIT"));
  assert.ok(!fake.statements.some((statement) => statement.startsWith("DELETE FROM users")));
  assert.ok(!fake.statements.some((statement) => statement.startsWith("DELETE FROM elders")));
  assert.equal(fake.wasReleased(), true);
});

test("missing account is idempotent and still commits the transaction", async () => {
  const fake = createTransactionDb({ found: false });
  const result = await deleteAccountDataPostgres("missing-uid", fake.db);

  assert.equal(result.user, 0);
  assert.equal(result.elder, 0);
  assert.deepEqual(fake.statements.slice(-1), ["COMMIT"]);
  assert.ok(!fake.statements.some((statement) => statement.startsWith("DELETE FROM")));
  assert.equal(fake.wasReleased(), true);
});

test("production never falls back to JSON when PostgreSQL is unavailable", async () => {
  const db = {
    async isPostgresAvailable() {
      return false;
    },
  };

  await assert.rejects(
    () =>
      deleteAccountData("firebase-uid", {
        postgres: db,
        env: { APP_ENV: "production" },
      }),
    (error) => error && error.code === "POSTGRES_REQUIRED",
  );
});
