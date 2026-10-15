'use strict';

// Standalone review artifact. No app imports, file/data reads, or SDK load in dry-run.
const ENDPOINT = 'https://api.openai.com/v1/chat/completions';
const MODEL = 'gpt-6-luna';
const MAX_OUTPUT = 256;
const MAX_RESPONSE_BYTES = 65536;
const REQUEST_MS = 20000;
const DEADLINE_MS = 60000;
const CASES = Object.freeze([
  Object.freeze({ id: 'synthetic-chat', system: 'Reply in Traditional Chinese, in one short friendly sentence. Do not use tools.', user: '今天散步看到了漂亮的花，心情很好。' }),
  Object.freeze({ id: 'synthetic-memory', system: 'Return only JSON with one key memoryText. Preserve the independent durable fact, exclude the temporary topic boundary. Do not invent facts.', user: '我喜歡散步，今天先不聊女兒。' }),
]);

function requestBody(index) {
  const item = CASES[index];
  if (!item) throw new Error('invalid-case');
  return { model: MODEL, reasoning_effort: 'none', max_completion_tokens: MAX_OUTPUT,
    n: 1, stream: false, store: false, service_tier: 'default',
    messages: [{ role: 'system', content: item.system }, { role: 'user', content: item.user }] };
}

function costBound() {
  // Published 2026-10-15. Full context used instead of an unverified tokenizer estimate.
  // Highest input category (cache write), long-context, fast, regional premiums.
  const perRequestUsd = (1050000 * 0.125 * 2 * 2 * 1.1 + MAX_OUTPUT * 0.50 * 1.5 * 2 * 1.1) / 1000000;
  return { pricingDate: '2026-10-15', requests: 2, perRequestUsd,
    batchUpperBoundUsd: perRequestUsd * 2, authorizedBudgetUsd: 2,
    basis: 'published-standard-token-pricing-excludes-tax-custom-prices-and-other-traffic' };
}

function plan() {
  return { mode: 'dry-run', endpoint: ENDPOINT, model: MODEL, cases: CASES.map(x => x.id),
    reasoning: 'none', maxOutputTokens: MAX_OUTPUT, retries: 0, requestMs: REQUEST_MS,
    deadlineMs: DEADLINE_MS, maxResponseBytes: MAX_RESPONSE_BYTES, cost: costBound() };
}

function safeUsage(value) {
  const result = {};
  for (const key of ['prompt_tokens', 'completion_tokens', 'total_tokens']) {
    const n = value?.[key];
    if (!Number.isSafeInteger(n) || n < 0 || n > 1050000 + MAX_OUTPUT) return null;
    result[key] = n;
  }
  if (result.completion_tokens > MAX_OUTPUT || result.prompt_tokens > 1050000 ||
      result.total_tokens !== result.prompt_tokens + result.completion_tokens) return null;
  return result;
}

function evaluate(index, data) {
  const choice = data?.choices?.[0];
  const content = choice?.message?.content;
  const usage = safeUsage(data?.usage);
  let pass = data?.model === MODEL || (typeof data?.model === 'string' && /^gpt-6-luna-\d{4}-\d{2}-\d{2}$/.test(data.model));
  pass = Boolean(pass && usage && data.choices.length === 1 && choice.finish_reason === 'stop' &&
    !choice.message.refusal && !choice.message.tool_calls && typeof content === 'string' && content.trim());
  if (pass && index === 1) {
    try {
      const parsed = JSON.parse(content);
      pass = parsed && Object.keys(parsed).length === 1 && typeof parsed.memoryText === 'string' &&
        /^(?:我|使用者)?喜歡散步[。.!！]?$/.test(parsed.memoryText.trim());
    } catch { pass = false; }
  }
  // Never emit provider text, headers, IDs, errors, model strings or unknown usage fields.
  return { caseId: CASES[index].id, model: MODEL, pass: Boolean(pass), usage };
}

