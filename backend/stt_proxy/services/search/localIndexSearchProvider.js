const { listDocuments } = require("./documentStore");

function tokenize(text) {
  const normalized = (text || "").toLowerCase();
  const cjkTokens = normalized.match(/[\u4e00-\u9fa5]{2,}/g) || [];
  const words = normalized.match(/[a-z0-9]{2,}/g) || [];
  const healthSynonyms = [];
  if (normalized.includes("睡")) healthSynonyms.push("睡眠", "作息", "失眠");
  if (normalized.includes("水")) healthSynonyms.push("喝水", "補水", "飲水");
  if (normalized.includes("運動")) healthSynonyms.push("散步", "伸展", "高齡");
  if (normalized.includes("藥")) healthSynonyms.push("用藥", "藥師", "醫師");
  if (normalized.includes("跌")) healthSynonyms.push("防跌", "跌倒");
  return [...new Set([...cjkTokens, ...words, ...healthSynonyms])];
}

function scoreDocument(queryTokens, doc, mode) {
  const haystack = `${doc.title} ${doc.summary} ${doc.content} ${doc.category}`.toLowerCase();
  let score = 0;
  for (const token of queryTokens) {
    if (haystack.includes(token.toLowerCase())) score += token.length >= 4 ? 2 : 1;
  }
  if (mode === doc.category) score += 2;
  if (doc.sourceType === "mock_trusted" || doc.sourceType === "trusted_crawl") score += 1;
  return score;
}

async function searchLocalIndex({ query, mode = "health_tip", limit = 4 }) {
  const docs = await listDocuments();
  const tokens = tokenize(query);
  const ranked = docs
    .filter((doc) => doc.isActive !== false)
    .map((doc) => ({
      ...doc,
      provider: "local_index",
      snippet: doc.summary || doc.content.slice(0, 160),
      score: scoreDocument(tokens, doc, mode),
    }))
    .filter((doc) => doc.score > 0 || (mode === "health_tip" && doc.category === "health_tip"))
    .sort((a, b) => b.score - a.score)
    .slice(0, limit);

  return {
    provider: "local_index",
    results: ranked,
    confidence: ranked.length > 0 && ranked[0].score >= 2 ? "high" : ranked.length > 0 ? "medium" : "low",
  };
}

module.exports = {
  searchLocalIndex,
};
