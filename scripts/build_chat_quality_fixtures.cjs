'use strict';
// OFFLINE ONLY: read pinned public source with git, execute isolated pure fragments, never require server.
const { execFileSync } = require('node:child_process');
const { createHash } = require('node:crypto');
const { runInNewContext } = require('node:vm');
const { readFileSync, writeFileSync } = require('node:fs');
const { resolve } = require('node:path');
const SOURCE = 'b84c52428ce043a145c96e04ecb7b18dc63e6fc5';
const root = resolve(__dirname, '..');
const hash = value => createHash('sha256').update(value).digest('hex');
function source(path) { return execFileSync('git', ['show', `${SOURCE}:${path}`], { cwd: root, encoding: 'utf8', maxBuffer: 2000000 }); }
function section(text, start, end) {
  const a = text.indexOf(start); const b = text.indexOf(end, a + start.length);
  if (a < 0 || b < 0) throw new Error('source markers changed');
  return text.slice(a, b);
}
async function build() {
  const paths = ['backend/stt_proxy/server.js', 'backend/companion/voice_prompt_policy.js', 'backend/stt_proxy/services/companionChatService.js'];
  const [server, policy, service] = paths.map(source);
  const persona = section(server, 'const COMPANION_CHAT_PERSONA =', 'function fallbackGreeting(');
  const builder = section(server, 'function buildCompanionChatInstructions(', 'async function loadRelevantMemorySummaries(');
  const route = server.slice(server.indexOf('app.post("/api/companion/chat"'));
  const assembly = section(route, '  const petName =', '  // CR-0072');
  const promptScope = { module: { exports: {} } };
  runInNewContext(policy + '\n' + persona + '\n' + builder + '\nmodule.exports = { buildCompanionChatInstructions };', promptScope, { timeout: 100 });
  const serviceScope = { module: { exports: {} }, require(name) {
    if (name !== './privacy/redaction') throw new Error('unexpected dependency');
    return { safeErrorMessage: () => 'synthetic-error' };
  } };
  runInNewContext(service, serviceScope, { timeout: 100 });
  const cases = [
    { id: 'temporary-boundary', body: { petName: '合成小白', replyLanguage: 'zh-TW',
      memoryContextSummary: '使用者喜歡散步，也有一位女兒。', userText: '我喜歡散步，但今天不聊女兒，陪我聊花吧', history: [] } },
    { id: 'cancelled-move', body: { petName: '合成小白', replyLanguage: 'zh-TW', memoryContextSummary: '',
      userText: '明天再想想要去哪裡散步', history: [{ role: 'user', content: '我可能下個月搬去台中' }, { role: 'user', content: '不搬了，還住原處' }] } },
  ];
  const requests = [];
  for (const item of cases) {
    const scope = { req: { body: item.body }, buildCompanionChatInstructions: promptScope.module.exports.buildCompanionChatInstructions };
    const systemPrompt = runInNewContext(assembly + '\nsystemPrompt;', scope, { timeout: 100 });
    for (const model of ['gpt-4o-mini', 'gpt-6-luna']) {
      let captured;
      const client = { chat: { completions: { create: async body => { captured = body; return { choices: [{ message: { content: '合成' } }] }; } } } };
      await serviceScope.module.exports.generateCompanionReply({ userText: item.body.userText, systemPrompt, history: item.body.history }, { client, model });
      const body = JSON.parse(JSON.stringify({ ...captured, n: 1, stream: false, store: false, service_tier: 'default' }));
      requests.push({ caseId: item.id, body, sha256: hash(JSON.stringify(body)) });
    }
  }
  return { sourceCommit: SOURCE, sourceSha256: Object.fromEntries(paths.map((p, i) => [p, hash([server, policy, service][i])])),
    derivation: 'isolated pinned persona/policy/builder/route assembly and service capture; safety-only n/stream/store/service_tier added', requests };
}
module.exports = { build, hash };
if (require.main === module) build().then(value => {
  const fixture = resolve(__dirname, 'fixtures/companion_quality.json');
  const runner = resolve(__dirname, 'companion_quality.cjs');
  if (process.argv[2] === '--write') {
    writeFileSync(fixture, JSON.stringify(value, null, 2) + '\n');
    const text = readFileSync(runner, 'utf8');
    writeFileSync(runner, text.replace(/\/\/ BEGIN FROZEN\n[\s\S]*?\/\/ END FROZEN/, '// BEGIN FROZEN\nconst FROZEN = ' + JSON.stringify(value) + ';\n// END FROZEN'));
  } else {
    if (JSON.stringify(value) !== JSON.stringify(JSON.parse(readFileSync(fixture, 'utf8')))) throw new Error('fixture mismatch');
    console.log('Pinned fixture regeneration matches.');
  }
}).catch(() => { console.error('Offline fixture generation failed.'); process.exitCode = 1; });
