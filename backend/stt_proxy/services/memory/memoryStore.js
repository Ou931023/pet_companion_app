const fs = require("fs/promises");
const path = require("path");

const postgres = require("../../db/postgres");
const { safeErrorMessage } = require("../privacy/redaction");

const PROVIDER_POSTGRES = "postgres_pgvector";
const PROVIDER_JSON = "json_fallback";

const MEMORY_TYPES = new Set([
  "preference",
  "emotion_event",
  "routine",
  "family",
  "health_note",
  "reminder_context",
  "personal_story",
  "emotion",
  "reminder",
  "care_need",
  "story_preference",
  "health_lifestyle",
  "reminiscence",
  "other",
]);

const EMOTION_LABELS = new Set([
  "happy",
  "neutral",
  "sad",
  "lonely",
  "anxious",
  "tired",
  "angry",
  "unknown",
]);

const EVENT_TYPES = new Set([
  "created",
  "retrieved",
  "used_in_prompt",
  "updated",
  "archived",
  "deduplicated",
  "error",
]);

class MemoryValidationError extends Error {
  constructor(message, field) {
    super(message);
    this.name = "MemoryValidationError";
    this.field = field;
    this.statusCode = 400;
  }
}

function dataDir() {
  return process.env.MEMORY_DATA_DIR || path.join(__dirname, "../../data");
}

function memoriesPath() {
  return path.join(dataDir(), "companion_memories.json");
}

function eventsPath() {
  return path.join(dataDir(), "memory_events.json");
}

async function readJson(filePath, fallback) {
  try {
    return JSON.parse(await fs.readFile(filePath, "utf8"));
  } catch (_) {
    return fallback;
  }
}

async function writeJson(filePath, data) {
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  await fs.writeFile(filePath, `${JSON.stringify(data, null, 2)}\n`);
}

function normalizeUserId(userId) {
  return (userId || "default_user").toString().trim() || "default_user";
}

function normalizeLimit(limit) {
  const parsed = Number(limit || 5);
  if (!Number.isFinite(parsed) || parsed <= 0) return 5;
  return Math.min(Math.trunc(parsed), 20);
}

function toVectorLiteral(values) {
  if (!Array.isArray(values) || values.length === 0) {
    throw new MemoryValidationError("embedding must be a non-empty numeric array", "embedding");
  }
  const normalized = values.map((value) => {
    const number = Number(value);
    if (!Number.isFinite(number)) {
      throw new MemoryValidationError("embedding must contain only finite numbers", "embedding");
    }
    return Number.isInteger(number) ? number.toString() : number.toPrecision(12);
  });
  return `[${normalized.join(",")}]`;
}

function normalizeEmbedding(embedding) {
  if (embedding == null) return null;
  if (!Array.isArray(embedding) || embedding.length === 0) {
    throw new MemoryValidationError("embedding must be a non-empty numeric array", "embedding");
  }
  return embedding.map((value) => {
    const number = Number(value);
    if (!Number.isFinite(number)) {
      throw new MemoryValidationError("embedding must contain only finite numbers", "embedding");
    }
    return number;
  });
}

