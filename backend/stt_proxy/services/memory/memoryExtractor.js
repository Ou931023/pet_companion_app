const OpenAI = require("openai");
const { safeErrorMessage } = require("../privacy/redaction");

const MEMORY_TYPES = new Set([
  "preference",
  "routine",
  "emotion",
  "reminder",
  "care_need",
  "story_preference",
  "health_lifestyle",
  "family",
  "personal_story",
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

const CHATTER = new Set(["你好", "哈", "哈哈", "嗯", "嗯嗯", "好", "好的", "謝謝", "謝謝你"]);

let client;

function getClient() {
  if (!process.env.OPENAI_API_KEY) return null;
  if (!client) {
    client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
  }
  return client;
}

function chineseCharCount(text) {
  return (text.match(/[\u4e00-\u9fff]/g) || []).length;
}

function normalizeEmotionLabel(value) {
  const normalized = (value || "unknown").toString().trim();
  return EMOTION_LABELS.has(normalized) ? normalized : "unknown";
}

function hasAny(text, words) {
  return words.some((word) => text.includes(word));
}

function isSensitiveOrDiagnosis(text) {
  return hasAny(text, [
    "確診",
    "診斷",
    "我是憂鬱症",
    "我有癌症",
    "投票",
    "政黨",
    "宗教信仰",
    "身分證",
    "身份證",
  ]);
}

function falseResult(reason) {
  return {
    shouldRemember: false,
    reason,
  };
}

function buildMemory({
  memoryType,
  memoryText,
  memorySummary,
  importance,
  emotionLabel,
  confidence,
  reason,
}) {
  return {
    shouldRemember: true,
    memoryType,
    memoryText,
    memorySummary,
    importance,
    emotionLabel: normalizeEmotionLabel(emotionLabel),
    confidence,
    reason,
  };
}

function ruleBasedExtract({ userText, emotion }) {
  const text = (userText || "").toString().trim();
  if (!text) return falseResult("userText is required");
  if (CHATTER.has(text)) return falseResult("普通寒暄，不需保存");
  if (
    chineseCharCount(text) < 4 &&
    !hasAny(text, ["藥", "痛", "睡", "水", "累", "餓", "怕", "哭", "名", "叫"])
  ) {
    return falseResult("文字太短且沒有明確長期意義");
  }
  if (text.includes("今天天氣不錯") || text.includes("天氣不錯")) {
    return falseResult("一次性閒聊，不需保存");
  }
  if (isSensitiveOrDiagnosis(text)) {
    return falseResult("可能包含診斷或敏感推斷，不自動保存");
  }

  const emotionLabel = normalizeEmotionLabel(emotion);

  // CR-0073：自我介紹 / 家人關係是「要記住」的核心，但原本沒有對應 rule 分支
  // （production 只能靠 AI 補、無 key 則漏）。在此補上，確保穩定存入。
  if (hasAny(text, ["我叫", "我的名字", "名字是", "我是叫"])) {
    return buildMemory({
      memoryType: "personal_story",
      memoryText: text,
      memorySummary: `使用者自我介紹：${text}`,
      importance: 4,
      emotionLabel,
      confidence: 0.8,
      reason: "使用者提供姓名 / 自我介紹",
    });
  }
  if (hasAny(text, ["兒子", "女兒", "孫子", "孫女", "孫", "老伴", "先生", "太太", "老公", "老婆", "媽媽", "爸爸"])) {
    return buildMemory({
      memoryType: "family",
      memoryText: text,
      memorySummary: `使用者提到家人：${text}`,
      importance: 4,
      emotionLabel,
      confidence: 0.78,
      reason: "使用者提到家人 / 重要關係",
    });
  }
  if (hasAny(text, ["忘記喝水", "提醒我", "吃藥", "運動"])) {
    return buildMemory({
      memoryType: "care_need",
      memoryText: text,
      memorySummary: `使用者需要照護提醒：${text}`,
      importance: 4,
      emotionLabel,
      confidence: 0.78,
      reason: "使用者明確表達照護提醒需求",
    });
  }
  if (hasAny(text, ["明天", "下週", "下礼拜", "晚上八點", "早上", "下午"]) && hasAny(text, ["要去", "要吃", "要看", "要做", "醫院", "回診"])) {
    return buildMemory({
      memoryType: "reminder",
      memoryText: text,
      memorySummary: `使用者提到未來事項：${text}`,
      importance: 4,
      emotionLabel,
      confidence: 0.76,
      reason: "使用者明確提到未來需要記得的事項",
    });
  }
  if (hasAny(text, ["孤單", "難過", "焦慮", "擔心", "心情很低落", "很低落"])) {
    return buildMemory({
      memoryType: "emotion",
      memoryText: text,
      memorySummary: `使用者近期情緒狀態：${text}`,
      importance: 4,
      emotionLabel: hasAny(text, ["孤單"]) ? "lonely" : emotionLabel,
      confidence: 0.78,
      reason: "使用者明確表達近期情緒狀態",
    });
  }
  if (hasAny(text, ["睡不好", "沒精神", "很累", "白天很累", "晚上睡不著"])) {
    return buildMemory({
      memoryType: "health_lifestyle",
      memoryText: text,
      memorySummary: `使用者近期睡眠或精神狀態：${text}`,
      importance: 4,
      emotionLabel: hasAny(text, ["累", "沒精神"]) ? "tired" : emotionLabel,
      confidence: 0.76,
      reason: "使用者描述長期或近期健康生活狀態",
    });
  }
  if (hasAny(text, ["每天", "常常", "最近", "晚上", "早上"])) {
    return buildMemory({
      memoryType: "routine",
      memoryText: text,
      memorySummary: `使用者的生活習慣或近期狀況：${text}`,
      importance: 3,
      emotionLabel,
      confidence: 0.68,
      reason: "使用者描述生活習慣或反覆發生的狀況",
    });
  }
  if (hasAny(text, ["喜歡", "不喜歡"])) {
    const storyRelated = hasAny(text, ["故事", "真實故事", "地方故事", "台灣地方故事"]);
    return buildMemory({
      memoryType: storyRelated ? "story_preference" : "preference",
      memoryText: text,
      memorySummary: `使用者偏好：${text}`,
      importance: storyRelated ? 4 : 3,
      emotionLabel,
      confidence: 0.82,
      reason: "使用者明確表達偏好",
    });
  }

  return falseResult("沒有明確值得長期保存的資訊");
}

function sanitizeAiResult(data, fallbackInput) {
  if (!data || data.shouldRemember !== true) {
    return falseResult(data?.reason || "AI 判斷不需保存");
  }
  if (!MEMORY_TYPES.has(data.memoryType)) {
    return ruleBasedExtract(fallbackInput);
  }
  const importance = Number(data.importance);
  const confidence = Number(data.confidence);
  if (!Number.isInteger(importance) || importance < 1 || importance > 5) {
    return ruleBasedExtract(fallbackInput);
  }
  if (!Number.isFinite(confidence) || confidence < 0 || confidence > 1) {
    return ruleBasedExtract(fallbackInput);
  }
  return buildMemory({
    memoryType: data.memoryType,
    memoryText: (data.memoryText || fallbackInput.userText || "").toString().trim(),
    memorySummary: (data.memorySummary || "").toString().trim(),
    importance,
    emotionLabel: data.emotionLabel,
    confidence,
    reason: (data.reason || "AI 判斷值得保存").toString(),
  });
}

async function aiExtract(input) {
  const openai = getClient();
  if (!openai) return null;

  const model = process.env.MEMORY_EXTRACT_MODEL || "gpt-4o-mini";
  const response = await openai.chat.completions.create({
    model,
    temperature: 0,
    response_format: { type: "json_object" },
    messages: [
      {
        role: "system",
        content:
          "你是長者陪伴 App 的長期記憶抽取器。只根據使用者明確說出口的內容判斷是否保存。不要保存普通寒暄、一次性閒聊、醫療診斷、政治宗教或敏感身份推斷。只能輸出 JSON。",
      },
      {
        role: "user",
        content: JSON.stringify({
          schema: {
            shouldRemember: "boolean",
            memoryType:
              "preference | routine | emotion | reminder | care_need | story_preference | health_lifestyle | other",
            memoryText: "原始可依據文字",
            memorySummary: "一句話摘要",
            importance: "integer 1-5",
            emotionLabel: "happy | neutral | sad | lonely | anxious | tired | angry | unknown",
            confidence: "number 0-1",
            reason: "為什麼值得記住或不保存",
          },
          userText: input.userText,
          agentReply: input.agentReply,
          emotion: input.emotion,
        }),
      },
    ],
  });
  const raw = response.choices?.[0]?.message?.content || "{}";
  return JSON.parse(raw);
}

async function extractMemoryFromTurn(input) {
  const normalized = {
    userText: (input?.userText || "").toString().trim(),
    agentReply: (input?.agentReply || "").toString().trim(),
    emotion: (input?.emotion || "unknown").toString().trim(),
    sessionId: input?.sessionId || null,
    turnId: input?.turnId || null,
    userId: input?.userId || "default_user",
  };

  // CR-0073 去敏觀測：只記決策 / 類型 / reason / 輸入長度，不記任何原文或 userId。
  const logDecision = (result, source) => {
    console.log("[memory-extractor] decide", {
      shouldRemember: Boolean(result.shouldRemember),
      memoryType: result.memoryType || null,
      reason: result.reason || null,
      source,
      userTextLen: normalized.userText.length,
    });
    return result;
  };

  const precheck = ruleBasedExtract(normalized);
  if (!precheck.shouldRemember && (
    CHATTER.has(normalized.userText) ||
    normalized.userText.includes("天氣不錯") ||
    chineseCharCount(normalized.userText) < 4 ||
    isSensitiveOrDiagnosis(normalized.userText)
  )) {
    return logDecision(precheck, "rule_hardblock");
  }

  try {
    const aiResult = await aiExtract(normalized);
    if (aiResult) {
      const sanitized = sanitizeAiResult(aiResult, normalized);
      if (sanitized.shouldRemember) return logDecision(sanitized, "ai");
      if (precheck.shouldRemember) {
        return logDecision(
          {
            ...precheck,
            reason: `${precheck.reason}（AI 判 false 但規則命中，採信規則）`,
          },
          "rule_over_ai",
        );
      }
      return logDecision(sanitized, "ai");
    }
  } catch (error) {
    console.warn("[memory-extractor] AI extract failed, using fallback", safeErrorMessage(error));
  }

  return logDecision(precheck, "rule");
}

module.exports = {
  extractMemoryFromTurn,
  ruleBasedExtract,
};
