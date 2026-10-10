"use strict";

// CR-0073：記憶抽取放寬 + 自我介紹/家人分支 的單元測試。
// 只測 ruleBasedExtract（純規則、同步、不呼叫 OpenAI），避免測試打真 API / 受 .env 影響。

const assert = require("node:assert/strict");
const { test } = require("node:test");

const { ruleBasedExtract } = require("./memoryExtractor");

const temporaryBoundaries = [
  "今天先不聊我女兒",
  "不要再問我睡不好了",
  "我今天不想聊喜歡的故事",
  "現在暫時不聊每天散步的事",
  "請你不要再問我女兒，謝謝",
  "今天先不聊這個。不要再問我睡不好了",
  "不要再問了",
  "今天先不聊「女兒」",
];

test("boundary-only turns are not durable memories", () => {
  for (const userText of temporaryBoundaries) {
    const result = ruleBasedExtract({ userText, emotion: "neutral" });
    assert.equal(result.shouldRemember, false, userText);
    assert.equal(result.reason, "temporary_conversation_boundary", userText);
  }
});

test("quoted, reported, negated, durable and mixed statements retain existing extraction", () => {
  for (const userText of [
    "女兒說今天先不聊她的工作",
    "我不是說不要再問我睡不好了",
    "「不要再問我女兒」是什麼意思？",
    "我不喜歡恐怖故事",
    "以後永遠不要聊我女兒",
    "我喜歡散步，今天先不聊女兒",
    "今天先不聊女兒，但我喜歡散步",
    "現在我想聊女兒，她住在台中",
  ]) {
    assert.equal(ruleBasedExtract({ userText, emotion: "neutral" }).shouldRemember, true, userText);
  }
});

test("boundary hardblock precedes AI even when a provider client is available", () => {
  const { spawnSync } = require("node:child_process");
  const script = `
    const assert = require('node:assert/strict');
    const Module = require('node:module');
    const originalLoad = Module._load;
    let calls = 0;
    Module._load = function(name, ...args) {
      if (name === 'openai') return class {
        constructor() { this.chat = { completions: { create: async () => {
          calls++; return { choices: [{ message: { content: JSON.stringify({
            shouldRemember: true, memoryType: 'preference', memorySummary: 'synthetic',
            importance: 3, confidence: 0.8
          }) } }] };
        } } }; }
      };
      return originalLoad.call(this, name, ...args);
    };
    process.env.OPENAI_API_KEY = 'test-only-placeholder';
    const { extractMemoryFromTurn } = require('./memoryExtractor');
    (async () => {
      for (const userText of ${JSON.stringify(temporaryBoundaries)}) {
        const result = await extractMemoryFromTurn({userText});
        assert.equal(result.shouldRemember, false);
        assert.equal(result.reason, 'temporary_conversation_boundary');
      }
      assert.equal(calls, 0);
    })().catch(error => { console.error(error); process.exitCode = 1; });
  `;
  const result = spawnSync(process.execPath, ["-e", script], {
    cwd: __dirname, encoding: "utf8",
    env: { SystemRoot: process.env.SystemRoot, PATH: process.env.PATH, NODE_ENV: "test" },
  });
  assert.equal(result.status, 0, result.stdout + result.stderr);
});

test("CR-0073 自我介紹「我叫阿明」→ shouldRemember、memoryType personal_story", () => {
  const r = ruleBasedExtract({ userText: "我叫阿明", emotion: "neutral" });
  assert.equal(r.shouldRemember, true);
  assert.equal(r.memoryType, "personal_story");
});

test("CR-0073 家人「我女兒住在台中」→ shouldRemember、memoryType family", () => {
  const r = ruleBasedExtract({ userText: "我女兒住在台中", emotion: "neutral" });
  assert.equal(r.shouldRemember, true);
  assert.equal(r.memoryType, "family");
});

test("CR-0073 家人「我老伴上個月過世了」→ family", () => {
  const r = ruleBasedExtract({ userText: "我老伴上個月過世了", emotion: "sad" });
  assert.equal(r.shouldRemember, true);
  assert.equal(r.memoryType, "family");
});

test("純寒暄「哈哈」不存（不退化）", () => {
  assert.equal(ruleBasedExtract({ userText: "哈哈", emotion: "happy" }).shouldRemember, false);
});

test("一次性閒聊「今天天氣不錯」不存（不退化）", () => {
  assert.equal(
    ruleBasedExtract({ userText: "今天天氣不錯", emotion: "neutral" }).shouldRemember,
    false,
  );
});

test("敏感/診斷內容不自動保存（不退化）", () => {
  assert.equal(
    ruleBasedExtract({ userText: "醫生說我確診了", emotion: "anxious" }).shouldRemember,
    false,
  );
});

test("既有喜好分支仍正常：「我喜歡散步」→ shouldRemember", () => {
  const r = ruleBasedExtract({ userText: "我喜歡每天去公園散步", emotion: "happy" });
  assert.equal(r.shouldRemember, true);
});
