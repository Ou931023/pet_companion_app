const test = require("node:test");
const assert = require("node:assert/strict");

const {
  AGENT_INTENTS,
  classifyAgentIntent,
  buildAgentToolResult,
} = require("./agent_intent");

function intentOf(text) {
  return classifyAgentIntent({ userText: text });
}

// 使用者看得到的 message 不可出現工程字。
const BANNED_WORDS = ["api", "json", "database", "route", "payload", "toolname"];

test("「我想聽老歌」→ play_music", () => {
  const r = intentOf("我想聽老歌");
  assert.equal(r.intent, "play_music");
  assert.equal(r.needsConfirmation, false);
});

test("「幫我打給女兒」→ make_call（需確認）", () => {
  const r = intentOf("幫我打給女兒");
  assert.equal(r.intent, "make_call");
  assert.equal(r.needsConfirmation, true);
});

test("「幫我跟兒子說我今天很好」→ send_message（需確認）", () => {
  const r = intentOf("幫我跟兒子說我今天很好");
  assert.equal(r.intent, "send_message");
  assert.equal(r.needsConfirmation, true);
});

test("「晚上八點提醒我吃藥」→ create_reminder（低風險直接做）", () => {
  const r = intentOf("晚上八點提醒我吃藥");
  assert.equal(r.intent, "create_reminder");
  assert.equal(r.needsConfirmation, false);
});

test("「幫我記住女兒週末會回來」→ save_memory", () => {
  const r = intentOf("幫我記住女兒週末會回來");
  assert.equal(r.intent, "save_memory");
});

test("「你還記得我兒子什麼時候回來嗎」→ recall_memory", () => {
  const r = intentOf("你還記得我兒子什麼時候回來嗎");
  assert.equal(r.intent, "recall_memory");
});

test("「我要去玩遊戲」→ navigate", () => {
  const r = intentOf("我要去玩遊戲");
  assert.equal(r.intent, "navigate");
});

test("「我胸口很痛」→ health_risk 優先、走安全流程，不當工具", () => {
  const r = intentOf("我胸口很痛");
  assert.equal(r.intent, "health_risk");
  assert.equal(r.requiresSafetyFlow, true);
  assert.equal(r.toolName, null);
});

test("「我不想活了」→ emotional_risk 優先、走安全流程", () => {
  const r = intentOf("我不想活了");
  assert.equal(r.intent, "emotional_risk");
  assert.equal(r.requiresSafetyFlow, true);
  assert.equal(r.toolName, null);
});

test("語意不清 → clarify，不硬猜", () => {
  for (const text of ["那個…就是…齁", "嗯嗯嗯", ""]) {
    assert.equal(intentOf(text).intent, "clarify", `「${text}」應為 clarify`);
  }
});

test("健康 / 情緒危機優先於工具（同句含工具字也走安全）", () => {
  // 同時提到「打給」與胸口痛 → 仍優先 health_risk。
  const r = intentOf("我胸口很痛，幫我打給女兒");
  assert.equal(r.intent, "health_risk");
  assert.equal(r.requiresSafetyFlow, true);
});

test("tell_story / search_info 也被涵蓋", () => {
  assert.equal(intentOf("說一個故事給我聽").intent, "tell_story");
  assert.equal(intentOf("幫我查今天的防詐騙新聞").intent, "search_info");
});

test("AgentToolResult 結構固定，且 message 不含工程字", () => {
  const samples = [
    "我想聽老歌",
    "幫我打給女兒",
    "幫我跟兒子說我今天很好",
    "晚上八點提醒我吃藥",
    "幫我記住女兒週末會回來",
    "你還記得我兒子什麼時候回來嗎",
    "我要去玩遊戲",
    "我胸口很痛",
    "我不想活了",
    "那個…就是…",
    "說一個故事給我聽",
  ];
  for (const text of samples) {
    const r = intentOf(text);
    assert.deepEqual(Object.keys(r).sort(), [
      "error",
      "intent",
      "message",
      "needsConfirmation",
      "payload",
      "requiresSafetyFlow",
      "success",
      "toolName",
    ]);
    assert.ok(AGENT_INTENTS.includes(r.intent), `未知 intent：${r.intent}`);
    const lower = r.message.toLowerCase();
    for (const w of BANNED_WORDS) {
      assert.ok(!lower.includes(w), `「${text}」message 含工程字「${w}」：${r.message}`);
    }
  }
});

test("buildAgentToolResult：預設值安全（success/error 為 null、payload 為物件）", () => {
  const r = buildAgentToolResult({ intent: "clarify", message: "再說一次好嗎？" });
  assert.equal(r.success, null);
  assert.equal(r.error, null);
  assert.deepEqual(r.payload, {});
  assert.equal(r.needsConfirmation, false);
  assert.equal(r.requiresSafetyFlow, false);
});
