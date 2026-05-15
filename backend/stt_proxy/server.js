const express = require("express");
const cors = require("cors");
const multer = require("multer");
const dotenv = require("dotenv");
const fs = require("fs");
const rateLimit = require('express-rate-limit');
const OpenAI = require("openai");

dotenv.config();

const { createEmbedding } = require("./services/embeddingService");
const { extractAndStoreMemory } = require("./services/memoryExtractor");
const {
  needsWebSearch,
  searchAndSummarize,
} = require("./services/tavilySearchService");
const { search: verticalSearch } = require("./services/search/searchService");
const { refreshCrawler } = require("./services/search/crawlerService");
const {
  searchMemories,
  markMemoriesUsed,
  softDeleteRecentMemory,
} = require("./repositories/memoryRepository");
const {
  MemoryValidationError,
  createMemory,
  listMemories,
  searchMemoriesByEmbedding,
  archiveMemory,
  normalizeEmbedding,
  normalizeLimit,
} = require("./services/memory/memoryStore");
const { extractMemoryFromTurn } = require("./services/memory/memoryExtractor");
const { createEmbedding: createMemoryEmbedding } = require("./services/memory/embeddingService");
const {
  buildMemoryContext,
  buildMemoryGreeting,
} = require("./services/memory/memoryContextService");
const { analyzeCompanionTurn } = require("../companion/companion_engine");
const { retrieveRelevantMemories } = require("../memory/memory_retriever");
const { storeCompanionMemoryCandidate } = require("../memory/memory_policy");

const app = express();
const port = process.env.PORT || 3001;
const upload = multer({ dest: "uploads/" });
const host = process.env.HOST || "127.0.0.1";

// Configure CORS: allow origins from ALLOWED_ORIGINS env (comma separated), default allow none
const allowedOriginsEnv = (process.env.ALLOWED_ORIGINS || '').trim();
const allowedOrigins = allowedOriginsEnv ? allowedOriginsEnv.split(',').map(s => s.trim()) : [];
app.use(cors({
  origin: function(origin, callback) {
    if (!origin && allowedOrigins.length === 0) return callback(null, true); // allow non-browser (curl, server)
    if (!origin) return callback(null, true);
    if (allowedOrigins.length === 0 || allowedOrigins.indexOf(origin) !== -1) {
      return callback(null, true);
    }
    return callback(new Error('CORS not allowed'));
  }
}));
app.use(express.json());

// express-rate-limit (production-ready; respects env for max requests)
const globalLimiter = rateLimit({
  windowMs: Number(process.env.RATE_LIMIT_WINDOW_MS) || 60 * 1000,
  max: Number(process.env.RATE_LIMIT_MAX_CALLS) || 60,
  standardHeaders: true,
  legacyHeaders: false,
});
app.use(globalLimiter);

// Per-route limiter for realtime endpoints (more strict)
const realtimeLimiter = rateLimit({
  windowMs: Number(process.env.REALTIME_RATE_LIMIT_WINDOW_MS) || 60 * 1000,
  max: Number(process.env.REALTIME_RATE_LIMIT_MAX) || 6,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, message: 'Too many realtime requests' },
});

const client = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
});

function logInfo(message, extra = {}) {
  console.log(`[realtime-broker] ${message}`, extra);
}

function logError(message, extra = {}) {
  console.error(`[realtime-broker] ${message}`, extra);
}

const REALTIME_INSTRUCTIONS = `你是長者陪伴寵物，不是一般助理。
請使用繁體中文。
你負責即時、自然、不中斷的口語陪伴回應。
使用者不一定會直接說出「孤單、難過、焦慮」等字眼，你要從語意中理解可能的陪伴需求。
當使用者提到安靜、一個人、大家都很忙、沒事做、以前很熱鬧、睡不好、算了沒關係等內容時，要用溫柔方式接住感受。
不要武斷地說「你就是孤單」。
回覆要簡短、自然、像陪在身邊的寵物。
每次最多問一個問題。
不要像客服，不要像老師，不要做醫療診斷。
如果有 Companion Engine 提供的 nextStrategy，請優先遵守。
當使用者提到胸痛、呼吸困難、跌倒、嚴重不適、自傷意念時，請提高安全提醒，建議聯絡家人或尋求醫療協助。`;

