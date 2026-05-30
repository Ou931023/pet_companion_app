const express = require("express");
const cors = require("cors");
const multer = require("multer");
const dotenv = require("dotenv");
const fs = require("fs");
const os = require("os");
const path = require("path");
const rateLimit = require('express-rate-limit');
const OpenAI = require("openai");

dotenv.config();

const { createEmbedding } = require("./services/embeddingService");
const { extractAndStoreMemory } = require("./services/memoryExtractor");
const {
  needsWebSearch,
  searchAndSummarize,
} = require("./services/tavilySearchService");
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
const { classifySearchIntent } = require("../search/search_intent_classifier");
const { searchKnowledge } = require("../search/search_service");
const {
  routeAgentTool,
  listTools: listAgentTools,
} = require("../agent/agent_orchestrator");
const {
  TaigiAsrError,
  getTaigiAsrStatus,
  transcribeTaigiAudio,
  warmupTaigiAsr,
} = require("./services/taigiAsrService");
const {
  sendCareAlertNotification,
  shouldNotify: shouldTelegramNotify,
} = require("./services/telegramNotifyService");
const {
  saveAlert: saveCareAlert,
  listAlerts: listCareAlerts,
  getAlertById: getCareAlertById,
  updateAlertStatus: updateCareAlertStatus,
  normalizeRiskLevel,
} = require("./services/careAlertStoreService");
const {
  canSendTelegram,
  markTelegramSent,
} = require("./services/careAlertCooldown");
const { createSession } = require("./services/auth/sessionService");
const adminAnalysis = require("./services/admin/adminAnalysisService");

const app = express();
const port = process.env.PORT || 3001;
const upload = multer({ dest: "uploads/" });
const taigiAsrUploadDir = path.join(os.tmpdir(), "pet_companion_taigi_asr");
fs.mkdirSync(taigiAsrUploadDir, { recursive: true });
const taigiAsrUpload = multer({
  dest: taigiAsrUploadDir,
  limits: {
    fileSize: Number(process.env.TAIGI_ASR_MAX_UPLOAD_BYTES) || 10 * 1024 * 1024,
  },
  fileFilter: (req, file, callback) => {
    const allowedMimeTypes = new Set([
      "audio/wav",
      "audio/x-wav",
      "audio/wave",
      "audio/mpeg",
      "audio/mp4",
      "audio/m4a",
      "audio/aac",
      "audio/x-caf",
      "audio/caf",
    ]);
    const ext = path.extname(file.originalname || "").toLowerCase();
    const allowedExtensions = new Set([".wav", ".m4a", ".caf", ".mp3", ".aac"]);
    const isOctetAudio =
      file.mimetype === "application/octet-stream" && allowedExtensions.has(ext);
    if (allowedMimeTypes.has(file.mimetype) || isOctetAudio) {
      callback(null, true);
      return;
    }
    callback(new TaigiAsrError("TAIGI_ASR_INVALID_AUDIO", "Unsupported audio file", 400));
  },
});
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
你負責即時、自然、不中斷的口語陪伴回應。
使用者不一定會直接說出「孤單、難過、焦慮」等字眼，你要從語意中理解可能的陪伴需求。
當使用者提到安靜、一個人、大家都很忙、沒事做、以前很熱鬧、睡不好、算了沒關係等內容時，要用溫柔方式接住感受。
不要武斷地說「你就是孤單」。
回覆要簡短、自然、像陪在身邊的寵物。
每次最多問一個問題。
不要像客服，不要像老師，不要做醫療診斷。
如果有 Companion Engine 提供的 nextStrategy，請優先遵守。
當使用者提到胸痛、呼吸困難、跌倒、嚴重不適、自傷意念時，請提高安全提醒，建議聯絡家人或尋求醫療協助。

【你能做的事 / App 工具】
這個 App 是一款陪伴養成寵物應用，會自動幫你執行下列動作。下面每一項都列出該指令在 App 裡的意義，回覆時請用這個意義來回應，不要把詞語當成一般中文去解釋、不要說「我不太理解」「你是說什麼」「請問你的意思」之類反問。

