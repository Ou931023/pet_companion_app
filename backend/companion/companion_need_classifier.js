function includesAny(text, terms) {
  return terms.some((term) => text.includes(term));
}

function classifyCompanionNeed({ transcript = "", emotion = "neutral" } = {}) {
  const text = transcript.toString().trim();

  if (includesAny(text, ["以前", "從前", "年輕時", "很熱鬧", "懷念", "想當年"])) {
    return {
      companionNeed: "reminiscence",
      confidence: 0.87,
      reason: "memory and past-oriented cue",
    };
  }
  if (includesAny(text, ["睡不著", "睡不太著", "失眠", "睡不好", "緊張", "心慌", "害怕"])) {
    return {
      companionNeed: "grounding",
      confidence: 0.84,
      reason: "needs calming or grounding",
    };
  }
  if (includesAny(text, ["提醒", "吃藥", "喝水", "回診", "鬧鐘"])) {
    return {
      companionNeed: "reminder_support",
      confidence: 0.82,
      reason: "reminder-related request",
    };
  }
  if (includesAny(text, ["不知道要做什麼", "沒事做", "無聊"])) {
    return {
      companionNeed: "daily_chat",
      confidence: 0.78,
      reason: "open-ended daily companionship",
    };
  }
  if (includesAny(text, ["大家都很忙", "都很忙", "算了", "沒關係", "難過", "心情不好"])) {
    return {
      companionNeed: "emotional_support",
      confidence: 0.82,
      reason: "withdrawal or sadness cue",
    };
  }
  if (
    emotion === "lonely" ||
    includesAny(text, ["家裡好安靜", "家裡很安靜", "冷清", "一個人", "只有我一個", "沒人陪"])
  ) {
    return {
      companionNeed: "companionship",
      confidence: 0.86,
      reason: "social absence or quiet-home cue",
    };
  }
  if (emotion === "sad") {
    return {
      companionNeed: "emotional_support",
      confidence: 0.8,
      reason: "withdrawal or sadness cue",
    };
  }
  if (emotion === "happy") {
    return {
      companionNeed: "encouragement",
      confidence: 0.68,
      reason: "positive engagement can be encouraged",
    };
  }
  return {
    companionNeed: "daily_chat",
    confidence: 0.58,
    reason: "ordinary chat",
  };
}

module.exports = {
  classifyCompanionNeed,
};