function fallbackGreeting({ petName, localHour }) {
  if (localHour >= 5 && localHour <= 10) {
    return `早安，我是${petName}，今天也陪你聊聊天。`;
  }
  if (localHour >= 11 && localHour <= 16) {
    return `午安，我是${petName}，今天過得還好嗎？`;
  }
  if (localHour >= 17 && localHour <= 23) {
    return `晚安，我是${petName}，今天辛苦了，我陪你一下。`;
  }
  return `晚安，我是${petName}，這麼晚了，要不要準備休息了呢？`;
}

function buildRealtimeInstructions(petName, summaries = [], memoryContext = "", companionContext = "") {
  const normalizedPetName = (petName || "").toString().trim() || "陪伴寶";
  const header = `你的名字是 ${normalizedPetName}。
${REALTIME_INSTRUCTIONS}`;
  const companionBlock = companionContext
    ? `

Companion Engine 目前分析：
${companionContext}
請優先遵守這個 nextStrategy，但不要提到分析系統或欄位名稱。`
    : "";

  if (memoryContext) {
    return `${header}

${memoryContext}${companionBlock}`;
  }

  if (!summaries.length) {
    return `${header}${companionBlock}`;
  }

  const memoryBlock = summaries.map((item) => `- ${item}`).join("\n");
  return `${header}

以下是你自然記得的使用者近況：
${memoryBlock}

請自然地關心使用者，不要說「根據紀錄」或「資料庫顯示」。
如果使用者不想聊這件事，請溫柔轉換話題。${companionBlock}`;
}

async function loadRelevantMemorySummaries(userId, query, topK) {
  if (!userId) return [];
  try {
    const embedding = await createEmbedding(query);
    const rows = await searchMemories({
      userId,
      queryEmbedding: embedding,
      topK,
    });
    return rows.map((row) => row.summary).filter(Boolean).slice(0, topK);
  } catch (error) {
    logError("loadRelevantMemorySummaries failed", { error: error?.message || error });
    return [];
  }
}

function withTimeout(promise, timeoutMs, fallbackValue) {
  let timeoutId;
  const timeout = new Promise((resolve) => {
    timeoutId = setTimeout(() => resolve(fallbackValue), timeoutMs);
  });
  return Promise.race([promise, timeout]).finally(() => {
    if (timeoutId) clearTimeout(timeoutId);
  });
}

app.get("/health", (_, res) => {
  res.json({ status: "ok" });
});

app.post("/api/companion/analyze", async (req, res) => {
  try {
    const userId = req.body?.userId || "default_user";
    const transcript = req.body?.transcript || "";
    const retrieved = await retrieveRelevantMemories({
      userId,
      transcript,
      topK: req.body?.topK || process.env.MEMORY_TOP_K || 5,
    });
    const result = analyzeCompanionTurn({
      userId,
      sessionId: req.body?.sessionId,
      turnId: req.body?.turnId,
      petName: req.body?.petName,
      transcript,
      languageHint: req.body?.languageHint,
      recentTurns: req.body?.recentTurns,
      petState: req.body?.petState,
      audioFeatures: req.body?.audioFeatures,
      retrievedMemories: retrieved.memories,
    });
    if (result.memory?.shouldSave && result.memory?.candidate?.trim()) {
      storeCompanionMemoryCandidate({
        userId,
        sessionId: req.body?.sessionId,
        turnId: req.body?.turnId,
        emotion: result.emotion,
        memory: result.memory,
        safety: result.safety,
      }).catch((error) => {
        logError("companion memory store failed", { error: error?.message || error });
      });
    }
    return res.json(result);
  } catch (error) {
    logError("companion analyze failed", { error: error?.message || error });
    return res.status(500).json({
      turnId: req.body?.turnId || "",
      emotion: "neutral",
      emotionConfidence: 0.5,
      companionNeed: "unknown",
      needConfidence: 0.5,
      replyStrategy: "normal_chat",
      implicitMeaning: "Companion Engine 暫時無法分析。",
      petExpression: "idle",
      petAction: "stay",
      memory: {
        shouldSave: false,
        candidate: "",
        type: "none",
      },
      safety: {
        riskLevel: "normal",
        needsHumanSupport: false,
      },
      nextStrategy: {
        mode: "normal_chat",
        instruction: "下一輪回應保持自然、簡短、陪伴感，每次最多問一個問題。",
      },
    });
  }
});

