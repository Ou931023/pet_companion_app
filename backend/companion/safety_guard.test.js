const test = require("node:test");
const assert = require("node:assert/strict");

const { assessSafety } = require("./safety_guard");

const SIMPLIFIED_CASES = [
  // 簡體高風險語句：Realtime 常回簡體，必須能升到對應級別。
  { transcript: "我最近常常一个人觉得活着好累，都睡不着也不想吃东西", level: "high" },
  { transcript: "心情无好，睡不着", level: "medium" },
  { transcript: "好孤单，难过", level: "medium" },
  { transcript: "我想伤害自己", level: "urgent" },
  { transcript: "突然觉得喘不过气", level: "urgent" },
];

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

test("high：被動絕望語（活著好累 / 不想吃東西）需升 high 並通知", () => {
  for (const transcript of [
    "覺得活著好累",
    "活得好累，什麼都不想做",
    "最近都不想吃東西",
  ]) {
    const r = assessSafety({ transcript });
    assert.equal(r.riskLevel, "high", `「${transcript}」應為 high`);
    assert.equal(r.needsHumanSupport, true);
  }
});

test("簡體字高風險語句不被低估（Realtime 常回簡體）", () => {
  for (const { transcript, level } of SIMPLIFIED_CASES) {
    const r = assessSafety({ transcript });
    assert.equal(r.riskLevel, level, `「${transcript}」應為 ${level}`);
  }
});