意義對照表：
- 「簽到 / 幫我簽到 / 每日簽到 / 簽到了嗎 / 我簽到了嗎」 = App 的每日簽到功能（拿金幣獎勵）。回覆例：「好的，幫你簽到了」「OK，今天簽到完成」。如果使用者問「簽到了嗎」「我有簽到嗎」，請回「有的，今天已經幫你簽到了」。
- 「我還有多少金幣 / 金幣餘額 / 寵物狀態 / 寵物數值」 = 查詢使用者目前在 App 裡的金幣數或寵物數值。你不知道實際數字，請回「我幫你看一下喔」這類短句，App 端會更新畫面。
- 「今天有什麼任務 / 每日任務 / 任務清單」 = App 的任務系統。回「今天的任務我幫你列在畫面上了」之類。
- 「我喝水了 / 我吃飯了 / 我休息了 / 我完成任務」 = 完成每日任務。回「好的，幫你記下了」。
- 「幫我買 X / 買 X / 購買」 = App 內商城的購買。回「沒問題，幫你買好了」。
- 「把聲音關掉 / 打開聲音 / 字調大 / 字調小 / 說話慢一點 / 慢慢說 / 溫柔點」 = 調整 App 設定。回「好，幫你調好了」。
- 「播放音樂 / 放歌 / 聽放鬆音樂 / 台語老歌 / 白噪音」 = 開啟音樂搜尋。回「好的，幫你找音樂」。
- 「幫我打給 X / 打電話 / 撥電話」 = 開啟撥號。回「好，幫你打給 X」。
- 「寄 email 給 X / 寄信」 = 建立 Email 草稿。回「沒問題，幫你準備好信了」。
- 「提醒我 X」 = 建立提醒。回「好，幫你記下提醒」。
- 「查 X / 搜尋 X / 防詐騙新聞 / 新聞 / 健康小知識」 = 搜尋可信資訊。回「好的，幫你查」。
- 「帶我去商城 / 打開設定 / 開記憶 / 開記錄」 = App 內導頁。回「好，幫你開了」。
- 「記住 X / 我喜歡 X / 我不喜歡 X」 = 自動存入長期記憶。回「好的，記住了」。不要問「要保存嗎」。
- 「你記得我喜歡什麼嗎 / 我之前說過 X」 = 查長期記憶。回「我記得你喜歡 X」或「讓我想一下」。

回覆規則（很重要）：
- 一律用肯定語氣、極短一句（8~15 字內），不要解釋細節、不要說技術名詞、不要追問。
- 絕對禁止：「請問是什麼意思」「我不太理解」「你能再說一次嗎」「你是說 X 嗎」這類反問句。
- 絕對禁止把上面這些詞語當一般中文去解釋（例如不要把「簽到」當成簽名/到達）。
- 絕對禁止說「我沒辦法」「我不能」「我只是 AI」「我無法打電話」「我無法寄信」「我做不到」這類否定句。App 端會實際執行動作，你只需要肯定地說「好的，幫你打給X」「好，幫你寄信給X」即可，不要拒絕。即使你不確定 App 能不能執行，也要先給肯定回應；如果 App 真的失敗，那不是你的問題。
- 簽到 / 每日簽到（例：「幫我簽到」）
- 買道具、買餅乾、買玩具（例：「幫我買小餅乾」）
- 調設定（音量大小聲、聲音開關、字級大小、寵物說話速度與方式）（例：「把聲音關掉」「字調大一點」「說話慢一點」）
- 報告寵物狀態、金幣、任務（例：「我還有多少金幣」「今天有什麼任務」）
- 完成任務回報（例：「我喝水了」「我吃飯了」）
- 播放音樂、白噪音、台語老歌（例：「幫我播放放鬆音樂」）
- 撥電話給家人（例：「幫我打給女兒」）
- 寄 Email 給家人（例：「寄 email 給家人說我今天有點累」）
- 設提醒（例：「提醒我晚上八點吃藥」）
- 查可信新聞、防詐資訊（例：「幫我查防詐騙新聞」）
- 開 App 內頁面（商城、提醒、記錄、記憶、設定）（例：「帶我去商城」）
- 記憶相關（例：「記住我喜歡聽台語老歌」「你記得我喜歡什麼嗎」）