app.post("/api/stt/transcribe", upload.single("audio"), async (req, res) => {
  if (!process.env.OPENAI_API_KEY) {
    return res.status(500).json({
      success: false,
      message: "Missing OPENAI_API_KEY",
    });
  }
  if (!req.file) {
    return res.status(400).json({
      success: false,
      message: "audio file is required",
    });
  }

  try {
    const result = await client.audio.transcriptions.create({
      file: fs.createReadStream(req.file.path),
      model: "gpt-4o-transcribe",
      response_format: "json",
    });
    const text = (result.text || "").trim();
    if (!text) {
      return res.status(422).json({
        success: false,
        message: "Empty transcript",
      });
    }
    return res.json({
      success: true,
      text,
    });
  } catch (error) {
    return res.status(500).json({
      success: false,
      message: "STT failed",
      error: error?.message || "Unknown error",
    });
  } finally {
    fs.unlink(req.file.path, () => {});
  }
});

app.post("/api/memory/extract", async (req, res) => {
  try {
    const result = await extractAndStoreMemory({
      userId: req.body?.userId || "local_user",
      sessionId: req.body?.sessionId || null,
      turnId: req.body?.turnId || null,
      userText: req.body?.userText || "",
      aiReply: req.body?.aiReply || "",
      emotion: req.body?.emotion || "neutral",
      createdAt: req.body?.createdAt || null,
    });
    return res.json(result);
  } catch (error) {
    return res.status(500).json({
      shouldRemember: false,
      error: error?.message || "memory extract failed",
    });
  }
});

app.post("/api/memory/search", async (req, res) => {
  try {
    const userId = (req.body?.userId || "local_user").toString();
    const query = (req.body?.query || "").toString().trim();
    const topK = Number(req.body?.topK || process.env.MEMORY_TOP_K || 5);
    if (!query) {
      return res.status(400).json({ memories: [], message: "query is required" });
    }
    const queryEmbedding = await createEmbedding(query);
    const rows = await searchMemories({
      userId,
      queryEmbedding,
      topK,
    });
    return res.json({
      memories: rows.map((row) => ({
        id: row.id,
        summary: row.summary,
        memoryType: row.memory_type,
        emotion: row.emotion,
        importance: row.importance,
        similarity: Number(row.similarity || 0),
        createdAt: row.created_at,
      })),
    });
  } catch (error) {
    return res.status(500).json({
      memories: [],
      error: error?.message || "memory search failed",
    });
  }
});

app.get("/api/memory/greeting", async (req, res) => {
  try {
    const userId = (req.query?.userId || "local_user").toString();
    const petName = (req.query?.petName || "陪伴寶").toString();
    const localHour = Number(req.query?.localHour || 9);
    const topK = 3;

    const contextResult = await buildMemoryContext({
      userId,
      userText: "找出近期最適合主動關心使用者的偏好、生活習慣或近況",
      limit: topK,
    });
    const memoryRows = contextResult.memories || [];

    if (!memoryRows.length) {
      return res.json({
        greeting: fallbackGreeting({ petName, localHour }),
        usedMemoryIds: [],
      });
    }

    const memoryLines = memoryRows
      .map((row, index) => `${index + 1}. ${row.memorySummary || row.summary}`)
      .join("\n");
    const greetingResponse = await client.chat.completions.create({
      model: process.env.MEMORY_MODEL || "gpt-4o-mini",
      temperature: 0.5,
      messages: [
        {
          role: "system",
          content:
            "你是陪伴長者的 AI 寵物，請輸出 1~2 句繁中自然關心問候，不要提到紀錄、資料庫、系統。",
        },
        {
          role: "user",
          content: `寵物名稱：${petName}
當前小時：${localHour}
可參考的近期近況：
${memoryLines}
請生成自然問候。`,
        },
      ],
    });
    const greeting =
      greetingResponse.choices?.[0]?.message?.content?.trim() ||
      fallbackGreeting({ petName, localHour });
    const usedIds = contextResult.usedMemoryIds || memoryRows.map((row) => row.id);

    return res.json({
      greeting,
      usedMemoryIds: usedIds,
    });
  } catch (error) {
    const petName = (req.query?.petName || "陪伴寶").toString();
    const localHour = Number(req.query?.localHour || 9);
    return res.json({
      greeting: fallbackGreeting({ petName, localHour }),
      usedMemoryIds: [],
      error: error?.message || "greeting failed",
    });
  }
});

