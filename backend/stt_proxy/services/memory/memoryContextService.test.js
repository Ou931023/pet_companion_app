"use strict";

// CR-0073：記憶檢索門檻放寬 + env 可調 的單元測試（純函式 rankMemories，不需 DB）。

const assert = require("node:assert/strict");
const { test } = require("node:test");

const { rankMemories } = require("./memoryContextService");

const nowIso = "2026-06-11T00:00:00.000Z";

function mem(overrides = {}) {
  return {
    id: overrides.id || "m1",
    isActive: true,
    importance: 4,
    similarity: 0.5,
    createdAt: nowIso, // 近期 → recencyScore 高
    memorySummary: "使用者近況",
    ...overrides,
  };
}

test("CR-0073 放寬後：similarity 0.35 的相關記憶會被保留（原 0.40 門檻會擋掉）", () => {
  const ranked = rankMemories([mem({ similarity: 0.35, importance: 4 })], "postgres");
  assert.equal(ranked.length, 1, "sim 0.35 在放寬預設（0.30）下應通過");
});

test("CR-0073 放寬後：importance 2 的記憶會被保留（原 <3 會被排除）", () => {
  const ranked = rankMemories([mem({ similarity: 0.5, importance: 2 })], "postgres");
  assert.equal(ranked.length, 1, "importance 2 在放寬預設（>=2）下應通過");
});

test("similarity 太低（0.1）仍被擋（避免亂引用不相關記憶）", () => {
  const ranked = rankMemories([mem({ similarity: 0.1, importance: 4 })], "postgres");
  assert.equal(ranked.length, 0);
});

test("topK：候選很多時最多回 5 筆（放寬後預設）", () => {
  const many = Array.from({ length: 10 }, (_, i) =>
    mem({ id: `m${i}`, similarity: 0.6 - i * 0.01, importance: 4 }),
  );
  const ranked = rankMemories(many, "postgres");
  assert.ok(ranked.length <= 5, `應 <=5，實際 ${ranked.length}`);
  assert.equal(ranked.length, 5);
});

test("已封存（isActive:false）記憶被排除", () => {
  const ranked = rankMemories([mem({ isActive: false })], "postgres");
  assert.equal(ranked.length, 0);
});

test("CR-0073 env 可調：MEMORY_MIN_SIMILARITY=0.5 時 sim 0.35 被擋（fresh require）", () => {
  const modPath = require.resolve("./memoryContextService");
  const original = process.env.MEMORY_MIN_SIMILARITY;
  try {
    process.env.MEMORY_MIN_SIMILARITY = "0.5";
    delete require.cache[modPath];
    const fresh = require("./memoryContextService");
    const ranked = fresh.rankMemories([mem({ similarity: 0.35, importance: 4 })], "postgres");
    assert.equal(ranked.length, 0, "門檻調高到 0.5 後 sim 0.35 應被擋");
  } finally {
    if (original === undefined) delete process.env.MEMORY_MIN_SIMILARITY;
    else process.env.MEMORY_MIN_SIMILARITY = original;
    delete require.cache[modPath];
    require("./memoryContextService"); // 還原預設模組到 cache
  }
});
