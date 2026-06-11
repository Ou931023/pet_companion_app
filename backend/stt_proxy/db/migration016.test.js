const assert = require("node:assert/strict");
const { test } = require("node:test");
const fs = require("node:fs");
const path = require("node:path");

// CR-0068：migration 016 靜態審查（本機無 Postgres → 不對真 DB 跑，比照 migration014/015）。
// migrate.js 會 glob migrations/*.sql 重跑，故每個 statement 必須冪等可重跑：
// 只用 CREATE TABLE/INDEX IF NOT EXISTS + ADD COLUMN IF NOT EXISTS，無破壞性操作。

const SQL_PATH = path.join(__dirname, "migrations", "016_create_daily_care_tasks.sql");

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

test("migration 016 檔案存在", () => {
  assert.ok(fs.existsSync(SQL_PATH));
});

test("建立 daily_care_tasks / daily_care_task_submissions 兩表（IF NOT EXISTS）", () => {
  const sql = readSql();
  assert.match(sql, /CREATE TABLE IF NOT EXISTS daily_care_tasks/i);
  assert.match(sql, /CREATE TABLE IF NOT EXISTS daily_care_task_submissions/i);
});

test("submission 以 task_id FK 參照 tasks 並 ON DELETE CASCADE", () => {
  const sql = readSql();
  assert.match(sql, /task_id\s+TEXT\s+NOT NULL\s+REFERENCES daily_care_tasks\(id\) ON DELETE CASCADE/i);
});

test("id / elder_id 為 TEXT（不綁 elders UUID FK，避免 demo id FK 違規）", () => {
  const sql = readSql();
  assert.match(sql, /id TEXT PRIMARY KEY/i);
  assert.match(sql, /elder_id TEXT/i);
  assert.ok(!/REFERENCES elders/i.test(sql), "不應參照 elders 表");
});

test("verification 整包存 JSONB（verification_json）", () => {
  assert.match(readSql(), /verification_json JSONB/i);
});

test("所有 CREATE TABLE / CREATE INDEX 皆 IF NOT EXISTS、ALTER 皆 ADD COLUMN IF NOT EXISTS（冪等）", () => {
  for (const stmt of statements(readSql())) {
    if (/^CREATE TABLE/i.test(stmt)) {
      assert.match(stmt, /CREATE TABLE IF NOT EXISTS/i, `非冪等 CREATE TABLE: ${stmt.slice(0, 60)}`);
    }
    if (/^CREATE INDEX/i.test(stmt)) {
      assert.match(stmt, /CREATE INDEX IF NOT EXISTS/i, `非冪等 CREATE INDEX: ${stmt.slice(0, 60)}`);
    }
    if (/^ALTER TABLE/i.test(stmt)) {
      assert.match(stmt, /ADD COLUMN IF NOT EXISTS/i, `ALTER 僅限 ADD COLUMN IF NOT EXISTS: ${stmt.slice(0, 60)}`);
    }
  }
});

test("無破壞性操作（不得 DROP COLUMN / DROP TABLE / TRUNCATE / DELETE）", () => {
  const code = statements(readSql()).join(";\n");
  assert.ok(!/DROP\s+COLUMN/i.test(code), "不應 DROP COLUMN");
  assert.ok(!/DROP\s+TABLE/i.test(code), "不應 DROP TABLE");
  assert.ok(!/TRUNCATE/i.test(code), "不應 TRUNCATE");
  assert.ok(!/^DELETE\s+FROM/im.test(code), "不應 DELETE FROM");
});

test("不灌種子資料（任務由 App runtime 建立，無 INSERT）", () => {
  const code = statements(readSql()).join(";\n");
  assert.ok(!/INSERT\s+INTO/i.test(code), "016 不應有 INSERT 種子");
});
