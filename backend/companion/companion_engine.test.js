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
  ]);
  assert.deepEqual(Object.keys(result.memory), ["shouldSave", "candidate", "type"]);
  assert.deepEqual(Object.keys(result.safety), ["riskLevel", "needsHumanSupport"]);
  assert.deepEqual(Object.keys(result.nextStrategy), ["mode", "instruction"]);
  assert.equal(result.turnId, "turn-今天家裡好安靜");
});
