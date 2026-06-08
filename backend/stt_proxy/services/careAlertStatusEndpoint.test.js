const assert = require("node:assert/strict");
const { test, beforeEach } = require("node:test");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

// 在 require server 前指定 runtime data 檔到 temp，避免污染正式 data。
process.env.CARE_ALERTS_DATA_FILE = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), "care_alerts_status_ep_")),
  "care_alerts.json",
);
process.env.NODE_ENV = "test";
// CR-0039：Care Alert 讀取 / 狀態變更路由掛了 requireAdmin。
process.env.ADMIN_API_TOKEN = "test-admin-token";
const app = require("../server");

// require server 會載入 .env（含真 Telegram token）；清掉以確保不真的發 Telegram。
delete process.env.TELEGRAM_BOT_TOKEN;
delete process.env.TELEGRAM_CARE_CHAT_ID;

// CR-0039：admin 授權 header。
const ADMIN_HEADERS = { Authorization: "Bearer test-admin-token" };

beforeEach(() => {
  process.env.CARE_ALERTS_DATA_FILE = path.join(
    fs.mkdtempSync(path.join(os.tmpdir(), "care_alerts_status_ep_")),
    "care_alerts.json",
  );
});

function startServer() {
  return new Promise((resolve) => {
    const server = app.listen(0, "127.0.0.1", () => resolve(server));
  });
}

function postNotify(baseUrl) {
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
    }),
  });
}

async function createAlertAndGetId(baseUrl) {
  await postNotify(baseUrl);
  const { alerts } = await (
    await fetch(`${baseUrl}/api/care-alerts`, { headers: ADMIN_HEADERS })
  ).json();
  return alerts[0].id;
}

function patchStatus(baseUrl, id, body) {
  return fetch(`${baseUrl}/api/care-alerts/${id}/status`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json", ...ADMIN_HEADERS },
    body: JSON.stringify(body),
  });
}

test("PATCH /api/care-alerts/:id/status 成功更新 acknowledged", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const id = await createAlertAndGetId(baseUrl);
    const res = await patchStatus(baseUrl, id, { status: "acknowledged" });
    const body = await res.json();
    assert.equal(res.status, 200);
    assert.equal(body.success, true);
    assert.equal(body.alert.status, "acknowledged");
    assert.ok(body.alert.acknowledgedAt);
  } finally {
    server.close();
  }
});

test("PATCH /api/care-alerts/:id/status 成功更新 resolved", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const id = await createAlertAndGetId(baseUrl);
    const res = await patchStatus(baseUrl, id, { status: "resolved" });
    const body = await res.json();
    assert.equal(res.status, 200);
    assert.equal(body.success, true);
    assert.equal(body.alert.status, "resolved");
    assert.ok(body.alert.resolvedAt);
  } finally {
    server.close();
  }
});

test("PATCH 找不到 id 回 404 not_found", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await patchStatus(baseUrl, "does-not-exist", { status: "acknowledged" });
    const body = await res.json();
    assert.equal(res.status, 404);
    assert.deepEqual(body, { success: false, error: "not_found" });
  } finally {
    server.close();
  }
});

test("PATCH status 不合法回 400 invalid_status", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const id = await createAlertAndGetId(baseUrl);
    const res = await patchStatus(baseUrl, id, { status: "bogus" });
    const body = await res.json();
    assert.equal(res.status, 400);
    assert.deepEqual(body, { success: false, error: "invalid_status" });
  } finally {
    server.close();
  }
});

test("PATCH 缺 status 回 400 invalid_status", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const id = await createAlertAndGetId(baseUrl);
    const res = await patchStatus(baseUrl, id, {});
    const body = await res.json();
    assert.equal(res.status, 400);
    assert.deepEqual(body, { success: false, error: "invalid_status" });
  } finally {
    server.close();
  }
});

test("PATCH 後 GET /api/care-alerts/:id 讀得到更新後 status", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const id = await createAlertAndGetId(baseUrl);
    await patchStatus(baseUrl, id, { status: "resolved" });
    const body = await (
      await fetch(`${baseUrl}/api/care-alerts/${id}`, { headers: ADMIN_HEADERS })
    ).json();
    assert.equal(body.success, true);
    assert.equal(body.alert.status, "resolved");
    assert.ok(body.alert.resolvedAt);
  } finally {
    server.close();
  }
});

// CR-0039：PATCH 狀態變更為 admin 動作，未帶 / 錯誤 token 應被擋下。
test("PATCH /api/care-alerts/:id/status 無 Authorization → 401 missing_admin_token", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const id = await createAlertAndGetId(baseUrl);
    const res = await fetch(`${baseUrl}/api/care-alerts/${id}/status`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ status: "acknowledged" }),
    });
    const body = await res.json();
    assert.equal(res.status, 401);
    assert.deepEqual(body, { ok: false, error: "missing_admin_token" });
  } finally {
    server.close();
  }
});

// CR-0041 D2 語意變更：改掛 resolveAdminAuthContext，非共享 token 當 idToken 驗證；
// 不匹配 → 401 invalid_session（而非舊的 403）。授權未放寬。
test("PATCH /api/care-alerts/:id/status 非共享 / 無效 token → 401 invalid_session（CR-0041 語意變更）", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const id = await createAlertAndGetId(baseUrl);
    const res = await fetch(`${baseUrl}/api/care-alerts/${id}/status`, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        Authorization: "Bearer wrong-token",
      },
      body: JSON.stringify({ status: "acknowledged" }),
    });
    const body = await res.json();
    assert.equal(res.status, 401);
    assert.deepEqual(body, { ok: false, error: "invalid_session" });
  } finally {
    server.close();
  }
});
