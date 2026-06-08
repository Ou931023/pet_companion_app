const assert = require("node:assert/strict");
const { test } = require("node:test");
const fs = require("node:fs");
const path = require("node:path");

// CR-0043 B1：migration 014 靜態審查（本機無 Postgres → 不對真 DB 跑，比照 migration013.test.js）。
// migrate.js 會 glob migrations/*.sql 重跑，故每個 statement 必須冪等可重跑。

const SQL_PATH = path.join(__dirname, "migrations", "014_add_users_status.sql");

function readSql() {
  return fs.readFileSync(SQL_PATH, "utf8");
}

function statements(sql) {
  const stripped = sql
    .split("\n")
    .map((line) => line.replace(/--.*$/, ""))
    .join("\n");
  return stripped
    .split(";")
    .map((s) => s.trim())
    .filter(Boolean);
}

test("migration 014 檔案存在", () => {
  assert.ok(fs.existsSync(SQL_PATH));
});

test("新增 users.status 欄（TEXT NOT NULL DEFAULT 'active'）", () => {
  const sql = readSql();
  assert.match(
    sql,
    /ALTER TABLE users ADD COLUMN IF NOT EXISTS status\s+TEXT NOT NULL DEFAULT 'active'/i,
  );
});

test("每個 ALTER TABLE ADD COLUMN 皆 IF NOT EXISTS（可重跑冪等）", () => {
  const stmts = statements(readSql());
  assert.ok(stmts.length >= 1, "至少一條 statement");
  for (const stmt of stmts) {
    if (/^ALTER\s+TABLE/i.test(stmt)) {
      assert.match(stmt, /ADD COLUMN IF NOT EXISTS/i, `非冪等 ALTER: ${stmt.slice(0, 60)}`);
    }
  }
});

test("只動 users 表（純新增欄，不改既有欄、不動其他表）", () => {
  for (const stmt of statements(readSql())) {
    if (/^ALTER\s+TABLE/i.test(stmt)) {
      assert.match(stmt, /ALTER TABLE users/i, `不應動到其他表: ${stmt.slice(0, 60)}`);
    }
    // 不得出現 DROP / 改型別等破壞性操作。
    assert.ok(!/DROP\s+COLUMN/i.test(stmt), "不應 DROP COLUMN");
    assert.ok(!/ALTER\s+COLUMN/i.test(stmt), "不應 ALTER COLUMN（改既有欄）");
  }
});

test("預設 active → 對既有 row 零破壞（向後相容）", () => {
  assert.match(readSql(), /DEFAULT 'active'/i);
});
