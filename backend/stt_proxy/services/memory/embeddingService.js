const OpenAI = require("openai");

let client;

function getClient() {
  if (!process.env.OPENAI_API_KEY) return null;
  if (!client) {
    client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
  }
  return client;
}

async function createEmbedding(text) {
  const input = (text || "").toString().trim();
  const model = process.env.EMBEDDING_MODEL || "text-embedding-3-small";

  if (!input) {
    return {
      embedding: null,
      provider: "none",
      model,
      error: "text is required",
    };
  }

  const openai = getClient();
  if (!openai) {
    return {
      embedding: null,
      provider: "none",
      model,
      error: "OPENAI_API_KEY missing",
    };
  }

  try {
    const response = await openai.embeddings.create({
      model,
      input,
    });
    const embedding = response.data?.[0]?.embedding || null;
    if (!Array.isArray(embedding) || embedding.length !== 1536) {
      return {
        embedding: null,
        provider: "none",
        model,
        error: `Unexpected embedding dimension: ${Array.isArray(embedding) ? embedding.length : "none"}`,
      };
    }
    return {
      embedding,
      model,
      provider: "openai",
    };
  } catch (error) {
    console.warn("[memory-embedding] embedding failed", error?.message || error);
    return {
      embedding: null,
      provider: "none",
      model,
      error: error?.message || "embedding failed",
    };
  }
}

module.exports = {
  createEmbedding,
};