function normalizeMemoryInput(memory) {
  const memoryType = (memory.memoryType || memory.memory_type || "").toString().trim();
  const memoryText = (memory.memoryText || memory.memory_text || "").toString().trim();
  const memorySummary = (memory.memorySummary || memory.memory_summary || "").toString().trim();
  const emotionLabelRaw = memory.emotionLabel ?? memory.emotion_label ?? null;
  const emotionLabel = emotionLabelRaw == null || emotionLabelRaw === ""
    ? null
    : emotionLabelRaw.toString().trim();
  const importance = memory.importance == null ? 3 : Number(memory.importance);
  const confidence = memory.confidence == null ? 0.8 : Number(memory.confidence);

  if (!MEMORY_TYPES.has(memoryType)) {
    throw new MemoryValidationError("invalid memoryType", "memoryType");
  }
  if (!memoryText) {
    throw new MemoryValidationError("memoryText is required", "memoryText");
  }
  if (!memorySummary) {
    throw new MemoryValidationError("memorySummary is required", "memorySummary");
  }
  if (emotionLabel != null && !EMOTION_LABELS.has(emotionLabel)) {
    throw new MemoryValidationError("invalid emotionLabel", "emotionLabel");
  }
  if (!Number.isInteger(importance) || importance < 1 || importance > 5) {
    throw new MemoryValidationError("importance must be an integer between 1 and 5", "importance");
  }
  if (!Number.isFinite(confidence) || confidence < 0 || confidence > 1) {
    throw new MemoryValidationError("confidence must be between 0 and 1", "confidence");
  }

  return {
    userId: normalizeUserId(memory.userId || memory.user_id),
    memoryType,
    memoryText,
    memorySummary,
    emotionLabel,
    importance,
    confidence,
    sourceTurnId: memory.sourceTurnId || memory.source_turn_id || null,
    sourceSessionId: memory.sourceSessionId || memory.source_session_id || null,
    embedding: normalizeEmbedding(memory.embedding),
  };
}

function rowToMemory(row, provider, extra = {}) {
  if (!row) return null;
  return {
    id: row.id,
    userId: row.user_id ?? row.userId,
    memoryType: row.memory_type ?? row.memoryType,
    type: row.memory_type ?? row.memoryType,
    memoryText: row.memory_text ?? row.memoryText,
    memorySummary: row.memory_summary ?? row.memorySummary,
    content: row.memory_summary ?? row.memorySummary ?? row.memory_text ?? row.memoryText,
    emotionLabel: row.emotion_label ?? row.emotionLabel ?? null,
    importance: Number(row.importance ?? 3),
    confidence: Number(row.confidence ?? 0.8),
    sourceTurnId: row.source_turn_id ?? row.sourceTurnId ?? null,
    sourceSessionId: row.source_session_id ?? row.sourceSessionId ?? null,
    createdAt: row.created_at ?? row.createdAt,
    updatedAt: row.updated_at ?? row.updatedAt,
    lastUsedAt: row.last_used_at ?? row.lastUsedAt ?? null,
    useCount: Number(row.use_count ?? row.useCount ?? 0),
    isActive: row.is_active ?? row.isActive ?? true,
    archived: !(row.is_active ?? row.isActive ?? true),
    provider,
    ...extra,
  };
}

async function getJsonMemories() {
  return readJson(memoriesPath(), []);
}

async function saveJsonMemories(memories) {
  await writeJson(memoriesPath(), memories);
}

async function getJsonEvents() {
  return readJson(eventsPath(), []);
}

async function saveJsonEvents(events) {
  await writeJson(eventsPath(), events);
}

