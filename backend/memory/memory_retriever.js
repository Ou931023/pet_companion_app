const { createEmbedding } = require("./memory_embedding_service");
const { retrieveByEmbedding } = require("./memory_repository");

async function retrieveRelevantMemories({
  userId = "default_user",
  transcript = "",
  topK = 5,
} = {}) {
  const query = transcript.toString().trim();
  if (!query) {
    return {
      memories: [],
      provider: "none",
      embeddingProvider: "none",
      reason: "empty_query",
    };
  }

  const embeddingResult = await createEmbedding(query);
  if (!embeddingResult.embedding) {
    return {
      memories: [],
      provider: "none",
      embeddingProvider: embeddingResult.provider,
      reason: embeddingResult.error || "embedding_unavailable",
    };
  }

  const result = await retrieveByEmbedding(userId, embeddingResult.embedding, topK);
  return {
    ...result,
    embeddingProvider: embeddingResult.provider,
    embeddingModel: embeddingResult.model,
  };
}

module.exports = {
  retrieveRelevantMemories,
};