app.post("/api/memory/forget-recent", async (req, res) => {
  try {
    const userId = (req.body?.userId || "local_user").toString();
    const deleted = await softDeleteRecentMemory(userId);
    return res.json({ deleted });
  } catch (error) {
    return res.status(500).json({
      deleted: false,
      error: error?.message || "forget recent failed",
    });
  }
});

app.get("/api/memories", async (req, res) => {
  try {
    const userId = (req.query?.userId || "default_user").toString();
    const result = await listMemories(userId);
    return res.json(result);
  } catch (error) {
    logError("list companion memories failed", { error: error?.message || error });
    return res.status(500).json({
      memories: [],
      provider: "json_fallback",
      error: error?.message || "list memories failed",
    });
  }
});

app.post("/api/memories", async (req, res) => {
  try {
    const content = (req.body?.content || req.body?.memorySummary || req.body?.memoryText || "").toString().trim();
    const type = (req.body?.type || req.body?.memoryType || "other").toString().trim();
    const embedding = req.body?.embedding || (await createMemoryEmbedding(content)).embedding;
    const result = await createMemory({
      userId: req.body?.userId || "default_user",
      memoryType: type,
      memoryText: req.body?.memoryText || content,
      memorySummary: req.body?.memorySummary || content,
      emotionLabel: req.body?.emotionLabel,
      importance: req.body?.importance,
      confidence: req.body?.confidence,
      sourceTurnId: req.body?.sourceTurnId || req.body?.source_turn_id,
      sourceSessionId: req.body?.sourceSessionId || req.body?.sessionId,
      embedding,
    });
    return res.status(result.duplicate ? 200 : 201).json(result);
  } catch (error) {
    if (error instanceof MemoryValidationError || error?.statusCode === 400) {
      return res.status(400).json({
        success: false,
        message: error.message,
        field: error.field,
      });
    }
    logError("create companion memory failed", { error: error?.message || error });
    return res.status(500).json({
      success: false,
      message: error?.message || "create memory failed",
    });
  }
});

app.post("/api/memories/search", async (req, res) => {
  try {
    normalizeEmbedding(req.body?.embedding);
    const userId = (req.body?.userId || "default_user").toString();
    const limit = normalizeLimit(req.body?.limit);
    const result = await searchMemoriesByEmbedding(userId, req.body.embedding, limit);
    return res.json(result);
  } catch (error) {
    if (error instanceof MemoryValidationError || error?.statusCode === 400) {
      return res.status(400).json({
        memories: [],
        message: error.message,
        field: error.field,
      });
    }
    logError("search companion memories failed", { error: error?.message || error });
    return res.status(500).json({
      memories: [],
      provider: "json_fallback",
      error: error?.message || "search memories failed",
    });
  }
});

app.post("/api/memories/context", async (req, res) => {
  try {
    const result = await buildMemoryContext({
      userText: req.body?.userText || "",
      userId: req.body?.userId || "default_user",
      limit: req.body?.limit || 5,
    });
    return res.json(result);
  } catch (error) {
    logError("build companion memory context failed", { error: error?.message || error });
    return res.json({
      memoryUsed: false,
      usedMemoryIds: [],
      memoryContext: "",
      memoryContextSummary: "",
      reason: "memory context failed",
    });
  }
});

