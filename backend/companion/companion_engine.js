const { analyzeImplicitMeaning } = require("./companion_reflex_analyzer");
const { classifyEmotion } = require("./emotion_classifier");
const { classifyCompanionNeed } = require("./companion_need_classifier");
const { mapPetState, mapReplyStrategy } = require("./pet_state_mapper");
const { shouldSaveMemory } = require("./memory_policy");
const { assessSafety } = require("./safety_guard");
const { planNextStrategy } = require("./next_strategy_planner");
const { buildCareAlertSummary } = require("./companion_prompt_builder");
const { estimateVoiceFeatures } = require("./voice_feature_service");
const { fuseEmotion } = require("./emotion_fusion_service");
const { classifySearchIntent } = require("../search/search_intent_classifier");

function analyzeCompanionTurn(input = {}) {
  const transcript = (input.transcript || "").toString().trim();
  const turnId = (input.turnId || "").toString().trim() || `turn-${Date.now()}`;
  if (!transcript) {
    return structuredResult({
      turnId,
      emotion: "neutral",
      emotionConfidence: 0.5,
      companionNeed: "unknown",
      needConfidence: 0.5,
      replyStrategy: "normal_chat",
      implicitMeaning: "沒有可分析的 transcript。",
      petExpression: "idle",
      petAction: "stay",
      memory: { shouldSave: false, candidate: "", type: "none" },
      safety: { riskLevel: "low", needsHumanSupport: false },
      careAlertSummary: buildCareAlertSummary({ riskLevel: "low", transcript: "" }),
      nextStrategy: {
        mode: "normal_chat",
        instruction: "下一輪回應保持自然、簡短、陪伴感，每次最多問一個問題。",
      },
      voiceFeatures: estimateVoiceFeatures({ transcript, audioFeatures: input.audioFeatures }),
      fusion: {
        finalEmotion: "neutral",
        confidence: 0.5,
        reason: "沒有可分析的 transcript。",
      },
    });
  }

  const emotionResult = classifyEmotion(input);
  const voiceFeatures = estimateVoiceFeatures({
    transcript,
    audioFeatures: input.audioFeatures || {},
  });
  const needResult = classifyCompanionNeed({
    transcript,
    emotion: emotionResult.emotion,
  });
  const fusion = fuseEmotion({
    textEmotion: emotionResult.emotion,
    textConfidence: emotionResult.confidence,
    voiceFeatures,
    companionNeed: needResult.companionNeed,
  });
  fusion.textEmotion = emotionResult.emotion;
  const safety = assessSafety({ transcript });
  const searchIntent = classifySearchIntent(transcript);
  const replyStrategy = mapReplyStrategy({
    emotion: fusion.finalEmotion,
    companionNeed: needResult.companionNeed,
  });
  const petState = mapPetState({
    emotion: fusion.finalEmotion,
    companionNeed: needResult.companionNeed,
    replyStrategy,
  });
  const implicitMeaning = analyzeImplicitMeaning({
    transcript,
    emotion: fusion.finalEmotion,
    companionNeed: needResult.companionNeed,
  });
  const memory = shouldSaveMemory({
    transcript,
    emotion: fusion.finalEmotion,
    companionNeed: needResult.companionNeed,
  });
  const nextStrategy = planNextStrategy({
    emotion: fusion.finalEmotion,
    companionNeed: needResult.companionNeed,
    replyStrategy,
    safety,
    retrievedMemories: input.retrievedMemories || [],
    searchIntent,
    sourceReferences: input.sourceReferences || [],
    languageHint: input.languageHint || "zh",
  });

  return structuredResult({
    turnId,
    emotion: fusion.finalEmotion,
    emotionConfidence: fusion.confidence,
    companionNeed: needResult.companionNeed,
    needConfidence: needResult.confidence,
    replyStrategy,
    implicitMeaning,
    petExpression: petState.petExpression,
    petAction: petState.petAction,
    memory,
    safety,
    careAlertSummary: buildCareAlertSummary({
      riskLevel: safety.riskLevel,
      transcript,
    }),
    nextStrategy,
    voiceFeatures,
    fusion,
    needsSearch: searchIntent.needsSearch,
    searchTopic: searchIntent.topic,
    sourceReferences: input.sourceReferences || [],
    knowledgeAnswer: input.knowledgeAnswer || "",
  });
}

