const assert = require("node:assert/strict");
const { test, beforeEach, afterEach } = require("node:test");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

// CR-0086：GET /api/caregiver/analytics 授權 + 形狀端點測試。
// 沿用 careAlertAuthScopeEndpoint.test.js 的真 HTTP 授權 stub：
//   - super_admin = 共享 ADMIN_API_TOKEN。
//   - caregiver = Firebase idToken → stub 驗證 → mock pg 查 users(role)/links。
// 紅線：未登入 401；caregiver 跨住民 403；caregiver 授權住民 200；super_admin 任一 200；
// 缺 elderId 400；無資料時空狀態不崩潰、不洩漏其他住民。

const tmp0 = fs.mkdtempSync(path.join(os.tmpdir(), "cg_analytics_"));
process.env.CARE_ALERTS_DATA_FILE = path.join(tmp0, "care_alerts.json");
process.env.DAILY_CARE_TASKS_DATA_FILE = path.join(tmp0, "daily_care_tasks.json");
process.env.DAILY_CARE_TASK_SUBMISSIONS_DATA_FILE = path.join(
  tmp0,
  "daily_care_task_submissions.json",
);
process.env.NODE_ENV = "test";
process.env.ADMIN_API_TOKEN = "test-admin-token";

const app = require("../../server");
const authz = require("./authorizationService");
const adminAuth = require("./adminAuthContext");
const {
  installResidentCallerStub,
} = require("../auth/residentCallerContext.testsupport");

delete process.env.TELEGRAM_BOT_TOKEN;
delete process.env.TELEGRAM_CARE_CHAT_ID;

const ADMIN_HEADERS = { Authorization: "Bearer test-admin-token" };
const CG1_HEADERS = { Authorization: "Bearer cg-1-id-token" };

const ELDER_A = "11111111-1111-1111-1111-111111111111";
const ELDER_Z = "99999999-9999-9999-9999-999999999999";
const RES_TOKENS = { [ELDER_A]: "res-a-token", [ELDER_Z]: "res-z-token" };
let restoreResident = null;

function firebaseStub() {
  const map = { "cg-1-id-token": "fb-cg-1" };
  return {
    isConfigured: () => true,
    verifyIdToken: async (token) => (map[token] ? { uid: map[token] } : null),
  };
}

function sharedMockPg() {
  const usersByUid = { "fb-cg-1": { id: "cg-1", role: "caregiver" } };
  const linksByCaregiver = { "cg-1": [ELDER_A] }; // cg-1 只授權 ELDER_A
  return {
    isPostgresAvailable: async () => true,
    query: async (text, params) => {
      const key = params && params[0];
      if (/FROM users/i.test(text)) {
        const row = usersByUid[key];
        return { rows: row ? [row] : [] };
      }
      if (/resident_caregiver_links/i.test(text)) {
        const elderIds = linksByCaregiver[key] || [];
        return { rows: elderIds.map((elder_id) => ({ elder_id })) };
      }
      return { rows: [] };
    },
  };
}

beforeEach(() => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "cg_analytics_"));
  process.env.CARE_ALERTS_DATA_FILE = path.join(tmp, "care_alerts.json");
  process.env.DAILY_CARE_TASKS_DATA_FILE = path.join(tmp, "daily_care_tasks.json");
  process.env.DAILY_CARE_TASK_SUBMISSIONS_DATA_FILE = path.join(
    tmp,
    "daily_care_task_submissions.json",
  );
  adminAuth.setFirebaseAdminForTest(firebaseStub());
  const pg = sharedMockPg();
  adminAuth.setPgForTest(pg);
  authz.setPgForTest(pg);
  restoreResident = installResidentCallerStub({
    "res-a-token": { uid: "fb-res-a", userId: "user-res-a", elderId: ELDER_A },
    "res-z-token": { uid: "fb-res-z", userId: "user-res-z", elderId: ELDER_Z },
  });
});

afterEach(() => {
  adminAuth.setFirebaseAdminForTest(null);
  adminAuth.setPgForTest(null);
  authz.setPgForTest(null);
  if (restoreResident) restoreResident();
  restoreResident = null;
});

function startServer() {
  return new Promise((resolve) => {
    const server = app.listen(0, "127.0.0.1", () => resolve(server));
  });
}