app.get("/api/memories/greeting", async (req, res) => {
  const fallback = fallbackGreeting({
    petName: (req.query?.petName || "陪伴寶").toString(),
    localHour: Number(req.query?.localHour || new Date().getHours()),
  });
  try {
    const result = await buildMemoryGreeting({
      userId: (req.query?.userId || "default_user").toString(),
    });
    if (!result.memoryUsed) {
      return res.json({
        greeting: fallback,
        memoryUsed: false,
        memoryId: null,
        provider: "none",
        reason: result.reason || "no_relevant_memory",
      });
    }
    return res.json(result);
  } catch (error) {
    logError("memory greeting failed", { error: error?.message || error });
    return res.json({
      greeting: fallback,
      memoryUsed: false,
      memoryId: null,
      provider: "none",
      reason: "memory_greeting_failed",
    });
  }
});

app.post("/api/memories/extract", async (req, res) => {
  try {
    const userText = (req.body?.userText || "").toString().trim();
    if (!userText) {
      return res.status(400).json({
        shouldRemember: false,
        reason: "userText is required",
      });
    }

    const extracted = await extractMemoryFromTurn({
      userId: req.body?.userId || "default_user",
      userText,
      agentReply: req.body?.agentReply || req.body?.aiReply || "",
      emotion: req.body?.emotion || "unknown",
      sessionId: req.body?.sessionId || null,
      turnId: req.body?.turnId || null,
    });

    if (!extracted.shouldRemember) {
      return res.json(extracted);
    }

    const embeddingResult = await createMemoryEmbedding(extracted.memorySummary);
    const storeResult = await createMemory({
      userId: req.body?.userId || "default_user",
      memoryType: extracted.memoryType,
      memoryText: extracted.memoryText,
      memorySummary: extracted.memorySummary,
      emotionLabel: extracted.emotionLabel,
      importance: extracted.importance,
      confidence: extracted.confidence,
      sourceTurnId: req.body?.turnId || null,
      sourceSessionId: req.body?.sessionId || null,
      embedding: embeddingResult.embedding,
    });

    return res.status(storeResult.duplicate ? 200 : 201).json({
      shouldRemember: true,
      memory: storeResult.memory,
      reason: storeResult.reason || extracted.reason,
      duplicate: Boolean(storeResult.duplicate),
      embeddingProvider: embeddingResult.provider,
      embeddingError: embeddingResult.error,
      storeProvider: storeResult.provider,
    });
  } catch (error) {
    if (error instanceof MemoryValidationError || error?.statusCode === 400) {
      return res.status(400).json({
        shouldRemember: false,
        message: error.message,
        field: error.field,
      });
    }
    logError("extract companion memory failed", { error: error?.message || error });
    return res.json({
      shouldRemember: false,
      reason: "記憶抽取暫時失敗，已略過且不影響對話",
      error: error?.message || "memory extract failed",
    });
  }
});

app.post("/api/memories/:id/archive", async (req, res) => {
  try {
    const userId = (req.body?.userId || "default_user").toString();
    const result = await archiveMemory(req.params.id, userId);
    return res.json(result);
  } catch (error) {
    logError("archive companion memory failed", { error: error?.message || error });
    return res.status(500).json({
      success: false,
      error: error?.message || "archive memory failed",
    });
  }
});

app.patch("/api/memories/:id/archive", async (req, res) => {
  try {
    const userId = (req.body?.userId || req.query?.userId || "default_user").toString();
    const result = await archiveMemory(req.params.id, userId);
    return res.json(result);
  } catch (error) {
    logError("archive companion memory failed", { error: error?.message || error });
    return res.status(500).json({
      success: false,
      error: error?.message || "archive memory failed",
    });
  }
});

