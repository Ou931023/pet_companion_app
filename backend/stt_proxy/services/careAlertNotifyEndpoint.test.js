const assert = require("node:assert/strict");
const test = require("node:test");

process.env.NODE_ENV = "test";
const app = require("../server");

function startServer() {
  return new Promise((resolve) => {
    const server = app.listen(0, "127.0.0.1", () => resolve(server));
  });
}

const validBody = {
  riskLevel: "urgent",
  riskLevelLabel: "緊急",
  category: "other",
  categoryLabel: "其他",
  triggerSummary: "對話中偵測到需要關心的狀況",
  transcriptSnippet: "我昨天晚上都睡不好，今天有點頭暈。",
  createdAt: "2026-05-28T16:30:00.000Z",
  source: "companion_analysis",
};

test("POST /api/care-alerts/notify 缺欄位時回 400 invalid_payload", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const response = await fetch(`${baseUrl}/api/care-alerts/notify`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ riskLevel: "urgent" }),
    });
    const body = await response.json();
    assert.equal(response.status, 400);
    assert.deepEqual(body, { success: false, error: "invalid_payload" });
  } finally {
    server.close();
  }
});

test("POST /api/care-alerts/notify 成功時回 success:true", async () => {
  // 只攔截對 Telegram 的外連，讓 client→本機 server 的請求照常走真實 fetch。
  const realFetch = global.fetch;
  const originalToken = process.env.TELEGRAM_BOT_TOKEN;
  const originalChatId = process.env.TELEGRAM_CARE_CHAT_ID;
  const server = await startServer();
  try {
    process.env.TELEGRAM_BOT_TOKEN = "test-token";
    process.env.TELEGRAM_CARE_CHAT_ID = "123456";
    global.fetch = async (url, options) => {
      if (typeof url === "string" && url.includes("api.telegram.org")) {
        return { ok: true, status: 200, json: async () => ({ ok: true }) };
      }
      return realFetch(url, options);
    };
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const response = await fetch(`${baseUrl}/api/care-alerts/notify`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(validBody),
    });
    const body = await response.json();
    assert.equal(response.status, 200);
    assert.deepEqual(body, { success: true });
  } finally {
    global.fetch = realFetch;
    if (originalToken === undefined) delete process.env.TELEGRAM_BOT_TOKEN;
    else process.env.TELEGRAM_BOT_TOKEN = originalToken;
    if (originalChatId === undefined) delete process.env.TELEGRAM_CARE_CHAT_ID;
    else process.env.TELEGRAM_CARE_CHAT_ID = originalChatId;
    server.close();
  }
});

test("POST /api/care-alerts/notify 未設定 token 時回 success:false telegram_not_configured", async () => {
  const originalToken = process.env.TELEGRAM_BOT_TOKEN;
  const originalChatId = process.env.TELEGRAM_CARE_CHAT_ID;
  const server = await startServer();
  try {
    delete process.env.TELEGRAM_BOT_TOKEN;
    delete process.env.TELEGRAM_CARE_CHAT_ID;
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const response = await fetch(`${baseUrl}/api/care-alerts/notify`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(validBody),
    });
    const body = await response.json();
    assert.equal(response.status, 200);
    assert.deepEqual(body, { success: false, error: "telegram_not_configured" });
  } finally {
    if (originalToken === undefined) delete process.env.TELEGRAM_BOT_TOKEN;
    else process.env.TELEGRAM_BOT_TOKEN = originalToken;
    if (originalChatId === undefined) delete process.env.TELEGRAM_CARE_CHAT_ID;
    else process.env.TELEGRAM_CARE_CHAT_ID = originalChatId;
    server.close();
  }
});
