const express = require("express");
const multer = require("multer");
const dotenv = require("dotenv");
const fs = require("fs");
const os = require("os");
const path = require("path");
const rateLimit = require('express-rate-limit');
const OpenAI = require("openai");

dotenv.config();

// CR-0034 B1：集中化環境設定 + production 啟動 fail-fast。
// 非 production / NODE_ENV=test 一律 no-op（不影響既有啟動與測試）；
// production 缺必要設定 → 印安全訊息（只列變數名稱）後 process.exit(1)。
// 啟動層行為，不改任何路由 request/response 契約。
const {
  assertProductionEnvOrExit,
  describeMaskedConfig,
  resolveCorsOrigins,
  isFeatureUnavailableError,
} = require("./config/env");
assertProductionEnvOrExit(process.env, console);

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
  deleteMemoriesByUserId,
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
  deleteAlertsByElderId,
  normalizeRiskLevel,
  RISK_LEVEL_LABELS,
} = require("./services/careAlertStoreService");
const {
  canSendTelegram,
  markTelegramSent,
} = require("./services/careAlertCooldown");
const { logNotification } = require("./services/notificationLogService");
const { logAudit } = require("./services/auditLogService");
const {
  recordConsent,
  getConsent,
} = require("./services/consentStoreService");
const {
  createSession,
  deleteUserByFirebaseUid,
  mockAllowed: authMockAllowed,
} = require("./services/auth/sessionService");
const authFirebaseAdmin = require("./services/auth/firebaseAdmin");
const {
  createTask: createDailyCareTask,
  listTasks: listDailyCareTasks,
  getTaskById: getDailyCareTaskById,
  updateTaskStatus: updateDailyCareTaskStatus,
  recordSubmission: recordDailyCareTaskSubmission,
  getSubmissionById: getDailyCareTaskSubmissionById,
  listTasksForAdmin: listDailyCareTasksForAdmin,
} = require("./services/dailyCareTask/dailyCareTaskStore");
const {
  verifyProof: verifyDailyCareTaskProof,
} = require("./services/dailyCareTask/dailyCareTaskVisionService");
const adminAnalysis = require("./services/admin/adminAnalysisService");
const requireAdmin = require("./services/admin/requireAdmin");
// CR-0040 Batch C：resident-caregiver 授權範圍過濾（純 scope 函式）。
// CR-0041 D2：caregiver-or-admin 路由改掛 resolveAdminAuthContext（路線 A：Firebase idToken
// 當 bearer / 共享 ADMIN_API_TOKEN→super_admin），把解析結果掛到 req.authContext；
// route body 依 req.authContext 角色套 scope。super_admin-only 路由仍續用 requireAdmin。
const authz = require("./services/admin/authorizationService");
const {
  resolveAdminAuthContext,
} = require("./services/admin/adminAuthContext");
// CR-0045 B2：/api/care-alerts/notify 的 resident-caller 驗證（長者本人；Firebase idToken →
// users.elder_id）。server 權威推導 elderId 蓋寫在 alert 上。
const {
  requireResidentCaller,
} = require("./services/auth/residentCallerContext");
const { listSafeUsers } = require("./services/admin/adminUsersService");
// CR-0043：caregiver 帳號 + resident-caregiver link provisioning（super_admin-only，掛 requireAdmin）。
const caregiverProvisioning = require("./services/admin/caregiverProvisioningService");
const residentLinkProvisioning = require("./services/admin/residentLinkProvisioningService");
const marketplaceStore = require("./services/marketplace/marketplaceStore");
const { safeLogPayload, safeErrorMessage } = require("./services/privacy/redaction");
const { generateCompanionReply } = require("./services/companionChatService");

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

// CR-0064：單一 CORS middleware（取代先前重複 + hardcoded 的兩段）。
// 白名單來源：CORS_ALLOWED_ORIGINS 優先，相容別名 ALLOWED_ORIGINS（見 config/env.js）。
// 規則：
//   - 帶 Origin 且在白名單 → 回對應 Access-Control-Allow-Origin（逐一比對，fail-closed，不 allow-all、不反射任意 origin）。
//   - 不帶 Origin（curl / server-to-server / health check / 原生 App）→ 放行，不回 CORS 表頭。
//   - 未授權 Origin → 不回 Access-Control-Allow-Origin，瀏覽器自然擋下。
//   - OPTIONS preflight → 一律 204。
const corsAllowedOrigins = (resolveCorsOrigins(process.env) || "")
  .split(",")
  .map((origin) => origin.trim())
  .filter(Boolean);
const corsAllowMethods = "GET, HEAD, PUT, PATCH, POST, DELETE, OPTIONS";
const corsAllowHeaders =
  "Content-Type, Authorization, X-Admin-Token, X-Requested-With";

app.use((req, res, next) => {
  const origin = req.headers.origin;

  if (origin && corsAllowedOrigins.includes(origin)) {
    res.setHeader("Access-Control-Allow-Origin", origin);
    res.setHeader("Vary", "Origin");
    res.setHeader("Access-Control-Allow-Credentials", "true");
    res.setHeader("Access-Control-Allow-Methods", corsAllowMethods);
    res.setHeader("Access-Control-Allow-Headers", corsAllowHeaders);
  }

  if (req.method === "OPTIONS") {
    return res.sendStatus(204);
  }

  return next();
});
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

// CR-0047 B2：log 附帶物件 extra 一律經 safeLogPayload 遮蔽，避免呼叫端塞入
// token / email / 完整對話 / Care Alert summary·reason 等敏感內容落 log。
// 純輸出遮蔽，不改任何呼叫端控制流 / return / throw。
function logInfo(message, extra = {}) {
  console.log(`[realtime-broker] ${message}`, safeLogPayload(extra));
}

function logError(message, extra = {}) {
  console.error(`[realtime-broker] ${message}`, safeLogPayload(extra));
}

// CR-0057：production 停用功能（marketplace / dailyCareTask JSON-only）的統一 HTTP 回應。
// 規格（architecture-agent 裁決）：
//   - status code 一律 501（所有 production 停用路徑統一，不用 403/503）。
//   - 保留各族 discriminator：marketplace 用 key='ok'、daily-care 用 key='success'。
//   - wire error 統一映為 "not_enabled"（內部 feature_unavailable_in_production 只在此邊界映射）。
//   - message 為長者 / 管理端友善白話，絕不含工程字眼 / path / stack。
// 停用是「功能未開放」而非錯誤，呼叫端不應 logError（避免假警報）。
function respondFeatureDisabled(res, { key = "ok" } = {}) {
  return res.status(501).json({
    [key]: false,
    error: "not_enabled",
    message: "這項服務目前尚未開放，請稍後再試或改用其他方式。",
  });
}

// CR-P2B：通知 / 稽核 log 寫入採 **fire-and-forget best-effort**。
// 兩 service 內部已吞掉所有錯誤並回 {success:false}（永不 reject）；此處再包一層
// .catch 保險，確保稽核寫入**絕不阻塞、絕不拖垮** /notify 與敏感操作主流程，
// 也不改任何路由的 request/response 形狀（純旁路寫入）。
function recordNotificationLog(entry) {
  Promise.resolve()
    .then(() => logNotification(entry))
    .catch((error) =>
      logError("notification log write failed", { error: error?.message || error }),
    );
}

