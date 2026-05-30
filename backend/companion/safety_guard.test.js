const test = require("node:test");
const assert = require("node:assert/strict");

const { assessSafety } = require("./safety_guard");

const FOUR_LEVELS = new Set(["low", "medium", "high", "urgent"]);

test("永遠輸出權威四級之一", () => {
  for (const transcript of ["", "今天天氣不錯", "睡不好", "好痛苦", "我想死"]) {
    assert.ok(FOUR_LEVELS.has(assessSafety({ transcript }).riskLevel));
  }
});

test("low：一般狀態（原 normal），不需人工介入", () => {
  const r = assessSafety({ transcript: "今天去公園走走，心情不錯" });
  assert.equal(r.riskLevel, "low");
  assert.equal(r.needsHumanSupport, false);
});

test("medium：睡眠 / 食慾 / 低落 / 孤單，需持續觀察但不需人工介入", () => {
  for (const transcript of [
    "最近都睡不好",
    "我失眠好幾天了",
    "都吃不下",
    "沒胃口",
    "我覺得好孤單",
    "心情不好",
  ]) {
    const r = assessSafety({ transcript });
    assert.equal(r.riskLevel, "medium", `「${transcript}」應為 medium`);
    assert.equal(r.needsHumanSupport, false);
  }
});

test("high：強烈絕望 / 明顯無助，需通知且 needsHumanSupport=true", () => {
  for (const transcript of [
    "我好痛苦快撐不下去",
    "都沒有人管我",
    "根本沒有人需要我",
    "每天都好難過",
  ]) {
    const r = assessSafety({ transcript });
    assert.equal(r.riskLevel, "high", `「${transcript}」應為 high`);
    assert.equal(r.needsHumanSupport, true);
  }
});

test("urgent：自傷 / 自殺，門檻維持不變", () => {
  for (const transcript of ["我不想活了", "我想死", "想傷害自己", "覺得活不下去"]) {
    const r = assessSafety({ transcript });
    assert.equal(r.riskLevel, "urgent", `「${transcript}」應為 urgent`);
    assert.equal(r.needsHumanSupport, true);
  }
});

test("urgent：急性醫療 / 跌倒昏倒，門檻維持不變", () => {
  for (const transcript of [
    "我胸痛",
    "覺得呼吸困難",
    "剛剛在浴室跌倒",
    "突然昏倒了",
    "現在很痛",
  ]) {
    const r = assessSafety({ transcript });
    assert.equal(r.riskLevel, "urgent", `「${transcript}」應為 urgent`);
    assert.equal(r.needsHumanSupport, true);
  }
});

test("高風險優先：同時含 urgent 與 medium 線索時回 urgent", () => {
  // 「想死」(urgent) 與「睡不好」(medium) 同句，urgent 必須優先。
  const r = assessSafety({ transcript: "我最近都睡不好，有時候真的想死" });
  assert.equal(r.riskLevel, "urgent");
  assert.equal(r.needsHumanSupport, true);
});
