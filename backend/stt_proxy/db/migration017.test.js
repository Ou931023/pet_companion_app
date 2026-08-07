const assert = require("node:assert/strict");
const { test } = require("node:test");
const fs = require("node:fs");
const path = require("node:path");

// CR-0097：app_usage_events migration 靜態審查。
// 本機測試不碰真 Postgres，只檢查 schema 安全性與 migration 可重跑。

const SQL_PATH = path.join(__dirname, "migrations", "017_create_app_usage_events.sql");

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

test("migration 017 檔案存在，建立 app_usage_events", () => {
  const sql = readSql();
  assert.ok(fs.existsSync(SQL_PATH));
  assert.match(sql, /CREATE TABLE IF NOT EXISTS app_usage_events/i);
});

test("使用 server 推導 elder_id，事件 metadata 存 JSONB", () => {
  const sql = readSql();
  assert.match(sql, /elder_id TEXT NOT NULL/i);
  assert.match(sql, /user_id TEXT/i);
  assert.match(sql, /event_type TEXT NOT NULL/i);
  assert.match(sql, /metadata_json JSONB NOT NULL DEFAULT '\{\}'::jsonb/i);
});

test("查詢索引支援後台依長者與事件類型聚合", () => {
  const sql = readSql();
  assert.match(sql, /idx_app_usage_events_elder_time/i);
  assert.match(sql, /ON app_usage_events \(elder_id, event_at DESC\)/i);
  assert.match(sql, /idx_app_usage_events_type_time/i);
  assert.match(sql, /ON app_usage_events \(event_type, event_at DESC\)/i);
});

test("所有 CREATE TABLE / CREATE INDEX 皆 IF NOT EXISTS、ALTER 皆 ADD COLUMN IF NOT EXISTS", () => {
  for (const stmt of statements(readSql())) {
    if (/^CREATE TABLE/i.test(stmt)) {
      assert.match(stmt, /CREATE TABLE IF NOT EXISTS/i);
    }
    if (/^CREATE INDEX/i.test(stmt)) {
      assert.match(stmt, /CREATE INDEX IF NOT EXISTS/i);
    }
    if (/^ALTER TABLE/i.test(stmt)) {
      assert.match(stmt, /ADD COLUMN IF NOT EXISTS/i);
    }
  }
});

test("無破壞性操作與種子假資料", () => {
  const code = statements(readSql()).join(";\n");
  assert.ok(!/DROP\s+COLUMN/i.test(code));
  assert.ok(!/DROP\s+TABLE/i.test(code));
  assert.ok(!/TRUNCATE/i.test(code));
  assert.ok(!/^DELETE\s+FROM/im.test(code));
  assert.ok(!/INSERT\s+INTO/i.test(code), "usage events 不應有 seed 假資料");
});
