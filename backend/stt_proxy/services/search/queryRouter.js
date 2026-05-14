function includesAny(text, keywords) {
  return keywords.some((keyword) => text.includes(keyword));
}

function isStoryQuery(text) {
  return includesAny(text, ["故事", "講古", "童話"]);
}

function isWebStoryQuery(text) {
  return includesAny(text, [
    "真實故事",
    "新聞故事",
    "最近發生的故事",
    "最近發生",
    "最近的故事",
    "感人故事",
    "感人的真實故事",
    "歷史故事",
    "地方故事",
    "台灣地方故事",
    "臺灣地方故事",
    "有來源的故事",
  ]);
}

function hasFreshnessIntent(text) {
  return includesAny(text, ["今天", "最近", "新聞", "最新", "查一下", "幫我查", "搜尋"]);
}

function isHealthQuery(text) {
  return includesAny(text, ["健康", "睡眠", "運動", "喝水", "吃藥", "長輩", "老人", "高齡", "衛教"]);
}

function classifyQuery(query, requestedMode = "auto") {
  const text = (query || "").trim();
  if (!text) return { mode: "companion_chat", needsWebSearch: false };
  if (requestedMode && requestedMode !== "auto") {
    if (requestedMode === "story") {
      const storyType = isWebStoryQuery(text) ? "web_story" : "creative_story";
      return {
        mode: "story",
        storyType,
        needsWebSearch: storyType === "web_story",
      };
    }
    return {
      mode: requestedMode,
      needsWebSearch: ["news", "weather", "general_web_search"].includes(requestedMode),
    };
  }

  if (includesAny(text, ["孤單", "難過", "心情不好", "想哭", "寂寞", "焦慮"])) {
    return { mode: "companion_chat", needsWebSearch: false };
  }
  if (isStoryQuery(text)) {
    const storyType = isWebStoryQuery(text) ? "web_story" : "creative_story";
    return {
      mode: "story",
      storyType,
      needsWebSearch: storyType === "web_story",
    };
  }
  if (includesAny(text, ["天氣", "氣溫", "會下雨", "降雨"])) {
    return { mode: "weather", needsWebSearch: true };
  }
  if (hasFreshnessIntent(text)) {
    if (isHealthQuery(text)) {
      return { mode: "health_tip", needsWebSearch: true };
    }
    return { mode: "news", needsWebSearch: true };
  }
  if (isHealthQuery(text)) {
    return { mode: "health_tip", needsWebSearch: false };
  }
  return { mode: "general_web_search", needsWebSearch: true };
}

module.exports = {
  classifyQuery,
};
