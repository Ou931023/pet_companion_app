const { analyzeImplicitMeaning } = require("./companion_reflex_analyzer");
const { classifyEmotion } = require("./emotion_classifier");
const { classifyCompanionNeed } = require("./companion_need_classifier");
const { mapPetState, mapReplyStrategy } = require("./pet_state_mapper");
const { shouldSaveMemory } = require("./memory_policy");
const { assessSafety } = require("./safety_guard");
const { planNextStrategy } = require("./next_strategy_planner");

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
      safety: { riskLevel: "normal", needsHumanSupport: false },
      nextStrategy: {
        mode: "normal_chat",
        instruction: "下一輪回應保持自然、簡短、陪伴感，每次最多問一個問題。",
      },
    });
  }

  const emotionResult = classifyEmotion(input);
  const needResult = classifyCompanionNeed({
    transcript,
    emotion: emotionResult.emotion,
  });
  const safety = assessSafety({ transcript });
  const replyStrategy = mapReplyStrategy({
    emotion: emotionResult.emotion,
    companionNeed: needResult.companionNeed,
  });
  const petState = mapPetState({
    emotion: emotionResult.emotion,
    companionNeed: needResult.companionNeed,
    replyStrategy,
  });
  const implicitMeaning = analyzeImplicitMeaning({
    transcript,
    emotion: emotionResult.emotion,
    companionNeed: needResult.companionNeed,
  });
  const memory = shouldSaveMemory({
    transcript,
    emotion: emotionResult.emotion,
    companionNeed: needResult.companionNeed,
  });
  const nextStrategy = planNextStrategy({
    emotion: emotionResult.emotion,
    companionNeed: needResult.companionNeed,
    replyStrategy,
    safety,
    retrievedMemories: input.retrievedMemories || [],
  });

  return structuredResult({
    turnId,
    emotion: emotionResult.emotion,
    emotionConfidence: emotionResult.confidence,
    companionNeed: needResult.companionNeed,
    needConfidence: needResult.confidence,
    replyStrategy,
    implicitMeaning,
    petExpression: petState.petExpression,
    petAction: petState.petAction,
    memory,
    safety,
    nextStrategy,
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
      riskLevel: enumValue(result.safety?.riskLevel, RISK_LEVELS, "normal"),
      needsHumanSupport: Boolean(result.safety?.needsHumanSupport),
    },
    nextStrategy: {
      mode: (result.nextStrategy?.mode || "normal_chat").toString(),
      instruction: (result.nextStrategy?.instruction || "").toString(),
    },
  };
}

function enumValue(value, allowed, fallback) {
  const normalized = (value || "").toString();
  return allowed.has(normalized) ? normalized : fallback;
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
const RISK_LEVELS = new Set(["normal", "attention", "urgent"]);

module.exports = {
  analyzeCompanionTurn,
};
