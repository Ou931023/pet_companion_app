const pool = require('../db/pool');

function toVectorLiteral(values) {
  if (!Array.isArray(values) || values.length === 0) {
    throw new Error('Invalid embedding array');
  }
  return `[${values.map((value) => Number(value).toFixed(8)).join(',')}]`;
}

async function insertMemory(memory) {
  const vector = toVectorLiteral(memory.embedding);
  const result = await pool.query(
    `
    INSERT INTO memory_items (
      user_id,
      session_id,
      source_turn_id,
      memory_type,
      summary,
      original_user_text,
      ai_reply,
      emotion,
      importance,
      tags,
      embedding
    ) VALUES (
      $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11::vector
    )
    RETURNING id, memory_type, summary, importance, tags, created_at
    `,
    [
      memory.userId,
      memory.sessionId || null,
      memory.sourceTurnId || null,
      memory.memoryType,
      memory.summary,
      memory.originalUserText || null,
      memory.aiReply || null,
      memory.emotion || null,
      memory.importance ?? 0.5,
      memory.tags || [],
      vector,
    ],
  );
  return result.rows[0];
}

async function searchMemories({ userId, queryEmbedding, topK }) {
  const vector = toVectorLiteral(queryEmbedding);
  const result = await pool.query(
    `
    SELECT
      id,
      user_id,
      session_id,
      memory_type,
      summary,
      emotion,
      importance,
      tags,
      created_at,
      last_used_at,
      1 - (embedding <=> $1::vector) AS similarity
    FROM memory_items
    WHERE user_id = $2
      AND deleted_at IS NULL
    ORDER BY
      (embedding <=> $1::vector) ASC,
      importance DESC,
      created_at DESC
    LIMIT $3
    `,
    [vector, userId, topK],
  );
  return result.rows;
}

async function markMemoriesUsed(ids) {
  if (!Array.isArray(ids) || ids.length === 0) return;
  await pool.query(
    `
    UPDATE memory_items
    SET last_used_at = NOW()
    WHERE id = ANY($1::uuid[])
    `,
    [ids],
  );
}

async function softDeleteRecentMemory(userId) {
  const result = await pool.query(
    `
    WITH latest AS (
      SELECT id
      FROM memory_items
      WHERE user_id = $1
        AND deleted_at IS NULL
      ORDER BY created_at DESC
      LIMIT 1
    )
    UPDATE memory_items
    SET deleted_at = NOW()
    WHERE id IN (SELECT id FROM latest)
    RETURNING id
    `,
    [userId],
  );
  return result.rowCount > 0;
}

async function softDeleteMemoryById(id) {
  const result = await pool.query(
    `
    UPDATE memory_items
    SET deleted_at = NOW()
    WHERE id = $1::uuid
      AND deleted_at IS NULL
    `,
    [id],
  );
  return result.rowCount > 0;
}

module.exports = {
  insertMemory,
  searchMemories,
  markMemoriesUsed,
  softDeleteRecentMemory,
  softDeleteMemoryById,
  toVectorLiteral,
};
