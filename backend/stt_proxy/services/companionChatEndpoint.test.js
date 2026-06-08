"use strict";

const assert = require("node:assert/strict");
const { test } = require("node:test");

process.env.NODE_ENV = "test";
const app = require("../server");

// require server 會載入 .env（含真實金鑰 / token）。這裡清掉 OpenAI 金鑰，
// 確保此端點測試「絕不」真的打 OpenAI；client 已於 require 時建立，
// 端點以 request 時的 process.env.OPENAI_API_KEY 判斷可用性，故清掉後走 openai_unavailable。
delete process.env.OPENAI_API_KEY;
// 同時確保不誤發 Telegram。
delete process.env.TELEGRAM_BOT_TOKEN;
delete process.env.TELEGRAM_CARE_CHAT_ID;

function startServer() {
  return new Promise((resolve) => {
    const server = app.listen(0, "127.0.0.1", () => resolve(server));
  });
}

function postChat(baseUrl, body) {
  return fetch(`${baseUrl}/api/companion/chat`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

test("缺 userText → 400 + { success:false, error:'invalid_input' }", async () => {
  const server = await startServer();
  try {
    const { port } = server.address();
    const base = `http://127.0.0.1:${port}`;

    const empty = await postChat(base, { userText: "" });
    assert.equal(empty.status, 400);
    assert.deepEqual(await empty.json(), { success: false, error: "invalid_input" });

    const missing = await postChat(base, { petName: "小白" });
    assert.equal(missing.status, 400);
    assert.deepEqual(await missing.json(), {
      success: false,
      error: "invalid_input",
    });

    const whitespace = await postChat(base, { userText: "   " });
    assert.equal(whitespace.status, 400);
    assert.deepEqual(await whitespace.json(), {
      success: false,
      error: "invalid_input",
    });
  } finally {
    server.close();
  }
});

test("OpenAI 不可用（無金鑰）→ 503 + openai_unavailable，不回 fake reply / stack", async () => {
  const server = await startServer();
  try {
    const { port } = server.address();
    const base = `http://127.0.0.1:${port}`;

    const res = await postChat(base, {
      userText: "今天有點無聊，沒人陪我",
      petName: "小白",
      memoryContextSummary: "喜歡散步、女兒住台中",
    });
    assert.equal(res.status, 503);
    const body = await res.json();
    assert.deepEqual(body, { success: false, error: "openai_unavailable" });
    // 不得出現 fake reply 或 stack。
    assert.equal("reply" in body, false);
    assert.equal("stack" in body, false);
  } finally {
    server.close();
  }
});
