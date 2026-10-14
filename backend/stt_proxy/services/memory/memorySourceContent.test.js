"use strict";

const assert = require("node:assert/strict");
const { test } = require("node:test");
const { projectMemorySource, validateMemorySelection, isIndependentPreference } = require("./memorySourceContent");

test("declarative preference punctuation is recognized without altering the source", () => {
  for (const stem of ["我喜歡運動", "我不喜歡運動"]) {
    for (const ending of ["", "。", ".", "！", "!", "！！", "!!", " 。 ", "\t！", "　."]) {
      const text = ` \t${stem}${ending}\n`;
      assert.equal(isIndependentPreference(text), true, JSON.stringify(text));
      assert.deepEqual(projectMemorySource(text.trim()), { text: text.trim(), projected: false });
    }
  }
});

test("preference recognition never removes questions, quotes, negation or trailing scope", () => {
  for (const text of [
    "我喜歡運動嗎？", "我喜歡運動?", "我不喜歡運動嗎。", "我喜歡運動呢", "我喜歡運動！？",
    "「我喜歡運動。」", '"我不喜歡運動!"', "女兒說我喜歡運動。", "我不是說我喜歡運動。",
    "我喜歡運動...", "我喜歡運動…", "我喜歡運動，", "我喜歡運動；", "我喜歡運動。這部分別記住",
  ]) assert.equal(isIndependentPreference(text), false, text);
  for (const text of ["我喜歡運動嗎？", "我喜歡運動?", "我不喜歡運動嗎。", "我喜歡運動呢", "我喜歡運動！？"]) {
    assert.deepEqual(projectMemorySource(text), { text: null, projected: true }, text);
  }
});

test("whole-turn recognition retains only an unchanged, independently asserted source span", () => {
  for (const fact of ["我不喜歡恐怖故事", "我喜歡種花", "我兒子住在新竹", "媽媽可能搬去嘉義", "我女兒已經搬到臺北", "明天我要去醫院回診"]) {
    for (const userText of [`${fact}，今天先不聊女兒`, `現在不想談女兒，但${fact}`]) {
      const result = projectMemorySource(userText);
      assert.deepEqual(result, { text: fact, projected: true });
      assert.ok(userText.includes(result.text), "no generated words or pronoun expansion");
    }
  }
});

test("later confirmation, cancellation and indecision stay attached to the original proposition", () => {
  for (const ending of ["後來確定下週搬", "後來取消了", "還沒決定"]) {
    const fact = `女兒可能搬去台南，${ending}`;
    assert.equal(projectMemorySource(`${fact}，今天先不聊她`).text, fact);
  }
});

test("quoted, reported and negated scope is retained whole rather than cut at punctuation", () => {
  for (const text of [
    "女兒說，今天先不聊她", "我不是說，今天先不聊女兒",
    "女兒說「今天先不聊工作」，她還沒決定搬家", "「不要再問我女兒」是什麼意思？",
  ]) assert.deepEqual(projectMemorySource(text), { text, projected: false });
});

test("unknown reference is not resolved using a later topic; independent preference survives", () => {
  assert.equal(projectMemorySource("我喜歡散步，她住在台中，今天先不聊女兒").text, "我喜歡散步");
  for (const text of ["今天先不聊女兒，她住台中", "今天先不聊女兒和媽媽，她住台中", "今天先不聊女兒，她們住台中"]) {
    assert.deepEqual(projectMemorySource(text), { text: null, projected: true });
  }
});

test("unsupported grammar, scope changes and ambiguous continuations abstain without returning the mixed original", () => {
  for (const text of [
    "如果我喜歡散步，今天先不聊女兒", "我喜歡散步，不是今天不聊女兒",
    "女兒說，今天先不聊她。但我今天先不聊女兒", "我不是說今天先不聊女兒，是現在不聊",
    "女兒說她喜歡散步。今天先不聊女兒", "我不是說我喜歡散步。今天先不聊女兒",
    "今天先不聊女兒，以後也永遠不要再問", "以後永遠不要聊女兒，今天先不聊她",
    "我喜歡散步，今天先不聊女兒，不然我不喜歡散步", "我喜歡散步，請你別再追問女兒",
    "今天先不聊女兒她可能搬家", "我喜歡打保齡球，今天先不聊女兒",
  ]) assert.deepEqual(projectMemorySource(text), { text: null, projected: true }, text);
});

test("unscoped refusal is legacy compatibility, not evidence of an enduring preference", () => {
  for (const text of ["我不聊女兒", "以後永遠不要聊我女兒"]) {
    assert.deepEqual(projectMemorySource(text), { text, projected: false });
  }
});

test("storage exclusions are eligibility boundaries; ambiguous pointers never broaden storage", () => {
  assert.deepEqual(projectMemorySource("我喜歡散步。我的住址是測試路一號，住址不要保存"), { text: "我喜歡散步", projected: true });
  for (const text of [
    "我喜歡散步。我的住址是測試路一號，這部分別記住",
    "我喜歡散步。這部分別記住", "我的住址是測試路一號，住址不要保存",
    "我喜歡散步。我的住址是測試路一號，住址不要保存。散步也別記住",
    "我喜歡散步，這件事不想記錄", "請不要儲存我的喜好",
    "我喜歡散步，我的住址是測試路一號，請不要把住址保存",
    "我喜歡散步，住址不要被保存", "我喜歡散步，這部分別 記住",
  ]) assert.deepEqual(projectMemorySource(text), { text: null, projected: true });
});

test("provider selection keeps one complete eligible source unit, never the unselected turn", () => {
  const text = "我喜歡散步。我喜歡聽老歌";
  assert.equal(projectMemorySource(text).requiresSelection, true);
  assert.equal(validateMemorySelection(text, "我喜歡散步"), "我喜歡散步");
  assert.equal(validateMemorySelection(text, "我喜歡聽老歌"), "我喜歡聽老歌");
  assert.equal(validateMemorySelection(text, text), null);
  assert.equal(validateMemorySelection(text, "使用者喜歡散步"), null);
});

test("source substring alone cannot prove eligibility or preserve qualifiers", () => {
  for (const [text, selection] of [
    ["女兒可能搬去台南，後來取消了", "女兒可能搬去台南"],
    ["女兒可能搬去台南，還沒決定", "女兒可能搬去台南"],
    ["女兒說「今天先不聊工作」，她還沒決定搬家", "今天先不聊工作"],
    ["我喜歡散步。我不喜歡散步", "我喜歡散步"],
    ["我喜歡散步。今天穿藍色外套", "我喜歡散步"],
    ["我喜歡散步。這部分別記住", "我喜歡散步"],
    ["我喜歡散步", ""], ["我喜歡散步", null],
  ]) assert.equal(validateMemorySelection(text, selection), null);
});
