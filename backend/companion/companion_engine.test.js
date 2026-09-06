const test = require("node:test");
const assert = require("node:assert/strict");

const { analyzeCompanionTurn, normalizeRiskLevel } = require("./companion_engine");

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
  assert.equal(result.safety.riskLevel, "low");
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
    "careAlertSummary",
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

test("空白 transcript 的一般回覆指引也套用 CR-0105D 節奏", () => {
  const result = analyzeCompanionTurn({ transcript: "" });

  assert.equal(result.safety.riskLevel, "low");
  assert.match(result.nextStrategy.instruction, /1–3 句/);
  assert.match(result.nextStrategy.instruction, /最多一個問題/);
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

// ---- CR-0002 Batch 1：Care Alert 權威四級輸出 ----

test("safety 輸出權威四級之一，且空白 transcript 預設 low", () => {
  const valid = new Set(["low", "medium", "high", "urgent"]);
  const empty = analyze("");
  assert.equal(empty.safety.riskLevel, "low");
  assert.equal(empty.safety.needsHumanSupport, false);

  for (const text of ["今天太陽很好", "睡不好", "好絕望", "我想死"]) {
    assert.ok(valid.has(analyze(text).safety.riskLevel));
  }
});

test("一般低落 / 睡不好 / 孤單 → medium（需持續觀察，不需人工介入）", () => {
  for (const text of ["最近都睡不好", "吃不下飯", "我覺得好孤單", "心情不好"]) {
    const r = analyze(text);
    assert.equal(r.safety.riskLevel, "medium", `「${text}」應為 medium`);
    assert.equal(r.safety.needsHumanSupport, false);
  }
});

test("強烈絕望 / 明顯無助 → high（需通知，needsHumanSupport=true）", () => {
  for (const text of ["我覺得好痛苦撐不下去", "根本沒有人需要我", "每天都好難過"]) {
    const r = analyze(text);
    assert.equal(r.safety.riskLevel, "high", `「${text}」應為 high`);
    assert.equal(r.safety.needsHumanSupport, true);
  }
});

test("自傷 / 急性醫療 / 跌倒 → urgent，門檻不退化", () => {
  for (const text of ["我不想活了", "我想死", "我胸痛", "剛剛在浴室跌倒"]) {
    const r = analyze(text);
    assert.equal(r.safety.riskLevel, "urgent", `「${text}」應為 urgent`);
    assert.equal(r.safety.needsHumanSupport, true);
  }
});

test("normalizeRiskLevel 對舊值做讀取相容（normal→low、attention→medium）", () => {
  assert.equal(normalizeRiskLevel("normal"), "low");
  assert.equal(normalizeRiskLevel("attention"), "medium");
  assert.equal(normalizeRiskLevel("urgent"), "urgent");
  assert.equal(normalizeRiskLevel("high"), "high");
  // 大小寫 / 空白不敏感；未知值原樣交給 enumValue fallback 處理
  assert.equal(normalizeRiskLevel(" Attention "), "medium");
  assert.equal(normalizeRiskLevel("bogus"), "bogus");
});

// ---- CR-0003 Batch 2：careAlertSummary 與觸發策略 ----

test("#1 medium：有持續觀察摘要，但 needsHumanSupport=false", () => {
  const r = analyze("最近都睡不好");
  assert.equal(r.safety.riskLevel, "medium");
  assert.equal(r.safety.needsHumanSupport, false);
  assert.match(r.careAlertSummary, /持續觀察/);
});

test("#2 high：有 triggerSummary，且 needsHumanSupport=true", () => {
  const r = analyze("每天都好難過，覺得沒有人需要我");
  assert.equal(r.safety.riskLevel, "high");
  assert.equal(r.safety.needsHumanSupport, true);
  assert.ok(r.careAlertSummary.length > 0);
  assert.match(r.careAlertSummary, /主動關心/);
});

test("#3 urgent：有 triggerSummary，且 needsHumanSupport=true，建議立即確認安全", () => {
  const r = analyze("我剛剛在浴室跌倒了");
  assert.equal(r.safety.riskLevel, "urgent");
  assert.equal(r.safety.needsHumanSupport, true);
  assert.match(r.careAlertSummary, /確認安全/);
  assert.match(r.careAlertSummary, /立即|儘快/);
});

test("low：careAlertSummary 為一般狀態、不誇大警示", () => {
  const r = analyze("今天太陽很好");
  assert.equal(r.safety.riskLevel, "low");
  assert.equal(r.safety.needsHumanSupport, false);
  assert.match(r.careAlertSummary, /大致平穩|不需特別處理/);
  assert.doesNotMatch(r.careAlertSummary, /緊急|危險|立即|嚴重/);
});
