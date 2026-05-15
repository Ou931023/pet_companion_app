const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs/promises");
const os = require("os");
const path = require("path");

const { closePool } = require("../stt_proxy/db/postgres");
const { createLongTermMemory } = require("./memory_repository");
const { retrieveRelevantMemories } = require("./memory_retriever");
const { storeCompanionMemoryCandidate } = require("./memory_policy");
const { archiveLongTermMemory } = require("./memory_repository");
const { mockEmbedding } = require("./memory_embedding_service");

async function withMemoryFallback(t, fn) {
  const oldDataDir = process.env.MEMORY_DATA_DIR;
  const oldDatabaseUrl = process.env.DATABASE_URL;
  const oldPgvectorEnabled = process.env.PGVECTOR_ENABLED;
  const oldOpenAiApiKey = process.env.OPENAI_API_KEY;
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "memory-retriever-"));

  process.env.MEMORY_DATA_DIR = dir;
  delete process.env.DATABASE_URL;
  process.env.PGVECTOR_ENABLED = "false";
  delete process.env.OPENAI_API_KEY;
  await closePool();

  t.after(async () => {
    if (oldDataDir == null) delete process.env.MEMORY_DATA_DIR;
    else process.env.MEMORY_DATA_DIR = oldDataDir;
    if (oldDatabaseUrl == null) delete process.env.DATABASE_URL;
    else process.env.DATABASE_URL = oldDatabaseUrl;
    if (oldPgvectorEnabled == null) delete process.env.PGVECTOR_ENABLED;
    else process.env.PGVECTOR_ENABLED = oldPgvectorEnabled;
    if (oldOpenAiApiKey == null) delete process.env.OPENAI_API_KEY;
    else process.env.OPENAI_API_KEY = oldOpenAiApiKey;
    await closePool();
    await fs.rm(dir, { recursive: true, force: true });
  });

  return fn();
}

function memory(content, overrides = {}) {
  return {
    userId: "demo-user",
    memoryType: "preference",
    memoryText: content,
    memorySummary: content,
    importance: 4,
    confidence: 0.9,
    sourceTurnId: `turn_${content}_${Math.random()}`,
    sourceSessionId: "session-001",
    embedding: mockEmbedding(content),
    ...overrides,
  };
}

test("shouldSave memory candidate is stored", async (t) => {
  await withMemoryFallback(t, async () => {
    const result = await storeCompanionMemoryCandidate({
      userId: "demo-user",
      sessionId: "session-001",
      turnId: "turn-save-001",
      emotion: "lonely",
      memory: {
        shouldSave: true,
        candidate: "使用者提到家裡很安靜，可能需要陪伴。",
        type: "emotion_event",
      },
    });

    assert.equal(result.stored, true);
    assert.equal(result.memory.memoryType, "emotion_event");
  });
});

test("archived memory is not retrieved", async (t) => {
  await withMemoryFallback(t, async () => {
    const created = await createLongTermMemory(memory("使用者喜歡台灣地方故事"));
    await archiveLongTermMemory(created.memory.id, "demo-user");

    const result = await retrieveRelevantMemories({
      userId: "demo-user",
      transcript: "我想聽台灣地方故事",
      topK: 5,
    });

    assert.equal(result.memories.length, 0);
  });
});

test("similar memory is not stored twice", async (t) => {
  await withMemoryFallback(t, async () => {
    const first = await createLongTermMemory(memory("使用者喜歡台灣地方故事"));
    const second = await createLongTermMemory(memory("使用者喜歡台灣地方故事", {
      sourceTurnId: "different-turn",
    }));

    assert.equal(first.duplicate, false);
    assert.equal(second.duplicate, true);
  });
});

test("retrieve memories returns topK", async (t) => {
  await withMemoryFallback(t, async () => {
    await createLongTermMemory(memory("使用者喜歡台灣地方故事"));
    await createLongTermMemory(memory("使用者晚上睡不好", {
      memoryType: "health_note",
    }));
    await createLongTermMemory(memory("使用者喜歡聽老歌"));

    const result = await retrieveRelevantMemories({
      userId: "demo-user",
      transcript: "我想聽故事或老歌",
      topK: 2,
    });

    assert.equal(result.memories.length, 2);
  });
});