function structuredResult(result) {
  return {
    turnId: result.turnId,
    emotion: enumValue(result.emotion, EMOTIONS, "neutral"),
    emotionConfidence: clampConfidence(result.emotionConfidence),
    companionNeed: enumValue(result.companionNeed, COMPANION_NEEDS, "unknown"),
    needConfidence: clampConfidence(result.needConfidence),
    replyStrategy: enumValue(result.replyStrategy, REPLY_STRATEGIES, "normal_chat"),
    implicitMeaning: (result.implicitMeaning || "").toString(),
    petExpression: enumValue(result.petExpression, PET_EXPRESSIONS, "idle"),
    petAction: enumValue(result.petAction, PET_ACTIONS, "stay"),
    memory: {
      shouldSave: Boolean(result.memory?.shouldSave),
      candidate: (result.memory?.candidate || "").toString(),
      type: (result.memory?.type || "none").toString(),
    },
    safety: {
      riskLevel: enumValue(
        normalizeRiskLevel(result.safety?.riskLevel),
        RISK_LEVELS,
        "low",
      ),
      needsHumanSupport: Boolean(result.safety?.needsHumanSupport),
    },
    // Care Alert 人類可讀摘要（單一字串，供 Telegram / caregiver_web 顯示）。
    careAlertSummary: (result.careAlertSummary || "").toString(),
    nextStrategy: {
      mode: (result.nextStrategy?.mode || "normal_chat").toString(),
      instruction: (result.nextStrategy?.instruction || "").toString(),
    },
    voiceFeatures: {
      volumeMean: nullableNumber(result.voiceFeatures?.volumeMean),
      volumeVariance: nullableNumber(result.voiceFeatures?.volumeVariance),
      pauseDensity: nullableNumber(result.voiceFeatures?.pauseDensity),
      estimatedSpeechRate: nullableNumber(result.voiceFeatures?.estimatedSpeechRate),
      speechDuration: nullableNumber(result.voiceFeatures?.speechDuration),
      silenceDuration: nullableNumber(result.voiceFeatures?.silenceDuration),
      confidence: clampConfidence(result.voiceFeatures?.confidence),
    },
    fusion: {
      textEmotion: enumValue(result.fusion?.textEmotion, EMOTIONS, enumValue(result.emotion, EMOTIONS, "neutral")),
      finalEmotion: enumValue(result.fusion?.finalEmotion, EMOTIONS, enumValue(result.emotion, EMOTIONS, "neutral")),
      confidence: clampConfidence(result.fusion?.confidence ?? result.emotionConfidence),
      reason: (result.fusion?.reason || "").toString(),
    },
    needsSearch: Boolean(result.needsSearch),
    searchTopic: (result.searchTopic || "none").toString(),
    sourceReferences: Array.isArray(result.sourceReferences) ? result.sourceReferences : [],
    knowledgeAnswer: (result.knowledgeAnswer || "").toString(),
  };
}

function nullableNumber(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function enumValue(value, allowed, fallback) {
  const normalized = (value || "").toString();
  return allowed.has(normalized) ? normalized : fallback;
}

// 對舊代碼做讀取相容：normal→low、attention→medium；其餘原樣（含新權威四級）。
// 未知值交由 enumValue 的 fallback（low）處理。
const RISK_LEVEL_ALIASES = { normal: "low", attention: "medium" };
function normalizeRiskLevel(value) {
  const raw = (value || "").toString().trim().toLowerCase();
  return RISK_LEVEL_ALIASES[raw] || raw;
}

function clampConfidence(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) return 0.5;
  return Number(Math.min(1, Math.max(0, number)).toFixed(2));
}

const EMOTIONS = new Set(["happy", "neutral", "sad", "lonely", "anxious", "tired", "nostalgic"]);
const COMPANION_NEEDS = new Set([
  "companionship",
  "emotional_support",
  "daily_chat",
  "reminiscence",
  "reminder_support",
  "grounding",
  "encouragement",
  "unknown",
]);
const REPLY_STRATEGIES = new Set([
  "soft_companion",
  "gentle_checkin",
  "calm_down",
  "keep_company",
  "reminiscence_followup",
  "encourage_small_step",
  "normal_chat",
]);
const PET_EXPRESSIONS = new Set(["idle", "happy", "concerned", "sad", "calm", "excited", "sleepy"]);
const PET_ACTIONS = new Set(["stay", "move_closer", "wag_tail", "nod", "comfort", "cheer", "rest"]);
const RISK_LEVELS = new Set(["low", "medium", "high", "urgent"]);

module.exports = {
  analyzeCompanionTurn,
  normalizeRiskLevel,
};
