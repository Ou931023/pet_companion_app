function shouldSaveMemory({ transcript = "", emotion, companionNeed } = {}) {
  const text = transcript.toString().trim();
  if (text.length < 4) {
    return { shouldSave: false, candidate: "", type: "none" };
  }

  const emotionalNeeds = new Set(["companionship", "emotional_support", "reminiscence", "grounding"]);
  const emotionalStates = new Set(["lonely", "sad", "anxious", "tired", "nostalgic"]);
  const hasSpecificContext = /家裡|大家|以前|睡|吃飯|一個人|安靜|熱鬧|不知道/.test(text);

  if (emotionalNeeds.has(companionNeed) && (emotionalStates.has(emotion) || hasSpecificContext)) {
    return {
      shouldSave: true,
      candidate: `使用者提到「${text}」，可能需要${memoryNeedLabel(companionNeed)}。`,
      type: emotion === "nostalgic" || companionNeed === "reminiscence" ? "reminiscence" : "emotion_event",
    };
  }

  return { shouldSave: false, candidate: "", type: "none" };
}

function memoryNeedLabel(need) {
  return {
    companionship: "陪伴感",
    emotional_support: "情緒支持",
    reminiscence: "懷舊陪伴",
    grounding: "安定陪伴",
  }[need] || "陪伴";
}

module.exports = {
  shouldSaveMemory,
};
