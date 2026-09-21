const test = require("node:test");
const assert = require("node:assert/strict");
const { COMPANIONSHIP_VOICE_POLICY, TOOL_TRUTH_POLICY, outputLanguageInstruction } = require("./voice_prompt_policy");
const { planNextStrategy } = require("./next_strategy_planner");

test("ordinary prompts end the turn without suppressing requested detail or urgent safety", () => {
  assert.match(COMPANIONSHIP_VOICE_POLICY, /不例行追問/);
  assert.match(COMPANIONSHIP_VOICE_POLICY, /等待新的使用者輸入/);
  assert.match(COMPANIONSHIP_VOICE_POLICY, /工具完成也不另開話題/);
  assert.match(COMPANIONSHIP_VOICE_POLICY, /不可省略必要安全內容/);
  const ordinary = planNextStrategy({ transcript: "今天很開心", safety: { riskLevel: "low" } });
  assert.ok(ordinary.instruction.includes(COMPANIONSHIP_VOICE_POLICY));
  const urgent = planNextStrategy({ transcript: "我跌倒了", safety: { riskLevel: "urgent" } });
  assert.equal(urgent.mode, "safety_check");
  assert.match(urgent.instruction, /立刻聯絡家人/);
  assert.ok(!urgent.instruction.includes(COMPANIONSHIP_VOICE_POLICY));
});

test("selected Taiwanese wins over Mandarin ASR, including tool outcomes", () => {
  for (const replyLanguage of ["taigi", "mixed-zh-taigi"]) {
    const prompt = outputLanguageInstruction({ replyLanguage, languageHint: "zh", mode: "realtime" });
    assert.match(prompt, /以台語/);
    assert.match(prompt, /工具確認與結果也維持台語/);
    assert.match(prompt, /直到使用者明確改選/);
  }
  assert.match(outputLanguageInstruction({ replyLanguage: "zh", languageHint: "taigi", mode: "taigi_realtime" }), /Mandarin/);
  assert.match(outputLanguageInstruction({ languageHint: "taigi" }), /以台語/);
  assert.match(outputLanguageInstruction({ mode: "taigi_realtime" }), /以台語/);
});

test("tool prompt forbids premature success and distinguishes virtual from real orders", () => {
  assert.match(TOOL_TRUTH_POLICY, /不得提前聲稱成功/);
  assert.match(TOOL_TRUTH_POLICY, /搜尋頁開啟不等於已播放/);
  assert.match(TOOL_TRUTH_POLICY, /明確確認後才執行/);
  assert.match(TOOL_TRUTH_POLICY, /不能說已建立實體商品訂單/);
});