function recordAuditLog(entry) {
  Promise.resolve()
    .then(() => logAudit(entry))
    .catch((error) =>
      logError("audit log write failed", { error: error?.message || error }),
    );
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

// CR-0050：打字閒聊（/api/companion/chat）專用陪伴型 persona。
// 與 Realtime 語音流程不同：文字 chat 不會觸發任何 App 工具，所以這裡
// 刻意不放「意義對照表」/工具清單，也不指示模型肯定地回「幫你打給X」這類
// 假裝已執行的承諾（那是語音路徑因為真的會 fire tool 才需要）。
const COMPANION_CHAT_PERSONA = `你是長者的陪伴 AI 寵物，現在是用文字訊息陪長者聊天，不是客服、不是工具助理、也不是醫師。
先接住長者當下的情緒，再回應他說的內容；像一隻熟悉他、會關心他的溫暖寵物。
回覆要簡短、自然、長者讀得懂；不要長篇大論、不要條列、不要工程術語，也不要說「我是 AI 模型」或「我只是程式」這類生硬的話。
每次回覆最多問一個問題。不要一直給建議，也不要每次都用一樣的罐頭開場白。
語氣溫暖但不誇張、不幼稚；可以稍微可愛一點點就好。

【關於 App 動作】
你只是陪長者聊天，沒有辦法真的在 App 裡幫他打電話、寄信、簽到、買東西、播音樂或設提醒。
如果長者順口提到這些事，就用溫暖的方式接住他的心意，關心他想做什麼、為什麼想做，
但不要假裝你已經幫他完成了，也不要冷冰冰地拒絕說「我做不到」「我只是 AI」。自然地陪他聊就好。

【記憶界線】
沒有相關記憶時，不要捏造長者的家人、喜好或病史，也不要說「我記得」假裝知道不存在的事。
有自然記得的近況時，可以溫柔地提到，但不要說「根據紀錄」或「資料庫顯示」。

【健康與安全】
你提供的是陪伴與照護提醒，不是醫療診斷；不要給診斷、不要開處方、不要講藥物劑量。
遇到睡不好、吃不下、身體不舒服時，先關心他的感受，再溫和建議可以記錄狀況或告訴照護人員。
但遇到胸痛、呼吸困難、跌倒、嚴重不適或自傷意念等高風險情況時，語氣要穩定但明確，
請清楚建議長者立即聯絡照護人員或尋求醫療協助，不可因為語氣溫柔就淡化緊急程度。`;

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

// CR-0050：打字閒聊 chat 專用 prompt 組裝器。純組裝、不查記憶（memoryBlock 由呼叫端傳入）。
// 與 buildRealtimeInstructions 共用同樣的「你的名字是 X。」header 與 outputLanguageInstruction
// 語言控制，但 persona 換成 COMPANION_CHAT_PERSONA（無工具清單、不假裝執行 App 動作）。
function buildCompanionChatInstructions(petName, memoryBlock, languageOptions = {}) {
  const normalizedPetName = (petName || "").toString().trim() || "陪伴寶";
  const header = `你的名字是 ${normalizedPetName}。
${COMPANION_CHAT_PERSONA}
${outputLanguageInstruction(languageOptions)}`;
  return memoryBlock ? `${header}

${memoryBlock}` : header;
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

// CR-0051 Batch A：純重構（行為零變更）。將 /api/care-alerts/notify handler 內的
// Care Alert 編排邏輯（持久化 + 通知稽核欄位推導 + Telegram 推播）抽成可重用的內部 helper，
// 讓後續批次（typed chat）能重用而不必複製約 100 行。此 helper：
//   - 只做編排，不碰 req/res、不含 auth、不重新推導或採信 client elderId；
//     呼叫端必須先把 server-authoritative 的 body.elderId 蓋寫好再傳入。
//   - 回傳 { response, careAlert }：
//       response = 與原 handler 在 200 路徑傳給 res.json(...) 完全相同的物件
//                  （skipped_low_risk / skipped_cooldown / sendCareAlertNotification 的 result）。
//       careAlert = { created, id, riskLevel }（供 Batch B 讀取持久化結果；/notify 忽略不用）。
// throw-vs-sentinel 選擇：採「helper 在非預期例外時 throw、由 handler 外層 try/catch 產生 500」。
//   原本 Telegram 區塊的 catch（logError("care alert notify exception", ...) + 500 notify_failed）
//   移到 handler 外層 try/catch；helper 內 Telegram 編排不再自帶該 catch，例外原樣往上拋，
//   handler 以相同 log 訊息 / 相同狀態碼 / 相同 response 形狀回應 → /notify 行為一字不動。
//   註：原本「持久化失敗稽核」的 recordNotificationLog 位於 Telegram try 之前（未被包覆），
//   重構後它隨 helper 一起落在 handler 外層 try/catch 內。該呼叫設計上不會 throw（DB 不可用會自動略過），
//   且測試未觸發此邊界，故行為等價成立。
async function processCareAlert(body) {
  // 持久化：供長照管理者網頁查詢。
  // CR-0034 B2：**解耦通知與持久化**——持久化失敗（含 production DB-required 失敗）
  // 絕不阻擋 high/urgent 通知、絕不假成功；失敗時於 notification_logs 明確記一列
  // （channel='care_alert_store'、outcome='persist_failed'、error_code=持久化錯誤碼），
  // 避免靜默漏記。此為旁路 side-bus 寫入，不改 /notify 的 request/response 形狀。
  let storedAlert = null;
  let persistErrorCode = null;
  try {
    const stored = await saveCareAlert(body);
    if (!stored.success) {
      persistErrorCode = stored.error || "care_alert_persist_failed";
      logError("care alert persist failed", { error: persistErrorCode });
    } else {
      storedAlert = stored.alert;
    }
  } catch (error) {
    persistErrorCode = "care_alert_persist_exception";
    logError("care alert persist exception", { error: error?.message || error });
  }
  if (persistErrorCode) {
    // 持久化失敗：明確記一列稽核（alertId 無法取得 → null；用 body.elderId 盡力標識）。
    recordNotificationLog({
      alertId: null,
      elderId: typeof body.elderId === "string" ? body.elderId : (body.elderId ?? null),
      channel: "care_alert_store",
      riskLevel: normalizeRiskLevel(body.riskLevel),
      outcome: "persist_failed",
      errorCode: persistErrorCode,
    });
  }
  // CR-P2B：通知稽核 log 共用結構化欄位（白名單；絕不含對話原文 / snippet /
  // chat_id / token / URL）。alertId / elderId 取自持久化後的 alert（DB 化後 FK 指向
  // care_alerts.id）；DB 不可用時 service 會自動略過寫入。
  const notifRiskLevel = normalizeRiskLevel(body.riskLevel);
  const notifAlertId = storedAlert?.id ?? null;
  const notifElderId = storedAlert?.elderId ?? null;
  // careAlert 編排結果（供 Batch B 讀取；不影響 /notify response）。
  const careAlert = {
    created: Boolean(storedAlert),
    id: storedAlert?.id ?? null,
    riskLevel: notifRiskLevel,
  };
  // Telegram 推播規則：只有 high / urgent 推播；low / medium 只進 store / caregiver_web。
  // 並套用 in-process cooldown 防洗版（同 source+riskLevel 在冷卻期內只成功推一次）。
  if (!shouldTelegramNotify(body)) {
    // 低風險：已持久化、供 caregiver_web 查看，但不推 Telegram。
    recordNotificationLog({
      alertId: notifAlertId,
      elderId: notifElderId,
      channel: "telegram",
      riskLevel: notifRiskLevel,
      outcome: "skipped_low_risk",
    });
    return { response: { success: true, telegram: "skipped_low_risk" }, careAlert };
  }
  const cooldownKey = `${body.source || "unknown"}::${normalizeRiskLevel(body.riskLevel)}`;
  if (!canSendTelegram(cooldownKey)) {
    // 冷卻期內重複的同類高風險：略過 Telegram，避免洗版（alert 仍已持久化）。
    recordNotificationLog({
      alertId: notifAlertId,
      elderId: notifElderId,
      channel: "telegram",
      riskLevel: notifRiskLevel,
      outcome: "skipped_cooldown",
    });
    return { response: { success: true, telegram: "skipped_cooldown" }, careAlert };
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
    recordNotificationLog({
      alertId: notifAlertId,
      elderId: notifElderId,
      channel: "telegram",
      riskLevel: notifRiskLevel,
      outcome: "sent",
    });
  } else {
    // 僅記錄 error code / status，不含 token 或完整 Telegram URL。
    logError("care alert notify failed", {
      error: result.error,
      status: result.status,
    });
    recordNotificationLog({
      alertId: notifAlertId,
      elderId: notifElderId,
      channel: "telegram",
      riskLevel: notifRiskLevel,
      outcome: "failed",
      errorCode: result.error,
      httpStatus: result.status,
    });
  }
  return { response: result, careAlert };
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

// CR-0039：此為長者端 App 建立 Care Alert + 觸發通知的核心路徑（fire-and-forget）。
// CR-0045 B2：掛 requireResidentCaller（長者本人 Firebase idToken → users.elder_id）。
//   - 無 / 無效 token → 401；查無 / 無 elder 綁定 / inactive → 403（fail-closed）。
//   - server 權威推導 elderId 並蓋寫在 alert（防偽造，順帶修復既有 elderId=null 缺口）；
//     body 帶 elderId 且與 token 推導不符 → 403 forbidden_resident。
//   - 驗證通過後，persist / cooldown / notification-log / Telegram 推播規則與
//     { success, telegram } response 形狀一字不動。
app.post("/api/care-alerts/notify", requireResidentCaller, async (req, res) => {
  const body = req.body || {};
  const summary =
    typeof body.triggerSummary === "string" ? body.triggerSummary.trim() : "";
  const snippet =
    typeof body.transcriptSnippet === "string" ? body.transcriptSnippet.trim() : "";
  if (!summary || !snippet) {
    return res.status(400).json({ success: false, error: "invalid_payload" });
  }
  // CR-0045 B2：以 caller context 的 elderId 為權威來源（server-authoritative）。
  //   - body 無 elderId → 用 token 推導（填補 elderId=null 缺口）。
  //   - body 有 elderId 且 == token 推導 → 放行。
  //   - body 有 elderId 且 != token 推導 → 403 forbidden_resident（防偽造）。
  //   一律以 token 推導值寫入 alert；client 值僅供一致性檢核，永不採信為擁有者。
  const callerElderId = (req.residentCaller && req.residentCaller.elderId) || null;
  const bodyElderId =
    typeof body.elderId === "string" && body.elderId.trim()
      ? body.elderId.trim()
      : body.elderId != null
        ? String(body.elderId)
        : null;
  if (bodyElderId != null && callerElderId != null && bodyElderId !== callerElderId) {
    return res.status(403).json({ success: false, error: "forbidden_resident" });
  }
  body.elderId = callerElderId ?? bodyElderId ?? null;
  // CR-0051 Batch A：編排邏輯抽到 processCareAlert(body)（body.elderId 此時已為 server-authoritative）。
  // helper 在非預期例外時 throw，由此外層 try/catch 產生 500，行為與重構前一字不動。
  try {
    const { response } = await processCareAlert(body);
    return res.json(response);
  } catch (error) {
    logError("care alert notify exception", { error: error?.message || error });
    return res.status(500).json({ success: false, error: "notify_failed" });
  }
});

app.get("/api/care-alerts", resolveAdminAuthContext, async (req, res) => {
  try {
    const authContext = req.authContext;
    const alerts = await listCareAlerts({
      limit: req.query.limit,
      riskLevel: req.query.riskLevel,
      status: req.query.status,
      // CR-0008：明確帶入 elderId 才過濾，未帶回全部（含舊資料 elderId=null）。
      elderId: req.query.elderId,
    });
    // CR-0040：super_admin 原樣回傳（行為零變更）；caregiver 只見授權住民。
    const scoped = await authz.filterAlertsByAuthorizedResidents(
      authContext,
      alerts,
    );
    return res.json({ success: true, alerts: scoped });
  } catch (error) {
    logError("care alerts list failed", { error: error?.message || error });
    return res.status(500).json({ success: false, error: "care_alerts_list_failed" });
  }
});

app.get("/api/care-alerts/:id", resolveAdminAuthContext, async (req, res) => {
  try {
    const authContext = req.authContext;
    const alert = await getCareAlertById(req.params.id);
    if (!alert) {
      return res.status(404).json({ success: false, error: "not_found" });
    }
    // CR-0040：super_admin 一律可存取（行為零變更）；caregiver 跨住民 → 403。
    const canAccess = await authz.assertCanAccessResident(
      authContext,
      alert.elderId,
    );
    if (!canAccess) {
      return res.status(403).json({ success: false, error: "forbidden" });
    }
    return res.json({ success: true, alert });
  } catch (error) {
    logError("care alert get failed", { error: error?.message || error });
    return res.status(500).json({ success: false, error: "care_alert_get_failed" });
  }
});

app.patch("/api/care-alerts/:id/status", resolveAdminAuthContext, async (req, res) => {
  const status =
    req.body && typeof req.body.status === "string" ? req.body.status : "";
  try {
    // CR-0040：caregiver 須先通過授權檢查（跨住民 → 403）。super_admin 跳過此前置讀取，
    // 保持原流程與 response 完全不變（行為零變更）。
    const authContext = req.authContext;
    if (!authz.isSuperAdmin(authContext)) {
      const existing = await getCareAlertById(req.params.id);
      if (!existing) {
        return res.status(404).json({ success: false, error: "not_found" });
      }
      const canAccess = await authz.assertCanAccessResident(
        authContext,
        existing.elderId,
      );
      if (!canAccess) {
        return res.status(403).json({ success: false, error: "forbidden" });
      }
    }
    const result = await updateCareAlertStatus(req.params.id, status);
    if (result.success) {
      // CR-P2B：Care Alert 狀態變更為敏感操作 → best-effort 稽核。metadata 僅
      // 結構化（to status）；無原文 / PII。
      // CR-0041：actorId 取 authContext.userId（super_admin 共享 token 為 null；
      // caregiver / DB-admin 為 users.id，純識別子、非 PII）。
      recordAuditLog({
        actorType: authContext.role === authz.ROLE_CAREGIVER ? "caregiver" : "admin",
        actorId: authContext.userId ?? null,
        action: "care_alert_status_change",
        targetType: "care_alert",
        targetId: req.params.id,
        outcome: "success",
        metadata: { toStatus: result.alert?.status ?? status },
      });
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

// CR-0024：刪除帳號並清除該使用者後端所有資料（user / elder / 長期記憶 / Care
// Alert）。驗證邏輯比照 /api/auth/session：firebase configured → 驗 idToken 取
// 權威 uid；否則（允許 mock）採信傳入 firebaseUid。找不到 user → idempotent 回
// 成功（deleted 全 0）。前端在使用者刪除帳號時呼叫，best-effort（前端不因此擋住
// Firebase 帳號刪除）。只新增路由、不改既有路由形狀。
app.post("/api/auth/delete", async (req, res) => {
  const body = req.body || {};
  const rawUid =
    typeof body.firebaseUid === "string" ? body.firebaseUid.trim() : "";
  const idToken = typeof body.idToken === "string" ? body.idToken.trim() : "";
  if (!rawUid || !idToken) {
    return res.status(400).json({ success: false, error: "invalid_payload" });
  }

  try {
    // 決定權威 uid（與 createSession 一致）。
    let firebaseUid = rawUid;
    const configured = (() => {
      try {
        return authFirebaseAdmin.isConfigured();
      } catch (_) {
        return false;
      }
    })();
    if (configured) {
      const decoded = await authFirebaseAdmin.verifyIdToken(idToken);
      if (!decoded || !decoded.uid) {
        return res
          .status(401)
          .json({ success: false, error: "invalid_id_token" });
      }
      firebaseUid = decoded.uid; // 以驗證後的 uid 為權威，避免偽造。
    } else if (!authMockAllowed()) {
      return res
        .status(401)
        .json({ success: false, error: "invalid_id_token" });
    }

    // 1. 刪 user + elder，取回被刪的 userId / elderId 以級聯刪除其資料。
    const userResult = await deleteUserByFirebaseUid(firebaseUid);

    // 2. 級聯刪除長期記憶（依 userId）與 Care Alert（依 elderId）。
    //    找不到 user 時 userId/elderId 為 null → 級聯為 0（idempotent）。
    let memories = 0;
    let careAlerts = 0;
    if (userResult.userId != null) {
      memories = await deleteMemoriesByUserId(userResult.userId);
    }
    if (userResult.elderId != null) {
      careAlerts = await deleteAlertsByElderId(userResult.elderId);
    }

    // CR-P2B：帳號刪除為敏感操作 → best-effort 稽核。actorId/targetId 用內部
    // user_id（非 PII 明碼）；metadata 僅刪除計數；無 email / ip / token / 原文。
    recordAuditLog({
      actorType: "elder",
      actorId: userResult.userId != null ? String(userResult.userId) : null,
      action: "account_delete",
      targetType: "user",
      targetId: userResult.userId != null ? String(userResult.userId) : null,
      outcome: "success",
      metadata: {
        user: userResult.user,
        elder: userResult.elder,
        memories,
        careAlerts,
      },
    });

    return res.json({
      success: true,
      deleted: {
        user: userResult.user,
        elder: userResult.elder,
        memories,
        careAlerts,
      },
    });
  } catch (error) {
    logError("auth delete exception", { error: error?.message || error });
    return res.status(500).json({ success: false, error: "auth_delete_failed" });
  }
});

// CR-0036 Batch 2：知情同意稽核 API。契約見 PROJECT_ARCHITECTURE.md §10.4。
// 身份辨識沿用既有中介（比照 /api/auth/delete）：firebase configured → 驗 idToken
// 取權威 uid；否則 mock-allowed → 採信傳入識別。只新增路由、不改既有路由形狀。

// 決定權威 firebaseUid（與 /api/auth/delete / createSession 一致）。
// 回 { ok:true, firebaseUid } 或 { ok:false }（→ 401 invalid_id_token）。
async function resolveConsentIdentity(rawUid, idToken, { requireToken }) {
  const configured = (() => {
    try {
      return authFirebaseAdmin.isConfigured();
    } catch (_) {
      return false;
    }
  })();
  if (configured) {
    // configured 模式：POST 一律驗 token；GET 僅在有帶 idToken 時驗。
    if (requireToken || idToken) {
      const decoded = await authFirebaseAdmin.verifyIdToken(idToken);
      if (!decoded || !decoded.uid) {
        return { ok: false };
      }
      return { ok: true, firebaseUid: decoded.uid };
    }
    return { ok: true, firebaseUid: rawUid };
  }
  // 未 configured：mock 不允許 → 無法驗證，視為 401。
  if (!authMockAllowed()) {
    return { ok: false };
  }
  return { ok: true, firebaseUid: rawUid };
}

// 記錄一次同意 / 撤回（寫一列，append-only）。
app.post("/api/consent", async (req, res) => {
  const body = req.body || {};
  const consentType =
    typeof body.consentType === "string" ? body.consentType.trim() : "";
  const consentVersion =
    typeof body.consentVersion === "string" ? body.consentVersion.trim() : "";
  if (!consentType || !consentVersion) {
    return res.status(400).json({ success: false, error: "invalid_payload" });
  }

  try {
    const rawUid =
      typeof body.firebaseUid === "string" ? body.firebaseUid.trim() : "";
    const idToken = typeof body.idToken === "string" ? body.idToken.trim() : "";
    const identity = await resolveConsentIdentity(rawUid, idToken, {
      requireToken: true,
    });
    if (!identity.ok) {
      return res
        .status(401)
        .json({ success: false, error: "invalid_id_token" });
    }

    const result = await recordConsent({
      userId: body.userId,
      elderId: body.elderId,
      firebaseUid: identity.firebaseUid,
      consentType,
      consentVersion,
      action: body.action,
      source: body.source,
      appVersion: body.appVersion,
      platform: body.platform,
      agreedAt: body.agreedAt,
      // PII：後端從 request 自行擷取，僅落 DB 供稽核；body 不接受、回應/log 不回顯。
      ip: req.ip,
      userAgent: req.headers["user-agent"],
    });

    if (!result.success) {
      if (result.error === "invalid_payload") {
        return res
          .status(400)
          .json({ success: false, error: "invalid_payload" });
      }
      logError("consent record failed", { error: result.error });
      return res.status(500).json({ success: false, error: "consent_failed" });
    }
    // CR-P2B：consent 寫入為敏感操作 → best-effort 稽核。targetId 用 consent record
    // id；metadata 僅結構化（type / version / action）；無原文 / email / ip / token。
    recordAuditLog({
      actorType: "elder",
      actorId:
        typeof identity.firebaseUid === "string" && identity.firebaseUid.trim()
          ? identity.firebaseUid.trim()
          : null,
      action: "consent_record",
      targetType: "consent_record",
      targetId: result.record?.id ?? null,
      outcome: "success",
      metadata: {
        consentType: result.record?.consentType,
        consentVersion: result.record?.consentVersion,
        action: result.record?.action,
      },
    });
    return res.json({ success: true, record: result.record });
  } catch (error) {
    logError("consent record exception", { error: error?.message || error });
    return res.status(500).json({ success: false, error: "consent_failed" });
  }
});

// 查詢某使用者目前同意狀態 + 稽核歷史（遮蔽 PII）。
app.get("/api/consent", async (req, res) => {
  const q = req.query || {};
  const userId = typeof q.userId === "string" ? q.userId.trim() : "";
  const elderId = typeof q.elderId === "string" ? q.elderId.trim() : "";
  const rawUid =
    typeof q.firebaseUid === "string" ? q.firebaseUid.trim() : "";
  if (!userId && !elderId && !rawUid) {
    return res.status(400).json({ success: false, error: "invalid_payload" });
  }

  try {
    const idToken = typeof q.idToken === "string" ? q.idToken.trim() : "";
    // GET：firebase configured 且有帶 idToken 時驗證（取權威 uid）；未帶不強制。
    const identity = await resolveConsentIdentity(rawUid, idToken, {
      requireToken: false,
    });
    if (!identity.ok) {
      return res
        .status(401)
        .json({ success: false, error: "invalid_id_token" });
    }

    const result = await getConsent({
      userId,
      elderId,
      firebaseUid: identity.firebaseUid,
    });
    if (!result.success) {
      if (result.error === "invalid_payload") {
        return res
          .status(400)
          .json({ success: false, error: "invalid_payload" });
      }
      logError("consent get failed", { error: result.error });
      return res.status(500).json({ success: false, error: "consent_failed" });
    }
    return res.json({
      success: true,
      current: result.current,
      history: result.history,
    });
  } catch (error) {
    logError("consent get exception", { error: error?.message || error });
    return res.status(500).json({ success: false, error: "consent_failed" });
  }
});

// CR-0025 日常照護任務（Daily Care Task）：長者端拍照打卡 + AI 影像確認 +
// 管理者端追蹤。與既有遊戲化 CareTask 不同功能，獨立 daily care task 命名。
// 只新增路由，不改既有路由形狀。資料走 JSON store（runtime、不進版控）。

// 長者端：取得某長者的日常任務列表。
app.get("/api/daily-care-tasks", async (req, res) => {
  try {
    const elderId =
      typeof req.query.elderId === "string" && req.query.elderId.trim()
        ? req.query.elderId.trim()
        : null;
    const status =
      typeof req.query.status === "string" && req.query.status.trim()
        ? req.query.status.trim()
        : null;
    const tasks = await listDailyCareTasks({ elderId, status });
    return res.json({ success: true, tasks });
  } catch (error) {
    if (isFeatureUnavailableError(error)) return respondFeatureDisabled(res, { key: "success" });
    logError("daily care tasks list exception", {
      error: error?.message || error,
    });
    return res
      .status(500)
      .json({ success: false, error: "daily_care_tasks_list_failed" });
  }
});

// 建立任務（Agent / 管理者 / 種子資料可用）。
app.post("/api/daily-care-tasks", async (req, res) => {
  const body = req.body || {};
  const title = typeof body.title === "string" ? body.title.trim() : "";
  if (!title) {
    return res.status(400).json({ success: false, error: "invalid_payload" });
  }
  try {
    const task = await createDailyCareTask(body);
    return res.json({ success: true, task });
  } catch (error) {
    if (isFeatureUnavailableError(error)) return respondFeatureDisabled(res, { key: "success" });
    logError("daily care task create exception", {
      error: error?.message || error,
    });
    return res
      .status(500)
      .json({ success: false, error: "daily_care_task_create_failed" });
  }
});

// 長者端：上傳完成照片 → AI Vision 確認 → 更新任務狀態。
// AI 不確定 / 失敗 / 缺 key → needs_review（不 fake passed、不 crash）。
app.post(
  "/api/daily-care-tasks/:id/submit",
  upload.single("photo"),
  async (req, res) => {
    const taskId = req.params.id;
    const cleanup = () => {
      // 驗證失敗或找不到任務時清掉暫存檔；成功時保留供管理者查看（uploads/ 不進版控）。
      if (req.file) fs.unlink(req.file.path, () => {});
    };
    try {
      const task = await getDailyCareTaskById(taskId);
      if (!task) {
        cleanup();
        return res
          .status(404)
          .json({ success: false, error: "task_not_found" });
      }
      if (!req.file) {
        return res
          .status(400)
          .json({ success: false, error: "photo_required" });
      }

      const verification = await verifyDailyCareTaskProof({
        taskType: task.type,
        imagePath: req.file.path,
        mimeType: req.file.mimetype,
      });

      const result = await recordDailyCareTaskSubmission(taskId, {
        proofImagePath: req.file.path,
        proofMimeType: req.file.mimetype,
        verification,
        note: typeof req.body?.note === "string" ? req.body.note : "",
      });

      return res.json({
        success: true,
        task: result.task,
        submission: result.submission,
      });
    } catch (error) {
      cleanup();
      if (isFeatureUnavailableError(error)) return respondFeatureDisabled(res, { key: "success" });
      logError("daily care task submit exception", {
        error: error?.message || error,
      });
      return res
        .status(500)
        .json({ success: false, error: "daily_care_task_submit_failed" });
    }
  },
);

// 管理者 / 系統：更新任務狀態（如人工查看後 completed / rejected）。
app.patch("/api/daily-care-tasks/:id/status", async (req, res) => {
  const status =
    typeof req.body?.status === "string" ? req.body.status.trim() : "";
  try {
    const result = await updateDailyCareTaskStatus(req.params.id, status);
    if (!result.success) {
      if (isFeatureUnavailableError(result)) return respondFeatureDisabled(res, { key: "success" });
      const code = result.error === "not_found" ? 404 : 400;
      return res.status(code).json({ success: false, error: result.error });
    }
    return res.json({ success: true, task: result.task });
  } catch (error) {
    logError("daily care task status exception", {
      error: error?.message || error,
    });
    return res
      .status(500)
      .json({ success: false, error: "daily_care_task_status_failed" });
  }
});

// 管理者端：列出所有任務 + 每筆最新 submission（含 AI 結果），供 caregiver_web。
// CR-0041 D2：套 resident scope（CR-0040 §14 Batch D 硬前置 BLOCKER）。
//   - super_admin → 全量（行為零變更）。
//   - caregiver   → 只見授權住民的任務；若帶 elderId 但非授權 → 403；無授權 → 空陣列。
app.get("/api/admin/daily-care-tasks", resolveAdminAuthContext, async (req, res) => {
  try {
    const authContext = req.authContext;
    const elderId =
      typeof req.query.elderId === "string" && req.query.elderId.trim()
        ? req.query.elderId.trim()
        : null;
    const status =
      typeof req.query.status === "string" && req.query.status.trim()
        ? req.query.status.trim()
        : null;

    if (authz.isSuperAdmin(authContext)) {
      const tasks = await listDailyCareTasksForAdmin({ elderId, status });
      return res.json({ success: true, tasks });
    }

    // caregiver：若指定 elderId，須在授權範圍內（跨住民 → 403）。
    if (elderId) {
      const ok = await authz.assertCanAccessResident(authContext, elderId);
      if (!ok) {
        return res.status(403).json({ success: false, error: "forbidden" });
      }
      const tasks = await listDailyCareTasksForAdmin({ elderId, status });
      return res.json({ success: true, tasks });
    }

    // 未指定 elderId：取全部後依授權住民過濾（無授權 → 空陣列，fail-closed）。
    const authorized = await authz.getAuthorizedResidentIdsForCaregiver(
      authContext.caregiverId,
    );
    const all = await listDailyCareTasksForAdmin({ elderId: null, status });
    const tasks = (all || []).filter(
      (task) => task && task.elderId != null && authorized.has(task.elderId),
    );
    return res.json({ success: true, tasks });
  } catch (error) {
    if (isFeatureUnavailableError(error)) return respondFeatureDisabled(res, { key: "success" });
    logError("admin daily care tasks exception", {
      error: error?.message || error,
    });
    return res
      .status(500)
      .json({ success: false, error: "admin_daily_care_tasks_failed" });
  }
});

// 照片證明檢視入口（長者預覽 / 管理者查看）。只回 uploads/ 內的安全路徑。
app.get("/api/daily-care-tasks/proof/:submissionId", async (req, res) => {
  try {
    const submission = await getDailyCareTaskSubmissionById(
      req.params.submissionId,
    );
    if (!submission || !submission.proofImagePath) {
      return res.status(404).json({ success: false, error: "proof_not_found" });
    }
    const resolved = path.resolve(submission.proofImagePath);
    const uploadsRoot = path.resolve(path.join(__dirname, "uploads"));
    // 安全：只允許讀 uploads/ 內的檔案，避免路徑穿越。
    if (!resolved.startsWith(uploadsRoot + path.sep)) {
      return res.status(404).json({ success: false, error: "proof_not_found" });
    }
    if (!fs.existsSync(resolved)) {
      return res.status(404).json({ success: false, error: "proof_not_found" });
    }
    return res.sendFile(resolved);
  } catch (error) {
    if (isFeatureUnavailableError(error)) return respondFeatureDisabled(res, { key: "success" });
    logError("daily care task proof exception", {
      error: error?.message || error,
    });
    return res
      .status(500)
      .json({ success: false, error: "daily_care_task_proof_failed" });
  }
});

// CR-0007 Batch 2：健康後台 Admin API（契約見 PROJECT_ARCHITECTURE.md §11）。
// 只新增路由，不改既有路由形狀。生理 / 情緒 / 遊戲指標為確定性產生器供給，
// elders / care alert 為真實資料。未知 elderId → 404 elder_not_found。

app.get("/api/admin/overview", requireAdmin, async (_req, res) => {
  try {
    const overview = await adminAnalysis.getOverview();
    return res.json(overview);
  } catch (error) {
    logError("admin overview failed", { error: error?.message || error });
    return res.status(500).json({ success: false, error: "admin_overview_failed" });
  }
});

app.get("/api/admin/elders", resolveAdminAuthContext, async (req, res) => {
  try {
    const authContext = req.authContext;
    const elders = await adminAnalysis.listElderSummaries();
    // CR-0040：super_admin 不變；caregiver 只回授權住民。
    if (authz.isSuperAdmin(authContext)) {
      return res.json(elders);
    }
    const ids = await authz.getAuthorizedResidentIdsForCaregiver(
      authContext.caregiverId,
    );
    return res.json(elders.filter((row) => row && ids.has(row.elderId)));
  } catch (error) {
    logError("admin elders list failed", { error: error?.message || error });
    return res.status(500).json({ success: false, error: "admin_elders_failed" });
  }
});

app.get("/api/admin/elders/:elderId", resolveAdminAuthContext, async (req, res) => {
  try {
    // CR-0040：caregiver 跨住民 → 403；super_admin 不變。
    const authContext = req.authContext;
    if (!authz.isSuperAdmin(authContext)) {
      const ok = await authz.assertCanAccessResident(authContext, req.params.elderId);
      if (!ok) {
        return res.status(403).json({ success: false, error: "forbidden" });
      }
    }
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

app.get("/api/admin/elders/:elderId/physio", resolveAdminAuthContext, async (req, res) => {
  try {
    // CR-0040：caregiver 跨住民 → 403；super_admin 不變。
    const authContext = req.authContext;
    if (!authz.isSuperAdmin(authContext)) {
      const ok = await authz.assertCanAccessResident(authContext, req.params.elderId);
      if (!ok) {
        return res.status(403).json({ success: false, error: "forbidden" });
      }
    }
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

app.get("/api/admin/elders/:elderId/emotion", resolveAdminAuthContext, async (req, res) => {
  try {
    // CR-0040：caregiver 跨住民 → 403；super_admin 不變。
    const authContext = req.authContext;
    if (!authz.isSuperAdmin(authContext)) {
      const ok = await authz.assertCanAccessResident(authContext, req.params.elderId);
      if (!ok) {
        return res.status(403).json({ success: false, error: "forbidden" });
      }
    }
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

app.get("/api/admin/elders/:elderId/game-metrics", resolveAdminAuthContext, async (req, res) => {
  try {
    // CR-0040：caregiver 跨住民 → 403；super_admin 不變。
    const authContext = req.authContext;
    if (!authz.isSuperAdmin(authContext)) {
      const ok = await authz.assertCanAccessResident(authContext, req.params.elderId);
      if (!ok) {
        return res.status(403).json({ success: false, error: "forbidden" });
      }
    }
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

// CR-0029：管理者端使用者帳戶清單。受 requireAdmin 保護，資料只來自 PostgreSQL，
// 只回安全欄位、Email 已遮蔽，不回傳 password_hash / provider_user_id / token。
// 不使用 JSON fallback：PG 不可用即回 500 failed_to_load_users。
app.get("/api/admin/users", requireAdmin, async (_req, res) => {
  try {
    const users = await listSafeUsers();
    return res.json({ ok: true, users });
  } catch (error) {
    logError("admin users list failed", { error: error?.message || error });
    return res.status(500).json({ ok: false, error: "failed_to_load_users" });
  }
});

// ---- CR-0043：Caregiver 帳號 + Resident-Caregiver Link Provisioning（super_admin-only）----
//
// 全部掛 requireAdmin（共享 super_admin token only，fail-closed）：caregiver 持有效 idToken 也進不來
// （requireAdmin 只認字面 ADMIN_API_TOKEN）。契約見 docs/CHANGE_REVIEW.md CR-0043 與
// docs/CAREGIVER_PROVISIONING.md。每筆建立/修改/停用皆寫 logAudit（actorType=super_admin、
// actorId=null〔共享 token 無 per-actor 身分〕、metadata 無 PII / 無 token / 無 email 原文）。
//
// 安全：service 對外只回安全欄位（emailMasked / firebaseUid / status…），絕不回 password_hash /
// provider_user_id / token。失敗只回 { ok:false, error }，不外洩工程細節 / stack。

// 建立/修改/停用各類錯誤 → HTTP 狀態碼對映（client error vs server error）。
const CAREGIVER_CLIENT_ERRORS = {
  email_required: 400,
  invalid_payload: 400,
  invalid_status: 400,
  email_exists: 409,
  not_found: 404,
};
const LINK_CLIENT_ERRORS = {
  invalid_payload: 400,
  invalid_role: 400,
  invalid_status: 400,
  resident_not_found: 404,
  caregiver_not_found: 404,
  link_exists: 409,
  not_found: 404,
};

function provisioningStatusCode(error, map) {
  return map[error] || 500;
}

// 寫 provisioning 稽核（best-effort，metadata 只放結構化非敏感欄位）。
function auditProvisioning(action, targetType, targetId, outcome, metadata = {}) {
  // 不 await：稽核失敗絕不拖垮主流程（auditLogService 本身 best-effort、絕不丟例外）。
  logAudit({
    actorType: "super_admin",
    actorId: null, // 共享 token 無 per-actor 身分（CR-0043 §3 #3 誠實標註）。
    action,
    targetType,
    targetId: targetId == null ? null : String(targetId),
    outcome,
    metadata,
  }).catch(() => {});
}

// --- Caregiver 帳號 ---

app.get("/api/admin/caregivers", requireAdmin, async (_req, res) => {
  try {
    const caregivers = await caregiverProvisioning.listCaregivers();
    return res.json({ ok: true, caregivers });
  } catch (error) {
    logError("admin caregivers list failed", { error: error?.message || error });
    return res.status(500).json({ ok: false, error: "failed_to_load_caregivers" });
  }
});

app.post("/api/admin/caregivers", requireAdmin, async (req, res) => {
  const body = req.body || {};
  let result;
  try {
    result = await caregiverProvisioning.createCaregiver({
      email: body.email,
      displayName: body.displayName,
      firebaseUid: body.firebaseUid,
    });
  } catch (error) {
    logError("admin caregiver create failed", { error: error?.message || error });
    return res.status(500).json({ ok: false, error: "failed_to_create_caregiver" });
  }
  if (result.ok) {
    auditProvisioning("caregiver_create", "caregiver", result.caregiver.id, "success", {
      bound: result.caregiver.firebaseUid != null,
      status: result.caregiver.status,
    });
    return res.status(201).json(result);
  }
  auditProvisioning("caregiver_create", "caregiver", null, "failed", { reason: result.error });
  return res.status(provisioningStatusCode(result.error, CAREGIVER_CLIENT_ERRORS)).json(result);
});

app.patch("/api/admin/caregivers/:id", requireAdmin, async (req, res) => {
  const body = req.body || {};
  const input = {};
  if (body.displayName !== undefined) input.displayName = body.displayName;
  if (body.email !== undefined) input.email = body.email;
  if (body.firebaseUid !== undefined) input.firebaseUid = body.firebaseUid;
  let result;
  try {
    result = await caregiverProvisioning.updateCaregiver(req.params.id, input);
  } catch (error) {
    logError("admin caregiver update failed", { error: error?.message || error });
    return res.status(500).json({ ok: false, error: "failed_to_update_caregiver" });
  }
  if (result.ok) {
    auditProvisioning("caregiver_update", "caregiver", req.params.id, "success", {
      fields: Object.keys(input),
      bound: result.caregiver.firebaseUid != null,
    });
    return res.json(result);
  }
  auditProvisioning("caregiver_update", "caregiver", req.params.id, "failed", {
    reason: result.error,
  });
  return res.status(provisioningStatusCode(result.error, CAREGIVER_CLIENT_ERRORS)).json(result);
});

app.patch("/api/admin/caregivers/:id/status", requireAdmin, async (req, res) => {
  const status = req.body && typeof req.body.status === "string" ? req.body.status : "";
  let result;
  try {
    result = await caregiverProvisioning.setCaregiverStatus(req.params.id, status);
  } catch (error) {
    logError("admin caregiver status failed", { error: error?.message || error });
    return res.status(500).json({ ok: false, error: "failed_to_update_caregiver" });
  }
  if (result.ok) {
    auditProvisioning("caregiver_status_change", "caregiver", req.params.id, "success", {
      status: result.caregiver.status,
    });
    return res.json(result);
  }
  auditProvisioning("caregiver_status_change", "caregiver", req.params.id, "failed", {
    reason: result.error,
  });
  return res.status(provisioningStatusCode(result.error, CAREGIVER_CLIENT_ERRORS)).json(result);
});

// --- Resident-Caregiver Link ---

app.get("/api/admin/resident-caregiver-links", requireAdmin, async (_req, res) => {
  try {
    const links = await residentLinkProvisioning.listLinks();
    return res.json({ ok: true, links });
  } catch (error) {
    logError("admin links list failed", { error: error?.message || error });
    return res.status(500).json({ ok: false, error: "failed_to_load_links" });
  }
});

app.post("/api/admin/resident-caregiver-links", requireAdmin, async (req, res) => {
  const body = req.body || {};
  let result;
  try {
    result = await residentLinkProvisioning.createLink({
      residentId: body.residentId,
      caregiverId: body.caregiverId,
      role: body.role,
    });
  } catch (error) {
    logError("admin link create failed", { error: error?.message || error });
    return res.status(500).json({ ok: false, error: "failed_to_create_link" });
  }
  if (result.ok) {
    auditProvisioning("link_create", "resident_caregiver_link", result.link.id, "success", {
      role: result.link.role,
      status: result.link.status,
    });
    return res.status(201).json(result);
  }
  auditProvisioning("link_create", "resident_caregiver_link", null, "failed", {
    reason: result.error,
  });
  return res.status(provisioningStatusCode(result.error, LINK_CLIENT_ERRORS)).json(result);
});

app.patch("/api/admin/resident-caregiver-links/:id", requireAdmin, async (req, res) => {
  const role = req.body && typeof req.body.role === "string" ? req.body.role : "";
  let result;
  try {
    result = await residentLinkProvisioning.updateLinkRole(req.params.id, role);
  } catch (error) {
    logError("admin link update failed", { error: error?.message || error });
    return res.status(500).json({ ok: false, error: "failed_to_update_link" });
  }
  if (result.ok) {
    auditProvisioning("link_update", "resident_caregiver_link", req.params.id, "success", {
      role: result.link.role,
    });
    return res.json(result);
  }
  auditProvisioning("link_update", "resident_caregiver_link", req.params.id, "failed", {
    reason: result.error,
  });
  return res.status(provisioningStatusCode(result.error, LINK_CLIENT_ERRORS)).json(result);
});

// 停用授權關聯（soft-disable = status revoked）。DELETE 語意 = 停用，不實刪資料（保留稽核軌跡）。
app.delete("/api/admin/resident-caregiver-links/:id", requireAdmin, async (req, res) => {
  let result;
  try {
    result = await residentLinkProvisioning.setLinkStatus(req.params.id, "inactive");
  } catch (error) {
    logError("admin link disable failed", { error: error?.message || error });
    return res.status(500).json({ ok: false, error: "failed_to_update_link" });
  }
  if (result.ok) {
    auditProvisioning("link_status_change", "resident_caregiver_link", req.params.id, "success", {
      status: result.link.status,
    });
    return res.json(result);
  }
  auditProvisioning("link_status_change", "resident_caregiver_link", req.params.id, "failed", {
    reason: result.error,
  });
  return res.status(provisioningStatusCode(result.error, LINK_CLIENT_ERRORS)).json(result);
});

// ---- CR-0032 長照商品商城（Marketplace）----
//
// 長者端（公開）：瀏覽商品、建立訂單。
// 管理端（requireAdmin）：商品 CRUD / 上下架、訂單查詢 / 改狀態。
// 金額一律由 store 依當下商品重算，前端帶入的價格不被信任。
// 失敗只回 {ok:false,error}，長者端服務層會轉成白話訊息，不外洩工程細節。

// 長者端商品列表。預設只回 active；?status=all/inactive 供管理端使用；?category 可篩分類。
app.get("/api/marketplace/products", async (req, res) => {
  try {
    const products = await marketplaceStore.listProducts({
      status: typeof req.query.status === "string" ? req.query.status : "",
      category: typeof req.query.category === "string" ? req.query.category : "",
    });
    return res.json({ ok: true, products });
  } catch (error) {
    if (isFeatureUnavailableError(error)) return respondFeatureDisabled(res, { key: "ok" });
    logError("marketplace list products failed", { error: error?.message || error });
    return res.status(500).json({ ok: false, error: "failed_to_load_products" });
  }
});

app.get("/api/marketplace/products/:id", async (req, res) => {
  try {
    const product = await marketplaceStore.getProductById(req.params.id);
    if (!product) return res.status(404).json({ ok: false, error: "not_found" });
    return res.json({ ok: true, product });
  } catch (error) {
    if (isFeatureUnavailableError(error)) return respondFeatureDisabled(res, { key: "ok" });
    logError("marketplace get product failed", { error: error?.message || error });
    return res.status(500).json({ ok: false, error: "failed_to_load_product" });
  }
});

// 管理端：新增商品。
app.post("/api/admin/marketplace/products", requireAdmin, async (req, res) => {
  const result = await marketplaceStore.createProduct(req.body || {});
  if (result.ok) return res.json(result);
  if (isFeatureUnavailableError(result)) return respondFeatureDisabled(res, { key: "ok" });
  const code = result.error === "invalid_payload" ? 400 : 500;
  return res.status(code).json(result);
});

// 管理端：編輯商品（整筆更新）。
app.put("/api/admin/marketplace/products/:id", requireAdmin, async (req, res) => {
  const result = await marketplaceStore.updateProduct(req.params.id, req.body || {});
  if (result.ok) return res.json(result);
  if (isFeatureUnavailableError(result)) return respondFeatureDisabled(res, { key: "ok" });
  const code = result.error === "not_found" ? 404 : 500;
  return res.status(code).json(result);
});

// 管理端：商品上 / 下架。
app.patch(
  "/api/admin/marketplace/products/:id/status",
  requireAdmin,
  async (req, res) => {
    const status = req.body && typeof req.body.status === "string" ? req.body.status : "";
    const result = await marketplaceStore.setProductStatus(req.params.id, status);
    if (result.ok) return res.json(result);
    if (isFeatureUnavailableError(result)) return respondFeatureDisabled(res, { key: "ok" });
    const code =
      result.error === "not_found"
        ? 404
        : result.error === "invalid_status"
          ? 400
          : 500;
    return res.status(code).json(result);
  },
);

// 長者端：建立訂單。store 會重算金額、驗證庫存與同一長照中心、扣庫存。
app.post("/api/marketplace/orders", async (req, res) => {
  const body = req.body || {};
  const result = await marketplaceStore.createOrder({
    userId: body.userId,
    elderName: body.elderName,
    deliveryNote: body.deliveryNote,
    items: Array.isArray(body.items) ? body.items : [],
  });
  if (result.ok) return res.json(result);
  if (isFeatureUnavailableError(result)) return respondFeatureDisabled(res, { key: "ok" });
  const clientErrors = new Set([
    "empty_cart",
    "invalid_item",
    "product_not_found",
    "product_unavailable",
    "insufficient_stock",
    "multiple_centers",
  ]);
  const code = clientErrors.has(result.error) ? 400 : 500;
  return res.status(code).json(result);
});

// 管理端：訂單列表（?status 篩選）。
app.get("/api/admin/marketplace/orders", requireAdmin, async (req, res) => {
  try {
    const orders = await marketplaceStore.listOrders({
      status: typeof req.query.status === "string" ? req.query.status : "",
    });
    return res.json({ ok: true, orders });
  } catch (error) {
    if (isFeatureUnavailableError(error)) return respondFeatureDisabled(res, { key: "ok" });
    logError("marketplace list orders failed", { error: error?.message || error });
    return res.status(500).json({ ok: false, error: "failed_to_load_orders" });
  }
});

// 管理端：訂單詳情。
app.get("/api/admin/marketplace/orders/:id", requireAdmin, async (req, res) => {
  try {
    const order = await marketplaceStore.getOrderById(req.params.id);
    if (!order) return res.status(404).json({ ok: false, error: "not_found" });
    return res.json({ ok: true, order });
  } catch (error) {
    if (isFeatureUnavailableError(error)) return respondFeatureDisabled(res, { key: "ok" });
    logError("marketplace get order failed", { error: error?.message || error });
    return res.status(500).json({ ok: false, error: "failed_to_load_order" });
  }
});

// 管理端：更新訂單狀態（可一併填配送備註）。
app.patch(
  "/api/admin/marketplace/orders/:id/status",
  requireAdmin,
  async (req, res) => {
    const body = req.body || {};
    const status = typeof body.status === "string" ? body.status : "";
    const result = await marketplaceStore.updateOrderStatus(
      req.params.id,
      status,
      { deliveryNote: body.deliveryNote },
    );
    if (result.ok) return res.json(result);
    if (isFeatureUnavailableError(result)) return respondFeatureDisabled(res, { key: "ok" });
    const code =
      result.error === "not_found"
        ? 404
        : result.error === "invalid_status"
          ? 400
          : 500;
    return res.status(code).json(result);
  },
);

// 管理者刪除訂單（super_admin / Admin Token gated）：刪單並還原庫存。
app.delete("/api/admin/marketplace/orders/:id", requireAdmin, async (req, res) => {
  const result = await marketplaceStore.deleteOrder(req.params.id);
  if (result.ok) return res.json(result);
  if (isFeatureUnavailableError(result)) return respondFeatureDisabled(res, { key: "ok" });
  const code = result.error === "not_found" ? 404 : 500;
  return res.status(code).json(result);
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

// 正式陪伴聊天回覆（CR-0049-B1）：長者打字 / 非即時文字訊息的正式 AI 回覆來源，
// 取代 Flutter 端 MockAiService 罐頭回覆。OpenAI 由後端代理、金鑰留後端。
//
// 契約：
//   Request  { userText: string, petName?, memoryContextSummary?, languageHint?, replyLanguage? }
//   Success  { success: true, reply }
//   Failure  { success: false, error: 'invalid_input' | 'openai_unavailable' }
//
// persona / instructions 重用既有 `buildRealtimeInstructions`（同 Realtime 主流程 persona），
// 不自創 persona、不硬寫罐頭；memoryContextSummary 由前端傳入既有摘要，
// 本端點**不在此重查跨住民記憶**（避免跨住民記憶洩漏）。
// 失敗一律回明確 error code，不回 fake reply、不回 stack；log 經 redaction。
//
// CR-0045 / CR-0051 Batch B：
//   - 掛 requireResidentCaller（與 /notify 同一中介層），server 權威 elderId 取自
//     req.residentCaller.elderId；無 / 無效 token → 401，跨住民 / 未綁定 / 停用 → 403。
//     body.elderId 若帶且與 caller 不符 → 403 forbidden_resident（永不採信 client elderId）。
//   - 回覆生成成功後，以 analyzeCompanionTurn 做**純函式**風險側錄（不重查記憶 / 不查知識 /
//     不寫記憶），僅當 riskLevel ∈ {medium,high,urgent} 才經共用 processCareAlert 建立 Care Alert
//     （source='companion_chat' 為獨立 cooldown 來源）。風險分析 fail-open，永不阻擋回覆。
//     回應新增向後相容欄位 careAlert（low / neutral 一律省略）；只暴露 riskLevel，不外洩摘要 / debug。
app.post("/api/companion/chat", requireResidentCaller, async (req, res) => {
  const userText = (req.body?.userText || "").toString();
  if (!userText.trim()) {
    return res.status(400).json({ success: false, error: "invalid_input" });
  }

  // server 權威 elderId（與 /notify 同一 reconcile-or-403 規則；永不採信 client elderId）。
  const callerElderId = (req.residentCaller && req.residentCaller.elderId) || null;
  const bodyElderId =
    typeof req.body?.elderId === "string" && req.body.elderId.trim()
      ? req.body.elderId.trim()
      : req.body?.elderId != null
        ? String(req.body.elderId)
        : null;
  if (bodyElderId != null && callerElderId != null && bodyElderId !== callerElderId) {
    return res.status(403).json({ success: false, error: "forbidden_resident" });
  }

  const petName = (req.body?.petName || "").toString();
  const memoryContextSummary = (req.body?.memoryContextSummary || "")
    .toString()
    .trim();
  const memoryBlock = memoryContextSummary
    ? `以下是你自然記得的使用者近況：
${memoryContextSummary}
請自然地關心使用者，不要說「根據紀錄」或「資料庫顯示」。如果使用者不想聊這件事，請溫柔轉換話題。`
    : "";

  const systemPrompt = buildCompanionChatInstructions(petName, memoryBlock, {
    languageHint: req.body?.languageHint,
    replyLanguage: req.body?.replyLanguage,
  });

  // CR-0072：選用 history（最近對話歷史，user/assistant 陣列）。清洗 / 則數 / 長度
  // 上限由 generateCompanionReply 的 sanitizeHistory 統一處理；非陣列 / 髒值安全降級為無。
  const result = await generateCompanionReply(
    { userText, systemPrompt, history: req.body?.history },
    {
      client,
      hasApiKey: Boolean(process.env.OPENAI_API_KEY),
      model:
        process.env.COMPANION_CHAT_MODEL ||
        process.env.MEMORY_MODEL ||
        "gpt-4o-mini",
      logError,
    },
  );

  if (!result.success) {
    const status = result.error === "invalid_input" ? 400 : 503;
    return res.status(status).json({ success: false, error: result.error });
  }

  // 風險側錄（fail-open）：以 analyzeCompanionTurn 做純函式風險判斷，不重查記憶 /
  // 不查知識 / 不寫記憶（避免跨住民 I/O），不改動回覆文字。任何例外都不阻擋 200 回覆。
  let careAlert;
  try {
    const analysis = analyzeCompanionTurn({
      transcript: userText,
      petName,
      languageHint: req.body?.languageHint,
      retrievedMemories: [],
    });
    // 在 seam 正規化 legacy（engine fallback 會吐 "normal"；attention→medium）。
    const riskLevel = normalizeRiskLevel(analysis.safety?.riskLevel);
    if (riskLevel === "medium" || riskLevel === "high" || riskLevel === "urgent") {
      const triggerSummary =
        (analysis.careAlertSummary || "").toString().trim() ||
        "對話中偵測到需要關心的狀況";
      const alertBody = {
        elderId: callerElderId, // server-authoritative
        riskLevel, // already normalized
        riskLevelLabel: RISK_LEVEL_LABELS[riskLevel] || "",
        category: "other",
        categoryLabel: "其他",
        triggerSummary,
        // §9.2 不存過長原文：截斷至前 ~200 字。
        transcriptSnippet: userText.slice(0, 200),
        createdAt: new Date().toISOString(),
        source: "companion_chat", // 獨立 cooldown 來源（語音用 companion_analysis）。
      };
      try {
        const { careAlert: stored } = await processCareAlert(alertBody);
        careAlert = {
          created: Boolean(stored && stored.created),
          riskLevel,
          id: (stored && stored.id) || null,
        };
      } catch (alertError) {
        // 持久化 / 通知側例外：回覆不受影響，僅標示 alert 未建立。
        logError("companion chat care alert failed", {
          error: alertError?.message || alertError,
        });
        careAlert = { created: false, riskLevel, id: null };
      }
    }
    // low / neutral：省略 careAlert 欄位（不建立、不推播）。
  } catch (analysisError) {
    // 風險分析本身失敗：fail-open，省略 careAlert（不外洩風險 debug）。
    logError("companion chat risk analysis failed", {
      error: analysisError?.message || analysisError,
    });
  }

  return res.json({
    success: true,
    reply: result.reply,
    ...(careAlert ? { careAlert } : {}),
  });
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

// CR-0075：記憶端點統一身分驗證。所有記憶路由掛 requireResidentCaller，
// 記憶 key 一律取 server 權威的 caller.elderId（= users.elder_id，與 Flutter 既有
// currentElderId 一致，不孤立既有記憶）。client 若帶與 caller 不符的 userId → 403。
// 回傳 elderId（成功）或 null（已寫好 403 response，呼叫端須直接 return）。
function resolveMemoryCaller(req, res) {
  const callerKey = (req.residentCaller && req.residentCaller.elderId) || null;
  if (!callerKey) {
    res.status(403).json({ success: false, error: "forbidden_resident" });
    return null;
  }
  const claimed =
    typeof req.body?.userId === "string" && req.body.userId.trim()
      ? req.body.userId.trim()
      : typeof req.query?.userId === "string" && req.query.userId.trim()
        ? req.query.userId.trim()
        : null;
  if (claimed != null && claimed !== callerKey) {
    res.status(403).json({ success: false, error: "forbidden_resident" });
    return null;
  }
  return callerKey;
}

app.post("/api/memory/extract", requireResidentCaller, async (req, res) => {
  const userId = resolveMemoryCaller(req, res);
  if (userId == null) return;
  try {
    const result = await extractAndStoreMemory({
      userId,
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

app.post("/api/memory/search", requireResidentCaller, async (req, res) => {
  const userId = resolveMemoryCaller(req, res);
  if (userId == null) return;
  try {
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

app.get("/api/memory/greeting", requireResidentCaller, async (req, res) => {
  const userId = resolveMemoryCaller(req, res);
  if (userId == null) return;
  try {
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

// 對話標題（CR-0027）：用 LLM 為一段對話產生簡短自然的繁中標題。
// 純新增端點，不更動既有 API 契約。無金鑰 / 失敗時退回本地短標題，
// 前端再依序退回「第一則訊息 → 未命名對話」，畫面永遠不卡。
function localShortTitle(text) {
  const cleaned = (text || "")
    .toString()
    .replace(/\s+/g, " ")
    .replace(/^[\s，。、！？!?,.…~～]+/, "")
    .trim();
  if (!cleaned) return "";
  return cleaned.length > 14 ? cleaned.slice(0, 14) : cleaned;
}

function sanitizeConversationTitle(raw) {
  let title = (raw || "").toString();
  title = title.replace(/[\r\n]+/g, " ").trim();
  // 去掉前後引號與結尾標點。
  title = title.replace(/^["'「『（(]+/, "").replace(/["'」』）)]+$/, "").trim();
  title = title.replace(/[。．.!！?？,，、；;：:~～\s]+$/g, "").trim();
  if (title.length > 16) title = title.slice(0, 16);
  return title;
}

app.post("/api/conversation/title", async (req, res) => {
  const firstUserText = (req.body?.firstUserText || "").toString();
  const conversationText = (req.body?.conversationText || "").toString();
  const source = (conversationText.trim() || firstUserText.trim()).slice(0, 800);
  const fallback = localShortTitle(firstUserText || conversationText);
  try {
    if (!process.env.OPENAI_API_KEY || !source) {
      return res.json({ title: fallback });
    }
    const response = await client.chat.completions.create({
      model: process.env.CONVERSATION_TITLE_MODEL || "gpt-4o-mini",
      temperature: 0.3,
      messages: [
        {
          role: "system",
          content:
            "你是幫長者與寵物的對話下標題的助手。用 6 到 14 個繁體中文字，下一個簡短、自然、好辨識的標題。標題要描述「使用者這次主要在說什麼或什麼心情」，以使用者說的內容為主，不要只寫寵物的安慰。只輸出標題本身：不要標點符號、不要引號、不要英文、不要情緒標籤（例如 lonely、neutral）、不要『情緒：』『寵物心情：』這類欄位字。",
        },
        {
          role: "user",
          content: `使用者第一句話：${firstUserText || "（無）"}\n完整對話：\n${source}\n請以使用者說的內容為主，給一個簡短標題。`,
        },
      ],
    });
    const title =
      sanitizeConversationTitle(response.choices?.[0]?.message?.content) ||
      fallback;
    return res.json({ title });
  } catch (error) {
    logError("conversation title failed", { error: error?.message || error });
    return res.json({ title: fallback, error: error?.message || "title failed" });
  }
});

app.post("/api/memory/forget-recent", requireResidentCaller, async (req, res) => {
  const userId = resolveMemoryCaller(req, res);
  if (userId == null) return;
  try {
    const deleted = await softDeleteRecentMemory(userId);
    return res.json({ deleted });
  } catch (error) {
    return res.status(500).json({
      deleted: false,
      error: error?.message || "forget recent failed",
    });
  }
});

app.get("/api/memories", requireResidentCaller, async (req, res) => {
  const userId = resolveMemoryCaller(req, res);
  if (userId == null) return;
  try {
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

app.post("/api/memories", requireResidentCaller, async (req, res) => {
  const userId = resolveMemoryCaller(req, res);
  if (userId == null) return;
  try {
    const content = (req.body?.content || req.body?.memorySummary || req.body?.memoryText || "").toString().trim();
    const type = (req.body?.type || req.body?.memoryType || "other").toString().trim();
    const embedding = req.body?.embedding || (await createMemoryEmbedding(content)).embedding;
    const result = await createMemory({
      userId,
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

app.post("/api/memories/search", requireResidentCaller, async (req, res) => {
  const userId = resolveMemoryCaller(req, res);
  if (userId == null) return;
  try {
    normalizeEmbedding(req.body?.embedding);
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

app.post("/api/memories/context", requireResidentCaller, async (req, res) => {
  const userId = resolveMemoryCaller(req, res);
  if (userId == null) return;
  try {
    const result = await buildMemoryContext({
      userText: req.body?.userText || "",
      userId,
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

app.get("/api/memories/greeting", requireResidentCaller, async (req, res) => {
  const fallback = fallbackGreeting({
    petName: (req.query?.petName || "陪伴寶").toString(),
    localHour: Number(req.query?.localHour || new Date().getHours()),
  });
  const userId = resolveMemoryCaller(req, res);
  if (userId == null) return;
  try {
    const result = await buildMemoryGreeting({ userId });
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

app.post("/api/memories/extract", requireResidentCaller, async (req, res) => {
  const userId = resolveMemoryCaller(req, res);
  if (userId == null) return;
  try {
    const userText = (req.body?.userText || "").toString().trim();
    if (!userText) {
      return res.status(400).json({
        shouldRemember: false,
        reason: "userText is required",
      });
    }

    const extracted = await extractMemoryFromTurn({
      userId,
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
      userId,
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

app.post("/api/memories/:id/archive", requireResidentCaller, async (req, res) => {
  const userId = resolveMemoryCaller(req, res);
  if (userId == null) return;
  try {
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

app.patch("/api/memories/:id/archive", requireResidentCaller, async (req, res) => {
  const userId = resolveMemoryCaller(req, res);
  if (userId == null) return;
  try {
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
  // CR-0032：實際啟動 server 時，若商城商品檔為空，寫入 Demo 種子商品，
  // 方便展示（測試以 require 載入 app，require.main !== module，不會觸發）。
  marketplaceStore
    .seedDefaultProducts()
    .catch((error) =>
      logError("marketplace seed failed", { error: error?.message || error }),
    );
  // CR-0034 B2：啟動時印「一律遮蔽」的設定摘要，方便維運確認敏感設定是否就緒，
  // 但絕不輸出任何完整 token / secret / DATABASE_URL / email（皆走 mask helper）。
  console.log("[config] effective config (masked)", describeMaskedConfig(process.env));
  app.listen(port, host, () => {
    console.log(`STT Proxy listening on http://${host}:${port}`);
  });
}

module.exports = app;
// CR-0050：匯出供單元測試驗證打字 chat persona 組裝（不需打 OpenAI）。
module.exports.buildCompanionChatInstructions = buildCompanionChatInstructions;
