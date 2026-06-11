"use strict";

const assert = require("node:assert/strict");
const { test, beforeEach, afterEach } = require("node:test");

process.env.NODE_ENV = "test";
const app = require("../server");
const {
  installResidentCallerStub,
} = require("./auth/residentCallerContext.testsupport");

// require server 會載入 .env（含真實金鑰 / token）。這裡清掉 OpenAI 金鑰，
// 確保此端點測試「絕不」真的打 OpenAI；client 已於 require 時建立，
// 端點以 request 時的 process.env.OPENAI_API_KEY 判斷可用性，故清掉後走 openai_unavailable。
delete process.env.OPENAI_API_KEY;
// 同時確保不誤發 Telegram。
delete process.env.TELEGRAM_BOT_TOKEN;
delete process.env.TELEGRAM_CARE_CHAT_ID;

// CR-0051 Batch B：/api/companion/chat 現掛 requireResidentCaller。
// 需帶有效 resident token 才能觸發 invalid_input(400) / openai_unavailable(503)。
const ELDER_A = "11111111-1111-1111-1111-111111111111";
const RES_A = { Authorization: "Bearer res-a-token" };
let restoreResident = null;

beforeEach(() => {
  restoreResident = installResidentCallerStub({
    "res-a-token": { uid: "fb-res-a", userId: "user-a", elderId: ELDER_A },
  });
});

afterEach(() => {
  if (restoreResident) restoreResident();
  restoreResident = null;
});

function startServer() {
  return new Promise((resolve) => {
    const server = app.listen(0, "127.0.0.1", () => resolve(server));
  });
}

function postChat(baseUrl, body, headers = RES_A) {
  return fetch(`${baseUrl}/api/companion/chat`, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
}

test("無 token → 401（requireResidentCaller，不進入 reply / 風險分析）", async () => {
  const server = await startServer();
  try {
    const { port } = server.address();
    const base = `http://127.0.0.1:${port}`;

    const res = await postChat(base, { userText: "今天有點無聊" }, {});
    assert.equal(res.status, 401);
    const body = await res.json();
    assert.equal(body.success, false);
    assert.equal("reply" in body, false);
    assert.equal("careAlert" in body, false);
  } finally {
    server.close();
  }
});

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

// ---- CR-0072：history 欄位向後相容（帶 / 壞值都不應讓路由壞掉或變 500）----

test("CR-0072 帶合法 history 仍正常處理（無金鑰→503，非 500/非崩潰）", async () => {
  const server = await startServer();
  try {
    const { port } = server.address();
    const base = `http://127.0.0.1:${port}`;
    const res = await postChat(base, {
      userText: "我剛剛說我叫什麼？",
      history: [
        { role: "user", content: "我叫阿明" },
        { role: "assistant", content: "阿明你好呀" },
      ],
    });
    assert.equal(res.status, 503);
    assert.deepEqual(await res.json(), {
      success: false,
      error: "openai_unavailable",
    });
  } finally {
    server.close();
  }
});

test("CR-0072 history 為壞值（非陣列 / 髒元素）不報錯（仍走既有驗證流程）", async () => {
  const server = await startServer();
  try {
    const { port } = server.address();
    const base = `http://127.0.0.1:${port}`;

    // history 非陣列 + 有效 userText → 不崩潰，無金鑰下回 503。
    const bad = await postChat(base, { userText: "嗨", history: "not-an-array" });
    assert.equal(bad.status, 503);
    assert.deepEqual(await bad.json(), {
      success: false,
      error: "openai_unavailable",
    });

    // history 含髒元素 + 缺 userText → 仍應 400 invalid_input（驗證優先、不被 history 影響）。
    const invalid = await postChat(base, {
      userText: "",
      history: [null, { role: "x" }, 123],
    });
    assert.equal(invalid.status, 400);
    assert.deepEqual(await invalid.json(), {
      success: false,
      error: "invalid_input",
    });
  } finally {
    server.close();
  }
});
