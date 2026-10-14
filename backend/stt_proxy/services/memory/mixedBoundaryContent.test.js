"use strict";

// Synthetic content contract for the active HTTP extraction path. Each provider
// mode runs in a fresh process; no provider, database or notification can be used.
// Intentionally red on main: this is a draft regression specification, not a fix.
const assert = require("node:assert/strict");
const { test } = require("node:test");
const { spawnSync } = require("node:child_process");

const cases = [
  ["fact first", "我喜歡散步，今天先不聊女兒", "我喜歡散步"],
  ["boundary first", "今天先不聊女兒，但我喜歡散步", "我喜歡散步"],
  ["family fact and pronoun boundary", "女兒住台中但今天不聊她", "女兒住台中"],
  ["retained reference", "我女兒住台中，她喜歡散步，今天先不聊她", "我女兒住台中，她喜歡散步"],
  ["reference to removed topic", "今天先不聊女兒，她住在台中", "女兒住在台中"],
  ["reference after independent preference", "我喜歡散步，她住在台中，今天先不聊女兒", "我喜歡散步，女兒住在台中"],
  ["reference before another person", "今天先不聊女兒，她說媽媽住台中", "女兒說媽媽住台中"],
  ["uncertain move", "女兒可能搬去台南，今天先不聊她", "女兒可能搬去台南"],
  ["move confirmed", "女兒可能搬去台南，後來確定下週搬，今天先不聊她", "女兒可能搬去台南，後來確定下週搬"],
  ["move cancelled", "女兒可能搬去台南，後來取消了，今天先不聊她", "女兒可能搬去台南，後來取消了"],
  ["move unresolved", "女兒可能搬去台南，還沒決定，今天先不聊她", "女兒可能搬去台南，還沒決定"],
  ["completed move", "女兒已搬到台南，今天先不聊她", "女兒已搬到台南"],
  ["future appointment", "明天我要去醫院回診，今天先不聊女兒", "明天我要去醫院回診"],
  ["only boundary", "今天先不聊我女兒", null],
  ["reported boundary", "女兒說今天先不聊她的工作", "女兒說今天先不聊她的工作"],
  ["reported boundary after punctuation", "女兒說，今天先不聊她", "女兒說，今天先不聊她"],
  ["quoted boundary", "女兒說「今天先不聊工作」，她還沒決定搬家", "女兒說「今天先不聊工作」，她還沒決定搬家"],
  ["negated boundary", "我不是說不要再問我睡不好了", "我不是說不要再問我睡不好了"],
  ["negated boundary after punctuation", "我不是說，今天先不聊女兒", "我不是說，今天先不聊女兒"],
  ["reopened topic", "現在我想聊女兒，她住在台中", "現在我想聊女兒，她住在台中"],
  ["permanent preference", "以後永遠不要聊我女兒", "以後永遠不要聊我女兒"],
  ["unscoped preference", "我不聊女兒", "我不聊女兒"],
  ["uncertain move control", "女兒可能搬去台南", "女兒可能搬去台南"],
  ["confirmed future control", "女兒可能搬去台南，後來確定下週搬", "女兒可能搬去台南，後來確定下週搬"],
  ["cancelled control", "女兒可能搬去台南，後來取消了", "女兒可能搬去台南，後來取消了"],
  ["unresolved control", "女兒可能搬去台南，還沒決定", "女兒可能搬去台南，還沒決定"],
  ["completed control", "女兒已搬到台南", "女兒已搬到台南"],
  ["appointment control", "明天我要去醫院回診", "明天我要去醫院回診"],
  ["ambiguous unpunctuated continuation", "今天先不聊女兒她可能搬家", null],
  ["ambiguous referent", "今天先不聊女兒和媽媽，她住台中", null],
  ["plural is not a singular referent", "今天先不聊女兒，她們住台中", null],
];