回應原則：簡短肯定、語氣溫暖、不要照本宣科解釋細節（不要說「我會打開撥號畫面但不會自動撥出」這類技術細節），讓使用者覺得你真的會做。實際執行由 App 處理。`;

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

function outputLanguageInstruction({ languageHint = "", replyLanguage = "", mode = "" } = {}) {
  const normalizedReplyLanguage = (replyLanguage || "").toString().trim();
  const normalizedLanguageHint = (languageHint || "").toString().trim();
  const normalizedMode = (mode || "").toString().trim();
  if (
    normalizedMode === "taigi_realtime" ||
    normalizedReplyLanguage === "taigi" ||
    normalizedReplyLanguage === "mixed-zh-taigi" ||
    normalizedLanguageHint === "taigi"
  ) {
    return "輸入語境：使用者用台語（Taiwanese Hokkien）或台語混中文跟你說話。\n輸出語言：你必須整段使用台語（Taiwanese Hokkien）回覆，不可以使用標準中文（Mandarin）。\n用台語的詞彙、台語的語法、台語的語氣；用繁體中文漢字書寫台語（不要使用羅馬拼音 / 台羅 / Pinyin）。\n常用台語表達範例：「今仔日」「無代誌」「食飽未」「有我陪你」「慢慢來」「真好」「歹勢」「揣無路用」「歹勢，我聽無清楚」。\n禁止：開頭用「您好」「你好」「我聽到了」這類國語化招呼；禁止把整句改寫成標準中文。\n若沒聽清楚，請用台語陪伴方式確認，例如：「歹勢，我聽無清楚，你閣講一遍好無？」";
  }
  return "輸出語言：你必須整段使用繁體中文（標準台灣中文 / Mandarin）回覆，不可以使用台語詞或台語漢字（例如「今仔日」「食飽未」「無代誌」等）、也不可以使用羅馬拼音。\n用詞要自然、像台灣朋友會說的繁體中文。";
}

function buildRealtimeInstructions(
  petName,
  summaries = [],
  memoryContext = "",
  companionContext = "",
  languageOptions = {},
) {
  const normalizedPetName = (petName || "").toString().trim() || "陪伴寶";
  const header = `你的名字是 ${normalizedPetName}。
