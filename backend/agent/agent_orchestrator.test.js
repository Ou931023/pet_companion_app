const test = require("node:test");
const assert = require("node:assert/strict");
const { routeAgentTool } = require("./agent_orchestrator");
const { buildSafeIntent } = require("./tool_policy");

test("phone call routes to high risk dialer with confirmation", () => {
  const result = routeAgentTool({ userText: "幫我打給女兒" });
  assert.equal(result.hasToolIntent, true);
  assert.equal(result.intent.toolName, "open_phone_dialer");
  assert.equal(result.intent.riskLevel, "high");
  assert.equal(result.intent.requiresConfirmation, true);
});

test("email routes to medium risk draft with confirmation", () => {
  const result = routeAgentTool({ userText: "幫我寄 email 給家人說我今天有點累" });
  assert.equal(result.intent.toolName, "create_email_draft");
  assert.equal(result.intent.riskLevel, "medium");
  assert.equal(result.intent.requiresConfirmation, true);
});

test("music routes to low risk play music", () => {
  const result = routeAgentTool({ userText: "幫我播放放鬆音樂" });
  assert.equal(result.intent.toolName, "play_music");
  assert.equal(result.intent.riskLevel, "low");
  assert.equal(result.intent.requiresConfirmation, false);
});

test("reminder routes to medium risk reminder", () => {
  const result = routeAgentTool({ userText: "提醒我晚上八點吃藥" });
  assert.equal(result.intent.toolName, "create_reminder");
  assert.equal(result.intent.riskLevel, "medium");
  assert.equal(result.intent.requiresConfirmation, true);
});

test("fraud news routes to trusted search", () => {
  const result = routeAgentTool({ userText: "幫我查今天的防詐騙新聞" });
  assert.equal(result.intent.toolName, "search_trusted_info");
  assert.equal(result.intent.riskLevel, "low");
});

test("unknown tools are rejected by policy", () => {
  const result = buildSafeIntent({ toolName: "delete_everything", arguments: {} });
  assert.equal(result.ok, false);
  assert.equal(result.reason, "unknown_tool");
});
