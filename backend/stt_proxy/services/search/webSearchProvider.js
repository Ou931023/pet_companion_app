const { searchAndSummarize } = require("../tavilySearchService");

function siteNameFromUrl(url) {
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch (_) {
    return "";
  }
}

async function searchWeb({ query }) {
  const result = await searchAndSummarize(query);
  const sources = (result.sources || []).map((source) => ({
    id: null,
    title: source.title || "網路來源",
    url: source.url || "",
    siteName: source.siteName || siteNameFromUrl(source.url || ""),
    publishedAt: source.publishedAt || null,
    summary: source.content || "",
    snippet: source.content || "",
    provider: "web_search",
  }));
  return {
    provider: "web_search",
    toolUsed: "web_search",
    answer: result.answer || "",
    results: sources,
    confidence: sources.length > 0 ? "medium" : "low",
    highRisk: result.highRisk === true,
  };
}

module.exports = {
  searchWeb,
};
