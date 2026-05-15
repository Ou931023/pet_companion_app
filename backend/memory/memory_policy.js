const { createEmbedding } = require("./memory_embedding_service");
const { createLongTermMemory } = require("./memory_repository");

const TYPE_MAP = {
  preference: "preference",
  emotion_event: "emotion_event",
  routine: "routine",
  family: "family",
  health_note: "health_note",
  reminder_context: "reminder_context",
  personal_story: "personal_story",
  reminiscence: "personal_story",
  other: "other",
};

function normalizeMemoryType(type = "other") {
  return TYPE_MAP[type] || "other";
}

function importanceFor({ type, safety }) {
  if (safety?.riskLevel === "urgent") return 5;
  if (type === "health_note" || type === "reminder_context") return 4;
  if (type === "emotion_event" || type === "personal_story") return 4;
  return 3;
}

async function storeCompanionMemoryCandidate({
  userId = "default_user",
  sessionId = null,
  turnId = null,
  emotion = "unknown",
  memory,
  safety,
} = {}) {
  if (!memory?.shouldSave || !memory?.candidate?.trim()) {
    return { stored: false, reason: "memory_not_requested" };
  }

  const content = memory.candidate.trim();
  const memoryType = normalizeMemoryType(memory.type);
  const embeddingResult = await createEmbedding(content);
  const result = await createLongTermMemory({
    userId,
    memoryType,
    memoryText: content,
    memorySummary: content,
    emotionLabel: emotion,
    importance: importanceFor({ type: memoryType, safety }),
    confidence: 0.84,
    sourceTurnId: turnId,
    sourceSessionId: sessionId,
    embedding: embeddingResult.embedding,
  });

  return {
    stored: !result.duplicate,
    duplicate: Boolean(result.duplicate),
    memory: result.memory,
    provider: result.provider,
    reason: result.reason,
    embeddingProvider: embeddingResult.provider,
    embeddingError: embeddingResult.error,
  };
}

module.exports = {
  normalizeMemoryType,
  storeCompanionMemoryCandidate,
};
