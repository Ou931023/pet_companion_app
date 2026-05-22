const { createEmbedding } = require("./embeddingService");
const { listMemories } = require("./memoryStore");
const {
  searchMemoriesByEmbedding,
  markMemoriesUsed,
} = require("./memoryStore");

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

const MIN_SIMILARITY = 0.40;
const MIN_FINAL_SCORE = 0.55;

function rankMemories(memories = [], provider = "none") {
  const ranked = memories
    .filter((memory) => memory && memory.isActive !== false)
    .map(scoreMemory)
    .filter((memory) => {
      if (memory.importance < 3) return false;
      if (memory.similarity == null && provider === "json_fallback") {
        return memory.finalScore >= MIN_FINAL_SCORE;
      }
      return memory.similarity >= MIN_SIMILARITY && memory.finalScore >= MIN_FINAL_SCORE;
    })
    .sort((a, b) => b.finalScore - a.finalScore)
    .slice(0, 3);
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
    const ranked = rankMemories(searchResult.memories, searchResult.provider);
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
    console.warn("[memory-context] build failed", error?.message || error);
    return emptyContext("memory context failed");
  }
}

function isSensitiveGreetingMemory(memory) {
  const text = `${memory.memorySummary || ""} ${memory.memoryText || ""}`;
  return /身分證|身份證|宗教|政黨|投票|診斷|確診/.test(text);
}

function greetingFromMemory(memory) {
  const text = memory.memorySummary || memory.memoryText || "";
  if (/睡不好|睡眠|沒精神|很累|疲倦/.test(text)) {
    return "最近睡眠比較辛苦的話，我今天也會陪你慢慢放鬆。";
  }
  if (/台灣地方故事|地方故事|真實故事|故事/.test(text)) {
    return "你之前喜歡台灣地方故事，等等我也可以說一個給你聽。";
  }
  if (/孤單|難過|低落|焦慮|擔心/.test(text)) {
    return "如果今天心裡有點悶，我會在旁邊陪你慢慢說。";
  }
  if (/喝水|吃藥|運動|提醒/.test(text)) {
    return "今天我也會溫柔陪你照顧自己，慢慢來就好。";
  }
  return `我還記得${compact(text, 28)}，今天也陪你慢慢聊。`;
}

async function buildMemoryGreeting({ userId = "default_user" } = {}) {
  try {
    const result = await listMemories(userId);
    const memories = result.memories
      .filter((memory) => memory.isActive !== false)
      .filter((memory) => Number(memory.importance || 0) >= 3)
      .filter((memory) => !isSensitiveGreetingMemory(memory))
      .sort((a, b) => {
        const importance = Number(b.importance || 0) - Number(a.importance || 0);
        if (importance !== 0) return importance;
        return String(b.createdAt).localeCompare(String(a.createdAt));
      });
    const memory = memories[0];
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
    console.warn("[memory-context] greeting failed", error?.message || error);
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
};
