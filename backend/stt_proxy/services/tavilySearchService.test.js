const test = require("node:test");
const assert = require("node:assert/strict");

const {
  extractWeatherLocation,
  isWeatherQuery,
  needsWebSearch,
  isHighRiskQuery,
} = require("./tavilySearchService");

test("needsWebSearch detects real-time information queries", () => {
  assert.equal(needsWebSearch("今天有什麼防詐新聞？"), true);
  assert.equal(needsWebSearch("幫我查天氣"), true);
  assert.equal(needsWebSearch("附近有什麼活動？"), true);
  assert.equal(needsWebSearch("最近詐騙新聞有哪些？"), true);
});

// CR-0080：擴充即時資訊偵測——天氣 / 補助 / 政策 / 價格時刻等問題
// 不應被當成一般閒聊而回「不能馬上查」。
test("needsWebSearch detects subsidies, policy, prices and weather variants", () => {
  assert.equal(needsWebSearch("今天嘉義天氣如何？"), true);
  assert.equal(needsWebSearch("最近有什麼長照補助？"), true);
  assert.equal(needsWebSearch("現在有什麼股市新聞？"), true);
  assert.equal(needsWebSearch("敬老津貼怎麼申請？"), true);
  assert.equal(needsWebSearch("今天油價多少？"), true);
  assert.equal(needsWebSearch("這個颱風會不會放假？"), true);
});

test("needsWebSearch asks preference for broad news instead of searching", () => {
  assert.equal(needsWebSearch("今天有什麼新聞？"), false);
  assert.equal(needsWebSearch("今仔日有啥新聞？"), false);
  assert.equal(needsWebSearch("有啥物新聞？"), false);
  assert.equal(needsWebSearch("新聞予我聽"), false);
  assert.equal(needsWebSearch("現在有什麼重要新聞？"), false);
});

test("needsWebSearch ignores ordinary companionship chat", () => {
  assert.equal(needsWebSearch("我今天有點累"), false);
  assert.equal(needsWebSearch("陪我聊聊天"), false);
  assert.equal(needsWebSearch("我現在心情不太好"), false);
  assert.equal(needsWebSearch("最近都睡不好"), false);
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
