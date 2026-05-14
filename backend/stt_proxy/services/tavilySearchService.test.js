const test = require("node:test");
const assert = require("node:assert/strict");

const {
  extractWeatherLocation,
  isWeatherQuery,
  needsWebSearch,
  isHighRiskQuery,
} = require("./tavilySearchService");

test("needsWebSearch detects real-time information queries", () => {
  assert.equal(needsWebSearch("今天有什麼新聞？"), true);
  assert.equal(needsWebSearch("幫我查天氣"), true);
  assert.equal(needsWebSearch("附近有什麼活動？"), true);
  assert.equal(needsWebSearch("最近詐騙新聞有哪些？"), true);
});

test("needsWebSearch ignores ordinary companionship chat", () => {
  assert.equal(needsWebSearch("我今天有點累"), false);
  assert.equal(needsWebSearch("陪我聊聊天"), false);
});

test("isHighRiskQuery detects health, legal, and finance topics", () => {
  assert.equal(isHighRiskQuery("查一下這個健康資訊"), true);
  assert.equal(isHighRiskQuery("這個合約有沒有法律問題"), true);
  assert.equal(isHighRiskQuery("最近股票投資可以買嗎"), true);
});

test("weather query helpers detect and extract locations", () => {
  assert.equal(isWeatherQuery("幫我查嘉義市天氣"), true);
  assert.equal(extractWeatherLocation("幫我查嘉義市天氣"), "嘉義市");
  assert.equal(extractWeatherLocation("查天氣"), "嘉義市");
});