async function createMemoryPostgres(memory) {
  const duplicateCheck = await findDuplicateMemory(memory.userId, memory.memorySummary, memory.embedding);
  if (duplicateCheck.memory) {
    await recordMemoryEvent(duplicateCheck.memory.id, "deduplicated", duplicateCheck.reason);
    return {
      memory: duplicateCheck.memory,
      provider: PROVIDER_POSTGRES,
      duplicate: true,
      reason: duplicateCheck.reason,
    };
  }

  const vector = memory.embedding ? toVectorLiteral(memory.embedding) : null;
  const result = await postgres.query(
    `
    INSERT INTO companion_memories (
      user_id,
      memory_type,
      memory_text,
      memory_summary,
      emotion_label,
      importance,
      confidence,
      source_turn_id,
      source_session_id,
      embedding
    ) VALUES (
      $1,$2,$3,$4,$5,$6,$7,$8,$9,$10::vector
    )
    ON CONFLICT (user_id, source_turn_id)
    WHERE source_turn_id IS NOT NULL
    DO NOTHING
    RETURNING *
    `,
    [
      memory.userId,
      memory.memoryType,
      memory.memoryText,
      memory.memorySummary,
      memory.emotionLabel,
      memory.importance,
      memory.confidence,
      memory.sourceTurnId,
      memory.sourceSessionId,
      vector,
    ],
  );

  if (result.rows[0]) {
    const created = rowToMemory(result.rows[0], PROVIDER_POSTGRES);
    await recordMemoryEvent(created.id, "created", "memory created");
    return { memory: created, provider: PROVIDER_POSTGRES, duplicate: false };
  }

  const existing = await postgres.query(
    `
    SELECT *
    FROM companion_memories
    WHERE user_id = $1
      AND source_turn_id = $2
    LIMIT 1
    `,
    [memory.userId, memory.sourceTurnId],
  );
  const duplicate = rowToMemory(existing.rows[0], PROVIDER_POSTGRES);
  // CR-0073 防呆：INSERT 因 ON CONFLICT DO NOTHING 沒回列、但再查也查不到（race /
  // 非預期）時 duplicate 可能為 null。先判空，避免 `duplicate.id` TypeError 讓整條寫入崩潰。
  if (!duplicate) {
    return {
      memory: null,
      provider: PROVIDER_POSTGRES,
      duplicate: false,
      reason: "insert_conflict_no_row",
    };
  }
  await recordMemoryEvent(duplicate.id, "deduplicated", "duplicate sourceTurnId ignored");
  return { memory: duplicate, provider: PROVIDER_POSTGRES, duplicate: true };
}

async function createMemoryJson(memory) {
  const memories = await getJsonMemories();
  if (memory.sourceTurnId) {
    const existing = memories.find(
      (item) =>
        item.userId === memory.userId &&
        item.sourceTurnId === memory.sourceTurnId,
    );
    if (existing) {
      await recordMemoryEvent(existing.id, "deduplicated", "duplicate sourceTurnId ignored");
      return {
        memory: rowToMemory(existing, PROVIDER_JSON),
        provider: PROVIDER_JSON,
        duplicate: true,
      };
    }
  }
  const sameSummary = memories.find(
    (item) =>
      item.userId === memory.userId &&
      item.isActive !== false &&
      item.memorySummary === memory.memorySummary,
  );
  if (sameSummary) {
    await recordMemoryEvent(sameSummary.id, "deduplicated", "duplicate memorySummary ignored");
    return {
      memory: rowToMemory(sameSummary, PROVIDER_JSON),
      provider: PROVIDER_JSON,
      duplicate: true,
      reason: "duplicate memorySummary ignored",
    };
  }

  const now = new Date().toISOString();
  const maxId = memories.reduce((max, item) => Math.max(max, Number(item.id) || 0), 0);
  const item = {
    id: maxId + 1,
    userId: memory.userId,
    memoryType: memory.memoryType,
    memoryText: memory.memoryText,
    memorySummary: memory.memorySummary,
    emotionLabel: memory.emotionLabel,
    importance: memory.importance,
    confidence: memory.confidence,
    sourceTurnId: memory.sourceTurnId,
    sourceSessionId: memory.sourceSessionId,
    embedding: memory.embedding,
    createdAt: now,
    updatedAt: now,
    lastUsedAt: null,
    useCount: 0,
    isActive: true,
  };
  memories.push(item);
  await saveJsonMemories(memories);
  await recordMemoryEvent(item.id, "created", "memory created");
  return { memory: rowToMemory(item, PROVIDER_JSON), provider: PROVIDER_JSON, duplicate: false };
}

async function createMemory(memory) {
  const normalized = normalizeMemoryInput(memory || {});
  if (await postgres.isPostgresAvailable()) {
    try {
      return await createMemoryPostgres(normalized);
    } catch (error) {
      console.error("[memory-store] postgres create failed, falling back to json", safeErrorMessage(error));
    }
  }
  return createMemoryJson(normalized);
}

