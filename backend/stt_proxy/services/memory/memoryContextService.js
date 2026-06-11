const { createEmbedding } = require("./embeddingService");
const { listMemories } = require("./memoryStore");
const {
  searchMemoriesByEmbedding,
  markMemoriesUsed,
} = require("./memoryStore");
const { safeErrorMessage } = require("../privacy/redaction");

const CHATTER = new Set(["你好", "哈", "哈哈", "嗯", "嗯嗯", "好", "好的", "謝謝", "謝謝你"]);

function chineseCharCount(text) {
  return (text.match(/[\u4e00-\u9fff]/g) || []).length;
}

function emptyContext(reason, provider = "none") {
  return {
    memoryUsed: false,
    usedMemoryIds: [],
    memoryContext: "",
    memoryContextSummary: "",
    memories: [],
    provider,
    reason,
  };
}

function compact(text, maxLength) {
  const normalized = (text || "").toString().replace(/\s+/g, " ").trim();
  if (normalized.length <= maxLength) return normalized;
  return `${normalized.substring(0, maxLength - 1)}…`;
}

function recencyScore(createdAt) {
  const created = new Date(createdAt || 0);
  if (Number.isNaN(created.getTime())) return 0.2;
  const days = (Date.now() - created.getTime()) / 86400000;
  if (days <= 7) return 1.0;
  if (days <= 30) return 0.8;
  if (days <= 90) return 0.5;
  return 0.2;
}

function scoreMemory(memory) {
  const similarity =
    typeof memory.similarity === "number" ? memory.similarity : null;
  const importance = Number(memory.importance || 0);
  const importanceScore = importance / 5;
  const recent = recencyScore(memory.createdAt);
  const finalScore = similarity == null
    ? (importanceScore * 0.65) + (recent * 0.35)
    : (similarity * 0.60) + (importanceScore * 0.25) + (recent * 0.15);
  return {
    ...memory,
    similarity,
    importance,
    recencyScore: recent,
    finalScore,
  };
}

// CR-0073：檢索門檻改 env 可調（fallback 為放寬後的預設），讓 production 不需改 code /
// 重 build 就能微調記憶召回。數值不合法（NaN / <=0）一律回退預設。
function envNumber(name, fallback) {
  const value = Number(process.env[name]);
  return Number.isFinite(value) && value > 0 ? value : fallback;
}

const MIN_SIMILARITY = envNumber("MEMORY_MIN_SIMILARITY", 0.30); // 原 0.40
const MIN_FINAL_SCORE = envNumber("MEMORY_MIN_FINAL_SCORE", 0.42); // 原 0.55
const MIN_IMPORTANCE = envNumber("MEMORY_MIN_IMPORTANCE", 2); // 原硬編 3
const CONTEXT_TOPK = Math.max(1, Math.round(envNumber("MEMORY_CONTEXT_TOPK", 5))); // 原 3

function rankMemories(memories = [], provider = "none") {
  const ranked = memories
    .filter((memory) => memory && memory.isActive !== false)
    .map(scoreMemory)
    .filter((memory) => {
      if (memory.importance < MIN_IMPORTANCE) return false;
      if (memory.similarity == null && provider === "json_fallback") {
        return memory.finalScore >= MIN_FINAL_SCORE;
      }
      return memory.similarity >= MIN_SIMILARITY && memory.finalScore >= MIN_FINAL_SCORE;
    })
    .sort((a, b) => b.finalScore - a.finalScore)
    .slice(0, CONTEXT_TOPK);
  return ranked;
}

function buildPromptBlock(memories = []) {
  if (!memories.length) return { memoryContext: "", memoryContextSummary: "" };
  const lines = memories.map((memory, index) =>
    `${index + 1}. ${compact(memory.memorySummary || memory.memoryText || "", 80)}`.trim(),
  );
  const rawContext = `可參考的使用者長期記憶：
${lines.join("\n")}

使用規則：
- 這些記憶只作為陪伴脈絡。
- 可以自然延續相關話題，但不要硬提。
- 不要說「我查到你的記憶」或「資料庫顯示」。
- 健康相關內容不可做醫療診斷。
- 如果和目前問題無關，請忽略。`;
  const topic = compact(memories[0].memorySummary || memories[0].memoryText || "相關近況", 40);
  return {
    memoryContext: compact(rawContext, 500),
    memoryContextSummary: `使用了 ${memories.length} 筆長期記憶：${topic}`,
  };
}

