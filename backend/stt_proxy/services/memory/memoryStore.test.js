const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs/promises");
const os = require("os");
const path = require("path");

const {
  MemoryValidationError,
  PROVIDER_JSON,
  createMemory,
  listMemories,
  searchMemoriesByEmbedding,
  archiveMemory,
} = require("./memoryStore");
const { createEmbedding } = require("./embeddingService");
const { extractMemoryFromTurn } = require("./memoryExtractor");
const {
  buildMemoryContext,
  rankMemories,
  buildPromptBlock,
} = require("./memoryContextService");
const { closePool } = require("../../db/postgres");

async function withJsonFallback(t, fn) {
  const oldDataDir = process.env.MEMORY_DATA_DIR;
  const oldDatabaseUrl = process.env.DATABASE_URL;
  const oldPgvectorEnabled = process.env.PGVECTOR_ENABLED;
  const oldOpenAiApiKey = process.env.OPENAI_API_KEY;
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "memory-store-"));

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

  return fn(dir);
}

function sampleMemory(overrides = {}) {
  return {
    userId: "default_user",
    memoryType: "preference",
    memoryText: "使用者喜歡聽台灣地方故事。",
    memorySummary: "使用者喜歡聽台灣地方故事。",
    emotionLabel: "happy",
    importance: 4,
    confidence: 0.9,
    sourceTurnId: `turn_${Date.now()}_${Math.random()}`,
    sourceSessionId: "manual_session",
    embedding: [0.1, 0.2, 0.3],
    ...overrides,
  };
}

test("createMemory can create a memory with JSON fallback", async (t) => {
  await withJsonFallback(t, async () => {
    const result = await createMemory(sampleMemory({ sourceTurnId: "create_001" }));
    assert.equal(result.provider, PROVIDER_JSON);
    assert.equal(result.duplicate, false);
    assert.equal(result.memory.memoryType, "preference");
  });
});

test("listMemories returns active memories ordered by latest first", async (t) => {
  await withJsonFallback(t, async () => {
    await createMemory(sampleMemory({ sourceTurnId: "list_001", memorySummary: "較早記憶" }));
    await new Promise((resolve) => setTimeout(resolve, 5));
    await createMemory(sampleMemory({ sourceTurnId: "list_002", memorySummary: "較晚記憶" }));

    const result = await listMemories("default_user");
    assert.equal(result.provider, PROVIDER_JSON);
    assert.equal(result.memories.length, 2);
    assert.equal(result.memories[0].memorySummary, "較晚記憶");
  });
});

test("archiveMemory removes memory from active list", async (t) => {
  await withJsonFallback(t, async () => {
    const created = await createMemory(sampleMemory({ sourceTurnId: "archive_001" }));
    const archived = await archiveMemory(created.memory.id, "default_user");
    assert.equal(archived.success, true);

    const listed = await listMemories("default_user");
    assert.equal(listed.memories.length, 0);
  });
});

test("searchMemoriesByEmbedding does not crash with JSON fallback", async (t) => {
  await withJsonFallback(t, async () => {
    await createMemory(sampleMemory({
      sourceTurnId: "search_001",
      memorySummary: "喜歡地方故事",
      embedding: [1, 0, 0],
    }));
    await createMemory(sampleMemory({
      sourceTurnId: "search_002",
      memorySummary: "喜歡睡前音樂",
      embedding: [0, 1, 0],
    }));

    const result = await searchMemoriesByEmbedding("default_user", [1, 0, 0], 5);
    assert.equal(result.provider, PROVIDER_JSON);
    assert.equal(result.memories[0].memorySummary, "喜歡地方故事");
    assert.ok(result.memories[0].similarity > 0.99);
  });
});

test("PostgreSQL unavailable uses JSON fallback", async (t) => {
  await withJsonFallback(t, async () => {
    const result = await createMemory(sampleMemory({ sourceTurnId: "fallback_001" }));
    assert.equal(result.provider, PROVIDER_JSON);
  });
});

test("invalid memoryType is rejected", async (t) => {
  await withJsonFallback(t, async () => {
    await assert.rejects(
      () => createMemory(sampleMemory({ memoryType: "bad_type" })),
      MemoryValidationError,
    );
  });
});

test("importance outside 1 to 5 is rejected", async (t) => {
  await withJsonFallback(t, async () => {
    await assert.rejects(
      () => createMemory(sampleMemory({ importance: 6 })),
      MemoryValidationError,
    );
  });
});

test("confidence outside 0 to 1 is rejected", async (t) => {
  await withJsonFallback(t, async () => {
    await assert.rejects(
      () => createMemory(sampleMemory({ confidence: 1.2 })),
      MemoryValidationError,
    );
  });
});

