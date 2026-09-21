const assert = require('node:assert/strict');
const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const sql = fs.readFileSync(path.join(__dirname, 'migrations/019_create_mood_diary_entries.sql'), 'utf8');
test('diary migration is additive and replayable with ownership cascades and private default', () => {
  assert.match(sql, /CREATE TABLE IF NOT EXISTS mood_diary_entries/);
  assert.match(sql, /user_id UUID NOT NULL REFERENCES users\(id\) ON DELETE CASCADE/);
  assert.match(sql, /elder_id UUID NOT NULL REFERENCES elders\(id\) ON DELETE CASCADE/);
  assert.match(sql, /shared_with_caregiver BOOLEAN NOT NULL DEFAULT FALSE/);
  assert.match(sql, /char_length\(content\) BETWEEN 1 AND 1000/);
  assert.match(sql, /'happy', 'okay', 'low', 'worried'/);
  assert.equal((sql.match(/CREATE INDEX IF NOT EXISTS/g) || []).length, 2);
  assert.match(sql, /WHERE shared_with_caregiver = TRUE/);
  assert.doesNotMatch(sql, /\b(DROP|TRUNCATE|INSERT|DELETE)\s+(TABLE|FROM|INTO)/i);
});
