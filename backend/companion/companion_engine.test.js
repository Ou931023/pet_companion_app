const test = require("node:test");
const assert = require("node:assert/strict");

const { analyzeCompanionTurn } = require("./companion_engine");

function analyze(transcript) {
  return analyzeCompanionTurn({
    userId: "demo-user",
    sessionId: "session-001",
    turnId: `turn-${transcript}`,
    petName: "陪伴寶",
    transcript,
    languageHint: "zh",
    recentTurns: [],
    petState: {
      mood: "neutral",
      expression: "idle",
      intimacy: 50,
      hunger: 70,
      energy: 60,
    },
    audioFeatures: {
      volumeMean: null,
      pauseDensity: null,
      speechRate: null,
    },
  });
}

test("detects implicit quiet-home loneliness", () => {
  const result = analyze("今天家裡好安靜");
  assert.equal(result.emotion, "lonely");
  assert.equal(result.companionNeed, "companionship");
  assert.equal(result.replyStrategy, "soft_companion");
  assert.equal(result.petExpression, "concerned");
  assert.equal(result.petAction, "move_closer");
  assert.equal(result.memory.shouldSave, true);
});

test("detects busy-family emotional support", () => {
  const result = analyze("大家都很忙");
  assert.ok(["lonely", "sad"].includes(result.emotion));
  assert.equal(result.companionNeed, "emotional_support");
  assert.equal(result.replyStrategy, "gentle_checkin");
});

test("detects open-ended daily chat need", () => {
  const result = analyze("我不知道要做什麼");
  assert.ok(["neutral", "lonely", "sad"].includes(result.emotion));
  assert.equal(result.companionNeed, "daily_chat");
  assert.equal(result.replyStrategy, "keep_company");
});

test("detects reminiscence", () => {
  const result = analyze("以前家裡很熱鬧");
  assert.equal(result.emotion, "nostalgic");
  assert.equal(result.companionNeed, "reminiscence");
  assert.equal(result.replyStrategy, "reminiscence_followup");
});

test("detects sleep difficulty grounding", () => {
  const result = analyze("睡不太著");
  assert.ok(["anxious", "tired"].includes(result.emotion));
  assert.equal(result.companionNeed, "grounding");
  assert.equal(result.replyStrategy, "calm_down");
});

test("detects resigned sadness", () => {
  const result = analyze("算了沒關係");
  assert.equal(result.emotion, "sad");
  assert.equal(result.companionNeed, "emotional_support");
  assert.equal(result.replyStrategy, "gentle_checkin");
});

test("keeps sunny ordinary statement positive or neutral", () => {
  const result = analyze("今天太陽很好");
  assert.ok(["happy", "neutral"].includes(result.emotion));
  assert.notEqual(result.companionNeed, "companionship");
  assert.equal(result.safety.riskLevel, "normal");
});

test("detects eating alone as companionship cue", () => {
  const result = analyze("我剛剛吃飯只有我一個人");
  assert.equal(result.emotion, "lonely");
  assert.equal(result.companionNeed, "companionship");
  assert.equal(result.replyStrategy, "soft_companion");
});

test("returns fixed structured schema", () => {
  const result = analyze("今天家裡好安靜");
  assert.deepEqual(Object.keys(result), [
    "turnId",
    "emotion",
    "emotionConfidence",
    "companionNeed",
    "needConfidence",
    "replyStrategy",
    "implicitMeaning",
    "petExpression",
    "petAction",
    "memory",
    "safety",
    "nextStrategy",
    "voiceFeatures",
    "fusion",
    "needsSearch",
    "searchTopic",
    "sourceReferences",
    "knowledgeAnswer",
  ]);
  assert.deepEqual(Object.keys(result.memory), ["shouldSave", "candidate", "type"]);
  assert.deepEqual(Object.keys(result.safety), ["riskLevel", "needsHumanSupport"]);
  assert.deepEqual(Object.keys(result.nextStrategy), ["mode", "instruction"]);
  assert.deepEqual(Object.keys(result.fusion), ["textEmotion", "finalEmotion", "confidence", "reason"]);
  assert.equal(result.turnId, "turn-今天家裡好安靜");
});

test("marks knowledge search intent", () => {
  const result = analyze("跟我說健康小知識");
  assert.equal(result.needsSearch, true);
  assert.equal(result.nextStrategy.mode, "knowledge_response");
});

test("adds taigi guidance when languageHint is taigi", () => {
  const result = analyzeCompanionTurn({
    userId: "demo-user",
    sessionId: "session-001",
    turnId: "turn-taigi",
    petName: "陪伴寶",
    transcript: "睡不太著",
    languageHint: "taigi",
    recentTurns: [],
    petState: {
      mood: "neutral",
      expression: "idle",
      intimacy: 50,
      hunger: 70,
      energy: 60,
    },
  });

  assert.match(result.nextStrategy.instruction, /台灣長者自然聽得懂/);
  assert.match(result.nextStrategy.instruction, /溫和追問/);
});

test("fusion boosts lonely when pause density is high", () => {
  const result = analyzeCompanionTurn({
    transcript: "今天家裡好安靜",
    turnId: "turn-lonely-pause",
    audioFeatures: { pauseDensity: 0.7, estimatedSpeechRate: 1.8, confidence: 0.8 },
  });

  assert.equal(result.fusion.textEmotion, "lonely");
  assert.equal(result.fusion.finalEmotion, "lonely");
  assert.ok(result.fusion.confidence > 0.78);
});

test("fusion uses slow speech and high pause for neutral text", () => {
  const result = analyzeCompanionTurn({
    transcript: "今天下午在客廳坐了一下",
    turnId: "turn-slow-neutral",
    audioFeatures: { pauseDensity: 0.65, estimatedSpeechRate: 1.1, confidence: 0.8 },
  });

  assert.equal(result.fusion.textEmotion, "neutral");
  assert.ok(["tired", "sad"].includes(result.fusion.finalEmotion));
});

test("fusion boosts anxious when speech is fast", () => {
  const result = analyzeCompanionTurn({
    transcript: "我有點擔心",
    turnId: "turn-anxious-fast",
    audioFeatures: { estimatedSpeechRate: 4.8, volumeVariance: 0.2, confidence: 0.8 },
  });

  assert.equal(result.fusion.finalEmotion, "anxious");
  assert.ok(result.fusion.confidence > 0.72);
});

test("fusion falls back to text emotion when voice features are missing", () => {
  const result = analyzeCompanionTurn({
    transcript: "我有點孤單",
    turnId: "turn-no-audio",
  });

  assert.equal(result.fusion.textEmotion, "lonely");
  assert.equal(result.fusion.finalEmotion, "lonely");
  assert.match(result.fusion.reason, /文字情緒推測/);
});

test("fusion never returns unsupported emotion", () => {
  const result = analyzeCompanionTurn({
    transcript: "我有點擔心",
    turnId: "turn-supported-emotion",
    audioFeatures: { pauseDensity: 0.2, estimatedSpeechRate: 4.5, confidence: 0.8 },
  });
  const supported = ["happy", "neutral", "sad", "lonely", "anxious", "tired", "nostalgic"];

  assert.ok(supported.includes(result.fusion.finalEmotion));
  assert.ok(supported.includes(result.emotion));
});
