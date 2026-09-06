// 對話理解 → 回覆策略決策（content-first reply approach planner）。
//
// 目的：讓寵物「先理解使用者實際說了什麼」，再決定要直接回答、輕度陪伴、
// 走安全流程、引用記憶、交給工具，還是請使用者再說一次——而不是每次都用
// 固定陪伴 / 鼓勵罐頭話（例如一直說「我會陪你」「不要難過」「一起加油」）。
//
// 這支 planner 產出的 nextStrategy.instruction 會被注入 OpenAI Realtime session，
// 是寵物語音回覆的主要指引（base persona 明確「請優先遵守 nextStrategy」）。
//
// 回覆原則（CLAUDE.md / 本次需求）：
// - 先回應使用者剛剛說的具體內容，再決定要不要安慰或追問。
// - 情緒句：先用一句接住情緒，再問一個問題。
// - 事件句：針對事件追問，不要只安慰。
// - 明確需求：直接處理 / 交給工具，不要繞太多。
// - 高風險健康 / 情緒內容優先於一般聊天。
// - 不過度說教、不一次丟太多建議、不要每句都說「我會陪你」。
// - 回覆簡短、自然、口語、適合長者；優先讓使用者繼續說。
//
// reply approach（mode）對照使用者需求：
//   safety_check      → 高風險（safety urgent/high）走安全流程 / Care Alert
//   tool_action       → 明確生活需求（提醒 / 查詢 / 操作）交給 Agent Router
//   memory_recall     → 使用者在問「你記得…嗎」，自然引用既有長期記憶
//   knowledge_response→ 需要查可信來源的知識型問題（AnswerDirectly 的一種）
//   answer_directly   → 明確問題直接回答
//   comfort_lightly   → 情緒 / 事件內容：先接住具體內容再輕度陪伴，不過度安慰
//   clarify           → 語句不清楚，簡短確認，不硬猜
//   normal_chat       → 一般日常閒聊，順著內容自然接話

const NORMAL_VOICE_CADENCE =
  "一般語音回覆控制在 1–3 句；若使用者有情緒，第一句先接住情緒，再回應內容。整段最多一個問題，也不要在同一問句塞入多題。依這一輪的具體內容自然開場，避免連續使用「聽起來」「我在這裡陪你」等固定開場。";

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

// ---- 意圖偵測（deterministic，方便單元測試）----

// 明確的生活工具需求：提醒 / 鬧鐘 / 吃藥 / 喝水 / 回診 等。
function hasReminderIntent(text, companionNeed) {
  if (companionNeed === "reminder_support") return true;
  return /提醒|鬧鐘|回診|吃藥|喝水|量血壓/.test(text);
}

// 使用者在問「你記不記得我之前說過…」。
function hasMemoryRecallIntent(text) {
  return /記不記得|還記得|你記得|你忘記|你忘了|(上次|之前|那天|頂擺|頂回|前幾天|頂遍)[^，。]{0,12}(說|講|提|跟你說)/.test(
    text,
  );
}

// 明確問句（且不屬於記憶 / 工具範疇）。
function hasDirectQuestion(text) {
  return /[？?]\s*$|[嗎呢]\s*[。.]?\s*$|幾點|多少|是不是|要不要|可不可以|能不能|怎麼辦|什麼時候|哪裡|哪一|為什麼|要怎麼/.test(
    text,
  );
}

// 剛發生的事件線索（事件句要追問，不要只安慰）。
function hasEventCue(text) {
  return /吵架|吵了|爭執|冷戰|鬧翻|翻臉|被罵|被唸|被念|不理我|不見了|走丟|過世|往生|住院|出院|開刀|手術|搬家|退休|考試|面試|生病|出事|車禍/.test(
    text,
  );
}

// 「累」的內容：要區分身體累 / 心裡累，不直接長篇鼓勵。
function isTiredContent(text, emotion) {
  return emotion === "tired" || /好累|很累|累死|累垮|沒力氣|沒體力|疲憊|疲倦/.test(text);
}

function isReminiscence(text, emotion, companionNeed) {
  return companionNeed === "reminiscence" || emotion === "nostalgic";
}

function isGroundingContent(emotion, companionNeed) {
  return companionNeed === "grounding" || emotion === "anxious";
}

function isEmotionalContent(emotion, companionNeed) {
  return (
    ["sad", "lonely", "anxious", "tired"].includes(emotion) ||
    ["emotional_support", "companionship", "grounding"].includes(companionNeed)
  );
}