function runCases(mode) {
  const script = `
    const assert = require('node:assert/strict');
    const Module = require('node:module');
    const originalLoad = Module._load;
    const mode = ${JSON.stringify(mode)};
    let currentText = '';
    let saved = [];
    let embeddingInputs = [];
    let providerCalls = 0;
    const store = {
      MemoryValidationError: class extends Error {},
      createMemory: async input => {
        saved.push({ ...input, id: 'synthetic-memory', isActive: true });
        return { memory: saved[0], provider: 'synthetic' };
      },
      listMemories: async () => ({ memories: saved, provider: 'synthetic' }),
      searchMemoriesByEmbedding: async () => ({ memories: saved.map(m => ({ ...m, similarity: 1 })), provider: 'synthetic' }),
      markMemoriesUsed: async () => {},
    };
    Module._load = function(name, parent, ...rest) {
      if (name === 'openai') return class {
        constructor() {
          this.chat = { completions: { create: async () => {
            providerCalls++;
            if (mode === 'throw') throw new Error('synthetic provider failure');
            const payload = mode === 'false' ? { shouldRemember: false } : {
              shouldRemember: true, memoryType: mode === 'invalid' ? 'invalid' : 'family',
              memoryText: currentText, memorySummary: currentText,
              importance: 4, confidence: 0.8, emotionLabel: 'neutral', reason: 'synthetic'
            };
            return { choices: [{ message: { content: mode === 'malformed' ? '{broken' : JSON.stringify(payload) } }] };
          } } };
        }
      };
      if (name.endsWith('/memoryStore') || (name === './memoryStore' && parent.filename.includes('services'))) return store;
      if (name === './services/memory/embeddingService' || (name === './embeddingService' && parent.filename.includes('services' + require('node:path').sep + 'memory'))) {
        return { createEmbedding: async text => {
          embeddingInputs.push(text);
          return { embedding: [1, 0], provider: 'synthetic' };
        } };
      }
      return originalLoad.call(this, name, parent, ...rest);
    };
    // Environment is allowlisted by the parent. The placeholder only permits
    // server construction; every OpenAI constructor above is an in-process stub.
    process.env.OPENAI_API_KEY = 'test-only-placeholder';
    const app = require('../../server');
    if (mode === 'none') delete process.env.OPENAI_API_KEY;
    const { installResidentCallerStub } = require('../auth/residentCallerContext.testsupport');
    const restore = installResidentCallerStub({
      'synthetic-resident': { uid: 'synthetic-uid', userId: 'synthetic-user', elderId: '11111111-1111-1111-1111-111111111111' }
    });
    const { buildPromptBlock, greetingFromMemory } = require('./memoryContextService');
    const failures = [];
    (async () => {
      const server = await new Promise(resolve => { const s = app.listen(0, '127.0.0.1', () => resolve(s)); });
      try {
        for (const [label, userText, expected] of ${JSON.stringify(cases)}) {
          saved = []; embeddingInputs = []; currentText = userText;
          const callsBefore = providerCalls;
          const response = await fetch('http://127.0.0.1:' + server.address().port + '/api/memories/extract', {
            method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer synthetic-resident' },
            body: JSON.stringify({ userText, agentReply: '今天先不聊女兒', turnId: 'synthetic-turn', sessionId: 'synthetic-session' })
          });
          const result = await response.json();
          try {
            if (expected === null) {
              if (label === 'only boundary') assert.equal(providerCalls, callsBefore, 'boundary-only input must not reach the provider');
              assert.equal(result.shouldRemember, false);
              assert.equal(saved.length, 0);
              assert.deepEqual(embeddingInputs, []);
              continue;
            }
            assert.equal(response.status, 201);
            assert.equal(saved.length, 1, 'one source turn must still create only one record');
            assert.equal(saved[0].sourceTurnId, 'synthetic-turn');
            const contentFailures = [];
            const check = (field, fn) => { try { fn(); } catch (error) { contentFailures.push(field + ': ' + error.message); } };
            check('memoryText', () => assert.equal(saved[0].memoryText, expected, 'preserve facts, reference, tense and uncertainty'));
            check('memorySummary', () => assert.ok(saved[0].memorySummary.includes(expected), 'preserve the complete qualifying content'));
            check('embedding', () => assert.deepEqual(embeddingInputs, [saved[0].memorySummary], 'consume the checked summary'));
            const context = buildPromptBlock(saved).memoryContext;
            const greeting = greetingFromMemory(saved[0]);
            if (expected !== userText) {
              for (const [field, content] of Object.entries({ memoryText: saved[0].memoryText, memorySummary: saved[0].memorySummary, embedding: embeddingInputs[0], context, greeting })) {
                check(field, () => assert.doesNotMatch(content, /今天.*不聊|先不聊/, 'boundary must not reappear in any durable consumer'));
              }
            }
            assert.deepEqual(contentFailures, [], contentFailures.join('\\n'));
          } catch (error) {
            failures.push(label + ': ' + error.message);
          }
        }
        if (mode === 'none') assert.equal(providerCalls, 0);
        else assert.ok(providerCalls > 0, 'provider mode must be exercised by unchanged control cases');
        console.log('CONTENT_MATRIX ' + JSON.stringify({ mode, total: ${cases.length}, passed: ${cases.length} - failures.length, failed: failures.length }));
        assert.deepEqual(failures, [], failures.join('\\n'));
      } finally {
        restore();
        await new Promise(resolve => server.close(resolve));
      }
    })().catch(error => { console.error(error); process.exitCode = 1; });
  `;
  return spawnSync(process.execPath, ["-e", script], {
    cwd: __dirname,
    encoding: "utf8",
    timeout: 30000,
    env: {
      SystemRoot: process.env.SystemRoot,
      PATH: process.env.PATH,
      TEMP: process.env.TEMP,
      TMP: process.env.TMP,
      NODE_ENV: "test",
      APP_ENV: "test",
      PGVECTOR_ENABLED: "false",
    },
  });
}

for (const mode of ["none", "false", "malformed", "invalid", "throw", "normal"]) {
  test(`mixed boundary content through HTTP/store/embedding/context/greeting: ${mode}`, () => {
    const result = runCases(mode);
    assert.equal(result.status, 0, result.stdout + result.stderr);
  });
}
