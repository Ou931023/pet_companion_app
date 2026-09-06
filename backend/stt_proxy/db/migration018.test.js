"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const sql = fs.readFileSync(
  path.join(__dirname, "migrations", "018_store_daily_care_proof_images.sql"),
  "utf8",
);

test("migration 018 將照護照片與 MIME type 持久化到 PostgreSQL", () => {
  assert.match(sql, /proof_image_bytes\s+BYTEA/i);
  assert.match(sql, /proof_mime_type\s+TEXT/i);
  assert.match(sql, /ADD COLUMN IF NOT EXISTS/i);
  assert.doesNotMatch(sql, /\bDROP\b|\bTRUNCATE\b/i);
});
