'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const { runInNewContext } = require('node:vm');
const doc = readFileSync(resolve(__dirname, '../docs/TEXT_RELEASE_READINESS_20261015.md'), 'utf8');
const source = doc.split("<<'MODEL_SETTINGS'\n")[1].split('\nMODEL_SETTINGS')[0];
const keys = ['COMPANION_CHAT_MODEL','MEMORY_MODEL','MEMORY_EXTRACT_MODEL','CONVERSATION_TITLE_MODEL','SEARCH_SUMMARY_MODEL','WEB_SEARCH_SUMMARY_MODEL','DAILY_CARE_VISION_MODEL','STT_MODEL','REALTIME_MODEL','LEGACY_REALTIME_MODEL','STT_LANGUAGES'];
function inspect(values) {
  const lines = []; const reads = [];
  const env = new Proxy(values, { get(target, key) { assert.ok(keys.includes(key)); reads.push(key); return target[key]; },
    ownKeys() { assert.fail('must not enumerate environment'); } });
  runInNewContext(source, { process: { env }, console: { log: x => lines.push(x) } }, { timeout: 100 });
  assert.deepEqual(reads, keys); assert.equal(lines.length, 11); return lines.join('\n');
}
test('fixed whitelist reads only named settings and reports absent/empty', () => {
  const out = inspect({ MEMORY_MODEL: '' });
  assert.ok(out.includes('MEMORY_MODEL=EMPTY')); assert.ok(out.includes('STT_MODEL=UNSET'));
});
test('known model IDs and language codes print safely', () => {
  const out = inspect({ COMPANION_CHAT_MODEL: 'gpt-6-luna', STT_LANGUAGES: 'zh-tw, en,cmn' });
  assert.ok(out.includes('COMPANION_CHAT_MODEL=gpt-6-luna')); assert.ok(out.includes('STT_LANGUAGES=zh-tw,en,cmn'));
});
for (const secret of ['sk-synthetic-secret', 'gpt-synthetic-secret', 'https://user:pass@example.com', 'gpt-6-luna\nKEY=secret', 'en,sk-synthetic-secret', 'x'.repeat(500), 'gpt-6-luna-2026-10-15']) {
  test('unknown or suspicious value is masked: ' + secret.slice(0, 18), () => {
    const out = inspect({ MEMORY_MODEL: secret, STT_LANGUAGES: secret, OPENAI_API_KEY: 'never-read' });
    assert.ok(out.includes('MEMORY_MODEL=REDACTED')); assert.ok(out.includes('STT_LANGUAGES=REDACTED'));
    assert.ok(!out.includes(secret)); assert.ok(!out.includes('never-read'));
  });
}
test('reported token base-price arithmetic is reproducible', () => {
  assert.equal((39 + 49) * 0.10 / 1e6 + (28 + 13) * 0.50 / 1e6, 0.0000293);
});
