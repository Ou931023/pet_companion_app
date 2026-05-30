const test = require("node:test");
const assert = require("node:assert/strict");

const {
  buildCareAlertSummary,
  detectSignals,
} = require("./companion_prompt_builder");

const DIAGNOSTIC_TERMS = /憂鬱症|確診|病人|診斷|罹患|疾病/;
const ALARM_TERMS = /緊急|危險|立即|嚴重|警示|馬上/;

test("detectSignals 偵測睡眠 / 情緒 / 孤單等訊號並組成自然片語", () => {
  const signals = detectSignals("我最近都睡不好，心情不好，覺得好孤單");
  assert.ok(signals.includes("睡眠不佳"));
  assert.ok(signals.includes("情緒低落"));
  assert.ok(signals.includes("感到孤單"));
});

test("medium 摘要為持續觀察語氣、含偵測訊號", () => {
  const s = buildCareAlertSummary({ riskLevel: "medium", transcript: "最近都睡不好" });
  assert.match(s, /持續觀察/);
  assert.match(s, /睡眠不佳/);
  assert.doesNotMatch(s, ALARM_TERMS);
});

test("high 摘要建議主動關心，含原因/訊號/行動", () => {
  const s = buildCareAlertSummary({
    riskLevel: "high",
    transcript: "每天都好難過，覺得沒有人需要我",
  });
  assert.match(s, /主動關心/);
  assert.match(s, /強烈的無助或難過/);
  assert.ok(s.length > 0);
});

test("#4 urgent 摘要必須建議立即確認安全，不退化為普通關心", () => {
  const s = buildCareAlertSummary({
    riskLevel: "urgent",
    transcript: "我剛剛在浴室跌倒了，現在很痛",
  });
  assert.match(s, /確認安全/);
  assert.match(s, /立即|儘快/);
  // 不可與 high/medium 的普通關心語句相同
  const high = buildCareAlertSummary({ riskLevel: "high", transcript: "我剛剛在浴室跌倒了" });
  const medium = buildCareAlertSummary({ riskLevel: "medium", transcript: "我剛剛在浴室跌倒了" });
  assert.notEqual(s, high);
  assert.notEqual(s, medium);
});

test("urgent 即使沒有可辨識訊號，仍給出立即確認安全的建議", () => {
  const s = buildCareAlertSummary({ riskLevel: "urgent", transcript: "……" });
  assert.match(s, /確認安全/);
  assert.match(s, /立即|儘快/);
});

test("#5 各級摘要皆不得使用診斷式語氣", () => {
  const cases = [
    { riskLevel: "low", transcript: "今天天氣很好" },
    { riskLevel: "medium", transcript: "最近都睡不好，心情不好" },
    { riskLevel: "high", transcript: "每天都好難過，沒有人需要我" },
    { riskLevel: "urgent", transcript: "我想死" },
  ];
  for (const c of cases) {
    const s = buildCareAlertSummary(c);
    assert.doesNotMatch(s, DIAGNOSTIC_TERMS, `「${c.riskLevel}」摘要不應含診斷字眼：${s}`);
  }
});

test("#6 low 摘要不誇大、不含警示語", () => {
  const s = buildCareAlertSummary({ riskLevel: "low", transcript: "今天去公園散步" });
  assert.match(s, /大致平穩|不需特別處理/);
  assert.doesNotMatch(s, ALARM_TERMS);
});

test("預設（無參數）視為 low，回穩定的一般狀態摘要", () => {
  const s = buildCareAlertSummary();
  assert.doesNotMatch(s, ALARM_TERMS);
  assert.ok(s.length > 0);
});
