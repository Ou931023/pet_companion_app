function compact(text, maxLength = 42) {
  const normalized = (text || "").toString().replace(/\s+/g, " ").trim();
  if (normalized.length <= maxLength) return normalized;
  return `${normalized.substring(0, maxLength - 1)}…`;
}

function memoryInstruction(retrievedMemories = []) {
  if (!Array.isArray(retrievedMemories) || !retrievedMemories.length) return "";
  const memory = retrievedMemories[0];
  const summary = compact(memory.memorySummary || memory.content || memory.memoryText || "");
  if (!summary) return "";
  return ` 可自然參考使用者過去提到的「${summary}」，但不要說出「記憶」或「資料庫」。`;
}

function planNextStrategy({ emotion, companionNeed, replyStrategy, safety, retrievedMemories = [] }) {
  const memoryHint = memoryInstruction(retrievedMemories);
  if (safety?.riskLevel === "urgent") {
    return {
      mode: "safety_support",
      instruction: `下一輪回應要保持冷靜，簡短確認狀況，鼓勵使用者立刻聯絡家人或當地緊急/醫療支援。${memoryHint}`,
    };
  }
  if (replyStrategy === "reminiscence_followup") {
    return {
      mode: "reminiscence_followup",
      instruction: `下一輪回應可以接住懷舊情緒，邀請使用者分享以前熱鬧時的一個小片段，最多問一個問題。${memoryHint}`,
    };
  }
  if (replyStrategy === "calm_down") {
    return {
      mode: "grounding",
      instruction: `下一輪回應要放慢語氣，先陪使用者安定下來，可以提供一個很小的呼吸或放鬆步驟。${memoryHint}`,
    };
  }
  if (emotion === "lonely" || companionNeed === "companionship") {
    return {
      mode: "soft_followup",
      instruction: `下一輪回應要保持溫柔陪伴語氣，可以輕問使用者想不想聊聊今天發生的事。${memoryHint}`,
    };
  }
  if (emotion === "sad" || companionNeed === "emotional_support") {
    return {
      mode: "gentle_checkin",
      instruction: `下一輪回應要先接住感受，不急著建議，輕輕確認使用者是否想多說一點。${memoryHint}`,
    };
  }
  return {
    mode: "normal_chat",
    instruction: `下一輪回應保持自然、簡短、陪伴感，每次最多問一個問題。${memoryHint}`,
  };
}

module.exports = {
  planNextStrategy,
};
