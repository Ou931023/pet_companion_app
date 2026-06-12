"use strict";

// CR-0075：記憶端點身分驗證測試。
// 驗：所有記憶端點掛 requireResidentCaller（無 token → 401）、有效 token 通過、
// client 帶與 caller.elderId 不符的 userId → 403 forbidden_resident（防讀寫他人記憶）。
// 用 installResidentCallerStub（同 companionChatEndpoint.test.js）；無 OPENAI key / 無 DB
// 走 JSON fallback，MEMORY_DATA_DIR 指向 temp 避免污染正式 data。

const assert = require("node:assert/strict");
const { test, beforeEach, afterEach } = require("node:test");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

process.env.NODE_ENV = "test";
process.env.MEMORY_DATA_DIR = fs.mkdtempSync(path.join(os.tmpdir(), "mem_auth_"));
delete process.env.OPENAI_API_KEY;
delete process.env.DATABASE_URL;
process.env.PGVECTOR_ENABLED = "false";
delete process.env.TELEGRAM_BOT_TOKEN;

const app = require("../../server");
const {
  installResidentCallerStub,
} = require("../auth/residentCallerContext.testsupport");

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

async function send(base, method, route, { body, headers } = {}) {
  const r = await fetch(`${base}${route}`, {
    method,
    headers: { "Content-Type": "application/json", ...(headers || {}) },
    body: body == null ? undefined : JSON.stringify(body),
  });
  let parsed = null;
  try {
    parsed = await r.json();
  } catch {
    parsed = null;
  }
  return { status: r.status, body: parsed };
}

test("無 token → 記憶端點一律 401 missing_resident_token", async () => {
  const server = await startServer();
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    const context = await send(base, "POST", "/api/memories/context", {
      body: { userText: "我想聊聊最近的生活" },
    });
    assert.equal(context.status, 401);
    assert.equal(context.body.error, "missing_resident_token");

    const list = await send(base, "GET", "/api/memories");
    assert.equal(list.status, 401);

    const forget = await send(base, "POST", "/api/memory/forget-recent", { body: {} });
    assert.equal(forget.status, 401);
  } finally {
    server.close();
  }
});

test("有效 token + 未帶 userId → 通過（非 401/403）", async () => {
  const server = await startServer();
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    const context = await send(base, "POST", "/api/memories/context", {
      headers: RES_A,
      body: { userText: "我想聊聊最近的生活" },
    });
    assert.notEqual(context.status, 401);
    assert.notEqual(context.status, 403);

    const list = await send(base, "GET", "/api/memories", { headers: RES_A });
    assert.equal(list.status, 200);
  } finally {
    server.close();
  }
});

test("有效 token + 帶與 caller.elderId 相符的 userId → 通過", async () => {
  const server = await startServer();
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    const res = await send(base, "POST", "/api/memories/context", {
      headers: RES_A,
      body: { userText: "我想聊聊最近的生活", userId: ELDER_A },
    });
    assert.notEqual(res.status, 401);
    assert.notEqual(res.status, 403);
  } finally {
    server.close();
  }
});

test("有效 token + 帶不符的 userId（body）→ 403 forbidden_resident", async () => {
  const server = await startServer();
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    const res = await send(base, "POST", "/api/memories/context", {
      headers: RES_A,
      body: { userText: "我想聊聊最近的生活", userId: "someone-else" },
    });
    assert.equal(res.status, 403);
    assert.equal(res.body.error, "forbidden_resident");
  } finally {
    server.close();
  }
});

test("有效 token + 帶不符的 userId（query）→ 403 forbidden_resident", async () => {
  const server = await startServer();
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    const res = await send(base, "GET", "/api/memories?userId=someone-else", {
      headers: RES_A,
    });
    assert.equal(res.status, 403);
    assert.equal(res.body.error, "forbidden_resident");
  } finally {
    server.close();
  }
});

test("archive / extract / forget-recent 無 token 皆 401；有 token 不再 401", async () => {
  const server = await startServer();
  try {
    const base = `http://127.0.0.1:${server.address().port}`;

    const archiveNoAuth = await send(base, "PATCH", "/api/memories/some-id/archive", {
      body: {},
    });
    assert.equal(archiveNoAuth.status, 401);

    const extractNoAuth = await send(base, "POST", "/api/memories/extract", {
      body: { userText: "我女兒住台中" },
    });
    assert.equal(extractNoAuth.status, 401);

    const forgetWithAuth = await send(base, "POST", "/api/memory/forget-recent", {
      headers: RES_A,
      body: {},
    });
    assert.notEqual(forgetWithAuth.status, 401);
    assert.notEqual(forgetWithAuth.status, 403);
  } finally {
    server.close();
  }
});