async function listMemories(userId = "default_user") {
  const normalizedUserId = normalizeUserId(userId);
  if (await postgres.isPostgresAvailable()) {
    try {
      const result = await postgres.query(
        `
        SELECT *
        FROM companion_memories
        WHERE user_id = $1
          AND is_active = TRUE
        ORDER BY created_at DESC
        `,
        [normalizedUserId],
      );
      return {
        memories: result.rows.map((row) => rowToMemory(row, PROVIDER_POSTGRES)),
        provider: PROVIDER_POSTGRES,
      };
    } catch (error) {
      console.error("[memory-store] postgres list failed, falling back to json", safeErrorMessage(error));
    }
  }

  const memories = await getJsonMemories();
  return {
    memories: memories
      .filter((item) => item.userId === normalizedUserId && item.isActive !== false)
      .sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)))
      .map((item) => rowToMemory(item, PROVIDER_JSON)),
    provider: PROVIDER_JSON,
  };
}

async function findDuplicateMemory(userId = "default_user", memorySummary, embedding = null) {
  const normalizedUserId = normalizeUserId(userId);
  const summary = (memorySummary || "").toString().trim();

  if (await postgres.isPostgresAvailable()) {
    try {
      if (summary) {
        const exact = await postgres.query(
          `
          SELECT *
          FROM companion_memories
          WHERE user_id = $1
            AND is_active = TRUE
            AND memory_summary = $2
          LIMIT 1
          `,
          [normalizedUserId, summary],
        );
        if (exact.rows[0]) {
          return {
            memory: rowToMemory(exact.rows[0], PROVIDER_POSTGRES),
            provider: PROVIDER_POSTGRES,
            reason: "duplicate memorySummary ignored",
          };
        }
      }
      if (embedding) {
        const vector = toVectorLiteral(embedding);
        const similar = await postgres.query(
          `
          SELECT *,
            1 - (embedding <=> $1::vector) AS similarity
          FROM companion_memories
          WHERE user_id = $2
            AND is_active = TRUE
            AND embedding IS NOT NULL
          ORDER BY embedding <=> $1::vector
          LIMIT 1
          `,
          [vector, normalizedUserId],
        );
        const row = similar.rows[0];
        const similarity = Number(row?.similarity || 0);
        if (row && similarity > 0.92) {
          return {
            memory: rowToMemory(row, PROVIDER_POSTGRES, { similarity }),
            provider: PROVIDER_POSTGRES,
            reason: `similar memory ignored (${similarity.toFixed(3)})`,
          };
        }
      }
      return { memory: null, provider: PROVIDER_POSTGRES };
    } catch (error) {
      console.error("[memory-store] postgres dedup failed, falling back to json", safeErrorMessage(error));
    }
  }

  const memories = await getJsonMemories();
  const sameSummary = memories.find(
    (item) =>
      item.userId === normalizedUserId &&
      item.isActive !== false &&
      item.memorySummary === summary,
  );
  if (sameSummary) {
    return {
      memory: rowToMemory(sameSummary, PROVIDER_JSON),
      provider: PROVIDER_JSON,
      reason: "duplicate memorySummary ignored",
    };
  }
  return { memory: null, provider: PROVIDER_JSON };
}

function cosineSimilarity(a, b) {
  const length = Math.min(a.length, b.length);
  let dot = 0;
  let normA = 0;
  let normB = 0;
  for (let i = 0; i < length; i += 1) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  if (!normA || !normB) return 0;
  return dot / (Math.sqrt(normA) * Math.sqrt(normB));
}

