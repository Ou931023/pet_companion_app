"use strict";
const { test, after } = require("node:test");
const assert = require("node:assert/strict");

// All memory I/O is stubbed before importing the actual HTTP route.
process.env.NODE_ENV = "test";
process.env.APP_ENV = "test";
process.env.OPENAI_API_KEY = "test-only-placeholder";
delete process.env.DATABASE_URL;
delete process.env.TELEGRAM_BOT_TOKEN;
delete process.env.TELEGRAM_CARE_CHAT_ID;
const calls = { embeddings: [], writes: [], reads: 0 };
const originals = [];
function stub(name, exports) {
  const id = require.resolve(name);
  originals.push([id, require.cache[id]]);
  require.cache[id] = { id, filename: id, loaded: true, exports };
}
stub("../../memory/memory_embedding_service", { createEmbedding: async text => {
  calls.embeddings.push(text); return { embedding: [0], provider: "synthetic" };
} });
stub("../../memory/memory_repository", {
  createLongTermMemory: async memory => {
    calls.writes.push(memory); return { memory, duplicate: false, provider: "synthetic" };
  },
  retrieveByEmbedding: async () => { calls.reads++; return { memories: [], provider: "synthetic" }; },
});
stub("../../search/search_service", { searchKnowledge: async () => {
  throw new Error("Synthetic opt-out cases must not request search");
} });
const app = require("../server");
const { analyzeCompanionTurn } = require("../../companion/companion_engine");
after(() => { for (const [id, original] of originals) {
  if (original) require.cache[id] = original; else delete require.cache[id];
} });

for (const [transcript, allowed] of [
  ["我今天很孤單，這件事不要保存", false],
  ["這件事不要保存，我今天很孤單", false],
  ["我今天很孤單，這件事不要記住", false],
  ["我今天很孤單，不要保存。我不想活了", false],
  ["我今天很孤單。大家都很忙", false],
  ["我今天很孤單", true],
]) {
  test(`actual analyze route keeps memory privacy and safety: ${transcript}`, async () => {
    calls.embeddings.length = 0; calls.writes.length = 0; calls.reads = 0;
    const server = await new Promise(resolve => {
      const listener = app.listen(0, "127.0.0.1", () => resolve(listener));
    });
    try {
      const response = await fetch(`http://127.0.0.1:${server.address().port}/api/companion/analyze`, {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ userId: "synthetic-user", turnId: "synthetic-turn", transcript }),
      });
      assert.equal(response.status, 200);
      const body = await response.json();
      await new Promise(resolve => setImmediate(resolve));
      assert.equal(body.memory.shouldSave, allowed);
      assert.equal(calls.embeddings.length, allowed ? 2 : 0);
      assert.equal(calls.reads, allowed ? 1 : 0);
      assert.equal(calls.writes.length, allowed ? 1 : 0);
      const safety = analyzeCompanionTurn({ transcript }).safety;
      assert.deepEqual(body.safety, safety);
      if (transcript.includes("不想活")) {
        assert.equal(body.safety.riskLevel, "urgent");
        assert.equal(body.safety.needsHumanSupport, true);
        assert.ok(body.careAlertSummary.length > 0);
      }
      if (allowed) {
        assert.equal(calls.embeddings[0], transcript);
        assert.equal(calls.embeddings[1], body.memory.candidate);
        assert.equal(calls.writes[0].memoryText, body.memory.candidate);
        assert.equal(calls.writes[0].memorySummary, body.memory.candidate);
      } else assert.equal(body.memory.candidate, "");
    } finally {
      await new Promise(resolve => server.close(resolve));
    }
  });
}
