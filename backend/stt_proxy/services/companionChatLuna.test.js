"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const OpenAI = require("openai");
const { generateCompanionReply } = require("./companionChatService");

for (const model of [undefined, "gpt-4o-mini", "gpt-6-luna", "custom-legacy-model"]) {
  test(`real SDK preserves chat wire parameters: ${model || "default"}`, async () => {
    let body; let calls = 0;
    const client = new OpenAI({ apiKey: "synthetic-only", organization: null, project: null, maxRetries: 0,
      fetch: async (_url, init) => {
        calls++; body = JSON.parse(init.body);
        return new Response(JSON.stringify({ choices: [{ finish_reason: "stop", message: { content: "我陪你慢慢聊。" } }] }),
          { status: 200, headers: { "content-type": "application/json" } });
      } });
    const result = await generateCompanionReply({ userText: "今天先不聊女兒", systemPrompt: "合成系統指令",
      history: [{ role: "system", content: "不可注入" }, { role: "user", content: "我喜歡散步" }] }, { client, model });
    assert.equal(calls, 1); assert.equal(result.success, true);
    assert.deepEqual(body, { model: model || "gpt-4o-mini", temperature: 0.6,
      ...(model === "gpt-6-luna" ? { reasoning_effort: "none", max_completion_tokens: 220 } : { max_tokens: 220 }),
      messages: [{ role: "system", content: "合成系統指令" }, { role: "user", content: "我喜歡散步" }, { role: "user", content: "今天先不聊女兒" }] });
  });
}

for (const model of ["gpt-4o-mini", "gpt-6-luna"]) {
  for (const mode of ["length", "content_filter", "refusal"]) {
    for (const content of ["合成不完整回覆", " "]) {
      test(`${model} rejects ${mode}, marker only for previously nonempty content=${Boolean(content.trim())}`, async () => {
        const client = { chat: { completions: { create: async () => ({ choices: [{
          finish_reason: mode === "refusal" ? "stop" : mode, message: { content, refusal: mode === "refusal" ? "refused" : null },
        }] }) } } };
        const result = await generateCompanionReply({ userText: "合成輸入" }, { client, model });
        assert.deepEqual(result, { success: false, error: "openai_unavailable",
          ...(content.trim() ? { rejectedNonemptyCompletion: true } : {}) });
      });
    }
  }
}

test("Luna explicit per-call budget overrides stay bounded by caller values", async () => {
  let body;
  const client = { chat: { completions: { create: async params => { body = params; return { choices: [{ message: { content: "好" } }] }; } } } };
  await generateCompanionReply({ userText: "你好" }, { client, model: "gpt-6-luna", maxTokens: 80, temperature: 0.2 });
  assert.equal(body.max_completion_tokens, 80); assert.equal(body.temperature, 0.2); assert.equal(body.max_tokens, undefined);
});