async function searchMemoriesByEmbedding(userId = "default_user", embedding, limit = 5) {
  const normalizedUserId = normalizeUserId(userId);
  const normalizedEmbedding = normalizeEmbedding(embedding);
  const normalizedLimit = normalizeLimit(limit);

  if (await postgres.isPostgresAvailable()) {
    try {
      const vector = toVectorLiteral(normalizedEmbedding);
      const result = await postgres.query(
        `
        SELECT
          id,
          user_id,
          memory_type,
          memory_text,
          memory_summary,
          emotion_label,
          importance,
          confidence,
          source_turn_id,
          source_session_id,
          created_at,
          updated_at,
          last_used_at,
          use_count,
          is_active,
          1 - (embedding <=> $1::vector) AS similarity
        FROM companion_memories
        WHERE user_id = $2
          AND is_active = TRUE
          AND embedding IS NOT NULL
        ORDER BY embedding <=> $1::vector
        LIMIT $3
        `,
        [vector, normalizedUserId, normalizedLimit],
      );
      return {
        memories: result.rows.map((row) =>
          rowToMemory(row, PROVIDER_POSTGRES, {
            similarity: Number(row.similarity || 0),
          }),
        ),
        provider: PROVIDER_POSTGRES,
      };
    } catch (error) {
      console.error("[memory-store] postgres vector search failed, falling back to json", safeErrorMessage(error));
    }
  }

  const memories = await getJsonMemories();
  const active = memories
    .filter((item) => item.userId === normalizedUserId && item.isActive !== false);
  const withEmbedding = active.filter((item) => Array.isArray(item.embedding) && item.embedding.length);
  const source = withEmbedding.length ? withEmbedding : active;
  const ranked = source
    .map((item) => ({
      item,
      similarity: Array.isArray(item.embedding)
        ? cosineSimilarity(normalizedEmbedding, item.embedding)
        : null,
    }))
    .sort((a, b) => {
      if (a.similarity != null || b.similarity != null) {
        return Number(b.similarity || 0) - Number(a.similarity || 0);
      }
      return String(b.item.createdAt).localeCompare(String(a.item.createdAt));
    })
    .slice(0, normalizedLimit)
    .map(({ item, similarity }) =>
      rowToMemory(item, PROVIDER_JSON, {
        similarity: similarity == null ? undefined : similarity,
      }),
    );

  return { memories: ranked, provider: PROVIDER_JSON };
}

async function archiveMemory(memoryId, userId = "default_user") {
  const normalizedUserId = normalizeUserId(userId);
  if (await postgres.isPostgresAvailable()) {
    try {
      const result = await postgres.query(
        `
        UPDATE companion_memories
        SET is_active = FALSE
        WHERE id = $1
          AND user_id = $2
          AND is_active = TRUE
        RETURNING id
        `,
        [memoryId, normalizedUserId],
      );
      if (result.rowCount > 0) {
        await recordMemoryEvent(memoryId, "archived", "memory archived");
      }
      return {
        success: result.rowCount > 0,
        provider: PROVIDER_POSTGRES,
      };
    } catch (error) {
      console.error("[memory-store] postgres archive failed, falling back to json", safeErrorMessage(error));
    }
  }

  const memories = await getJsonMemories();
  const index = memories.findIndex(
    (item) => String(item.id) === String(memoryId) && item.userId === normalizedUserId,
  );
  if (index === -1 || memories[index].isActive === false) {
    return { success: false, provider: PROVIDER_JSON };
  }
  memories[index] = {
    ...memories[index],
    isActive: false,
    updatedAt: new Date().toISOString(),
  };
  await saveJsonMemories(memories);
  await recordMemoryEvent(memoryId, "archived", "memory archived");
  return { success: true, provider: PROVIDER_JSON };
}

