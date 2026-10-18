"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { analyzeCompanionTurn } = require("../companion/companion_engine");

function storageHarness() {
  const calls = { embeddings: [], writes: [] };
  const module = { exports: {} };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, "memory_policy.js"), "utf8"), {
    module,
    require(name) {
      if (name === "./memory_embedding_service") return { createEmbedding: async text => {
        calls.embeddings.push(text); return { embedding: [0], provider: "synthetic" };
      } };
      if (name === "./memory_repository") return { createLongTermMemory: async memory => {
        calls.writes.push(memory); return { memory, duplicate: false, provider: "synthetic" };
      } };
      if (name === "../companion/memory_policy") return require(name);
      throw new Error("Unexpected dependency: " + name);
    },
  });
  return { calls, store: module.exports.storeCompanionMemoryCandidate };
}

for (const transcript of [
  "我今天很孤單，這件事不要保存",
  "這件事不要保存，我今天很孤單",
  "我今天很孤單，請別記住這件事",
  "我今天很孤單，這部分不要記錄",
  "我今天很孤單，不要保存。我不想活了",
]) {
  test(`companion storage exclusion blocks candidate and all storage side effects: ${transcript}`, async () => {
    const analyzed = analyzeCompanionTurn({ transcript });
    const { calls, store } = storageHarness();
    // Deliberately supply a stale/unsafe candidate as defense-in-depth coverage.
    const result = await store({ transcript, memory: { shouldSave: true,
      candidate: `使用者提到「${transcript}」，可能需要陪伴感。`, type: "emotion_event" } });
    assert.equal(calls.embeddings.length, 0);
    assert.equal(calls.writes.length, 0);
    assert.equal(result.stored, false);
    assert.equal(analyzed.memory.shouldSave, false);
    assert.equal(analyzed.memory.candidate, "");
    assert.ok(analyzed.safety.riskLevel === "medium" || analyzed.safety.riskLevel === "urgent");
    if (transcript.includes("不想活")) {
      assert.equal(analyzed.safety.riskLevel, "urgent");
      assert.equal(analyzed.safety.needsHumanSupport, true);
    }
  });
}

test("normal companion candidate still embeds and stores once", async () => {
  const transcript = "我今天很孤單";
  const analyzed = analyzeCompanionTurn({ transcript });
  assert.equal(analyzed.memory.shouldSave, true);
  const { calls, store } = storageHarness();
  const result = await store({ transcript, memory: analyzed.memory, turnId: "synthetic-turn" });
  assert.equal(result.stored, true);
  assert.deepEqual(calls.embeddings, [analyzed.memory.candidate]);
  assert.equal(calls.writes.length, 1);
  assert.equal(calls.writes[0].sourceTurnId, "synthetic-turn");
});

for (const transcript of [undefined, null, 123, "", "我今天很孤單。大家都很忙", "我喜歡散步，今天先不聊女兒",
  "女兒說「不要保存這件事」，我今天很孤單", "我不是說不要保存，我今天很孤單"]) {
  test(`unverified or ambiguous source fails closed before storage: ${String(transcript)}`, async () => {
    const { calls, store } = storageHarness();
    const result = await store({ transcript, memory: { shouldSave: true, candidate: "stale synthetic candidate" } });
    assert.equal(result.stored, false);
    assert.equal(calls.embeddings.length, 0);
    assert.equal(calls.writes.length, 0);
  });
}

for (const transcript of ["女兒說「今天先不聊工作」，我今天很孤單", "我不是說今天先不聊女兒，我今天很孤單"]) {
  test(`reported or negated topic boundary retains existing source eligibility: ${transcript}`, () => {
    const { canStoreCompanionSource } = require("../companion/memory_policy");
    assert.equal(canStoreCompanionSource(transcript), true);
  });
}
