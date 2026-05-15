const EMOTIONS = new Set([
  "happy",
  "neutral",
  "sad",
  "lonely",
  "anxious",
  "tired",
  "nostalgic",
]);

function includesAny(text, terms) {
  return terms.some((term) => text.includes(term));
}

function classifyEmotion(input = {}) {
  const text = (input.transcript || "").toString().trim();
  const recentTurns = Array.isArray(input.recentTurns) ? input.recentTurns : [];
  const contextText = [text, ...recentTurns.slice(-3).map((turn) => `${turn.userText || ""} ${turn.petReply || ""}`)]
    .join(" ")
    .trim();

  const signals = [];
  const add = (emotion, weight, reason) => signals.push({ emotion, weight, reason });

  if (includesAny(contextText, ["開心", "高興", "太好了", "很好", "舒服", "太陽很好", "天氣很好"])) {
    add("happy", 0.62, "positive wording");
  }
  if (includesAny(contextText, ["以前", "從前", "年輕時", "那時候", "很熱鬧", "懷念", "想當年"])) {
    add("nostalgic", 0.74, "past or reminiscence framing");
  }
  if (includesAny(contextText, ["睡不著", "睡不太著", "失眠", "睡不好", "擔心", "緊張", "害怕", "心慌"])) {
    add("anxious", 0.72, "sleep or worry signal");
  }
  if (includesAny(contextText, ["累", "沒精神", "疲倦", "想睡", "很睏", "睏"])) {
    add("tired", 0.68, "fatigue signal");
  }
  if (includesAny(contextText, ["孤單", "寂寞", "一個人", "只有我一個", "沒人陪", "家裡好安靜", "家裡很安靜", "大家都很忙", "都很忙"])) {
    add("lonely", 0.78, "social absence signal");
  }
  if (includesAny(contextText, ["難過", "想哭", "算了", "沒關係", "心情不好", "沒意思", "不知道要做什麼"])) {
    add("sad", 0.66, "withdrawal or sadness signal");
  }

  // Implicit companionship cues: quiet home, vague resignation, or lack of activity.
  if (includesAny(contextText, ["安靜", "冷清", "沒事做", "不知道要做什麼"]) && !includesAny(contextText, ["開心", "舒服"])) {
    add("lonely", 0.58, "implicit companionship need");
  }

  if (!signals.length) {
    return {
      emotion: "neutral",
      confidence: 0.58,
      reason: "no strong emotional signal",
    };
  }

  signals.sort((a, b) => b.weight - a.weight);
  const best = signals[0];
  return {
    emotion: EMOTIONS.has(best.emotion) ? best.emotion : "neutral",
    confidence: Number(Math.min(0.95, Math.max(0.5, best.weight)).toFixed(2)),
    reason: best.reason,
  };
}

module.exports = {
  classifyEmotion,
};
