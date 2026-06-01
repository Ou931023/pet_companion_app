const test = require("node:test");
const assert = require("node:assert/strict");

const { analyzeCompanionTurn } = require("./companion_engine");
const {
  planNextStrategy,
  hasReminderIntent,
  hasMemoryRecallIntent,
  hasEventCue,
  isTiredContent,
  isAmbiguous,
} = require("./next_strategy_planner");

function analyze(transcript, extra = {}) {
  return analyzeCompanionTurn({
    userId: "demo-user",
    sessionId: "session-001",
    turnId: `turn-${transcript}`,
    petName: "咕咕",
    transcript,
    languageHint: "zh",
    recentTurns: [],
    ...extra,
  });
}

// 模板化罐頭話：回覆策略指引不應「叫 AI 一直用陪伴 / 鼓勵罐頭話」。
const TEMPLATE_PHRASES = ["一起加油", "不要難過", "別難過"];

test("情境①：『今天我跟朋友吵架了』→ 針對事件追問，不是只說會陪你", () => {
  const r = analyze("今天我跟朋友吵架了");
  assert.equal(r.nextStrategy.mode, "comfort_lightly");
  // 指引要求針對事件本身回應 / 追問，而不是只給安慰。
  assert.match(r.nextStrategy.instruction, /事|追問|後來|感覺/);
  assert.match(r.nextStrategy.instruction, /不要只給安慰|不要只安慰|不要過度安慰|不要只給安慰或鼓勵/);
  for (const phrase of TEMPLATE_PHRASES) {
    assert.ok(
      !r.nextStrategy.instruction.includes(phrase),
      `指引不應出現罐頭話「${phrase}」`,
    );
  }
});

test("情境②：『我今天好累』→ 區分身體累 / 心裡累，不直接長篇鼓勵", () => {
  const r = analyze("我今天好累");
  assert.equal(r.nextStrategy.mode, "comfort_lightly");
  assert.match(r.nextStrategy.instruction, /身體累|心裡累/);
  assert.match(r.nextStrategy.instruction, /不要.*長篇|別.*長篇|不要說教|最多/);
});

test("情境③：『提醒我晚上八點吃藥』→ 走 tool_action 交給工具，不只聊天", () => {
  const r = analyze("提醒我晚上八點吃藥");
  assert.equal(r.nextStrategy.mode, "tool_action");
  assert.match(r.nextStrategy.instruction, /提醒|處理|記下/);
  assert.match(r.nextStrategy.instruction, /不要只.*閒聊|工具|功能接手/);
});

test("情境④：『你還記得我上次說我兒子要回來嗎』→ 走 memory_recall 引用記憶", () => {
  const r = analyze("你還記得我上次說我兒子要回來嗎");
  assert.equal(r.nextStrategy.mode, "memory_recall");
  // 自然引用、且不可說出「記憶 / 資料庫」字眼。
  assert.match(r.nextStrategy.instruction, /記得|先前|之前|回想|接話/);
  assert.match(r.nextStrategy.instruction, /不要說出/);
});

test("情境⑤：語句不清楚（只有語助詞）→ 走 clarify 簡短確認，不硬猜", () => {
  const r = analyze("那個…那個就是…齁");
  assert.equal(r.nextStrategy.mode, "clarify");
  assert.match(r.nextStrategy.instruction, /再說一次|說清楚|覆述/);
  assert.match(r.nextStrategy.instruction, /不要硬猜|不要假裝/);
});

test("高風險健康內容優先於一般聊天：『我胸口很痛』→ safety_check", () => {
  const r = analyze("我胸口很痛");
  assert.equal(r.safety.riskLevel, "urgent");
  assert.equal(r.nextStrategy.mode, "safety_check");
  assert.match(r.nextStrategy.instruction, /安全|聯絡|緊急|醫療/);
  // 不可用醫療診斷語氣（指引明確要求「不要做醫療診斷」）。
  assert.match(r.nextStrategy.instruction, /不要做醫療診斷/);
});

test("強烈無助（high）也走 safety_check，但語氣不診斷", () => {
  const r = analyze("每天都好難過，覺得沒有人需要我");
  assert.equal(r.safety.riskLevel, "high");
  assert.equal(r.nextStrategy.mode, "safety_check");
  assert.match(r.nextStrategy.instruction, /先.*接住|認真在聽|確認/);
  assert.match(r.nextStrategy.instruction, /不要做醫療診斷|不要說教/);
});

