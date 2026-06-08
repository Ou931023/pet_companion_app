const OpenAI = require("openai");
const { safeErrorMessage } = require("../privacy/redaction");

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
      embedding: mockEmbedding(input),
      provider: "mock",
      model,
      error: "OPENAI_API_KEY missing; using deterministic mock embedding",
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
    console.warn("[memory-embedding] embedding failed", safeErrorMessage(error));
    return {
      embedding: mockEmbedding(input),
      provider: "mock",
      model,
      error: error?.message || "embedding failed; using deterministic mock embedding",
    };
  }
}

function mockEmbedding(text) {
  const input = (text || "").toString();
  const vector = new Array(1536).fill(0);
  for (let i = 0; i < input.length; i += 1) {
    const code = input.charCodeAt(i);
    const index = (code * 31 + i * 17) % vector.length;
    vector[index] += ((code % 97) + 1) / 100;
  }
  let norm = Math.sqrt(vector.reduce((sum, value) => sum + value * value, 0));
  if (!norm) norm = 1;
  return vector.map((value) => Number((value / norm).toFixed(8)));
}

module.exports = {
  createEmbedding,
  mockEmbedding,
};