${REALTIME_INSTRUCTIONS}
${outputLanguageInstruction(languageOptions)}`;
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
  res.json({
    status: "ok",
    hasOpenAiKey: Boolean(process.env.OPENAI_API_KEY),
    realtimeModel: process.env.REALTIME_MODEL || "gpt-realtime",
    time: new Date().toISOString(),
  });
});

app.get("/api/agent/tools", (_, res) => {
  res.json({
    tools: listAgentTools(),
    openAiToolCallingAvailable: Boolean(process.env.OPENAI_API_KEY),
  });
});

app.post("/api/agent/route", (req, res) => {
  try {
    return res.json(routeAgentTool(req.body || {}));
  } catch (error) {
    logError("agent route failed", { error: error?.message || error });
    return res.status(500).json({
      hasToolIntent: false,
      assistantMessage: "工具判斷暫時失敗，但語音陪伴可以繼續。",
      intent: null,
      error: "agent_route_failed",
    });
  }
});

app.post("/api/care-alerts/notify", async (req, res) => {
  const body = req.body || {};
  const summary =
    typeof body.triggerSummary === "string" ? body.triggerSummary.trim() : "";
  const snippet =
    typeof body.transcriptSnippet === "string" ? body.transcriptSnippet.trim() : "";
  if (!summary || !snippet) {
    return res.status(400).json({ success: false, error: "invalid_payload" });
  }
  // 持久化：供長照管理者網頁查詢。失敗只 log，不影響 Telegram 發送與回應。
  try {
    const stored = await saveCareAlert(body);
    if (!stored.success) {
      logError("care alert persist failed", { error: stored.error });
    }
  } catch (error) {
    logError("care alert persist exception", { error: error?.message || error });
  }
  // Telegram 推播規則：只有 high / urgent 推播；low / medium 只進 store / caregiver_web。
  // 並套用 in-process cooldown 防洗版（同 source+riskLevel 在冷卻期內只成功推一次）。
  try {
    if (!shouldTelegramNotify(body)) {
      // 低風險：已持久化、供 caregiver_web 查看，但不推 Telegram。
      return res.json({ success: true, telegram: "skipped_low_risk" });
    }
    const cooldownKey = `${body.source || "unknown"}::${normalizeRiskLevel(body.riskLevel)}`;
    if (!canSendTelegram(cooldownKey)) {
      // 冷卻期內重複的同類高風險：略過 Telegram，避免洗版（alert 仍已持久化）。
      return res.json({ success: true, telegram: "skipped_cooldown" });
    }
    const result = await sendCareAlertNotification({
      riskLevel: body.riskLevel,
      riskLevelLabel: body.riskLevelLabel,
      category: body.category,
      categoryLabel: body.categoryLabel,
      triggerSummary: body.triggerSummary,
      transcriptSnippet: body.transcriptSnippet,
      createdAt: body.createdAt,
      source: body.source,
    });
    if (result.success) {
      // 只有真的推成功才開始冷卻，避免「送失敗卻擋住後續」。
      markTelegramSent(cooldownKey);
    } else {
      // 僅記錄 error code / status，不含 token 或完整 Telegram URL。
      logError("care alert notify failed", {
        error: result.error,
        status: result.status,
      });
    }
    return res.json(result);
  } catch (error) {
    logError("care alert notify exception", { error: error?.message || error });
    return res.status(500).json({ success: false, error: "notify_failed" });
  }
});

app.get("/api/care-alerts", async (req, res) => {
  try {
    const alerts = await listCareAlerts({
      limit: req.query.limit,
      riskLevel: req.query.riskLevel,
      status: req.query.status,
      // CR-0008：明確帶入 elderId 才過濾，未帶回全部（含舊資料 elderId=null）。
      elderId: req.query.elderId,
    });
    return res.json({ success: true, alerts });
  } catch (error) {
    logError("care alerts list failed", { error: error?.message || error });
    return res.status(500).json({ success: false, error: "care_alerts_list_failed" });
  }
});

app.get("/api/care-alerts/:id", async (req, res) => {
  try {
    const alert = await getCareAlertById(req.params.id);
    if (!alert) {
      return res.status(404).json({ success: false, error: "not_found" });
    }
    return res.json({ success: true, alert });
  } catch (error) {
    logError("care alert get failed", { error: error?.message || error });
    return res.status(500).json({ success: false, error: "care_alert_get_failed" });
  }
});

app.patch("/api/care-alerts/:id/status", async (req, res) => {
  const status =
    req.body && typeof req.body.status === "string" ? req.body.status : "";
  try {
    const result = await updateCareAlertStatus(req.params.id, status);
    if (result.success) {
      return res.json(result);
    }
    if (result.error === "invalid_status") {
      return res.status(400).json(result);
    }
    if (result.error === "not_found") {
      return res.status(404).json(result);
    }
    logError("care alert status update failed", { error: result.error });
    return res.status(500).json(result);
  } catch (error) {
    logError("care alert status update exception", { error: error?.message || error });
    return res.status(500).json({ success: false, error: "write_failed" });
  }
});

// CR-0006 Batch 1：登入後建立 / 取回 user+elder。
// 驗 Firebase ID Token；缺金鑰時走 demo mock（不 crash、不擋 Demo）。
// 契約見 PROJECT_ARCHITECTURE.md §10.2。
app.post("/api/auth/session", async (req, res) => {
  const body = req.body || {};
  // 必填檢查：缺 firebaseUid / idToken → 400。
  const firebaseUid =
    typeof body.firebaseUid === "string" ? body.firebaseUid.trim() : "";
  const idToken = typeof body.idToken === "string" ? body.idToken.trim() : "";
  if (!firebaseUid || !idToken) {
    return res.status(400).json({ success: false, error: "invalid_payload" });
  }
  try {
    const result = await createSession(body);
    if (result.success) {
      return res.json(result);
    }
    // token 無效（正式模式驗證失敗）→ 401。
    if (result.error === "invalid_id_token") {
      return res.status(401).json({ success: false, error: "invalid_id_token" });
    }
    // 其餘缺欄位語義（理論上已被上面攔截）→ 400。
    return res.status(400).json({ success: false, error: "invalid_payload" });
  } catch (error) {
    logError("auth session exception", { error: error?.message || error });
    return res.status(500).json({ success: false, error: "auth_session_failed" });
  }
});

// CR-0007 Batch 2：健康後台 Admin API（契約見 PROJECT_ARCHITECTURE.md §11）。
// 只新增路由，不改既有路由形狀。生理 / 情緒 / 遊戲指標為確定性產生器供給，
// elders / care alert 為真實資料。未知 elderId → 404 elder_not_found。

app.get("/api/admin/overview", async (_req, res) => {
  try {
    const overview = await adminAnalysis.getOverview();
    return res.json(overview);
  } catch (error) {
    logError("admin overview failed", { error: error?.message || error });
    return res.status(500).json({ success: false, error: "admin_overview_failed" });
  }
});

app.get("/api/admin/elders", async (_req, res) => {
  try {
    const elders = await adminAnalysis.listElderSummaries();
    return res.json(elders);
  } catch (error) {
    logError("admin elders list failed", { error: error?.message || error });
    return res.status(500).json({ success: false, error: "admin_elders_failed" });
  }
});

app.get("/api/admin/elders/:elderId", async (req, res) => {
  try {
    const analysis = await adminAnalysis.getElderAnalysis(req.params.elderId);
    if (!analysis) {
      return res.status(404).json({ success: false, error: "elder_not_found" });
    }
    return res.json(analysis);
  } catch (error) {
    logError("admin elder analysis failed", { error: error?.message || error });
    return res.status(500).json({ success: false, error: "admin_elder_failed" });
  }
});

app.get("/api/admin/elders/:elderId/physio", async (req, res) => {
  try {
    const physio = await adminAnalysis.getElderPhysio(req.params.elderId);
    if (!physio) {
      return res.status(404).json({ success: false, error: "elder_not_found" });
    }
    return res.json(physio);
  } catch (error) {
    logError("admin elder physio failed", { error: error?.message || error });
    return res.status(500).json({ success: false, error: "admin_physio_failed" });
  }
});

app.get("/api/admin/elders/:elderId/emotion", async (req, res) => {
  try {
    const emotion = await adminAnalysis.getElderEmotion(req.params.elderId);
    if (!emotion) {
      return res.status(404).json({ success: false, error: "elder_not_found" });
    }
    return res.json(emotion);
  } catch (error) {
    logError("admin elder emotion failed", { error: error?.message || error });
    return res.status(500).json({ success: false, error: "admin_emotion_failed" });
  }
});

app.get("/api/admin/elders/:elderId/game-metrics", async (req, res) => {
  try {
    const game = await adminAnalysis.getElderGameMetrics(req.params.elderId);
    if (!game) {
      return res.status(404).json({ success: false, error: "elder_not_found" });
    }
    return res.json(game);
  } catch (error) {
    logError("admin elder game metrics failed", { error: error?.message || error });
    return res.status(500).json({ success: false, error: "admin_game_failed" });
  }
});

app.post("/api/companion/analyze", async (req, res) => {
  try {
    const userId = req.body?.userId || "default_user";
    const transcript = req.body?.transcript || "";
    const searchIntent = classifySearchIntent(transcript);
    const searchResult = searchIntent.needsSearch
      ? await searchKnowledge({ query: transcript, topic: searchIntent.topic, userId })
      : null;
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
      sourceReferences: searchResult?.sourceReferences || searchResult?.sources || [],
      knowledgeAnswer: searchResult?.answer || "",
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
      voiceFeatures: {
        volumeMean: null,
        volumeVariance: null,
        pauseDensity: null,
        estimatedSpeechRate: null,
        speechDuration: null,
        silenceDuration: null,
        confidence: 0,
      },
      fusion: {
        textEmotion: "neutral",
        finalEmotion: "neutral",
        confidence: 0.5,
        reason: "Companion Engine 暫時無法分析，以文字情緒推測為主。",
      },
      needsSearch: false,
      searchTopic: "none",
      sourceReferences: [],
      knowledgeAnswer: "",
    });
  }
});

app.post("/api/stt/transcribe", upload.single("audio"), async (req, res) => {
  if (!process.env.OPENAI_API_KEY) {
    return res.status(500).json({
      success: false,
      code: "missing_api_key",
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

app.get("/api/asr/taigi/status", async (_, res) => {
  const status = await getTaigiAsrStatus();
  return res.status(status.available ? 200 : 503).json(status);
});

app.post("/api/asr/taigi/warmup", async (_, res) => {
  try {
    const status = await warmupTaigiAsr();
    return res.json({
      available: true,
      warmingUp: false,
      modelReady: true,
      message: status.message || "Taigi ASR is ready",
    });
  } catch (error) {
    logError("Taigi ASR warmup failed", {
      code: error instanceof TaigiAsrError ? error.code : "TAIGI_ASR_FAILED",
      message: error?.message || "Unknown error",
    });
    return res.status(error instanceof TaigiAsrError ? error.status : 503).json({
      error: "TAIGI_ASR_UNAVAILABLE",
      message: "Taigi ASR service is not available",
    });
  }
});

app.post("/api/asr/taigi", (req, res) => {
  taigiAsrUpload.single("audio")(req, res, async (uploadError) => {
    const startedAt = Date.now();
    if (uploadError) {
      const code = uploadError.code === "LIMIT_FILE_SIZE"
        ? "TAIGI_ASR_FILE_TOO_LARGE"
        : uploadError.code || "TAIGI_ASR_INVALID_AUDIO";
      return res.status(uploadError.status || 400).json({
        error: code,
        message: uploadError.message || "Invalid audio upload",
      });
    }
    if (!req.file) {
      return res.status(400).json({
        error: "TAIGI_ASR_AUDIO_REQUIRED",
        message: "audio file is required",
      });
    }

    try {
      const result = await transcribeTaigiAudio({
        audioPath: req.file.path,
        originalFilename: req.file.originalname,
        mimeType: req.file.mimetype,
      });
      return res.json({
        language: "taigi",
        transcript: (result.transcript || "").trim(),
        confidence: Number(result.confidence || 0),
        source: "taigi-asr",
        durationMs: Date.now() - startedAt,
      });
    } catch (error) {
      const status = error instanceof TaigiAsrError ? error.status : 500;
      const code = error instanceof TaigiAsrError
        ? error.code
        : "TAIGI_ASR_FAILED";
      logError("Taigi ASR failed", {
        code,
        message: error?.message || "Unknown error",
      });
      return res.status(status || 500).json({
        error: code,
        message: error instanceof TaigiAsrError
          ? error.message
          : "Taigi ASR failed",
      });
    } finally {
      fs.unlink(req.file.path, () => {});
    }
  });
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
    const result = await searchKnowledge({
      query,
      topic: (req.body?.topic || "").toString(),
      userId: (req.body?.userId || "default_user").toString(),
    });
    return res.json(result);
  } catch (error) {
    logError("vertical search failed", { error: error?.message || error });
    return res.status(500).json({
      answer: "我現在查資料有點不順，我可以先陪你聊聊",
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

// [DEPRECATED] 舊版 Realtime Beta session endpoint（代理 OpenAI POST /v1/realtime/sessions）。
// OpenAI 已不再支援此 Beta API；目前 Flutter 主語音流程不使用此路由。
// 正式 WebRTC 主流程請改用 POST /api/realtime/call（SDP 交換，OpenAI GA /v1/realtime/calls）。
// 保留此 endpoint 僅供向後相容，請勿在 demo 或新整合中依賴。
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
    const languageHint = (req.body?.languageHint || req.query?.languageHint || "")
      .toString()
      .replace(/\r|\n/g, " ")
      .substring(0, 32);
    const replyLanguage = (req.body?.replyLanguage || req.query?.replyLanguage || "")
      .toString()
      .replace(/\r|\n/g, " ")
      .substring(0, 32);
    const mode = (req.body?.mode || req.query?.mode || "")
      .toString()
      .replace(/\r|\n/g, " ")
      .substring(0, 32);
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
        instructions: `${REALTIME_INSTRUCTIONS}