test("duplicate sourceTurnId returns existing memory without crashing", async (t) => {
  await withJsonFallback(t, async () => {
    const first = await createMemory(sampleMemory({
      sourceTurnId: "duplicate_001",
      memorySummary: "第一筆",
    }));
    const second = await createMemory(sampleMemory({
      sourceTurnId: "duplicate_001",
      memorySummary: "第二筆不應新增",
    }));

    assert.equal(second.duplicate, true);
    assert.equal(second.memory.id, first.memory.id);
    assert.equal(second.memory.memorySummary, "第一筆");

    const listed = await listMemories("default_user");
    assert.equal(listed.memories.length, 1);
  });
});

test("extractor remembers story preferences", async (t) => {
  await withJsonFallback(t, async () => {
    const result = await extractMemoryFromTurn({
      userText: "我喜歡聽台灣地方故事",
      agentReply: "好，我下次可以多說這類故事。",
      emotion: "happy",
    });
    assert.equal(result.shouldRemember, true);
    assert.ok(["story_preference", "preference"].includes(result.memoryType));
  });
});

test("extractor remembers sleep and low energy as health lifestyle", async (t) => {
  await withJsonFallback(t, async () => {
    const result = await extractMemoryFromTurn({
      userText: "我最近晚上都睡不好，白天很沒精神",
      agentReply: "我陪你慢慢調整。",
      emotion: "tired",
    });
    assert.equal(result.shouldRemember, true);
    assert.ok(["health_lifestyle", "care_need"].includes(result.memoryType));
  });
});

test("extractor remembers future hospital visit as reminder", async (t) => {
  await withJsonFallback(t, async () => {
    const result = await extractMemoryFromTurn({
      userText: "我明天要去醫院",
      agentReply: "我會記得提醒你。",
      emotion: "neutral",
    });
    assert.equal(result.shouldRemember, true);
    assert.equal(result.memoryType, "reminder");
  });
});

test("extractor remembers hydration reminder as care need", async (t) => {
  await withJsonFallback(t, async () => {
    const result = await extractMemoryFromTurn({
      userText: "我常常忘記喝水，可以提醒我嗎",
      agentReply: "可以，我會提醒你。",
      emotion: "neutral",
    });
    assert.equal(result.shouldRemember, true);
    assert.equal(result.memoryType, "care_need");
  });
});

test("extractor rejects ordinary chatter", async (t) => {
  await withJsonFallback(t, async () => {
    const haha = await extractMemoryFromTurn({ userText: "哈哈", agentReply: "", emotion: "happy" });
    const mm = await extractMemoryFromTurn({ userText: "嗯", agentReply: "", emotion: "neutral" });
    assert.equal(haha.shouldRemember, false);
    assert.equal(mm.shouldRemember, false);
  });
});

test("extractor rejects one-off weather chat", async (t) => {
  await withJsonFallback(t, async () => {
    const result = await extractMemoryFromTurn({
      userText: "今天天氣不錯",
      agentReply: "是呀。",
      emotion: "neutral",
    });
    assert.equal(result.shouldRemember, false);
  });
});

test("missing OPENAI_API_KEY uses non-crashing embedding fallback", async (t) => {
  await withJsonFallback(t, async () => {
    const result = await createEmbedding("使用者喜歡台灣地方故事");
    assert.equal(Array.isArray(result.embedding), true);
    assert.equal(result.embedding.length, 1536);
    assert.equal(result.provider, "mock");
    assert.match(result.error, /OPENAI_API_KEY/);
  });
});

test("same memorySummary is deduplicated without crashing", async (t) => {
  await withJsonFallback(t, async () => {
    const first = await createMemory(sampleMemory({
      sourceTurnId: "same_summary_001",
      memorySummary: "使用者喜歡聽台灣地方故事。",
    }));
    const second = await createMemory(sampleMemory({
      sourceTurnId: "same_summary_002",
      memorySummary: "使用者喜歡聽台灣地方故事。",
    }));
    assert.equal(second.duplicate, true);
    assert.equal(second.memory.id, first.memory.id);
  });
});

test("rankMemories uses similarity, importance, and recency thresholds", () => {
  const now = new Date().toISOString();
  const ranked = rankMemories([
    {
      id: 1,
      memorySummary: "低相似記憶",
      similarity: 0.3,
      importance: 5,
      createdAt: now,
      isActive: true,
    },
    {
      id: 2,
      memorySummary: "可用記憶",
      similarity: 0.55,
      importance: 4,
      createdAt: now,
      isActive: true,
    },
  ], "postgres_pgvector");
  assert.equal(ranked.length, 1);
  assert.equal(ranked[0].id, 2);
  assert.ok(ranked[0].finalScore >= 0.55);
});

