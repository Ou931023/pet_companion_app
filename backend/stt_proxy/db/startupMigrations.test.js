"use strict";

const assert = require("node:assert/strict");
const fs = require("fs");
const os = require("os");
const path = require("path");
const test = require("node:test");

const {
  shouldRunStartupMigrations,
} = require("./startupMigrations");

test("shouldRunStartupMigrations：production 預設不自動改 schema", () => {
  assert.equal(
    shouldRunStartupMigrations({
      NODE_ENV: "production",
      DATABASE_URL: "postgresql://example.invalid/db",
    }),
    false,
  );
});

test("shouldRunStartupMigrations：只有明確開啟才執行", () => {
  assert.equal(
    shouldRunStartupMigrations({
      NODE_ENV: "production",
      DATABASE_URL: "postgresql://example.invalid/db",
      AUTO_MIGRATE_ON_START: "true",
    }),
    true,
  );
  assert.equal(
    shouldRunStartupMigrations({
      NODE_ENV: "test",
      DATABASE_URL: "postgresql://example.invalid/db",
    }),
    false,
  );
  assert.equal(
    shouldRunStartupMigrations({
      NODE_ENV: "production",
      DATABASE_URL: "postgresql://example.invalid/db",
      AUTO_MIGRATE_ON_START: "false",
    }),
    false,
  );
});

test("startup migration runner source keeps migrations idempotent and ordered", () => {
  const source = fs.readFileSync(path.join(__dirname, "startupMigrations.js"), "utf8");
  assert.match(source, /CREATE EXTENSION IF NOT EXISTS pgcrypto/);
  assert.match(source, /CREATE EXTENSION IF NOT EXISTS vector/);
  assert.match(source, /\.filter\(\(name\) => name\.endsWith\("\.sql"\)\)\s*\.sort\(\)/);
  assert.match(source, /await client\.query\(sql\)/);
});

test("startup migration test fixture can create ordered SQL files", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "startup-migrations-"));
  fs.writeFileSync(path.join(dir, "002_second.sql"), "SELECT 2;");
  fs.writeFileSync(path.join(dir, "001_first.sql"), "SELECT 1;");
  const files = fs.readdirSync(dir).filter((name) => name.endsWith(".sql")).sort();
  assert.deepEqual(files, ["001_first.sql", "002_second.sql"]);
});
