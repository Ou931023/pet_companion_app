function includesAny(text, terms) {
  return terms.some((term) => text.includes(term));
}

function classifySearchIntent(input = "") {
  const text = input.toString().trim();
  if (!text) {
    return { needsSearch: false, topic: "none", reason: "empty_query" };
  }

  if (includesAny(text, ["新聞", "新鮮事", "最新", "今天有什麼", "最近發生"])) {
    return { needsSearch: true, topic: "news", reason: "freshness_or_news" };
  }
  if (includesAny(text, ["防詐", "詐騙", "165", "假投資", "假冒"])) {
    return { needsSearch: true, topic: "fraud_prevention", reason: "fraud_prevention" };
  }
  if (includesAny(text, ["健康小知識", "睡不好", "睡不著", "運動", "長輩", "老人", "高齡", "生活建議", "衛教"])) {
    return { needsSearch: true, topic: "elder_life_health", reason: "elder_health_education" };
  }
  if (includesAny(text, ["真實故事", "防詐故事", "新聞故事", "有來源的故事", "地方故事"])) {
    return { needsSearch: true, topic: "sourced_story", reason: "sourced_story" };
  }

  return { needsSearch: false, topic: "none", reason: "ordinary_companion_chat" };
}

module.exports = {
  classifySearchIntent,
};
