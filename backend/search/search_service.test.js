const test = require("node:test");
const assert = require("node:assert/strict");

const { classifySearchIntent } = require("./search_intent_classifier");
const { filterTrustedSources } = require("./trusted_source_filter");
const { searchKnowledge } = require("./search_service");

test("fraud prevention query triggers search", () => {
  const intent = classifySearchIntent("說一個防詐故事");
  assert.equal(intent.needsSearch, true);
  assert.equal(intent.topic, "fraud_prevention");
});

test("ordinary companion chat does not trigger search", () => {
  const intent = classifySearchIntent("今天家裡好安靜");
  assert.equal(intent.needsSearch, false);
});

test("來源過濾：一般來源全部放行，只擋成人內容", () => {
  const filtered = filterTrustedSources([
    { title: "官方防詐", url: "https://165.npa.gov.tw/article", sourceType: "government" },
    { title: "一般新聞", url: "https://www.reuters.com/world/asia" },
    { title: "個人部落格", url: "https://random-blog.example/post" },
    { title: "成人內容", url: "https://www.pornhub.com/view" },
  ]);
  const urls = filtered.map((s) => s.url);
  // 官方、主流新聞、一般部落格都應保留（政策：盡量不限制）。
  assert.ok(urls.includes("https://165.npa.gov.tw/article"));
  assert.ok(urls.includes("https://www.reuters.com/world/asia"));
  assert.ok(urls.includes("https://random-blog.example/post"));
  // 只有限制級 / 成人內容被擋掉。
  assert.ok(!urls.some((u) => u.includes("pornhub")));
});

test("knowledge search returns sourceReferences for fraud query", async () => {
  const result = await searchKnowledge({
    query: "長者防詐提醒",
    topic: "fraud_prevention",
    userId: "demo-user",
  });
  assert.equal(result.needsSearch, true);
  assert.ok(result.answer.length > 0);
  assert.ok(result.sourceReferences.length > 0);
  assert.ok(result.sourceReferences[0].title);
  assert.ok(result.sourceReferences[0].url);
});

test("search fallback uses gentle companion message when no trusted source", async () => {
  const result = await searchKnowledge({
    query: "完全沒有可信資料的奇怪查詢 zzzzzzz",
    topic: "news",
    userId: "demo-user",
  });
  if (result.sourceReferences.length === 0) {
    assert.equal(result.answer, "我現在查資料有點不順，我可以先陪你聊聊。");
  }
});
