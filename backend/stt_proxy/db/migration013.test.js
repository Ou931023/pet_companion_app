const assert = require("node:assert/strict");
const { test } = require("node:test");
const fs = require("node:fs");
const path = require("node:path");

// CR-0040 Batch A：migration 013 靜態審查。
// 本機無 Postgres → migration 不對真 DB 跑。此測試以靜態解析驗冪等與 schema 形狀
// （migrate.js 會 glob migrations/*.sql 重跑，每個 statement 必須冪等可重跑）。

const SQL_PATH = path.join(
  __dirname,
  "migrations",
  "013_create_resident_caregiver_links.sql",
);

function readSql() {
  return fs.readFileSync(SQL_PATH, "utf8");
}

// 去掉行註解（-- ...）後切成 statement，方便逐句檢查冪等 guard。
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

test("migration 013 檔案存在", () => {
  assert.ok(fs.existsSync(SQL_PATH));
});

test("表名為 resident_caregiver_links（對齊 CLAUDE.md §3.3）", () => {
  const sql = readSql();
  assert.match(sql, /CREATE TABLE IF NOT EXISTS resident_caregiver_links/);
});

test("每個 CREATE TABLE / INDEX / EXTENSION 皆 IF NOT EXISTS（可重跑冪等）", () => {
  for (const stmt of statements(readSql())) {
    if (/^CREATE\s+TABLE/i.test(stmt)) {
      assert.match(stmt, /CREATE TABLE IF NOT EXISTS/i, `非冪等 CREATE TABLE: ${stmt.slice(0, 60)}`);
    }
    if (/^CREATE\s+(UNIQUE\s+)?INDEX/i.test(stmt)) {
      assert.match(stmt, /IF NOT EXISTS/i, `非冪等 CREATE INDEX: ${stmt.slice(0, 60)}`);
    }
    if (/^CREATE\s+EXTENSION/i.test(stmt)) {
      assert.match(stmt, /IF NOT EXISTS/i, `非冪等 CREATE EXTENSION: ${stmt.slice(0, 60)}`);
    }
  }
});

test("每個 ALTER TABLE ADD COLUMN 皆 IF NOT EXISTS（可重跑冪等）", () => {
  for (const stmt of statements(readSql())) {
    if (/^ALTER\s+TABLE/i.test(stmt)) {
      assert.match(stmt, /ADD COLUMN IF NOT EXISTS/i, `非冪等 ALTER: ${stmt.slice(0, 60)}`);
    }
  }
});

test("欄位採 elder_id（resident=elder）+ caregiver_id，FK 指向既有表", () => {
  const sql = readSql();
  assert.match(sql, /elder_id\s+UUID[^,]*REFERENCES\s+elders\(id\)/i);
  assert.match(sql, /caregiver_id\s+UUID[^,]*REFERENCES\s+users\(id\)/i);
});

test("含 role / status / 時間戳欄位", () => {
  const sql = readSql();
  assert.match(sql, /\brole\s+TEXT/i);
  assert.match(sql, /\bstatus\s+TEXT/i);
  assert.match(sql, /created_at\s+TIMESTAMPTZ/i);
  assert.match(sql, /revoked_at\s+TIMESTAMPTZ/i);
});

test("唯一鍵限制 active (elder_id, caregiver_id)", () => {
  const sql = readSql();
  assert.match(sql, /CREATE UNIQUE INDEX IF NOT EXISTS[\s\S]*resident_caregiver_links[\s\S]*\(elder_id,\s*caregiver_id\)[\s\S]*WHERE status = 'active'/i);
});

test("不改既有表（不含 elders / users / care_alerts 的 ALTER）", () => {
  for (const stmt of statements(readSql())) {
    if (/^ALTER\s+TABLE/i.test(stmt)) {
      assert.match(
        stmt,
        /ALTER TABLE resident_caregiver_links/i,
        `不應動到既有表: ${stmt.slice(0, 60)}`,
      );
    }
  }
});