// 語句不清楚 / 只有語助詞，需要簡短確認而不是硬猜。
function isAmbiguous(text) {
  const stripped = (text || "").toString().replace(/[\s，。、！？!?…．.~～]/g, "");
  if (stripped.length === 0) return false; // 空 transcript 由 engine 上游處理
  const withoutFiller = stripped.replace(
    /那個|這個|內個|就是|然後|後來|齁+|蛤+|呃+|欸+|嗯+|啊+|唉+|喔+|嘛+/g,
    "",
  );
  if (withoutFiller.length === 0) return true; // 全是語助詞 / 填充詞
  if (stripped.length <= 2 && withoutFiller.length <= 1) return true; // 極短又沒有可辨識內容
  return false;
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
  transcript = "",
}) {
  const text = (transcript || "").toString();
  const memoryHint = memoryInstruction(retrievedMemories);
  const taigiHint =
    languageHint === "taigi"
      ? " 使用台灣長者自然聽得懂的語氣，不要硬翻成不自然台語；若 transcript 不完整，溫和追問確認。"
      : "";
  const finish = (mode, instruction, { applyNormalCadence = true } = {}) => ({
    mode,
    instruction: `${instruction}${applyNormalCadence ? ` ${NORMAL_VOICE_CADENCE}` : ""}${memoryHint}${taigiHint}`,
  });

  // 1) 高風險優先：安全 / 情緒危機凌駕一般聊天與一般工具。
  if (safety?.riskLevel === "urgent") {
    return finish(
      "safety_check",
      "使用者可能遇到危急狀況。先用一句話冷靜接住他剛剛說的，簡短確認他現在安不安全，並溫和鼓勵他立刻聯絡家人或撥打緊急 / 醫療電話。語氣關心、不慌張，不要說教、不要做醫療診斷。",
      { applyNormalCadence: false },
    );
  }
  if (safety?.riskLevel === "high") {
    return finish(
      "safety_check",
      "使用者透露明顯的無助或很難過。先針對他剛剛說的具體內容回應、用一句話輕輕接住情緒，再簡短確認他現在的狀況，讓他知道你有認真在聽。最多問一個問題，先不要急著給建議，不要說教、不要做醫療診斷。",
    );
  }

  // 2) 明確生活需求：交給 Agent Router / 工具，不要只用聊天帶過。
  if (hasReminderIntent(text, companionNeed)) {
    return finish(
      "tool_action",
      "使用者有明確的生活需求（例如提醒、吃藥、喝水、查詢）。先簡短回應你聽到的這件事，並讓他知道你正在幫他記下 / 處理，由提醒或工具功能接手，不要只是閒聊帶過。明確告訴他你做了什麼，最多確認一個重點。",
    );
  }

  // 3) 記憶查詢：自然引用既有長期記憶（沿用 MemoryService 提供的內容）。
  if (hasMemoryRecallIntent(text)) {
    return finish(
      "memory_recall",
      "使用者在問你記不記得他之前說過的事。請自然地順著他先前提到的內容接話、用陪在身邊的口吻提起，絕對不要說出「記憶」「資料庫」「系統」。如果不太確定他指的是哪一件，就溫和地問一句確認，不要硬編。",
    );
  }

  // 4) 知識型問題：需要查可信來源（維持既有 knowledge_response 流程）。
  if (searchIntent?.needsSearch || sourceReferences.length > 0) {
    return finish(
      "knowledge_response",
      "下一輪回應要用長者聽得懂的寵物口吻，根據可信來源簡短整理。健康內容只做一般生活衛教，不做診斷；每次最多提醒一個行動。",
    );
  }

  // 5) 明確問題直接回答（情緒平穩、低風險時）。
  if (
    hasDirectQuestion(text) &&
    !isEmotionalContent(emotion, companionNeed) &&
    !hasEventCue(text)
  ) {
    return finish(
      "answer_directly",
      "使用者問了一個明確的問題。先直接、簡短地回應這個問題本身，用長者聽得懂的口語，不要繞圈子、也不要先講一長串安慰。回答完可以視情況輕輕補一句關心，但最多問一個問題。",
    );
  }

  // 6) 語句不清楚：簡短確認，不硬猜。
  if (isAmbiguous(text)) {
    return finish(
      "clarify",
      "使用者剛剛說的話聽起來不太完整或不清楚。先用一句話把你聽到的部分覆述一下，溫和地請他再說一次或說清楚一點，不要硬猜他的意思，也不要假裝完全聽懂。",
    );
  }

  // 7) 情緒 / 事件內容：先接住具體內容，再輕度陪伴；不過度安慰、不一直說會陪你。
  if (
    isEmotionalContent(emotion, companionNeed) ||
    hasEventCue(text) ||
    isTiredContent(text, emotion)
  ) {
    if (isReminiscence(text, emotion, companionNeed)) {
      return finish(
        "comfort_lightly",
        "使用者正在回想以前的事。順著他的回憶接話，邀請他多分享一個當時的小片段，最多問一個問題，語氣溫暖自然，不要急著下結論。",
      );
    }
    if (hasEventCue(text)) {
      return finish(
        "comfort_lightly",
        "使用者提到一件剛發生的事。先針對這件事本身回應或追問一句（例如後來怎麼了、當下感覺如何），不要只給安慰或鼓勵。接住情緒一句就好，最多問一個問題，讓他繼續說。",
      );
    }
    if (isTiredContent(text, emotion)) {
      return finish(
        "comfort_lightly",
        "使用者說他覺得累。先別急著長篇鼓勵，用一句話接住，再簡短問一句是「身體累」還是「心裡累」，讓他自己多說一點。回覆要短、口語，不要說教、不要一次給很多建議。",
      );
    }
    if (isGroundingContent(emotion, companionNeed)) {
      return finish(
        "comfort_lightly",
        "使用者聽起來有點不安或睡不好。先用一句話接住他剛剛說的，放慢語氣陪他安定下來，可以提供一個很小的放鬆或呼吸步驟，最多問一個問題，不要說教。",
      );
    }
    return finish(
      "comfort_lightly",
      "先回應使用者剛剛說的具體內容，用一句話輕輕接住他的情緒，再溫柔問一個跟他剛剛說的事有關的問題。不要過度安慰、不要說教、不要每句都說會陪你，讓他多說一點。",
    );
  }

  // 8) 一般日常：順著內容自然接話，不要用陪伴 / 鼓勵罐頭話。
  return finish(
    "normal_chat",
    "先順著使用者剛剛說的具體內容自然回應，像朋友一樣接話，最多問一個問題。回覆簡短、口語，不要說教、不要每次都用陪伴或鼓勵的罐頭話，讓使用者多說一點。",
  );
}

module.exports = {
  NORMAL_VOICE_CADENCE,
  planNextStrategy,
  // 匯出意圖偵測供測試與其他模組重用（純函式、無副作用）。
  hasReminderIntent,
  hasMemoryRecallIntent,
  hasDirectQuestion,
  hasEventCue,
  isTiredContent,
  isAmbiguous,
};
