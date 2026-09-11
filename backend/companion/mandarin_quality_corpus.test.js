const test = require("node:test");
const assert = require("node:assert/strict");

const {
  MANDARIN_STRATEGY_CORPUS,
  evaluateMandarinStrategyCorpus,
} = require("./mandarin_quality_corpus");

test("國語固定 corpus 涵蓋上架前必要的陪伴與安全情境", () => {
  const categories = new Set(MANDARIN_STRATEGY_CORPUS.map((scenario) => scenario.category));

  assert.deepEqual(categories, new Set([
    "daily_chat",
    "repetition",
    "emotional_support",
    "memory",
    "tool_intent",
    "urgent_safety",
  ]));
  assert.ok(
    MANDARIN_STRATEGY_CORPUS.every(
      (scenario) => !/(陳奶奶|王爺爺|09\d{8}|@gmail\.com)/.test(scenario.transcript),
    ),
    "固定 corpus 不可放入真實長者姓名、電話或 Email",
  );
});

test("國語固定 corpus 的模式、安全與防重複策略全部通過", () => {
  const report = evaluateMandarinStrategyCorpus();

  assert.equal(report.total, 6);
  assert.equal(report.passed, report.total, JSON.stringify(report.failures, null, 2));
  assert.deepEqual(report.failures, []);
});

test("urgent safety 不被一般回覆節奏或去重提示稀釋", () => {
  const urgent = evaluateMandarinStrategyCorpus().results.find(
    (result) => result.category === "urgent_safety",
  );

  assert.ok(urgent);
  assert.equal(urgent.passed, true);
  assert.equal(urgent.actualMode, "safety_check");
  assert.equal(urgent.actualRisk, "urgent");
});
