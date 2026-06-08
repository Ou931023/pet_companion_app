"use strict";

const assert = require("node:assert/strict");
const { test } = require("node:test");

const { generateCompanionReply } = require("./companionChatService");

// 固定回覆的 mock OpenAI client（不需真 key）。
function fakeClient(reply) {
  return {
    chat: {
      completions: {
        create: async () => ({
          choices: [{ message: { content: reply } }],
        }),
      },
    },
  };
}

test("正常輸入 → 回 { success:true, reply }（mock OpenAI 回固定字串）", async () => {
  const result = await generateCompanionReply(
    { userText: "今仔日有點無聊", systemPrompt: "你是陪伴寵物" },
    { client: fakeClient("有我陪你，免煩惱"), hasApiKey: true },
  );
  assert.deepEqual(result, { success: true, reply: "有我陪你，免煩惱" });
});

test("缺 userText → { success:false, error:'invalid_input' }，不呼叫 OpenAI", async () => {
  let called = false;
  const client = {
    chat: { completions: { create: async () => { called = true; return {}; } } },
  };
  const empty = await generateCompanionReply({ userText: "" }, { client, hasApiKey: true });
  const whitespace = await generateCompanionReply(
    { userText: "   \n  " },
    { client, hasApiKey: true },
  );
  const missing = await generateCompanionReply({}, { client, hasApiKey: true });
  assert.deepEqual(empty, { success: false, error: "invalid_input" });
  assert.deepEqual(whitespace, { success: false, error: "invalid_input" });
  assert.deepEqual(missing, { success: false, error: "invalid_input" });
  assert.equal(called, false);
});

test("無金鑰 / 無 client → openai_unavailable，不假成功", async () => {
  const noKey = await generateCompanionReply(
    { userText: "你好" },
    { client: fakeClient("hi"), hasApiKey: false },
  );
  const noClient = await generateCompanionReply(
    { userText: "你好" },
    { hasApiKey: true },
  );
  assert.deepEqual(noKey, { success: false, error: "openai_unavailable" });
  assert.deepEqual(noClient, { success: false, error: "openai_unavailable" });
  assert.equal(noKey.reply, undefined);
});

test("OpenAI 回空內容 → openai_unavailable，不退罐頭", async () => {
  const result = await generateCompanionReply(
    { userText: "你好" },
    { client: fakeClient("   "), hasApiKey: true },
  );
  assert.deepEqual(result, { success: false, error: "openai_unavailable" });
});

test("OpenAI 失敗 → openai_unavailable，不假成功、不回 stack，log 不外洩 secret", async () => {
  const logs = [];
  const throwingClient = {
    chat: {
      completions: {
        create: async () => {
          // 模擬第三方錯誤訊息夾帶金鑰。
          throw new Error("Auth failed for key sk-livesecret1234567890abcd");
        },
      },
    },
  };
  const result = await generateCompanionReply(
    { userText: "你好嗎", systemPrompt: "persona" },
    {
      client: throwingClient,
      hasApiKey: true,
      logError: (msg, extra) => logs.push({ msg, extra }),
    },
  );

  assert.deepEqual(result, { success: false, error: "openai_unavailable" });
  // 不回 reply、不回 stack。
  assert.equal(result.reply, undefined);
  assert.equal("stack" in result, false);

  // log 經 redaction：不得出現完整金鑰原文。
  const serialized = JSON.stringify(logs);
  assert.ok(
    !serialized.includes("sk-livesecret1234567890abcd"),
    "log 不可含完整金鑰原文",
  );
  // 也不可把使用者原文整段塞進 log。
  assert.ok(!serialized.includes("你好嗎"), "log 不可含 userText 原文");
});

test("成功路徑不呼叫 logError、不外洩 userText / reply", async () => {
  const logs = [];
  const result = await generateCompanionReply(
    { userText: "我今天有點累", systemPrompt: "persona" },
    {
      client: fakeClient("辛苦了，慢慢休息就好"),
      hasApiKey: true,
      logError: (msg, extra) => logs.push({ msg, extra }),
    },
  );
  assert.equal(result.success, true);
  assert.equal(logs.length, 0);
});