async function buildMemoryContext({
  userText,
  userId = "default_user",
  limit = 5,
  queryEmbedding = null,
} = {}) {
  const normalized = (userText || "").toString().trim();
  if (!normalized || CHATTER.has(normalized) || chineseCharCount(normalized) < 4) {
    return emptyContext("userText too short or not meaningful");
  }

  try {
    let embedding = queryEmbedding;
    let embeddingProvider = "test";
    if (!embedding) {
      const embeddingResult = await createEmbedding(normalized);
      embedding = embeddingResult.embedding;
      embeddingProvider = embeddingResult.provider;
      if (!embedding) {
        return emptyContext(
          embeddingResult.error || "embedding unavailable",
          embeddingProvider,
        );
      }
    }

    const searchResult = await searchMemoriesByEmbedding(userId, embedding, limit);
    const candidates = searchResult.memories || [];
    const ranked = rankMemories(candidates, searchResult.provider);
    // CR-0073 去敏觀測：只記筆數 / 最高相似度（數字）/ provider / 門檻，不記任何記憶內容或 userId。
    const topSimilarity = candidates.reduce(
      (max, m) => (typeof m.similarity === "number" && m.similarity > max ? m.similarity : max),
      0,
    );
    console.log("[memory-context] retrieve", {
      provider: searchResult.provider,
      candidates: candidates.length,
      ranked: ranked.length,
      topSimilarity: Number(topSimilarity.toFixed(3)),
      minSimilarity: MIN_SIMILARITY,
      minFinalScore: MIN_FINAL_SCORE,
    });
    if (!ranked.length) {
      return emptyContext("no_relevant_memory", "none");
    }

    const usedMemoryIds = ranked.map((memory) => memory.id);
    await markMemoriesUsed(usedMemoryIds);
    const { memoryContext, memoryContextSummary } = buildPromptBlock(ranked);
    return {
      memoryUsed: true,
      usedMemoryIds,
      memoryContext,
      memoryContextSummary,
      memories: ranked,
      provider: searchResult.provider,
      embeddingProvider,
    };
  } catch (error) {
    // CR-0073：失敗仍回 emptyContext（不影響回覆），但 log 帶去敏 reason 供 production 診斷。
    console.warn("[memory-context] build failed", { reason: safeErrorMessage(error) });
    return emptyContext("memory context failed");
  }
}

function isSensitiveGreetingMemory(memory) {
  const text = `${memory.memorySummary || ""} ${memory.memoryText || ""}`;
  return /身分證|身份證|宗教|政黨|投票|診斷|確診/.test(text);
}

// 只有語助詞 / 沒有陪伴價值的片段，不可拿來當首頁開場。
const GREETING_FILLER = new Set([
  "好", "好的", "嗯", "嗯嗯", "對", "對啊", "是", "是的", "沒有", "不知道",
  "我不知道", "不曉得", "可以", "都可以", "隨便", "沒事", "那個", "所有的",
  "還好", "算了", "不用", "沒關係", "也沒有",
]);

// 像分類標籤 / 內部欄位的內容（理論上不該進到使用者內容，保險過濾）。
const GREETING_METADATA_PATTERN =
  /可能需要(陪伴感|情緒支持|懷舊陪伴|安定陪伴|照護|陪伴)|情緒支持|risk_?level|emotion|category|summary|metadata|payload|toolName|pgvector/i;