async function markMemoriesUsed(memoryIds = []) {
  const ids = Array.isArray(memoryIds)
    ? memoryIds.filter((id) => id != null).map((id) => id.toString())
    : [];
  if (!ids.length) return { success: true, provider: PROVIDER_JSON, updated: 0 };

  if (await postgres.isPostgresAvailable()) {
    try {
      const result = await postgres.query(
        `
        UPDATE companion_memories
        SET last_used_at = NOW(),
            use_count = use_count + 1
        WHERE id = ANY($1::bigint[])
          AND is_active = TRUE
        RETURNING id
        `,
        [ids],
      );
      for (const row of result.rows) {
        await recordMemoryEvent(row.id, "used_in_prompt", "memory used in prompt context");
      }
      return {
        success: true,
        provider: PROVIDER_POSTGRES,
        updated: result.rowCount,
      };
    } catch (error) {
      console.error("[memory-store] postgres mark used failed, falling back to json", safeErrorMessage(error));
    }
  }

  const memories = await getJsonMemories();
  const idSet = new Set(ids);
  let updated = 0;
  const now = new Date().toISOString();
  const next = memories.map((item) => {
    if (!idSet.has(String(item.id)) || item.isActive === false) return item;
    updated += 1;
    return {
      ...item,
      lastUsedAt: now,
      useCount: Number(item.useCount || 0) + 1,
      updatedAt: now,
    };
  });
  await saveJsonMemories(next);
  for (const id of ids) {
    await recordMemoryEvent(id, "used_in_prompt", "memory used in prompt context");
  }
  return { success: true, provider: PROVIDER_JSON, updated };
}

async function recordMemoryEvent(memoryId, eventType, detail = null) {
  if (!EVENT_TYPES.has(eventType)) return { success: false };
  try {
    if (await postgres.isPostgresAvailable()) {
      try {
        await postgres.query(
          `
          INSERT INTO memory_events (memory_id, event_type, detail)
          VALUES ($1,$2,$3)
          `,
          [memoryId, eventType, detail],
        );
        return { success: true, provider: PROVIDER_POSTGRES };
      } catch (error) {
        console.error("[memory-store] postgres event failed, falling back to json", safeErrorMessage(error));
      }
    }

    const events = await getJsonEvents();
    const maxId = events.reduce((max, item) => Math.max(max, Number(item.id) || 0), 0);
    events.push({
      id: maxId + 1,
      memoryId,
      eventType,
      detail,
      createdAt: new Date().toISOString(),
    });
    await saveJsonEvents(events);
    return { success: true, provider: PROVIDER_JSON };
  } catch (error) {
    console.error("[memory-store] event record failed", safeErrorMessage(error));
    return { success: false };
  }
}

// 永久刪除某位使用者的所有長期記憶（帳號刪除時清資料用）。
// 與 archiveMemory（軟刪：is_active=false）不同，這裡是硬刪整批。
// 回傳實際刪除筆數。Postgres 優先、失敗 fallback JSON（比照其他操作）。
async function deleteMemoriesByUserId(userId = "default_user") {
  const normalizedUserId = normalizeUserId(userId);

  if (await postgres.isPostgresAvailable()) {
    try {
      const result = await postgres.query(
        `DELETE FROM companion_memories WHERE user_id = $1 RETURNING id`,
        [normalizedUserId],
      );
      return result.rowCount;
    } catch (error) {
      console.error(
        "[memory-store] postgres delete-by-user failed, falling back to json",
        safeErrorMessage(error),
      );
    }
  }

  const memories = await getJsonMemories();
  const remaining = memories.filter((item) => item.userId !== normalizedUserId);
  const removed = memories.length - remaining.length;
  if (removed > 0) {
    await saveJsonMemories(remaining);
  }
  return removed;
}

module.exports = {
  PROVIDER_POSTGRES,
  PROVIDER_JSON,
  MEMORY_TYPES,
  EMOTION_LABELS,
  EVENT_TYPES,
  MemoryValidationError,
  createMemory,
  listMemories,
  searchMemoriesByEmbedding,
  archiveMemory,
  recordMemoryEvent,
  markMemoriesUsed,
  findDuplicateMemory,
  deleteMemoriesByUserId,
  normalizeLimit,
  normalizeEmbedding,
  toVectorLiteral,
};
