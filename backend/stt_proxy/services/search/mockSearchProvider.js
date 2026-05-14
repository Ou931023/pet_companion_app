function companionChat(query) {
  return {
    answer: `我在這裡陪你。你剛剛說「${query}」，聽起來心裡有一點重，我們可以慢慢聊，不急著解決。`,
    summary: "陪伴聊天，不查網路。",
    sources: [],
    provider: "companion_reply",
    toolUsed: "internal_reply",
    confidence: "high",
  };
}

function originalStory() {
  return {
    answer:
      "從前有一隻小小的陪伴寵物，每天都坐在窗邊等陽光。牠發現，只要輕輕問一句「今天還好嗎」，人的心就會慢慢暖起來。後來牠學會了，陪伴不一定要說很多話，只要一直在，就很有力量。",
    summary: "原創陪伴小故事。",
    sources: [],
    provider: "creative_story",
    toolUsed: "internal_reply",
    confidence: "high",
  };
}

function fallback(mode) {
  const message =
    mode === "weather"
      ? "我現在暫時查不到天氣，出門前可以再看一下氣象資訊，也記得帶水和外套。"
      : "目前沒有取得可靠來源，我先不亂說，我可以先陪你聊聊或稍後再幫你查。";
  return {
    answer: message,
    summary: message,
    sources: [],
    provider: "mock_fallback",
    toolUsed: "fallback",
    confidence: "low",
  };
}

module.exports = {
  companionChat,
  originalStory,
  fallback,
};
