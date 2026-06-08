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
// CR-0039：Care Alert 讀取路由掛了 requireAdmin，測試以固定 admin token 通過擋門。
process.env.ADMIN_API_TOKEN = "test-admin-token";
const app = require("../server");

// 重要：require server 會載入 .env（含真實 Telegram token）。這裡清掉，
// 確保測試「絕不」真的發 Telegram；持久化與 Telegram 無關，仍照常運作。
delete process.env.TELEGRAM_BOT_TOKEN;
delete process.env.TELEGRAM_CARE_CHAT_ID;

// CR-0039：admin 讀取路由的授權 header。
const ADMIN_HEADERS = { Authorization: "Bearer test-admin-token" };

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

    const res = await fetch(`${baseUrl}/api/care-alerts`, { headers: ADMIN_HEADERS });
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

    const res = await fetch(`${baseUrl}/api/care-alerts?riskLevel=urgent`, {
      headers: ADMIN_HEADERS,
    });
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
    const { alerts } = await (
      await fetch(`${baseUrl}/api/care-alerts`, { headers: ADMIN_HEADERS })
    ).json();
    const id = alerts[0].id;

    const res = await fetch(`${baseUrl}/api/care-alerts/${id}`, {
      headers: ADMIN_HEADERS,
    });
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
    const res = await fetch(`${baseUrl}/api/care-alerts/does-not-exist`, {
      headers: ADMIN_HEADERS,
    });
    const body = await res.json();
    assert.equal(res.status, 404);
    assert.equal(body.success, false);
    assert.equal(body.error, "not_found");
  } finally {
    server.close();
  }
});

// CR-0039：requireAdmin 擋門 — 未帶 / 錯誤 token 應被擋下，不洩漏 Care Alert 資料。
test("GET /api/care-alerts 無 Authorization → 401 missing_admin_token", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetch(`${baseUrl}/api/care-alerts`);
    const body = await res.json();
    assert.equal(res.status, 401);
    assert.deepEqual(body, { ok: false, error: "missing_admin_token" });
  } finally {
    server.close();
  }
});

// CR-0041 D2 語意變更：此路由由 requireAdmin 改掛 resolveAdminAuthContext（接受 caregiver
// Firebase idToken）。非共享 token 的 bearer 一律當 idToken 驗證；不匹配 = 無效 session
// → 401 invalid_session（而非舊的 403 admin_permission_required）。授權未放寬：無 token 仍 401，
// 共享 token 仍 200，無效身分被拒。
test("GET /api/care-alerts 非共享 / 無效 token → 401 invalid_session（CR-0041 語意變更）", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetch(`${baseUrl}/api/care-alerts`, {
      headers: { Authorization: "Bearer wrong-token" },
    });
    const body = await res.json();
    assert.equal(res.status, 401);
    assert.deepEqual(body, { ok: false, error: "invalid_session" });
  } finally {
    server.close();
  }
});

test("GET /api/care-alerts/:id 無 Authorization → 401 missing_admin_token", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetch(`${baseUrl}/api/care-alerts/whatever`);
    const body = await res.json();
    assert.equal(res.status, 401);
    assert.deepEqual(body, { ok: false, error: "missing_admin_token" });
  } finally {
    server.close();
  }
});
