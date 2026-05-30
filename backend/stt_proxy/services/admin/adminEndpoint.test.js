// CR-0007 Batch 2：健康後台 Admin API endpoint 測試（比照 careAlertListEndpoint.test.js 風格）。
// 覆蓋 6 條 GET 路由的 200 與未知 elderId 404。不需 .env / 不需真 DB。

const assert = require("node:assert/strict");
const { test } = require("node:test");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

// 指向 temp 空的 elders / users 檔，讓 admin 服務走「示範長者種子」，
// endpoint 測試可重現、不依賴正式 data。care alert 也指向 temp，避免污染。
const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "admin_ep_"));
process.env.ELDERS_DATA_FILE = path.join(tmpDir, "elders.json");
process.env.USERS_DATA_FILE = path.join(tmpDir, "users.json");
process.env.CARE_ALERTS_DATA_FILE = path.join(tmpDir, "care_alerts.json");
process.env.NODE_ENV = "test";

const app = require("../../server");
const { SEED_ELDERS } = require("./eldersSource");

// 確保測試絕不真的發 Telegram。
delete process.env.TELEGRAM_BOT_TOKEN;
delete process.env.TELEGRAM_CARE_CHAT_ID;

function startServer() {
  return new Promise((resolve) => {
    const server = app.listen(0, "127.0.0.1", () => resolve(server));
  });
}

const KNOWN_ELDER_ID = SEED_ELDERS[0].id;

test("GET /api/admin/overview 回六指標", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetch(`${baseUrl}/api/admin/overview`);
    const body = await res.json();
    assert.equal(res.status, 200);
    for (const key of [
      "totalElders",
      "activeToday",
      "careAlertsToday",
      "highRiskElders",
      "emotionAbnormalElders",
      "cognitiveDeclineElders",
    ]) {
      assert.ok(Number.isInteger(body[key]), `${key} 應為整數`);
    }
    assert.ok(body.totalElders >= 6);
  } finally {
    server.close();
  }
});

test("GET /api/admin/elders 回長者列表", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetch(`${baseUrl}/api/admin/elders`);
    const body = await res.json();
    assert.equal(res.status, 200);
    assert.ok(Array.isArray(body));
    assert.ok(body.length >= 6);
    assert.ok("elderId" in body[0]);
    // 對外不得出現工程字樣。
    const blob = JSON.stringify(body).toLowerCase();
    for (const banned of ["demo", "fake", "mock", "debug"]) {
      assert.ok(!blob.includes(banned), `不得出現工程字樣：${banned}`);
    }
  } finally {
    server.close();
  }
});

test("GET /api/admin/elders/:elderId 個人分析 200", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetch(`${baseUrl}/api/admin/elders/${KNOWN_ELDER_ID}`);
    const body = await res.json();
    assert.equal(res.status, 200);
    assert.equal(body.profile.elderId, KNOWN_ELDER_ID);
    assert.ok(Array.isArray(body.careAlerts));
    assert.ok(body.physio.series.length > 0);
    assert.ok(Array.isArray(body.emotionHistory));
    assert.ok(body.gameMetrics);
  } finally {
    server.close();
  }
});

test("GET /api/admin/elders/:elderId/physio 200", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetch(`${baseUrl}/api/admin/elders/${KNOWN_ELDER_ID}/physio`);
    const body = await res.json();
    assert.equal(res.status, 200);
    assert.ok(Array.isArray(body.series));
    assert.ok(body.summary);
  } finally {
    server.close();
  }
});

test("GET /api/admin/elders/:elderId/emotion 200", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetch(`${baseUrl}/api/admin/elders/${KNOWN_ELDER_ID}/emotion`);
    const body = await res.json();
    assert.equal(res.status, 200);
    assert.ok(Array.isArray(body.series));
    assert.ok("dominantEmotion" in body);
    assert.ok("abnormal" in body);
  } finally {
    server.close();
  }
});

test("GET /api/admin/elders/:elderId/game-metrics 200", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetch(
      `${baseUrl}/api/admin/elders/${KNOWN_ELDER_ID}/game-metrics`,
    );
    const body = await res.json();
    assert.equal(res.status, 200);
    assert.ok(Array.isArray(body.series));
    assert.ok(["stable", "declining"].includes(body.trend));
  } finally {
    server.close();
  }
});

test("未知 elderId → 404 elder_not_found（各 sub-route）", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const paths = [
      "/api/admin/elders/nobody",
      "/api/admin/elders/nobody/physio",
      "/api/admin/elders/nobody/emotion",
      "/api/admin/elders/nobody/game-metrics",
    ];
    for (const p of paths) {
      const res = await fetch(`${baseUrl}${p}`);
      const body = await res.json();
      assert.equal(res.status, 404, `${p} 應 404`);
      assert.equal(body.success, false);
      assert.equal(body.error, "elder_not_found");
    }
  } finally {
    server.close();
  }
});
