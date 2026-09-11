const { analyzeCompanionTurn } = require("./companion_engine");

// 固定、無真實使用者資料的國語策略 corpus。這裡評估 deterministic planner
// 與安全分流；實際模型措辭、首音延遲仍需另外以真 API / iOS 實機驗證。
const MANDARIN_STRATEGY_CORPUS = Object.freeze([
  {
    id: "daily-chat",
    category: "daily_chat",
    transcript: "我今天去公園走了一圈，風很舒服",
    expectedMode: "normal_chat",
    expectedRisk: "low",
  },
  {
    id: "repeated-paraphrase",
    category: "repetition",
    transcript: "今天天氣真的不錯",
    recentTurns: [
      { petReply: "今天天氣真不錯，你有出去走走嗎？" },
      { petReply: "聽起來今天很舒服，你想去附近散步嗎？" },
    ],
    expectedMode: "normal_chat",
    expectedRisk: "low",
    requiresRecentReplyGuard: true,
  },
  {
    id: "lonely-low-mood",
    category: "emotional_support",
    transcript: "今天家裡好安靜，都沒有人跟我說話",
    expectedMode: "comfort_lightly",
    expectedRisk: "low",
  },
  {
    id: "memory-recall",
    category: "memory",
    transcript: "你還記得我之前說女兒星期天要回來嗎？",
    retrievedMemories: [{ memorySummary: "女兒預計星期天回家吃飯" }],
    expectedMode: "memory_recall",
    expectedRisk: "low",
    requiresMemoryContext: true,
  },
  {
    id: "reminder-tool",
    category: "tool_intent",
    transcript: "提醒我晚上八點要吃藥",
    expectedMode: "tool_action",
    expectedRisk: "low",
  },
  {
    id: "urgent-safety",
    category: "urgent_safety",
    transcript: "我剛剛在浴室跌倒，現在站不起來",
    expectedMode: "safety_check",
    expectedRisk: "urgent",
    expectedHumanSupport: true,
    excludesRecentReplyGuard: true,
  },
]);

function evaluateMandarinStrategyCorpus(corpus = MANDARIN_STRATEGY_CORPUS) {
  const results = corpus.map((scenario) => {
    const analysis = analyzeCompanionTurn({
      userId: "corpus-user",
      sessionId: "mandarin-quality-corpus",
      turnId: scenario.id,
      petName: "陪伴寶",
      transcript: scenario.transcript,
      languageHint: "zh",
      recentTurns: scenario.recentTurns || [],
      retrievedMemories: scenario.retrievedMemories || [],
    });
    const instruction = analysis.nextStrategy.instruction;
    const checks = {
      mode: analysis.nextStrategy.mode === scenario.expectedMode,
      risk: analysis.safety.riskLevel === scenario.expectedRisk,
      humanSupport:
        scenario.expectedHumanSupport === undefined ||
        analysis.safety.needsHumanSupport === scenario.expectedHumanSupport,
      normalCadence:
        scenario.expectedRisk === "urgent" ||
        (/1–3 句/.test(instruction) && /最多一個問題/.test(instruction)),
      recentReplyGuard:
        !scenario.requiresRecentReplyGuard ||
        (/最近幾次已經回過/.test(instruction) && /不要逐字重複/.test(instruction)),
      memoryContext:
        !scenario.requiresMemoryContext || instruction.includes("女兒預計星期天回家吃飯"),
      urgentGuardIsolation:
        !scenario.excludesRecentReplyGuard || !instruction.includes("最近幾次已經回過"),
    };
    const failures = Object.entries(checks)
      .filter(([, passed]) => !passed)
      .map(([name]) => name);

    return {
      id: scenario.id,
      category: scenario.category,
      passed: failures.length === 0,
      failures,
      actualMode: analysis.nextStrategy.mode,
      actualRisk: analysis.safety.riskLevel,
    };
  });

  return {
    total: results.length,
    passed: results.filter((result) => result.passed).length,
    failures: results.filter((result) => !result.passed),
    results,
  };
}

module.exports = {
  MANDARIN_STRATEGY_CORPUS,
  evaluateMandarinStrategyCorpus,
};