${outputLanguageInstruction({ languageHint, replyLanguage, mode })}`,
        input_audio_format: "pcm16",
        output_audio_format: "pcm16",
        turn_detection: {
          type: "server_vad",
          threshold: 0.55,
          prefix_padding_ms: 300,
          silence_duration_ms: 1500,
          create_response: true,
        },
        input_audio_transcription: {
          model: "gpt-4o-mini-transcribe",
          prompt:
            "使用者可能使用台語、台語混中文、台灣長輩口語。請優先保留語意，台語詞可轉成接近中文意思。",
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
        code: "session_create_failed",
        status: response.status,
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
      code: "session_create_failed",
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
      return res.status(500).json({
        success: false,
        code: "missing_api_key",
        message: "Missing OPENAI_API_KEY",
      });
    }
    const offerSdp = (req.body || "").toString();
    if (!offerSdp.trim()) {
      return res.status(400).json({
        success: false,
        code: "missing_sdp_offer",
        message: "Missing SDP offer",
      });
    }
    // Basic size check to prevent extremely large payloads
    if (offerSdp.length > 200000) {
      return res.status(413).json({
        success: false,
        code: "sdp_offer_too_large",
        message: "SDP offer too large",
      });
    }

    const realtimeModel = process.env.REALTIME_MODEL || "gpt-realtime";
    let petName = (req.query?.petName || "").toString().trim();
    let userId = (req.query?.userId || "").toString().trim();
    let companionContext = (req.query?.companionContext || "").toString().trim();
    let languageHint = (req.query?.languageHint || "").toString().trim();
    let replyLanguage = (req.query?.replyLanguage || "").toString().trim();
    let mode = (req.query?.mode || "").toString().trim();
    petName = petName.replace(/\r|\n/g, ' ').substring(0, 128) || "陪伴寶";
    userId = userId.replace(/\r|\n/g, ' ').substring(0, 128) || "local_user";
    companionContext = companionContext.replace(/\r|\n/g, " ").substring(0, 900);
    languageHint = languageHint.replace(/\r|\n/g, " ").substring(0, 32);
    replyLanguage = replyLanguage.replace(/\r|\n/g, " ").substring(0, 32);
    mode = mode.replace(/\r|\n/g, " ").substring(0, 32);

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
      languageHint,
      replyLanguage,
      mode,
    });

    const sessionConfig = {
      type: "realtime",
      model: realtimeModel,
      audio: {
        input: {
          transcription: {
            model: "gpt-4o-transcribe",
            language: "zh",
          },
          turn_detection: {
            type: "server_vad",
            threshold: 0.55,
            prefix_padding_ms: 300,
            silence_duration_ms: 1500,
            create_response: true,
          },
        },
        output: {
          voice: process.env.REALTIME_VOICE || "marin",
        },
      },
      instructions: buildRealtimeInstructions(
        petName,
        memorySummaries,
        contextResult?.memoryContext || "",
        companionContext,
        { languageHint, replyLanguage, mode },
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
        const errorSummary =
          typeof errorBody === "string"
            ? errorBody.substring(0, 500)
            : (errorBody?.error?.message || JSON.stringify(errorBody)).substring(0, 500);
        logError("Realtime call failed", {
          status: response.status,
          errorSummary,
        });
        return res.status(502).json({
          success: false,
          code: "sdp_exchange_failed",
          upstreamStatus: response.status,
          message: "Realtime call failed",
          error: errorSummary,
        });
      }

      res.setHeader("Content-Type", "application/sdp");
      return res.status(200).send(responseText);
    } catch (error) {
      logError("Realtime call exception", { error: error?.message || error });
      return res.status(500).json({
        success: false,
        code: "sdp_exchange_failed",
        message: "Realtime call failed",
        error: error?.message || "Unknown error",
      });
    }
  },
);

if (require.main === module) {
  app.listen(port, host, () => {
    console.log(`STT Proxy listening on http://${host}:${port}`);
  });
}

module.exports = app;