test("buildPromptBlock hides technical details and includes usage rules", () => {
  const block = buildPromptBlock([
    { memorySummary: "使用者喜歡聽台灣地方故事。" },
  ]);
  assert.match(block.memoryContext, /可參考的使用者長期記憶/);
  assert.match(block.memoryContext, /不要說「我查到你的記憶」/);
  assert.doesNotMatch(block.memoryContext, /pgvector|embedding|資料庫 id/i);
});

test("buildMemoryContext returns empty context when embedding is unavailable", async (t) => {
  await withJsonFallback(t, async () => {
    const result = await buildMemoryContext({
      userId: "default_user",
      userText: "我想聽故事",
    });
    assert.equal(result.memoryUsed, false);
    assert.equal(result.provider, "none");
  });
});

test("buildMemoryContext retrieves ranked JSON fallback memories and marks them used", async (t) => {
  await withJsonFallback(t, async (dir) => {
    const created = await createMemory(sampleMemory({
      sourceTurnId: "context_001",
      memorySummary: "使用者喜歡聽台灣地方故事。",
      memoryText: "我喜歡聽台灣地方故事",
      memoryType: "story_preference",
      importance: 4,
      embedding: [1, 0, 0],
    }));
    await createMemory(sampleMemory({
      sourceTurnId: "context_002",
      memorySummary: "使用者不重要的低分記憶。",
      importance: 2,
      embedding: [1, 0, 0],
    }));

    const result = await buildMemoryContext({
      userId: "default_user",
      userText: "說一個台灣故事",
      queryEmbedding: [1, 0, 0],
    });
    assert.equal(result.memoryUsed, true);
    assert.deepEqual(result.usedMemoryIds, [created.memory.id]);
    assert.match(result.memoryContextSummary, /台灣地方故事/);

    const listed = await listMemories("default_user");
    const used = listed.memories.find((memory) => memory.id === created.memory.id);
    assert.equal(used.useCount, 1);
    assert.ok(used.lastUsedAt);
    const events = JSON.parse(
      await fs.readFile(path.join(dir, "memory_events.json"), "utf8"),
    );
    assert.ok(events.some((event) =>
      String(event.memoryId) === String(created.memory.id) &&
      event.eventType === "used_in_prompt",
    ));
  });
});

test("sleep health query recalls sleep memory", async (t) => {
  await withJsonFallback(t, async () => {
    await createMemory(sampleMemory({
      sourceTurnId: "sleep_context_001",
      memorySummary: "使用者最近晚上睡不好，白天精神較差。",
      memoryType: "health_lifestyle",
      importance: 4,
      embedding: [1, 0, 0],
    }));
    const result = await buildMemoryContext({
      userId: "default_user",
      userText: "給我一個睡眠健康小知識",
      queryEmbedding: [1, 0, 0],
    });
    assert.equal(result.memoryUsed, true);
    assert.match(result.memoryContextSummary, /使用了 1 筆長期記憶/);
    assert.ok(result.memoryContext.length <= 500);
  });
});

test("story query recalls story preference", async (t) => {
  await withJsonFallback(t, async () => {
    await createMemory(sampleMemory({
      sourceTurnId: "story_context_001",
      memorySummary: "使用者喜歡聽台灣地方故事。",
      memoryType: "story_preference",
      importance: 4,
      embedding: [1, 0, 0],
    }));
    const result = await buildMemoryContext({
      userId: "default_user",
      userText: "說一個故事給我聽",
      queryEmbedding: [1, 0, 0],
    });
    assert.equal(result.memoryUsed, true);
  });
});

test("unrelated tech news query does not force story memory", async (t) => {
  await withJsonFallback(t, async () => {
    await createMemory(sampleMemory({
      sourceTurnId: "story_context_002",
      memorySummary: "使用者喜歡聽台灣地方故事。",
      memoryType: "story_preference",
      importance: 4,
      embedding: [1, 0, 0],
    }));
    const result = await buildMemoryContext({
      userId: "default_user",
      userText: "今天有什麼科技新聞",
      queryEmbedding: [0, 1, 0],
    });
    assert.equal(result.memoryUsed, false);
    assert.equal(result.provider, "none");
    assert.equal(result.reason, "no_relevant_memory");
  });
});

test("no memories returns normalized empty context", async (t) => {
  await withJsonFallback(t, async () => {
    const result = await buildMemoryContext({
      userId: "default_user",
      userText: "給我一個睡眠健康小知識",
      queryEmbedding: [1, 0, 0],
    });
    assert.equal(result.memoryUsed, false);
    assert.equal(result.memoryContext, "");
    assert.equal(result.memoryContextSummary, "");
    assert.deepEqual(result.usedMemoryIds, []);
    assert.equal(result.provider, "none");
    assert.equal(result.reason, "no_relevant_memory");
  });
});