function stripGreetingPunct(text) {
  return (text || "")
    .toString()
    .replace(/[「」『』“”"'，。、！？!?,.\s…：:；;~～()（）]/g, "")
    .trim();
}

// 從記憶取出「可以自然對使用者說的內容」：去掉「使用者提到/偏好/近期…：」「『…』」
// 這類後端摘要包裝，只留下使用者實際說的事，避免把摘要原文或分類標籤講出來。
function extractMemoryContent(memory) {
  const text = (memory.memoryText || memory.memorySummary || "").toString().trim();
  const quoted = text.match(/「([^」]+)」/);
  if (quoted && quoted[1].trim()) return quoted[1].trim();
  const colon = text.match(/[:：]\s*([\s\S]+)$/);
  if (colon && colon[1].trim()) {
    return colon[1].replace(/[，。、！？!?,.]+$/, "").trim();
  }
  return text
    .replace(/^使用者(提到|說|表示|的)?[:：，、]?\s*/, "")
    .replace(/[，。、！？!?,.]+$/, "")
    .trim();
}

// 低品質記憶不可進入首頁開場：太短 / 純語助詞 / 像標籤或內部欄位 / 信心過低。
function isLowQualityGreetingMemory(memory) {
  if (!memory) return true;
  const content = extractMemoryContent(memory);
  const bare = stripGreetingPunct(content);
  if (!bare) return true;
  if (GREETING_FILLER.has(bare)) return true;
  if (chineseCharCount(bare) < 4) return true;
  if (GREETING_METADATA_PATTERN.test(content)) return true;
  if (memory.confidence != null && Number(memory.confidence) < 0.55) return true;
  return false;
}

// 溫和開場（情緒類記憶用）：影響語氣但不回放內容、不貼標籤。
const GENTLE_GREETINGS = [
  "今天也想陪你慢慢聊聊。你現在心情還好嗎？",
  "我在這裡陪你，今天想先聊聊什麼？",
  "今天想輕鬆聊聊，還是先休息一下？",
];

function pickGentleGreeting(seed) {
  const idx = Math.abs(Number(seed) || 0) % GENTLE_GREETINGS.length;
  return GENTLE_GREETINGS[idx];
}

const EMOTIONAL_GREETING_TYPES = new Set([
  "emotion", "emotion_event", "reminiscence", "health_lifestyle",
]);
const EMOTIONAL_GREETING_PATTERN =
  /孤單|寂寞|難過|想哭|低落|焦慮|擔心|害怕|睡不?好|睡不著|沒精神|很累|疲倦|不想活|活著好累|頭暈|想念|懷念/;
const REMINDER_GREETING_TYPES = new Set(["care_need", "reminder"]);
const PREFERENCE_GREETING_TYPES = new Set(["preference", "story_preference"]);

// 把高品質記憶轉成自然的寵物語氣開場（不出現「使用者提到 / 情緒支持」等工程感語句）。
function greetingFromMemory(memory) {
  const content = extractMemoryContent(memory);
  const type = (memory.memoryType || "").toString();

  // 情緒 / 健康狀態類：只用溫和開場，不回放內容、不貼標籤。
  if (EMOTIONAL_GREETING_TYPES.has(type) || EMOTIONAL_GREETING_PATTERN.test(content)) {
    return pickGentleGreeting(content.length + chineseCharCount(content));
  }
  // 照護提醒：不假裝已經設好提醒，改成詢問是否要提醒。
  if (REMINDER_GREETING_TYPES.has(type) || /吃藥|喝水|回診|醫院|運動|提醒/.test(content)) {
    return `你之前提過${compact(content, 24)}，今天需要我晚點提醒你嗎？`;
  }
  // 喜好。
  if (PREFERENCE_GREETING_TYPES.has(type) || /喜歡|不喜歡/.test(content)) {
    return `你之前說${compact(content, 24)}，今天想聊聊這個嗎？`;
  }
  // 生活習慣 / 近期狀況。
  if (type === "routine" || /每天|常常|最近|晚上|早上/.test(content)) {
    return `你之前說${compact(content, 24)}，今天也慢慢來，想聊聊嗎？`;
  }
  // 其他高品質（家人 / 近期事件等）。
  return `你之前說${compact(content, 24)}，今天也想陪你慢慢聊聊。`;
}

const GREETING_TYPE_RANK = {
  preference: 5,
  story_preference: 5,
  care_need: 4,
  reminder: 4,
  routine: 4,
  reminiscence: 3,
  health_lifestyle: 2,
  emotion: 1,
  emotion_event: 1,
};

function greetingTypeRank(memory) {
  const rank = GREETING_TYPE_RANK[(memory.memoryType || "").toString()];
  return rank == null ? 3 : rank;
}

// 從候選記憶挑出最適合開場的一筆（過濾低品質 / 封存 / 敏感；偏好具體正向類型）。
// 純函式、不碰 store，方便測試；找不到合格記憶回 null（呼叫端走一般 fallback 問候）。
function pickGreetingMemory(memories = []) {
  const eligible = (memories || [])
    .filter((memory) => memory && memory.isActive !== false)
    .filter((memory) => Number(memory.importance || 0) >= 3)
    .filter((memory) => !isSensitiveGreetingMemory(memory))
    .filter((memory) => !isLowQualityGreetingMemory(memory));
  if (!eligible.length) return null;
  eligible.sort((a, b) => {
    const rank = greetingTypeRank(b) - greetingTypeRank(a);
    if (rank !== 0) return rank;
    const importance = Number(b.importance || 0) - Number(a.importance || 0);
    if (importance !== 0) return importance;
    return String(b.createdAt || "").localeCompare(String(a.createdAt || ""));
  });
  return eligible[0];
}

async function buildMemoryGreeting({ userId = "default_user" } = {}) {
  try {
    const result = await listMemories(userId);
    const memory = pickGreetingMemory(result.memories);
    if (!memory) {
      return {
        greeting: "",
        memoryUsed: false,
        memoryId: null,
        provider: "none",
        reason: "no_relevant_memory",
      };
    }
    await markMemoriesUsed([memory.id]);
    return {
      greeting: greetingFromMemory(memory),
      memoryUsed: true,
      memoryId: memory.id,
      provider: result.provider,
    };
  } catch (error) {
    console.warn("[memory-context] greeting failed", safeErrorMessage(error));
    return {
      greeting: "",
      memoryUsed: false,
      memoryId: null,
      provider: "none",
      reason: "memory_greeting_failed",
    };
  }
}

module.exports = {
  buildMemoryContext,
  rankMemories,
  recencyScore,
  buildPromptBlock,
  buildMemoryGreeting,
  extractMemoryContent,
  isLowQualityGreetingMemory,
  greetingFromMemory,
  pickGreetingMemory,
};