app.post("/api/web/search", async (req, res) => {
  try {
    const query = (req.body?.query || "").toString().trim();
    if (!query) {
      return res.status(400).json({
        success: false,
        message: "query is required",
      });
    }

    if (!needsWebSearch(query)) {
      return res.json({
        success: true,
        needsSearch: false,
        answer: "",
        sources: [],
        highRisk: false,
      });
    }

    const result = await searchAndSummarize(query);
    return res.json({
      success: true,
      needsSearch: true,
      answer: result.answer,
      sources: result.sources,
      highRisk: result.highRisk,
    });
  } catch (error) {
    if (error?.code === "MISSING_TAVILY_API_KEY") {
      return res.status(500).json({
        success: false,
        code: "missing_api_key",
        message: "TAVILY_API_KEY is missing. Please set it in backend/stt_proxy/.env.",
      });
    }
    if (error?.code === "NETWORK_ERROR") {
      return res.status(503).json({
        success: false,
        code: "network_error",
        message: "現在好像連不上網路，我晚點再幫你查。",
      });
    }
    logError("web search failed", { error: error?.message || error });
    return res.status(502).json({
      success: false,
      code: "search_failed",
      message: "搜尋暫時失敗了，我晚點再幫你查。",
    });
  }
});

app.post("/api/search", async (req, res) => {
  try {
    const query = (req.body?.query || "").toString().trim();
    if (!query) {
      return res.status(400).json({
        answer: "你可以再告訴我想查什麼嗎？",
        summary: "query is required",
        sources: [],
        mode: "companion_chat",
        provider: "mock_fallback",
        confidence: "low",
        shouldShowSources: false,
      });
    }
    const result = await verticalSearch({
      query,
      mode: (req.body?.mode || "auto").toString(),
      userProfile: req.body?.userProfile || {},
    });
    return res.json(result);
  } catch (error) {
    logError("vertical search failed", { error: error?.message || error });
    return res.status(500).json({
      answer: "我現在查詢有點卡住了，先不亂說。我可以陪你聊聊，或等一下再幫你查。",
      summary: "search failed",
      sources: [],
      mode: "general_web_search",
      provider: "mock_fallback",
      confidence: "low",
      shouldShowSources: false,
    });
  }
});

app.post("/api/crawl/refresh", async (req, res) => {
  // DEV ONLY: protect this endpoint with authentication/authorization before production.
  try {
    const urls = Array.isArray(req.body?.urls) ? req.body.urls.map(String) : [];
    const result = await refreshCrawler({ urls });
    return res.json(result);
  } catch (error) {
    logError("crawl refresh failed", { error: error?.message || error });
    return res.status(500).json({
      success: false,
      message: "crawl refresh failed",
      error: error?.message || "Unknown error",
    });
  }
});

app.post("/api/realtime/session", realtimeLimiter, async (req, res) => {
  logInfo("POST /api/realtime/session received");
  logInfo("OPENAI_API_KEY exists", { hasApiKey: Boolean(process.env.OPENAI_API_KEY) });

  if (!process.env.OPENAI_API_KEY) {
    logError("OPENAI_API_KEY missing");
    return res.status(500).json({
      success: false,
      message: "Missing OPENAI_API_KEY",
    });
  }

  try {
    const realtimeModel = process.env.REALTIME_MODEL || "gpt-realtime";
    logInfo("Using realtime model", { model: realtimeModel });

    const response = await fetch("https://api.openai.com/v1/realtime/sessions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: realtimeModel,
        voice: process.env.REALTIME_VOICE || "alloy",
        modalities: ["audio", "text"],
        instructions: REALTIME_INSTRUCTIONS,
        input_audio_format: "pcm16",
        output_audio_format: "pcm16",
        turn_detection: {
          type: "server_vad",
          threshold: 0.5,
          prefix_padding_ms: 300,
          silence_duration_ms: 700,
          create_response: true,
        },
        input_audio_transcription: {
          model: "gpt-4o-mini-transcribe",
        },
      }),
    });

    const data = await response.json();
    logInfo("OpenAI realtime session response", { status: response.status });
    if (!response.ok) {
      logError("Realtime session creation failed", {
        status: response.status,
        errorBody: data,
      });
      return res.status(response.status).json({
        success: false,
        message: "Failed to create realtime session",
        error: data?.error?.message || "Unknown error",
      });
    }

    logInfo("Realtime session created", {
      hasClientSecret: Boolean(data?.client_secret),
      sessionId: data?.id || null,
    });
    // Return session info but avoid echoing secret values in logs.
    return res.json({
      success: true,
      model: data.model,
      client_secret: data.client_secret, // client uses this to connect
      expires_at: data.expires_at,
      session_id: data.id,
      session_type: data.type || "realtime",
    });
  } catch (error) {
    logError("Realtime session creation exception", { error: error?.message || error });
    return res.status(500).json({
      success: false,
      message: "Realtime session creation failed",
      error: error?.message || "Unknown error",
    });
  }
});

