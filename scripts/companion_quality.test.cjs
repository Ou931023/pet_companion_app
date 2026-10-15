'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createRequire } = require('node:module');
const { resolve } = require('node:path');
const { readFileSync } = require('node:fs');
const { spawnSync } = require('node:child_process');
const { build, hash } = require('./build_chat_quality_fixtures.cjs');
const probe = require('./companion_quality.cjs');
const OpenAI = createRequire(resolve(process.env.QUALITY_TEST_SDK_DIR || resolve(__dirname, '../backend/stt_proxy'), 'offline.cjs'))('openai');
const endpoint = 'https://api.openai.com/v1/chat/completions';
const output = i => ({ model: probe.requestBody(i).model, choices: [{ finish_reason: 'stop', message: { content: '合成回覆：我們聊聊花吧。' } }], usage: { prompt_tokens: 2000, completion_tokens: 20, total_tokens: 2020 } });
const response = (data, status = 200) => new Response(JSON.stringify(data), { status });
const loadSDK = () => class extends OpenAI { constructor(opts) { super({ ...opts, apiKey: 'sk-synthetic-only-never-real', organization: null, project: null }); } };
test('frozen request fixtures reproduce exact pinned candidate without loading server', async () => {
  const fixture = JSON.parse(readFileSync(resolve(__dirname, 'fixtures/companion_quality.json'), 'utf8'));
  assert.deepEqual(await build(), fixture);
  assert.equal(fixture.sourceCommit, 'b84c52428ce043a145c96e04ecb7b18dc63e6fc5');
  for (let i = 0; i < 4; i++) {
    assert.deepEqual(probe.requestBody(i), fixture.requests[i].body);
    assert.equal(hash(JSON.stringify(probe.requestBody(i))), fixture.requests[i].sha256);
    assert.equal(probe.requestBody(i).temperature, 0.6);
    assert.equal(probe.requestBody(i)[i % 2 ? 'max_completion_tokens' : 'max_tokens'], 220);
    assert.equal(probe.requestBody(i).reasoning_effort, i % 2 ? 'none' : undefined);
  }
  assert.match(probe.requestBody(0).messages[0].content, /目前對話以使用者最新明確意願優先/);
  assert.deepEqual(probe.requestBody(2).messages.slice(1).map(x => x.content), ['我可能下個月搬去台中', '不搬了，還住原處', '明天再想想要去哪裡散步']);
});
test('default dry-run is credential/SDK/network free and preserves prior spend', async () => {
  const records = [];
  assert.equal(await probe.run({ loadSDK() { assert.fail('SDK load'); }, fetchImpl() { assert.fail('network'); }, emit: x => records.push(x) }), 0);
  assert.equal(records[0].cost.batchUpperBoundUsd, 1.19439);
  assert.equal(records[0].cost.combinedEstimatedCeilingUsd, 1.1944193);
  assert.equal(records[0].cost.priorEstimatedUsd, 0.0000293);
});
test('stdin dry-run works and disabled TLS is refused before SDK', () => {
  const source = readFileSync(resolve(__dirname, 'companion_quality.cjs'), 'utf8');
  const dry = spawnSync(process.execPath, ['-', '--dry-run'], { input: source, env: {}, encoding: 'utf8' });
  assert.equal(dry.status, 0); assert.equal(JSON.parse(dry.stdout).requests.length, 4);
  const bad = spawnSync(process.execPath, ['--max-old-space-size=64', '--max-http-header-size=8192', '-', '--execute', '--standard-pricing-reviewed-2026-10-15', '--prior-charge-and-overall-budget-reviewed'],
    { input: source, env: { NODE_TLS_REJECT_UNAUTHORIZED: '0' }, encoding: 'utf8' });
  assert.equal(bad.status, 2); assert.equal(JSON.parse(bad.stdout).status, 'unsafe-launch-options'); assert.equal(bad.stderr, '');
});
test('real SDK sends exactly four fixed requests sequentially; complete bounded synthetic replies only', async () => {
  let calls = 0; let active = 0; const records = [];
  assert.equal(await probe.run({ execute: true, loadSDK, emit: x => records.push(x), fetchImpl: async (url, init) => {
    assert.equal(active++, 0); assert.equal(url, endpoint); assert.equal(init.redirect, 'error');
    assert.deepEqual(JSON.parse(init.body), probe.requestBody(calls));
    const data = output(calls++); data.secretHeader = 'NEVER-PRINT-METADATA'; active--;
    return response(data);
  } }), 0);
  assert.equal(calls, 4); assert.equal(records.length, 4);
  assert.ok(records.every(x => x.quality === 'human-review-required' && x.reply === '合成回覆：我們聊聊花吧。' && x.elapsedMs >= 0));
  assert.ok(!JSON.stringify(records).includes('NEVER-PRINT-METADATA'));
});
for (const failure of ['throw', '302', '429', '500', 'malformed', 'oversize', 'length', 'refusal', 'usage', 'reply-size', 'secret-pattern', 'model', 'tool']) {
  test('first failure stops without retry or metadata leak: ' + failure, async () => {
    let calls = 0; const records = [];
    const code = await probe.run({ execute: true, loadSDK, emit: x => records.push(x), fetchImpl: async () => {
      calls++; const data = output(0);
      if (failure === 'throw') throw new Error('NEVER-PRINT-ERROR');
      if (/^\d+$/.test(failure)) return response({ error: { message: 'NEVER-PRINT-ERROR' } }, Number(failure));
      if (failure === 'malformed') return new Response('NEVER-PRINT-ERROR');
      if (failure === 'oversize') return new Response('x'.repeat(65537));
      if (failure === 'length') data.choices[0].finish_reason = 'length';
      if (failure === 'refusal') data.choices[0].message.refusal = 'NEVER-PRINT-REFUSAL';
      if (failure === 'usage') data.usage.prompt_tokens = 'NEVER-PRINT-USAGE';
      if (failure === 'reply-size') data.choices[0].message.content = '花'.repeat(1400);
      if (failure === 'secret-pattern') data.choices[0].message.content = 'sk-synthetic-secret-canary';
      if (failure === 'model') data.model = 'NEVER-PRINT-MODEL';
      if (failure === 'tool') data.choices[0].message.tool_calls = [{ name: 'NEVER-PRINT-TOOL' }];
      return response(data);
    } });
    assert.equal(code, 1); assert.equal(calls, 1);
    assert.ok(!JSON.stringify(records).includes('NEVER-PRINT'));
    assert.ok(!JSON.stringify(records).includes('sk-synthetic-secret-canary'));
  });
}
test('transport rejects foreign URL, changed body and fifth call', async () => {
  let calls = 0;
  const fetch = probe.guardedFetch(async () => { calls++; return response(output(0)); });
  await assert.rejects(fetch('https://example.com', { method: 'POST', body: JSON.stringify(probe.requestBody(0)) }));
  await assert.rejects(fetch(endpoint, { method: 'POST', body: '{}' })); assert.equal(calls, 0);
  for (let i = 0; i < 4; i++) await fetch(endpoint, { method: 'POST', body: JSON.stringify(probe.requestBody(i)) });
  await assert.rejects(fetch(endpoint, { method: 'POST', body: JSON.stringify(probe.requestBody(0)) })); assert.equal(calls, 4);
});
test('body read timeout aborts the batch', async t => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  let ready; const started = new Promise(resolve => { ready = resolve; }); let calls = 0;
  const result = probe.run({ execute: true, loadSDK, fetchImpl: async (_url, init) => {
    calls++; return new Response(new ReadableStream({ start(c) { init.signal.addEventListener('abort', () => c.error(new Error('synthetic')), { once: true }); ready(); } }));
  } });
  await started; t.mock.timers.tick(20001); assert.equal(await result, 1); assert.equal(calls, 1);
});
test('JSON output escapes terminal controls without truncating valid synthetic text', () => {
  const data = output(0); data.choices[0].message.content = '合成\n\u001b[31m文字';
  const record = probe.evaluate(0, data, 12);
  const line = JSON.stringify(record);
  assert.ok(!line.includes('\u001b')); assert.ok(!line.includes('\n'));
  assert.equal(JSON.parse(line).reply, data.choices[0].message.content);
});
