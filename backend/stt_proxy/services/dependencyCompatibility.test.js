const { test } = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const multer = require('multer');
const { gzipSync } = require('node:zlib');
const { fetch: undiciFetch } = require('undici');

// Dependency-only fixtures: no application, DB, credentials or notification imports.
async function withServer(app, run) {
  const server = await new Promise(resolve => {
    const listening = app.listen(0, '127.0.0.1', () => resolve(listening));
  });
  try {
    await run(`http://127.0.0.1:${server.address().port}`);
  } finally {
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  }
}

test('JSON parser preserves gzip, malformed JSON and decoded size limits', async () => {
  const app = express();
  app.use(express.json({ limit: 32 }));
  app.post('/', (req, res) => res.json(req.body));
  app.use((error, _req, res, _next) => res.status(error.status || 500).end());
  await withServer(app, async base => {
    for (const [input, expected] of [
      ['{"value":"ok"}', 200], ['{"value":', 400],
      [JSON.stringify({ value: 'x'.repeat(64) }), 413],
    ]) {
      const response = await fetch(base, {
        method: 'POST', headers: { 'Content-Type': 'application/json', 'Content-Encoding': 'gzip' },
        body: gzipSync(input), signal: AbortSignal.timeout(3000),
      });
      assert.equal(response.status, expected);
      if (expected === 200) assert.deepEqual(await response.json(), { value: 'ok' });
      else await response.arrayBuffer();
    }
  });
});

test('multer accepts an exact fieldSize boundary and rejects one byte over', async () => {
  const app = express();
  app.post('/', multer({ limits: { fieldSize: 4, fields: 1, parts: 1 } }).none(),
    (req, res) => res.json(req.body));
  app.use((error, _req, res, _next) => res.status(400).json({ code: error.code }));
  await withServer(app, async base => {
    for (const value of ['abcd', 'abcde']) {
      const form = new FormData();
      form.set('note', value);
      const response = await fetch(base, { method: 'POST', body: form, signal: AbortSignal.timeout(3000) });
      assert.equal(response.status, value.length === 4 ? 200 : 400);
      assert.deepEqual(await response.json(), value.length === 4 ? { note: value } : { code: 'LIMIT_FIELD_VALUE' });
    }
  });
});

test('locked undici fetch handles gzip and HTTP error responses on loopback', async () => {
  const app = express();
  app.get('/ok', (_req, res) => res.set('Content-Encoding', 'gzip').send(gzipSync('synthetic response')));
  app.get('/missing', (_req, res) => res.status(404).send('synthetic missing'));
  await withServer(app, async base => {
    const ok = await undiciFetch(`${base}/ok`, { signal: AbortSignal.timeout(3000) });
    assert.equal(ok.status, 200);
    assert.equal(await ok.text(), 'synthetic response');
    const missing = await undiciFetch(`${base}/missing`, { signal: AbortSignal.timeout(3000) });
    assert.equal(missing.status, 404);
    assert.equal(await missing.text(), 'synthetic missing');
  });
});