function guardedFetch(fetchImpl) {
  let sends = 0;
  return async (url, init) => {
    if (String(url) !== ENDPOINT || init?.method !== 'POST' || sends >= CASES.length ||
        typeof init.body !== 'string' || init.body.length > 4096) throw new Error('transport-blocked');
    // Exact semantic body match; SDK whitespace formatting is allowed.
    if (JSON.stringify(JSON.parse(init.body)) !== JSON.stringify(requestBody(sends))) throw new Error('body-blocked');
    sends += 1; // Count before sending: exceptions/timeouts never free a slot.
    const response = await fetchImpl(ENDPOINT, { ...init, redirect: 'error' });
    const reader = response.body?.getReader();
    if (!reader) throw new Error('missing-body');
    const chunks = [];
    let bytes = 0;
    try {
      while (true) {
        const chunk = await reader.read();
        if (chunk.done) break;
        bytes += chunk.value.byteLength;
        if (bytes > MAX_RESPONSE_BYTES) throw new Error('response-too-large');
        chunks.push(chunk.value);
      }
    } finally { await reader.cancel().catch(() => {}); }
    // Whitelist response headers; do not propagate arbitrary provider metadata.
    return new Response(Buffer.concat(chunks), { status: response.status,
      headers: { 'content-type': 'application/json' } });
  };
}

async function run({ execute = false, loadSDK, fetchImpl = globalThis.fetch, emit = () => {} } = {}) {
  if (!execute) { emit(plan()); return 0; }
  let client;
  try {
    const OpenAI = loadSDK();
    client = new OpenAI({ baseURL: 'https://api.openai.com/v1', maxRetries: 0, timeout: REQUEST_MS,
      fetch: guardedFetch(fetchImpl) }); // SDK alone reads the inherited credential.
  } catch { emit({ status: 'setup-failed', attempts: 0 }); return 1; }
  for (let index = 0; index < CASES.length; index++) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), REQUEST_MS);
    try {
      const data = await client.chat.completions.create(requestBody(index), { signal: controller.signal, maxRetries: 0 });
      const result = evaluate(index, data);
      emit(result);
      if (!result.pass) return 1; // Fail closed; do not spend on a second case after failure.
    } catch {
      emit({ caseId: CASES[index].id, model: MODEL, pass: false, status: 'request-failed-cost-unknown' });
      return 1;
    } finally { clearTimeout(timer); }
  }
  return 0;
}

async function main(args) {
  const emit = value => process.stdout.write(`${JSON.stringify(value)}\n`);
  const live = args.length === 2 && args[0] === '--execute' && args[1] === '--standard-pricing-reviewed-2026-10-15';
  if (args.length && !(args.length === 1 && args[0] === '--dry-run') && !live) {
    emit({ status: 'invalid-arguments' }); return 2;
  }
  if (!live) return run({ emit });
  // Refuse ambient debugging/preloads; do not print their values. Shell launcher also removes them before Node starts.
  if (process.env.NODE_TLS_REJECT_UNAUTHORIZED === '0' ||
      process.env.DEBUG || process.env.NODE_DEBUG || process.env.NODE_DEBUG_NATIVE ||
      process.env.NODE_V8_COVERAGE || process.env.NODE_REDIRECT_WARNINGS ||
      process.env.NODE_OPTIONS || process.env.NODE_PATH || process.env.NODE_USE_ENV_PROXY ||
      !process.execArgv.includes('--max-old-space-size=64') || !process.execArgv.includes('--max-http-header-size=8192')) {
    emit({ status: 'unsafe-launch-options' }); return 2;
  }
  const deadline = setTimeout(() => { emit({ status: 'deadline-cost-unknown' }); process.exit(1); }, DEADLINE_MS);
  const memory = setInterval(() => {
    if (process.memoryUsage().rss > 128 * 1024 * 1024) { emit({ status: 'memory-limit-cost-unknown' }); process.exit(1); }
  }, 100);
  try {
    return await run({ execute: true, emit, loadSDK: () => {
      const { createRequire } = require('node:module');
      const { resolve } = require('node:path');
      // Resolve ONLY the already installed SDK from the Render backend working directory.
      const sdkRequire = createRequire(resolve(process.cwd(), 'synthetic-probe.cjs'));
      if (sdkRequire('openai/version').VERSION !== '4.104.0') throw new Error('unreviewed-sdk');
      return sdkRequire('openai');
    } });
  } finally { clearTimeout(deadline); clearInterval(memory); }
}

module.exports = { requestBody, costBound, plan, safeUsage, evaluate, guardedFetch, run, main };
if (require.main === module || (process.argv[1] === '-' && !module.parent)) main(process.argv.slice(2)).then(code => { process.exitCode = code; }).catch(() => {
  process.stdout.write('{"status":"internal-failure"}\n'); process.exitCode = 1;
});
