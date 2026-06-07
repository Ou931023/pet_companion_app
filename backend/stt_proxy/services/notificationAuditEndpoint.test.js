const assert = require("node:assert/strict");
const { test, beforeEach, after } = require("node:test");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

// 在 require server 前指定 runtime data 檔到 temp，避免污染正式 data。
process.env.CARE_ALERTS_DATA_FILE = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), "notif_audit_ep_")),
  "care_alerts.json",
);
process.env.NODE_ENV = "test";
const app = require("../server");

// 清掉 Telegram 設定，確保不真的發送（high/urgent 會走 telegram_not_configured → failed）。
delete process.env.TELEGRAM_BOT_TOKEN;
delete process.env.TELEGRAM_CARE_CHAT_ID;

// 注入「DB 可用但 query 必拋例外」的 mock pg：證明稽核寫入即使失敗，
// 也被 service best-effort 吞掉，路由 response 完全不受影響、不致 unhandledRejection。
const notifLog = require("./notificationLogService");
const auditLog = require("./auditLogService");

function makeThrowingPg() {
  return {
    isPostgresAvailable: async () => true,
    query: async () => {
      throw new Error("audit write boom");
    },
  };
}

beforeEach(() => {
  process.env.CARE_ALERTS_DATA_FILE = path.join(
    fs.mkdtempSync(path.join(os.tmpdir(), "notif_audit_ep_")),
    "care_alerts.json",
  );
  notifLog.setPgForTest(makeThrowingPg());
  auditLog.setPgForTest(makeThrowingPg());
});

after(() => {
  notifLog.setPgForTest(null);
  auditLog.setPgForTest(null);
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

test("/notify high/urgent：稽核寫入失敗不改回應（telegram_not_configured）", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await postNotify(baseUrl);
    const body = await res.json();
    assert.equal(res.status, 200);
    // 既有契約形狀不變：sendCareAlertNotification 回 telegram_not_configured。
    assert.equal(body.success, false);
    assert.equal(body.error, "telegram_not_configured");
  } finally {
    server.close();
  }
});

test("/notify 低風險：稽核寫入失敗不改 skipped_low_risk 回應", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await postNotify(baseUrl, { riskLevel: "low", riskLevelLabel: "一般" });
    const body = await res.json();
    assert.equal(res.status, 200);
    assert.deepEqual(body, { success: true, telegram: "skipped_low_risk" });
  } finally {
    server.close();
  }
});

test("PATCH /api/care-alerts/:id/status：稽核寫入失敗不改成功回應", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    await postNotify(baseUrl);
    const { alerts } = await (await fetch(`${baseUrl}/api/care-alerts`)).json();
    const id = alerts[0].id;
    const res = await fetch(`${baseUrl}/api/care-alerts/${id}/status`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ status: "acknowledged" }),
    });
    const body = await res.json();
    assert.equal(res.status, 200);
    assert.equal(body.success, true);
    assert.equal(body.alert.status, "acknowledged");
  } finally {
    server.close();
  }
});