app.post(
  "/api/realtime/call",
  realtimeLimiter,
  express.text({ type: ["application/sdp", "text/plain", "*/*"], limit: '512kb' }),
  async (req, res) => {
    logInfo("POST /api/realtime/call received");
    logInfo("OPENAI_API_KEY exists", { hasApiKey: Boolean(process.env.OPENAI_API_KEY) });
    if (!process.env.OPENAI_API_KEY) {
      logError("OPENAI_API_KEY missing");
      return res.status(500).send("Missing OPENAI_API_KEY");
    }
    const offerSdp = (req.body || "").toString();
    if (!offerSdp.trim()) {
      return res.status(400).send("Missing SDP offer");
    }
    // Basic size check to prevent extremely large payloads
    if (offerSdp.length > 200000) {
      return res.status(413).send("SDP offer too large");
    }

    const realtimeModel = process.env.REALTIME_MODEL || "gpt-realtime";
    let petName = (req.query?.petName || "").toString().trim();
    let userId = (req.query?.userId || "").toString().trim();
    let companionContext = (req.query?.companionContext || "").toString().trim();
    petName = petName.replace(/\r|\n/g, ' ').substring(0, 128) || "陪伴寶";
    userId = userId.replace(/\r|\n/g, ' ').substring(0, 128) || "local_user";
    companionContext = companionContext.replace(/\r|\n/g, " ").substring(0, 900);

    const memoryTopK = Number(process.env.MEMORY_TOP_K || 5);
    const contextResult = await withTimeout(
      buildMemoryContext({
        userId,
        userText: "找出最近值得自然關心使用者的長期偏好、生活習慣或近況",
        limit: memoryTopK,
      }).catch((error) => {
        logError("Realtime memory context failed", { error: error?.message || error });
        return null;
      }),
      1200,
      null,
    );
    if (!contextResult) {
      logInfo("Realtime memory context skipped", { reason: "timeout_or_failure" });
    }
    const memorySummaries = contextResult?.memories?.map((item) => item.memorySummary).filter(Boolean) || [];
    logInfo("[REALTIME_INSTRUCTIONS]", {
      petName,
      userId,
      memoryCount: memorySummaries.length,
      memoryProvider: contextResult?.provider || "none",
      hasCompanionContext: Boolean(companionContext),
    });

    const sessionConfig = {
      type: "realtime",
      model: realtimeModel,
      audio: {
        output: {
          voice: process.env.REALTIME_VOICE || "marin",
        },
      },
      instructions: buildRealtimeInstructions(
        petName,
        memorySummaries,
        contextResult?.memoryContext || "",
        companionContext,
      ),
    };

    try {
      logInfo("Using realtime model", { model: realtimeModel });
      logInfo("Realtime call session config", {
        hasAudioOutputVoice: Boolean(sessionConfig.audio?.output?.voice),
      });
      const form = new FormData();
      form.append("sdp", offerSdp);
      form.append("session", JSON.stringify(sessionConfig));

      const response = await fetch("https://api.openai.com/v1/realtime/calls", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
        },
        body: form,
      });
      const responseText = await response.text();
      logInfo("OpenAI realtime calls response", { status: response.status });
      if (!response.ok) {
        // Log detailed error internally, but return a generic message to caller
        let errorBody = responseText;
        try {
          errorBody = JSON.parse(responseText);
        } catch (_) {}
        logError("Realtime call failed", {
          status: response.status,
          errorBody,
        });
        return res.status(502).send("Realtime call failed");
      }

      res.setHeader("Content-Type", "application/sdp");
      return res.status(200).send(responseText);
    } catch (error) {
      logError("Realtime call exception", { error: error?.message || error });
      return res.status(500).send("Realtime call failed");
    }
  },
);

app.listen(port, host, () => {
  console.log(`STT Proxy listening on http://${host}:${port}`);
});
