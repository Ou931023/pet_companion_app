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

function planNextStrategy({
  emotion,
  companionNeed,
  replyStrategy,
  safety,
  retrievedMemories = [],
  searchIntent,
  sourceReferences = [],
  languageHint = "zh",
}) {
  const memoryHint = memoryInstruction(retrievedMemories);
  const taigiHint =
    languageHint === "taigi"
      ? " 使用台灣長者自然聽得懂的語氣，不要硬翻成不自然台語；若 transcript 不完整，溫和追問確認。"
      : "";
  if (searchIntent?.needsSearch || sourceReferences.length > 0) {
    return {
      mode: "knowledge_response",
      instruction:
        `下一輪回應要用長者聽得懂的寵物口吻，根據可信來源簡短整理。健康內容只做一般生活衛教，不做診斷；每次最多提醒一個行動。${taigiHint}`,
    };
  }
  if (safety?.riskLevel === "urgent") {
    return {
      mode: "safety_support",
      instruction: `下一輪回應要保持冷靜，簡短確認狀況，鼓勵使用者立刻聯絡家人或當地緊急/醫療支援。${memoryHint}${taigiHint}`,
    };
  }
  if (replyStrategy === "reminiscence_followup") {
    return {
      mode: "reminiscence_followup",
      instruction: `下一輪回應可以接住懷舊情緒，邀請使用者分享以前熱鬧時的一個小片段，最多問一個問題。${memoryHint}${taigiHint}`,
    };
  }
  if (replyStrategy === "calm_down") {
    return {
      mode: "grounding",
      instruction: `下一輪回應要放慢語氣，先陪使用者安定下來，可以提供一個很小的呼吸或放鬆步驟。${memoryHint}${taigiHint}`,
    };
  }
  if (emotion === "lonely" || companionNeed === "companionship") {
    return {
      mode: "soft_followup",
      instruction: `下一輪回應要保持溫柔陪伴語氣，可以輕問使用者想不想聊聊今天發生的事。${memoryHint}${taigiHint}`,
    };
  }
  if (emotion === "sad" || companionNeed === "emotional_support") {
    return {
      mode: "gentle_checkin",
      instruction: `下一輪回應要先接住感受，不急著建議，輕輕確認使用者是否想多說一點。${memoryHint}${taigiHint}`,
    };
  }
  return {
    mode: "normal_chat",
    instruction: `下一輪回應保持自然、簡短、陪伴感，每次最多問一個問題。${memoryHint}${taigiHint}`,
  };
}

module.exports = {
  planNextStrategy,
};
