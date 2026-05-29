const assert = require("node:assert/strict");
const { test, beforeEach } = require("node:test");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

// 在 require server 之前指定 runtime data 檔到 temp，避免污染正式 data。
process.env.CARE_ALERTS_DATA_FILE = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), "care_alerts_ep_")),
  "care_alerts.json",
);
process.env.NODE_ENV = "test";
const app = require("../server");

// 重要：require server 會載入 .env（含真實 Telegram token）。這裡清掉，
// 確保測試「絕不」真的發 Telegram；持久化與 Telegram 無關，仍照常運作。
delete process.env.TELEGRAM_BOT_TOKEN;
delete process.env.TELEGRAM_CARE_CHAT_ID;

beforeEach(() => {
  // 每個測試使用全新的 temp 檔（store 在呼叫時讀 env，所以動態切換有效）。
  process.env.CARE_ALERTS_DATA_FILE = path.join(
    fs.mkdtempSync(path.join(os.tmpdir(), "care_alerts_ep_")),
    "care_alerts.json",
  );
});

function startServer() {
  return new Promise((resolve) => {
    const server = app.listen(0, "127.0.0.1", () => resolve(server));
  });
}

function postNotify(baseUrl, overrides = {}) {
  return fetch(`${baseUrl}/api/care-alerts/notify`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      riskLevel: "urgent",
      riskLevelLabel: "緊急",
      category: "other",
      categoryLabel: "其他",
      triggerSummary: "對話中偵測到需要關心的狀況",
      transcriptSnippet: "我昨天晚上都睡不好",
      createdAt: "2026-05-29T10:00:00.000Z",
      source: "companion_analysis",
      ...overrides,
    }),
  });
}

test("POST /api/care-alerts/notify 後 GET /api/care-alerts 查得到", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const postRes = await postNotify(baseUrl);
    assert.equal(postRes.status, 200); // Telegram 未設定不影響持久化與回應狀態碼

    const res = await fetch(`${baseUrl}/api/care-alerts`);
    const body = await res.json();
    assert.equal(res.status, 200);
    assert.equal(body.success, true);
    assert.equal(body.alerts.length, 1);
    assert.equal(body.alerts[0].riskLevel, "urgent");
    assert.equal(body.alerts[0].status, "new");
    assert.ok(body.alerts[0].id);
  } finally {
    server.close();
  }
});

test("GET /api/care-alerts?riskLevel=urgent 可篩選", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    await postNotify(baseUrl, { riskLevel: "urgent", riskLevelLabel: "緊急" });
    await postNotify(baseUrl, { riskLevel: "attention", riskLevelLabel: "需注意" });

    const res = await fetch(`${baseUrl}/api/care-alerts?riskLevel=urgent`);
    const body = await res.json();
    assert.equal(body.success, true);
    assert.equal(body.alerts.length, 1);
    assert.equal(body.alerts[0].riskLevel, "urgent");
  } finally {
    server.close();
  }
});

test("GET /api/care-alerts/:id 找得到", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    await postNotify(baseUrl);
    const { alerts } = await (await fetch(`${baseUrl}/api/care-alerts`)).json();
    const id = alerts[0].id;

    const res = await fetch(`${baseUrl}/api/care-alerts/${id}`);
    const body = await res.json();
    assert.equal(res.status, 200);
    assert.equal(body.success, true);
    assert.equal(body.alert.id, id);
  } finally {
    server.close();
  }
});

test("GET /api/care-alerts/:id 找不到回 404 not_found", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetch(`${baseUrl}/api/care-alerts/does-not-exist`);
    const body = await res.json();
    assert.equal(res.status, 404);
    assert.equal(body.success, false);
    assert.equal(body.error, "not_found");
  } finally {
    server.close();
  }
});
