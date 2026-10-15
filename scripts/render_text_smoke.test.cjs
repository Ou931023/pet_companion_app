'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createRequire } = require('node:module');
const { resolve } = require('node:path');
const { spawnSync } = require('node:child_process');
const { readFileSync } = require('node:fs'); // Test source only; the runner never reads files.
const probe = require('./render_text_smoke.cjs');
const sdkRoot = process.env.SMOKE_TEST_SDK_DIR || resolve(__dirname, '../backend/stt_proxy');
const OpenAI = createRequire(resolve(sdkRoot, 'offline-test.cjs'))('openai');
const ENDPOINT = 'https://api.openai.com/v1/chat/completions';
const SENTINEL = 'SENSITIVE_SYNTHETIC_SENTINEL';
function payload(index = 0) {
  return { model: 'gpt-6-luna', choices: [{ finish_reason: 'stop', message: { content:
    index ? '{"memoryText":"我喜歡散步"}' : '聽起來今天散步很開心。' } }],
    usage: { prompt_tokens: 70, completion_tokens: 20, total_tokens: 90 } };
}
function response(value, status = 200) { return new Response(JSON.stringify(value), { status }); }
function sdkLoader(record) {
  return () => class extends OpenAI {
    constructor(options) { record.options = options; super({ ...options, apiKey: SENTINEL, organization: null, project: null }); }
  };
}
test('default dry-run never loads SDK or invokes transport', async () => {
  const output = [];
  assert.equal(await probe.run({ loadSDK() { throw new Error('must not load'); },
    fetchImpl() { assert.fail('network'); }, emit: x => output.push(x) }), 0);
  assert.equal(output[0].mode, 'dry-run');
});
test('CLI dry-run and invalid flags work without installed SDK or credentials', () => {
  for (const [args, code] of [[[], 0], [['--dry-run'], 0], [['--execute'], 2], [['--surprise'], 2]]) {
    const child = spawnSync(process.execPath, [resolve(__dirname, 'render_text_smoke.cjs'), ...args],
      { encoding: 'utf8', env: {} });
    assert.equal(child.status, code, child.stderr);
    assert.equal(child.stderr, '');
  }
});
test('cost calculation uses documented ceiling, not arbitrary reserve', () => {
  assert.ok(Math.abs(probe.costBound().batchUpperBoundUsd - 1.1558448) < 1e-12);
  assert.ok(probe.costBound().batchUpperBoundUsd < 2);
});
test('reviewed source runs from stdin with no source file on the server', () => {
  const child = spawnSync(process.execPath, ['-', '--dry-run'], { env: {}, encoding: 'utf8',
    input: readFileSync(resolve(__dirname, 'render_text_smoke.cjs'), 'utf8') });
  assert.equal(child.status, 0); assert.equal(JSON.parse(child.stdout).mode, 'dry-run');
});
test('real installed SDK serializes exact parameters; two synthetic requests only', async () => {
  const record = {}; const output = []; let calls = 0;
  const code = await probe.run({ execute: true, loadSDK: sdkLoader(record), emit: x => output.push(x),
    fetchImpl: async (url, options) => {
      assert.equal(url, ENDPOINT); assert.equal(options.redirect, 'error');
      assert.deepEqual(JSON.parse(options.body), probe.requestBody(calls));
      assert.equal(JSON.parse(options.body).reasoning_effort, 'none');
      assert.equal(JSON.parse(options.body).max_completion_tokens, 256);
      return response(payload(calls++));
    } });
  assert.equal(code, 0); assert.equal(calls, 2);
  assert.equal(record.options.maxRetries, 0); assert.equal(record.options.timeout, 20000);
  assert.ok(output.every(x => x.pass)); assert.ok(!JSON.stringify(output).includes(SENTINEL));
});
for (const status of [302, 400, 401, 429, 500]) {
  test(`HTTP ${status} stops after first request, no retry or provider-error output`, async () => {
    let calls = 0; const output = [];
    const code = await probe.run({ execute: true, loadSDK: sdkLoader({}), emit: x => output.push(x),
      fetchImpl: async (_url, init) => {
        calls++; assert.equal(init.redirect, 'error');
        return response({ error: { message: SENTINEL } }, status);
      } });
    assert.equal(code, 1); assert.equal(calls, 1);
    assert.ok(!JSON.stringify(output).includes(SENTINEL));
  });
}
test('transport exception never retries or leaks thrown error', async () => {
  let calls = 0; const output = [];
  assert.equal(await probe.run({ execute: true, loadSDK: sdkLoader({}), emit: x => output.push(x),
    fetchImpl: async () => { calls++; throw new Error(SENTINEL); } }), 1);
  assert.equal(calls, 1); assert.ok(!JSON.stringify(output).includes(SENTINEL));
});
test('transport rejects altered endpoint/body and third call before any send', async () => {
  let calls = 0;
  const fetch = probe.guardedFetch(async () => { calls++; return response(payload()); });
  const init = { method: 'POST', body: JSON.stringify(probe.requestBody(0)) };
  await assert.rejects(fetch('https://example.com/', init));
  await assert.rejects(fetch(ENDPOINT, { ...init, body: '{}' }));
  await assert.rejects(fetch(ENDPOINT, { ...init, method: 'GET' }));
  assert.equal(calls, 0);
  await fetch(ENDPOINT, init);
  await fetch(ENDPOINT, { ...init, body: JSON.stringify(probe.requestBody(1)) });
  await assert.rejects(fetch(ENDPOINT, init)); assert.equal(calls, 2);
});
test('oversize response is cancelled and prevents second request', async () => {
  let calls = 0; let cancelled = false;
  assert.equal(await probe.run({ execute: true, loadSDK: sdkLoader({}),
    fetchImpl: async () => {
      calls++;
      return new Response(new ReadableStream({ start(c) { c.enqueue(new Uint8Array(65537)); },
        cancel() { cancelled = true; } }));
    } }), 1);
  assert.equal(calls, 1); assert.equal(cancelled, true);
});
test('request deadline covers stalled response body, no retry', async t => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  let started; const ready = new Promise(resolve => { started = resolve; }); let calls = 0;
  const pending = probe.run({ execute: true, loadSDK: sdkLoader({}), fetchImpl: async (_url, init) => {
    calls++;
    return new Response(new ReadableStream({ start(c) {
      init.signal.addEventListener('abort', () => c.error(new Error(SENTINEL)), { once: true }); started();
    } }));
  } });
  await ready; t.mock.timers.tick(20001);
  assert.equal(await pending, 1); assert.equal(calls, 1);
});
for (const kind of ['length', 'refusal', 'malformed', 'usage', 'polluted-memory', 'tool']) {
  test(`rejects ${kind} output without printing it`, async () => {
    let calls = 0; const output = [];
    const code = await probe.run({ execute: true, loadSDK: sdkLoader({}), emit: x => output.push(x), fetchImpl: async () => {
      const p = payload(calls++);
      if (kind === 'length') p.choices[0].finish_reason = 'length';
      if (kind === 'refusal') p.choices[0].message.refusal = SENTINEL;
      if (kind === 'malformed') return new Response(SENTINEL);
      if (kind === 'usage') p.usage.prompt_tokens = SENTINEL;
      if (kind === 'tool') p.choices[0].message.tool_calls = [{ name: SENTINEL }];
      if (kind === 'polluted-memory' && calls === 2) p.choices[0].message.content = '{"memoryText":"我喜歡散步，今天不聊女兒"}';
      return response(p);
    } });
    assert.equal(code, 1); assert.equal(calls, kind === 'polluted-memory' ? 2 : 1);
    assert.ok(!JSON.stringify(output).includes(SENTINEL));
  });
}
test('SDK initialization failure is redacted', async () => {
  const output = [];
  assert.equal(await probe.run({ execute: true, loadSDK() { throw new Error(SENTINEL); }, emit: x => output.push(x) }), 1);
  assert.deepEqual(output, [{ status: 'setup-failed', attempts: 0 }]);
});
for (const text of ['我不喜歡散步', '我喜歡散步，也有三個兒子', '可能喜歡散步', '我喜歡散步，今天不聊女兒', '喜歡散步但只有明天']) {
  test(`fixed memory fixture rejects altered meaning: ${text}`, () => {
    const p = payload(1); p.choices[0].message.content = JSON.stringify({ memoryText: text });
    assert.equal(probe.evaluate(1, p).pass, false);
  });
}
test('memory fixture allows only narrow equivalent forms', () => {
  for (const text of ['我喜歡散步', '喜歡散步。', '使用者喜歡散步']) {
    const p = payload(1); p.choices[0].message.content = JSON.stringify({ memoryText: text });
    assert.equal(probe.evaluate(1, p).pass, true);
  }
});
