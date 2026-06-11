"use strict";

const assert = require("node:assert/strict");
const { test } = require("node:test");

const {
  generateCompanionReply,
  sanitizeHistory,
} = require("./companionChatService");

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

// 會記錄收到的 messages 的 mock client（驗 system→history→user 組裝）。
function capturingClient(reply) {
  const captured = { messages: null };
  return {
    captured,
    chat: {
      completions: {
        create: async (params) => {
          captured.messages = params.messages;
          return { choices: [{ message: { content: reply } }] };
        },
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

// ---- CR-0072：對話歷史 ----

test("CR-0072 帶 history → messages 順序為 system → history → 當前 user", async () => {
  const c = capturingClient("阿明你剛說想睡覺對吧");
  const result = await generateCompanionReply(
    {
      userText: "我剛剛說我想做什麼？",
      systemPrompt: "你是陪伴寵物",
      history: [
        { role: "user", content: "我叫阿明" },
        { role: "assistant", content: "阿明你好呀" },
        { role: "user", content: "我想睡覺" },
        { role: "assistant", content: "那早點休息喔" },
      ],
    },
    { client: c, hasApiKey: true },
  );
  assert.equal(result.success, true);
  const roles = c.captured.messages.map((m) => m.role);
  assert.deepEqual(roles, [
    "system",
    "user",
    "assistant",
    "user",
    "assistant",
    "user",
  ]);
  // 最後一則為當前 user 輸入。
  assert.equal(c.captured.messages.at(-1).content, "我剛剛說我想做什麼？");
  // 歷史內容有被帶入。
  assert.equal(c.captured.messages[1].content, "我叫阿明");
});

test("CR-0072 無 history → messages 與既有單則一致（system + user）", async () => {
  const c = capturingClient("嗨");
  await generateCompanionReply(
    { userText: "你好", systemPrompt: "persona" },
    { client: c, hasApiKey: true },
  );
  assert.deepEqual(
    c.captured.messages.map((m) => m.role),
    ["system", "user"],
  );
});

test("CR-0072 髒 history（壞 role / 空 content / 非物件）被清洗掉", async () => {
  const c = capturingClient("ok");
  await generateCompanionReply(
    {
      userText: "現在呢",
      systemPrompt: "p",
      history: [
        { role: "system", content: "我是壞 role" },
        { role: "user", content: "   " },
        null,
        "字串不是物件",
        { role: "assistant", content: "我是合法的" },
      ],
    },
    { client: c, hasApiKey: true },
  );
  // 只剩合法的 assistant + 當前 user（system 來自 prompt）。
  assert.deepEqual(
    c.captured.messages.map((m) => m.role),
    ["system", "assistant", "user"],
  );
  assert.equal(c.captured.messages[1].content, "我是合法的");
});

test("CR-0072 sanitizeHistory：非陣列→空；超量截最後 12 則；content 截長", () => {
  assert.deepEqual(sanitizeHistory(undefined), []);
  assert.deepEqual(sanitizeHistory("nope"), []);
  assert.deepEqual(sanitizeHistory(null), []);

  // 20 則合法 → 只留最後 12 則。
  const many = Array.from({ length: 20 }, (_, i) => ({
    role: i % 2 === 0 ? "user" : "assistant",
    content: `m${i}`,
  }));
  const capped = sanitizeHistory(many);
  assert.equal(capped.length, 12);
  assert.equal(capped[0].content, "m8"); // 20-12 = 從 index 8 起
  assert.equal(capped.at(-1).content, "m19");

  // content 截斷至 1000 字。
  const long = sanitizeHistory([{ role: "user", content: "x".repeat(5000) }]);
  assert.equal(long[0].content.length, 1000);
});
