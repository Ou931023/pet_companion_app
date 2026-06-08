const assert = require("node:assert/strict");
const test = require("node:test");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

// notify 現在會持久化 CareAlert；把 runtime data 檔導到 temp，避免污染正式 data。
process.env.CARE_ALERTS_DATA_FILE = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), "care_alerts_notify_ep_")),
  "care_alerts.json",
);
process.env.NODE_ENV = "test";
const app = require("../server");
const notificationLog = require("./notificationLogService");
// CR-0045 B2：/notify 現在掛 requireResidentCaller；安裝 resident-caller stub 並帶 token。
const { installResidentCallerStub } = require("./auth/residentCallerContext.testsupport");
installResidentCallerStub({
  "res-token": {
    uid: "fb-res",
    userId: "user-res",
    elderId: "11111111-1111-1111-1111-111111111111",
  },
});
const RES_AUTH = { Authorization: "Bearer res-token" };

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

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
      headers: { "Content-Type": "application/json", ...RES_AUTH },
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
      headers: { "Content-Type": "application/json", ...RES_AUTH },
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
      headers: { "Content-Type": "application/json", ...RES_AUTH },
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

// CR-0034 B2：解耦通知與持久化。
// 持久化失敗時——(1) high/urgent 通知照送、回應形狀不變；(2) notification_logs 明確記一列
// outcome='persist_failed'（不靜默漏記、不假成功）。
test("POST /api/care-alerts/notify：持久化失敗仍送通知，且記一列 persist_failed", async () => {
  const realFetch = global.fetch;
  const originalToken = process.env.TELEGRAM_BOT_TOKEN;
  const originalChatId = process.env.TELEGRAM_CARE_CHAT_ID;
  const originalDataFile = process.env.CARE_ALERTS_DATA_FILE;

  // 注入 mock pg 給 notificationLogService（攔截稽核寫入，DB 視為可用）。
  const captured = [];
  notificationLog.setPgForTest({
    isPostgresAvailable: async () => true,
    query: async (text, params) => {
      captured.push({ text, params });
      return { rows: [] };
    },
  });

  // 讓 CareAlert 持久化必定失敗：把資料檔的「目錄」指向一個既有檔案 → mkdir 失敗。
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "care_alerts_persist_fail_"));
  const blocker = path.join(dir, "blocker");
  fs.writeFileSync(blocker, "x");
  process.env.CARE_ALERTS_DATA_FILE = path.join(blocker, "care_alerts.json");

  const server = await startServer();
  try {
    process.env.TELEGRAM_BOT_TOKEN = "test-token";
    process.env.TELEGRAM_CARE_CHAT_ID = "123456";
    let telegramSent = false;
    global.fetch = async (url, options) => {
      if (typeof url === "string" && url.includes("api.telegram.org")) {
        telegramSent = true;
        return { ok: true, status: 200, json: async () => ({ ok: true }) };
      }
      return realFetch(url, options);
    };

    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    // 用獨立 source，避開與其他測試共用的 in-process Telegram cooldown。
    const response = await fetch(`${baseUrl}/api/care-alerts/notify`, {
      method: "POST",
      headers: { "Content-Type": "application/json", ...RES_AUTH },
      body: JSON.stringify({ ...validBody, source: "persist_fail_test" }),
    });
    const body = await response.json();

    // 通知照送、回應形狀不變（與成功情境一致）。
    assert.equal(response.status, 200);
    assert.deepEqual(body, { success: true });
    assert.equal(telegramSent, true, "持久化失敗不可阻擋 high/urgent 通知");

    // 等 fire-and-forget 稽核寫入完成。
    await sleep(50);
    const persistRow = captured.find(
      (c) => Array.isArray(c.params) && c.params[4] === "persist_failed",
    );
    assert.ok(persistRow, "持久化失敗應明確記一列 persist_failed");
    assert.equal(persistRow.params[2], "care_alert_store"); // channel
    assert.ok(persistRow.params[5], "應帶 error_code（持久化錯誤碼）");
    // 仍有一列 telegram 'sent'（通知未被漏記）。
    assert.ok(
      captured.some((c) => c.params && c.params[4] === "sent" && c.params[2] === "telegram"),
      "通知結局仍需記一列 sent",
    );
  } finally {
    global.fetch = realFetch;
    notificationLog.setPgForTest(null);
    if (originalToken === undefined) delete process.env.TELEGRAM_BOT_TOKEN;
    else process.env.TELEGRAM_BOT_TOKEN = originalToken;
    if (originalChatId === undefined) delete process.env.TELEGRAM_CARE_CHAT_ID;
    else process.env.TELEGRAM_CARE_CHAT_ID = originalChatId;
    if (originalDataFile === undefined) delete process.env.CARE_ALERTS_DATA_FILE;
    else process.env.CARE_ALERTS_DATA_FILE = originalDataFile;
    server.close();
  }
});
