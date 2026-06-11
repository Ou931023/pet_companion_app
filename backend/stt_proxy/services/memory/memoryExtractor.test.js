"use strict";

// CR-0073：記憶抽取放寬 + 自我介紹/家人分支 的單元測試。
// 只測 ruleBasedExtract（純規則、同步、不呼叫 OpenAI），避免測試打真 API / 受 .env 影響。

const assert = require("node:assert/strict");
const { test } = require("node:test");

const { ruleBasedExtract } = require("./memoryExtractor");

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
