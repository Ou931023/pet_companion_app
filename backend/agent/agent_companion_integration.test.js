// CR-0015c：Agent intent（CR-0015a）與 Companion 對話策略（CR-0014）的跨模組整合檢查。
//
// 兩者是互補的兩面：companion 決定「寵物怎麼說」（reply strategy），
// agent 決定「要不要執行工具」（tool intent）。本測試確認在「安全 / 記憶 /
// 聽不懂 / 提醒」這些關鍵情境，兩邊路由一致；高影響工具一律需確認；
// 兩邊給使用者看的文字都不含工程字。

const test = require("node:test");
const assert = require("node:assert/strict");

const { analyzeCompanionTurn } = require("../companion/companion_engine");
const { classifyAgentIntent } = require("./agent_intent");

const BANNED = ["api", "json", "database", "route", "payload", "toolname"];

function companion(transcript) {
  return analyzeCompanionTurn({ transcript, turnId: `t-${transcript}` }).nextStrategy;
}
function agent(transcript) {
  return classifyAgentIntent({ userText: transcript });
}

test("健康危急：companion 走 safety_check、agent 走 health_risk 並要求安全流程", () => {
  for (const text of ["我胸口很痛", "我喘不過氣"]) {
    assert.equal(companion(text).mode, "safety_check", `${text} companion`);
    const a = agent(text);
    assert.equal(a.intent, "health_risk", `${text} agent`);
    assert.equal(a.requiresSafetyFlow, true);
    assert.equal(a.toolName, null, "危急不當工具執行");
  }
});

test("情緒危機：companion 走 safety_check、agent 走 emotional_risk 並要求安全流程", () => {
  for (const text of ["我不想活了", "覺得沒有人需要我"]) {
    assert.equal(companion(text).mode, "safety_check", `${text} companion`);
    const a = agent(text);
    assert.equal(a.intent, "emotional_risk", `${text} agent`);
    assert.equal(a.requiresSafetyFlow, true);
  }
});

test("記憶查詢：companion memory_recall、agent recall_memory（兩邊一致走記憶）", () => {
  const text = "你還記得我上次說我兒子要回來嗎";
  assert.equal(companion(text).mode, "memory_recall");
  assert.equal(agent(text).intent, "recall_memory");
});

test("聽不懂：companion clarify、agent clarify（都不硬猜）", () => {
  const text = "那個…那個就是…齁";
  assert.equal(companion(text).mode, "clarify");
  assert.equal(agent(text).intent, "clarify");
});

test("提醒：companion tool_action 交給工具、agent create_reminder（低風險直接做）", () => {
  const text = "晚上八點提醒我吃藥";
  assert.equal(companion(text).mode, "tool_action");
  const a = agent(text);
  assert.equal(a.intent, "create_reminder");
  assert.equal(a.needsConfirmation, false);
});

test("高影響工具一律需確認（make_call / send_message）", () => {
  assert.equal(agent("幫我打給女兒").needsConfirmation, true);
  assert.equal(agent("幫我跟兒子說我今天很好").needsConfirmation, true);
});

test("跨模組：兩邊給使用者看的文字都不含工程字", () => {
  const samples = [
    "我胸口很痛",
    "我不想活了",
    "你還記得我上次說我兒子要回來嗎",
    "那個…就是…齁",
    "晚上八點提醒我吃藥",
    "幫我打給女兒",
    "幫我跟兒子說我今天很好",
    "我想聽老歌",
    "我要去玩遊戲",
    "今天太陽很好",
    "我今天好累",
  ];
  for (const text of samples) {
    const cInstruction = companion(text).instruction.toLowerCase();
    const aMessage = agent(text).message.toLowerCase();
    for (const w of BANNED) {
      assert.ok(!cInstruction.includes(w), `companion「${text}」含工程字 ${w}`);
      assert.ok(!aMessage.includes(w), `agent「${text}」含工程字 ${w}`);
    }
  }
});

test("安全優先：危急句即使含工具字，agent 仍優先走安全（不被工具吃掉）", () => {
  const a = agent("我胸口很痛，幫我打給女兒");
  assert.equal(a.intent, "health_risk");
  assert.equal(a.requiresSafetyFlow, true);
  // companion 同句也應判為高風險（safety_check）。
  assert.equal(companion("我胸口很痛，幫我打給女兒").mode, "safety_check");
});
