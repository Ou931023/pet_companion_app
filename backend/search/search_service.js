const { search } = require("../stt_proxy/services/search/searchService");
const { classifySearchIntent } = require("./search_intent_classifier");
const { formatSources } = require("./source_formatter");

const FALLBACK_ANSWER = "我現在查資料有點不順，我可以先陪你聊聊。";

function modeFromTopic(topic = "") {
  return {
    fraud_prevention: "health_tip",
    elder_life_health: "health_tip",
    sourced_story: "story",
    news: "news",
  }[topic] || "auto";
}

async function searchKnowledge({ query = "", topic = "", userId = "default_user" } = {}) {
  const normalized = query.toString().trim();
  if (!normalized) {
    return {
      answer: "你可以再告訴我想查什麼嗎？",
      sources: [],
      sourceReferences: [],
      topic: topic || "none",
      needsSearch: false,
      provider: "mock_fallback",
    };
  }

  const intent = classifySearchIntent(normalized);
  const resolvedTopic = topic || intent.topic;
  try {
    const result = await search({
      query: normalized,
      mode: modeFromTopic(resolvedTopic),
      userProfile: { userId, ageGroup: "elderly", language: "zh-TW" },
    });
    const sourceReferences = formatSources(result.sources || []);
    if (!sourceReferences.length && result.shouldShowSources) {
      return fallbackResult(resolvedTopic, "no_trusted_sources");
    }
    return {
      ...result,
      answer: result.answer || FALLBACK_ANSWER,
      sources: sourceReferences,
      sourceReferences,
      topic: resolvedTopic,
      needsSearch: true,
    };
  } catch (error) {
    return fallbackResult(resolvedTopic, error?.message || "search_failed");
  }
}

function fallbackResult(topic, reason) {
  return {
    answer: FALLBACK_ANSWER,
    summary: reason,
    sources: [],
    sourceReferences: [],
    topic,
    needsSearch: true,
    provider: "mock_fallback",
    toolUsed: "fallback",
    confidence: "low",
    shouldShowSources: false,
  };
}

module.exports = {
  FALLBACK_ANSWER,
  searchKnowledge,
};
