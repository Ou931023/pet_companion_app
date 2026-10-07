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

test("sharing permits one same-topic observation or optional invitation without repetitive questions or invented memory", () => {
  assert.match(COMPANIONSHIP_VOICE_POLICY, /1–3 句/);
  assert.match(COMPANIONSHIP_VOICE_POLICY, /分享事情或表示想聊.*同一話題.*小觀察/);
  assert.match(COMPANIONSHIP_VOICE_POLICY, /容易回答、可拒絕.*不必每次都問/);
  assert.match(COMPANIONSHIP_VOICE_POLICY, /未回答的問題也不反覆催問/);
  assert.match(COMPANIONSHIP_VOICE_POLICY, /不編造共同經歷或使用者喜好/);
  assert.match(COMPANIONSHIP_VOICE_POLICY, /不主動帶出健康、家庭衝突等敏感記憶/);
  assert.match(COMPANIONSHIP_VOICE_POLICY, /不把普通聊天拉回任務或養成進度/);
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

test("CR-0110 B: topic invitation is explicit, optional, non-repetitive and never idle speech", () => {
  assert.match(COMPANIONSHIP_VOICE_POLICY, /只有使用者明確表示無話題、無聊或沒事做時/);
  assert.match(COMPANIONSHIP_VOICE_POLICY, /一個低壓力、可拒絕/);
  assert.match(COMPANIONSHIP_VOICE_POLICY, /不想聊天.*不邀聊、不追問/);
  assert.match(COMPANIONSHIP_VOICE_POLICY, /沉默不是續講邀請/);
  assert.match(COMPANIONSHIP_VOICE_POLICY, /不要只換同義詞重複/);
  assert.match(COMPANIONSHIP_VOICE_POLICY, /使用者已回答或拒絕.*不再重問/);
  assert.match(COMPANIONSHIP_VOICE_POLICY, /不把喝水、吃藥等生活回報當成新增任務/);
});

test("CR-0110 B: reminder and news claims require real results, unknown outcomes never invite blind retry", () => {
  assert.match(TOOL_TRUTH_POLICY, /等待、失敗或結果未知/);
  assert.match(TOOL_TRUTH_POLICY, /不能自行重試有副作用的動作/);
  assert.match(TOOL_TRUTH_POLICY, /提醒只有收到實際建立成功結果才說已設定/);
  assert.match(TOOL_TRUTH_POLICY, /取消也必須有實際成功結果/);
  assert.match(TOOL_TRUTH_POLICY, /不承諾沒有工具支援的稍後主動提醒/);
  assert.match(TOOL_TRUTH_POLICY, /新聞沒有實際搜尋結果與來源時，不編造/);
  assert.match(COMPANIONSHIP_VOICE_POLICY, /沒有對應工具成功結果，不承諾稍後自動提醒/);
});