test("明確問句（低風險、無情緒）→ answer_directly 直接回答", () => {
  const r = analyze("現在幾點");
  assert.equal(r.nextStrategy.mode, "answer_directly");
  assert.match(r.nextStrategy.instruction, /直接|簡短/);
});

test("一般日常閒聊 → normal_chat，且不堆陪伴罐頭話", () => {
  const r = analyze("今天太陽很好");
  assert.equal(r.nextStrategy.mode, "normal_chat");
  assert.match(r.nextStrategy.instruction, /順著|自然接話|最多問一個問題/);
  assert.match(r.nextStrategy.instruction, /不要每次都用陪伴|罐頭話/);
});

test("知識型問題維持既有 knowledge_response（不被新流程吃掉）", () => {
  const r = analyze("跟我說健康小知識");
  assert.equal(r.needsSearch, true);
  assert.equal(r.nextStrategy.mode, "knowledge_response");
});

test("情境⑥：『我不想活了』→ emotional_risk，走安全流程、非一般聊天", () => {
  const r = analyze("我不想活了");
  assert.equal(r.safety.riskLevel, "urgent");
  assert.equal(r.safety.needsHumanSupport, true);
  assert.equal(r.nextStrategy.mode, "safety_check");
  assert.notEqual(r.nextStrategy.mode, "normal_chat");
});

test("回覆指引不堆過度模板化陪伴句（我會陪你 / 不要難過 / 一起加油）", () => {
  // 各輸入類型代表句：emotion / event / request / small_talk / memory /
  // health_risk / emotional_risk / unclear。
  const inputs = [
    "今天我跟朋友吵架了",
    "我今天好累",
    "提醒我晚上八點吃藥",
    "今天太陽很好",
    "你還記得我上次說的事嗎",
    "我胸口很痛",
    "我不想活了",
    "那個…就是…齁",
    "我剛吃飽",
    "我很煩",
  ];
  const banned = ["我會陪你", "不要難過", "別難過", "一起加油"];
  for (const text of inputs) {
    const instruction = analyze(text).nextStrategy.instruction;
    for (const phrase of banned) {
      assert.ok(
        !instruction.includes(phrase),
        `「${text}」的指引不應含模板化陪伴句「${phrase}」：${instruction}`,
      );
    }
  }
});

// ---- 意圖偵測純函式（邊界）----

test("hasReminderIntent / hasMemoryRecallIntent / hasEventCue 基本判斷", () => {
  assert.ok(hasReminderIntent("提醒我吃藥", "daily_chat"));
  assert.ok(hasReminderIntent("隨便講", "reminder_support"));
  assert.ok(!hasReminderIntent("今天天氣不錯", "daily_chat"));

  assert.ok(hasMemoryRecallIntent("你還記得我兒子嗎"));
  assert.ok(hasMemoryRecallIntent("我上次說的那件事"));
  assert.ok(!hasMemoryRecallIntent("我今天很開心"));

  assert.ok(hasEventCue("我跟鄰居吵架"));
  assert.ok(!hasEventCue("天氣很好"));
});

test("isTiredContent / isAmbiguous 邊界", () => {
  assert.ok(isTiredContent("好累", "neutral"));
  assert.ok(isTiredContent("還好", "tired"));
  assert.ok(!isTiredContent("我很開心", "happy"));

  assert.ok(isAmbiguous("那個…就是…"));
  assert.ok(isAmbiguous("嗯嗯嗯"));
  assert.ok(!isAmbiguous("我今天去公園散步"));
  assert.ok(!isAmbiguous("")); // 空字串交由 engine 上游處理
});

test("planNextStrategy 永遠回傳 {mode, instruction} 兩個欄位（schema 不變）", () => {
  const r = planNextStrategy({
    emotion: "neutral",
    companionNeed: "daily_chat",
    replyStrategy: "normal_chat",
    safety: { riskLevel: "low", needsHumanSupport: false },
    transcript: "今天太陽很好",
  });
  assert.deepEqual(Object.keys(r), ["mode", "instruction"]);
  assert.ok(r.instruction.length > 0);
});

test("台語 languageHint 仍附上自然台語與溫和追問指引", () => {
  const r = analyze("睡不太著", { languageHint: "taigi" });
  assert.match(r.nextStrategy.instruction, /台灣長者自然聽得懂/);
  assert.match(r.nextStrategy.instruction, /溫和追問/);
});