function postNotify(baseUrl, elderId, riskLevel = "urgent") {
  return fetch(`${baseUrl}/api/care-alerts/notify`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${RES_TOKENS[elderId]}`,
    },
    body: JSON.stringify({
      elderId,
      riskLevel,
      riskLevelLabel: "緊急",
      category: "other",
      categoryLabel: "其他",
      triggerSummary: "對話中偵測到需要關心的狀況",
      transcriptSnippet: "我昨天晚上都睡不好",
      source: "companion_analysis",
    }),
  });
}

test("未登入 → 401 missing_admin_token", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetch(`${baseUrl}/api/caregiver/analytics?elderId=${ELDER_A}`);
    const body = await res.json();
    assert.equal(res.status, 401);
    assert.deepEqual(body, { ok: false, error: "missing_admin_token" });
  } finally {
    server.close();
  }
});

test("缺 elderId → 400 elder_id_required", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetch(`${baseUrl}/api/caregiver/analytics`, { headers: ADMIN_HEADERS });
    const body = await res.json();
    assert.equal(res.status, 400);
    assert.deepEqual(body, { ok: false, error: "elder_id_required" });
  } finally {
    server.close();
  }
});

test("caregiver 查授權住民 → 200 + 形狀完整 + Care Alert 統計正確", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    await postNotify(baseUrl, ELDER_A, "urgent");
    await postNotify(baseUrl, ELDER_A, "medium");

    const res = await fetch(
      `${baseUrl}/api/caregiver/analytics?elderId=${ELDER_A}&rangeDays=7`,
      { headers: CG1_HEADERS },
    );
    const body = await res.json();
    assert.equal(res.status, 200);
    assert.equal(body.ok, true);
    assert.equal(body.elderId, ELDER_A);
    assert.equal(body.rangeDays, 7);
    // Care Alert 統計（真實資料）。
    assert.equal(body.careAlertStats.urgent, 1);
    assert.equal(body.careAlertStats.medium, 1);
    assert.equal(body.careAlertStats.total, 2);
    assert.equal(body.careAlertStats.highRiskRatio, 0.5);
    assert.equal(body.summary.rangeAlertCount, 2);
    // 形狀完整。
    for (const key of ["summary", "emotionTrend", "careAlertStats", "taskStats", "gameMetrics", "petStatus"]) {
      assert.ok(key in body, `回傳應含 ${key}`);
    }
    // 誠實空狀態。
    assert.equal(body.gameMetrics.hasEnoughData, false);
    assert.equal(body.petStatus.available, false);
  } finally {
    server.close();
  }
});

test("caregiver 查未授權住民 → 403 forbidden（不洩漏資料）", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    await postNotify(baseUrl, ELDER_Z, "urgent");
    const res = await fetch(`${baseUrl}/api/caregiver/analytics?elderId=${ELDER_Z}`, {
      headers: CG1_HEADERS,
    });
    const body = await res.json();
    assert.equal(res.status, 403);
    assert.deepEqual(body, { ok: false, error: "forbidden" });
  } finally {
    server.close();
  }
});

test("super_admin 查任一住民 → 200", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    await postNotify(baseUrl, ELDER_Z, "high");
    const res = await fetch(`${baseUrl}/api/caregiver/analytics?elderId=${ELDER_Z}`, {
      headers: ADMIN_HEADERS,
    });
    const body = await res.json();
    assert.equal(res.status, 200);
    assert.equal(body.ok, true);
    assert.equal(body.careAlertStats.high, 1);
  } finally {
    server.close();
  }
});

test("無資料住民 → 200 空狀態（全 0 / null，不崩潰）", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetch(`${baseUrl}/api/caregiver/analytics?elderId=${ELDER_A}`, {
      headers: ADMIN_HEADERS,
    });
    const body = await res.json();
    assert.equal(res.status, 200);
    assert.equal(body.careAlertStats.total, 0);
    assert.equal(body.taskStats.total, 0);
    assert.equal(body.taskStats.completionRate, null);
    assert.equal(body.summary.latestRiskLevel, null);
  } finally {
    server.close();
  }
});

test("rangeDays 非法 → 預設 7（不崩潰）", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetch(
      `${baseUrl}/api/caregiver/analytics?elderId=${ELDER_A}&rangeDays=abc`,
      { headers: ADMIN_HEADERS },
    );
    const body = await res.json();
    assert.equal(res.status, 200);
    assert.equal(body.rangeDays, 7);
  } finally {
    server.close();
  }
});
