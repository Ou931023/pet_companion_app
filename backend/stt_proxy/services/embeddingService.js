const OpenAI = require('openai');
const { safeErrorMessage } = require('./privacy/redaction');

const client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

async function createEmbedding(text, opts = {}) {
  const input = (text || '').toString().trim();
  if (!input) return [];
  const model = opts.model || process.env.EMBEDDING_MODEL || 'text-embedding-3-small';
  try {
    const resp = await client.embeddings.create({ model, input });
    const embedding = resp?.data?.[0]?.embedding || [];
    if (process.env.NODE_ENV !== 'production') {
      console.log('[embeddingService] created embedding length=', embedding.length);
    }
    return Array.isArray(embedding) ? embedding.map((n) => Number(n)) : [];
  } catch (err) {
    console.error('[embeddingService] embedding creation failed', safeErrorMessage(err));
    return [];
  }
}

module.exports = { createEmbedding };
