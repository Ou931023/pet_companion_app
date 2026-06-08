const OpenAI = require("openai");

const { createEmbedding } = require("./embeddingService");
const {
  insertMemory,
  softDeleteRecentMemory,
} = require("../repositories/memoryRepository");
const { safeErrorMessage } = require("./privacy/redaction");

const client = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
});

const LOW_VALUE_PATTERNS = [
  /^你好[啊呀]?$/,
  /^嗯+$/,
  /^哈哈+$/,
  /^謝謝(你)?$/,
  /^你在嗎$/,
  /^好$/,
  /^沒事$/,
];

const IMPORTANT_KEYWORDS = [
  "痛",
  "不舒服",
  "睡不好",
  "累",
  "吃不下",
  "頭暈",
  "胸悶",
  "孤單",
  "難過",
  "害怕",
  "擔心",
  "焦慮",
  "想念",
  "去醫院",
  "看醫生",
  "家人",
  "孫子",
  "朋友",
  "出門",
  "吃飯",
  "喜歡",
  "不喜歡",
  "習慣",
  "明天",
  "下週",
  "週五",
  "生日",
  "回診",
];

function isLowValueText(text) {
  const normalized = (text || "").trim();
  if (!normalized) return true;
  if (normalized.length <= 2 && !IMPORTANT_KEYWORDS.some((k) => normalized.includes(k))) {
    return true;
  }
  return LOW_VALUE_PATTERNS.some((pattern) => pattern.test(normalized));
}

function hasImportantSignal(text) {
  const normalized = (text || "").trim();
  return IMPORTANT_KEYWORDS.some((keyword) => normalized.includes(keyword));
}

function shouldSkipRememberByPrivacy(text) {
  const normalized = (text || "").trim();
  if (normalized.includes("不要記住這件事") || normalized.includes("不要記")) {
    return true;
  }
  return false;
}

function shouldForgetRecent(text) {
  const normalized = (text || "").trim();
  return normalized.includes("忘記我剛剛說的") || normalized.includes("忘記剛剛那件事");
}

const Ajv = require('ajv');
const ajv = new Ajv({ allErrors: true, strict: false });

const summarySchema = {
  type: 'object',
  properties: {
    shouldRemember: { type: 'boolean' },
    memoryType: { type: 'string', enum: ['profile', 'episodic', 'emotional'] },
    summary: { type: 'string' },
    importance: { type: 'number', minimum: 0, maximum: 1 },
    tags: { type: 'array', items: { type: 'string' }, maxItems: 5 },
  },
  required: ['shouldRemember', 'summary'],
  additionalProperties: false,
};
const validateSummary = ajv.compile(summarySchema);

async function summarizeMemoryWithLLM({ userText, aiReply, emotion }) {
  const prompt = `
你是陪伴型 AI 的記憶萃取器。請只輸出 JSON，不要多餘文字。
輸入內容：
- userText: ${userText}
- aiReply: ${aiReply}
- emotion: ${emotion || "neutral"}

判斷是否值得記憶，並輸出：
{
  "shouldRemember": true/false,
  "memoryType": "profile" | "episodic" | "emotional",
  "summary": "繁體中文一句話",
  "importance": 0~1,
  "tags": ["1~5個tag"]
}
`;

  try {
    const response = await client.chat.completions.create({
      model: process.env.MEMORY_MODEL || "gpt-4o-mini",
      temperature: 0.2,
      response_format: { type: "json_object" },
      messages: [
        {
          role: "system",
          content:
            "你負責把對話萃取成可檢索的照護記憶，輸出必須是合法 JSON，summary 要簡短。",
        },
        {
          role: "user",
          content: prompt,
        },
      ],
    });

    const content = response.choices?.[0]?.message?.content || "{}";
    let parsed = {};
    try {
      parsed = JSON.parse(content);
    } catch (err) {
      logError('LLM returned invalid JSON for memory summary', { error: err?.message || err, raw: content });
      return {
        shouldRemember: false,
        memoryType: 'episodic',
        summary: '',
        importance: 0.5,
        tags: [],
      };
    }

    // Validate against schema
    const valid = validateSummary(parsed);
    if (!valid) {
      logError('LLM memory summary failed schema validation', { errors: validateSummary.errors, raw: parsed });
      return {
        shouldRemember: false,
        memoryType: 'episodic',
        summary: '',
        importance: 0.5,
        tags: [],
      };
    }

    return {
      shouldRemember: Boolean(parsed.shouldRemember),
      memoryType: parsed.memoryType || 'episodic',
      summary: (parsed.summary || '').toString().trim(),
      importance: Math.max(0, Math.min(1, Number(parsed.importance) || 0.5)),
      tags: Array.isArray(parsed.tags) ? parsed.tags.map((x) => String(x)).filter(Boolean).slice(0,5) : [],
    };
  } catch (err) {
    // CR-0047 B2：只記安全摘要（code/遮蔽 message），不印 stack 全文。
    console.error('[memoryExtractor] summarizeMemoryWithLLM error', safeErrorMessage(err));
    return {
      shouldRemember: false,
      memoryType: 'episodic',
      summary: '',
      importance: 0.5,
      tags: [],
    };
  }
}

async function extractAndStoreMemory(input) {
  const userText = (input.userText || "").trim();
  const userId = (input.userId || "local_user").trim();

  try {
    if (shouldForgetRecent(userText)) {
      const deleted = await softDeleteRecentMemory(userId);
      return {
        shouldRemember: false,
        deletedRecent: deleted,
        skippedReason: 'forget_recent',
      };
    }

    if (shouldSkipRememberByPrivacy(userText)) {
      return {
        shouldRemember: false,
        skippedReason: 'privacy_opt_out',
      };
    }

    if (isLowValueText(userText) && !hasImportantSignal(userText)) {
      return {
        shouldRemember: false,
        skippedReason: 'low_value',
      };
    }

    const summaryResult = await summarizeMemoryWithLLM({
      userText,
      aiReply: input.aiReply || '',
      emotion: input.emotion || 'neutral',
    });

    if (!summaryResult.shouldRemember || !summaryResult.summary) {
      return {
        shouldRemember: false,
        skippedReason: 'llm_decision',
      };
    }

    const embedding = await createEmbedding(summaryResult.summary);

    const row = await insertMemory({
      userId,
      sessionId: input.sessionId || null,
      sourceTurnId: input.turnId || null,
      memoryType: summaryResult.memoryType,
      summary: summaryResult.summary,
      originalUserText: userText,
      aiReply: input.aiReply || '',
      emotion: input.emotion || null,
      importance: summaryResult.importance,
      tags: summaryResult.tags,
      embedding,
    });

    return {
      shouldRemember: true,
      memoryId: row.id,
      memoryType: row.memory_type,
      summary: row.summary,
      importance: row.importance,
      tags: row.tags,
    };
  } catch (err) {
    // CR-0047 B2：只記安全摘要，不印 stack 全文、不印對話原文（userText）片段。
    console.error('[memoryExtractor] extractAndStoreMemory error', safeErrorMessage(err));
    return {
      shouldRemember: false,
      error: err?.message || 'extract failed',
    };
  }
}

module.exports = {
  extractAndStoreMemory,
};
