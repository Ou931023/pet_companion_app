const assert = require("node:assert/strict");
const { test, beforeEach, afterEach } = require("node:test");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

// CR-0041 D2：care-alert + admin analytics + daily-care-tasks 路由的授權範圍過濾端點測試。
//
// 與 CR-0040 的差異：caregiver 身分不再以 authorizationService 測試 seam 注入，而是走「真正的
// HTTP 路徑」—— resolveAdminAuthContext 中介層（路線 A）：Bearer = Firebase idToken →
// 注入 stub firebaseAdmin 驗證 → uid → mock pg 查 users(role) → caregiver。共享 ADMIN_API_TOKEN
// 仍解析為 super_admin（行為零變更）。
//
// 紅線驗證：super_admin 行為零變更；caregiver 只見授權住民、跨住民 403、無授權空集合；
// daily-care-tasks 已 scope（CR-0040 §14 BLOCKER）；無 token → 401；非共享 / 無效 token → 401。

const scopeTmp = fs.mkdtempSync(path.join(os.tmpdir(), "care_alerts_scope_"));
process.env.CARE_ALERTS_DATA_FILE = path.join(scopeTmp, "care_alerts.json");
process.env.DAILY_CARE_TASKS_DATA_FILE = path.join(scopeTmp, "daily_care_tasks.json");
process.env.DAILY_CARE_TASK_SUBMISSIONS_DATA_FILE = path.join(
  scopeTmp,
  "daily_care_task_submissions.json",
);
process.env.NODE_ENV = "test";
process.env.ADMIN_API_TOKEN = "test-admin-token";

const app = require("../server");
const authz = require("./admin/authorizationService");
const adminAuth = require("./admin/adminAuthContext");
// CR-0045 B2：/notify 改掛 requireResidentCaller（resident self）。此檔的 postNotify 改帶
// 對應住民的 resident idToken；server 以 token 推導 elderId 蓋寫（body.elderId 須相符）。
const {
  installResidentCallerStub,
} = require("./auth/residentCallerContext.testsupport");

// require server 會載入 .env（含真實 Telegram token）→ 清掉確保測試絕不真的發 Telegram。
delete process.env.TELEGRAM_BOT_TOKEN;
delete process.env.TELEGRAM_CARE_CHAT_ID;

const ADMIN_HEADERS = { Authorization: "Bearer test-admin-token" };
// caregiver Firebase idToken（由 stub firebaseAdmin 解析為 uid）。
const CG1_HEADERS = { Authorization: "Bearer cg-1-id-token" };
const CG_NONE_HEADERS = { Authorization: "Bearer cg-none-id-token" };

const ELDER_A = "11111111-1111-1111-1111-111111111111";
const ELDER_Z = "99999999-9999-9999-9999-999999999999";

// resident self idToken（每位住民持自己的 token；server 由 token 推導 elderId）。
const RES_TOKENS = { [ELDER_A]: "res-a-token", [ELDER_Z]: "res-z-token" };
let restoreResident = null;

// stub firebaseAdmin：idToken → firebase_uid。
function firebaseStub() {
  const map = {
    "cg-1-id-token": "fb-cg-1",
    "cg-none-id-token": "fb-cg-none",
  };
  return {
    isConfigured: () => true,
    verifyIdToken: async (token) => (map[token] ? { uid: map[token] } : null),
  };
}

// 共用 mock pg：同時服務「users 查詢」（adminAuthContext）與
// 「resident_caregiver_links 查詢」（authorizationService）。
//   - cg-1（firebase_uid fb-cg-1）：role=caregiver，授權 [ELDER_A]。
//   - cg-none（firebase_uid fb-cg-none）：role=caregiver，無任何授權。
function sharedMockPg() {
  const usersByUid = {
    "fb-cg-1": { id: "cg-1", role: "caregiver" },
    "fb-cg-none": { id: "cg-none", role: "caregiver" },
  };
  const linksByCaregiver = {
    "cg-1": [ELDER_A],
    "cg-none": [],
  };
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

function installCaregiverAuth() {
  adminAuth.setFirebaseAdminForTest(firebaseStub());
  const pg = sharedMockPg();
  adminAuth.setPgForTest(pg);
  authz.setPgForTest(pg);
}

function installResidentAuth() {
  restoreResident = installResidentCallerStub({
    "res-a-token": { uid: "fb-res-a", userId: "user-res-a", elderId: ELDER_A },
    "res-z-token": { uid: "fb-res-z", userId: "user-res-z", elderId: ELDER_Z },
  });
}

beforeEach(() => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "care_alerts_scope_"));
  process.env.CARE_ALERTS_DATA_FILE = path.join(tmp, "care_alerts.json");
  process.env.DAILY_CARE_TASKS_DATA_FILE = path.join(tmp, "daily_care_tasks.json");
  process.env.DAILY_CARE_TASK_SUBMISSIONS_DATA_FILE = path.join(
    tmp,
    "daily_care_task_submissions.json",
  );
  // caregiver 身分機制預設安裝（super_admin 路徑不受影響，仍走共享 token）。
  installCaregiverAuth();
  // resident-caller（/notify seeding）身分安裝。
  installResidentAuth();
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

function postNotify(baseUrl, elderId, overrides = {}) {
  return fetch(`${baseUrl}/api/care-alerts/notify`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${RES_TOKENS[elderId]}`,
    },
    body: JSON.stringify({
      elderId,
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

function postTask(baseUrl, elderId, title) {
  return fetch(`${baseUrl}/api/daily-care-tasks`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ elderId, title, taskType: "medication" }),
  });
}

// --- super_admin（行為零變更）---

test("super_admin: GET /api/care-alerts 回全部住民（不過濾）", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    await postNotify(baseUrl, ELDER_A);
    await postNotify(baseUrl, ELDER_Z);

    const res = await fetch(`${baseUrl}/api/care-alerts`, { headers: ADMIN_HEADERS });
    const body = await res.json();
    assert.equal(res.status, 200);
    assert.equal(body.success, true);
    assert.equal(body.alerts.length, 2);
  } finally {
    server.close();
  }
});

test("super_admin: GET /api/care-alerts/:id 任一住民 200（不擋）", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    await postNotify(baseUrl, ELDER_Z);
    const { alerts } = await (
      await fetch(`${baseUrl}/api/care-alerts`, { headers: ADMIN_HEADERS })
    ).json();
    const id = alerts[0].id;

    const res = await fetch(`${baseUrl}/api/care-alerts/${id}`, { headers: ADMIN_HEADERS });
    const body = await res.json();
    assert.equal(res.status, 200);
    assert.equal(body.alert.id, id);
  } finally {
    server.close();
  }
});

test("super_admin: PATCH status 任一住民 200（不擋）", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    await postNotify(baseUrl, ELDER_Z);
    const { alerts } = await (
      await fetch(`${baseUrl}/api/care-alerts`, { headers: ADMIN_HEADERS })
    ).json();
    const id = alerts[0].id;

    const res = await fetch(`${baseUrl}/api/care-alerts/${id}/status`, {
      method: "PATCH",
      headers: { ...ADMIN_HEADERS, "Content-Type": "application/json" },
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

test("super_admin: PATCH 不存在 → 404 not_found（CR-0039 行為保留）", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetch(`${baseUrl}/api/care-alerts/does-not-exist/status`, {
      method: "PATCH",
      headers: { ...ADMIN_HEADERS, "Content-Type": "application/json" },
      body: JSON.stringify({ status: "acknowledged" }),
    });
    const body = await res.json();
    assert.equal(res.status, 404);
    assert.equal(body.error, "not_found");
  } finally {
    server.close();
  }
});

test("resident: POST /api/care-alerts/notify 帶 resident idToken → 200（CR-0045 收斂）", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await postNotify(baseUrl, ELDER_A);
    assert.equal(res.status, 200);
  } finally {
    server.close();
  }
});

test("resident: /notify 無 token → 401（CR-0045 caller 驗證，先於 persist）", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetch(`${baseUrl}/api/care-alerts/notify`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        elderId: ELDER_A,
        riskLevel: "urgent",
        triggerSummary: "對話中偵測到需要關心的狀況",
        transcriptSnippet: "我昨天晚上都睡不好",
        source: "companion_analysis",
      }),
    });
    assert.equal(res.status, 401);
    // 未授權不建立 alert：list（admin）應為空。
    const list = await (
      await fetch(`${baseUrl}/api/care-alerts`, { headers: ADMIN_HEADERS })
    ).json();
    assert.deepEqual(list.alerts, []);
  } finally {
    server.close();
  }
});

// --- caregiver scoped（真 HTTP：Firebase idToken）---

test("caregiver: GET /api/care-alerts 只見授權住民", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    await postNotify(baseUrl, ELDER_A);
    await postNotify(baseUrl, ELDER_Z);

    const res = await fetch(`${baseUrl}/api/care-alerts`, { headers: CG1_HEADERS });
    const body = await res.json();
    assert.equal(res.status, 200);
    assert.equal(body.alerts.length, 1);
    assert.equal(body.alerts[0].elderId, ELDER_A);
  } finally {
    server.close();
  }
});

test("caregiver: 無任何授權 → list 空集合", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    await postNotify(baseUrl, ELDER_A);

    const res = await fetch(`${baseUrl}/api/care-alerts`, { headers: CG_NONE_HEADERS });
    const body = await res.json();
    assert.equal(res.status, 200);
    assert.deepEqual(body.alerts, []);
  } finally {
    server.close();
  }
});

test("caregiver: GET /:id 跨住民 → 403；授權住民 → 200", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    await postNotify(baseUrl, ELDER_A);
    await postNotify(baseUrl, ELDER_Z);
    const { alerts } = await (
      await fetch(`${baseUrl}/api/care-alerts`, { headers: ADMIN_HEADERS })
    ).json();
    const aId = alerts.find((a) => a.elderId === ELDER_A).id;
    const zId = alerts.find((a) => a.elderId === ELDER_Z).id;

    const forbidden = await fetch(`${baseUrl}/api/care-alerts/${zId}`, { headers: CG1_HEADERS });
    assert.equal(forbidden.status, 403);
    assert.deepEqual(await forbidden.json(), { success: false, error: "forbidden" });

    const allowed = await fetch(`${baseUrl}/api/care-alerts/${aId}`, { headers: CG1_HEADERS });
    const allowedBody = await allowed.json();
    assert.equal(allowed.status, 200);
    assert.equal(allowedBody.alert.id, aId);
  } finally {
    server.close();
  }
});

test("caregiver: PATCH status 跨住民 → 403；授權住民 → 200", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    await postNotify(baseUrl, ELDER_A);
    await postNotify(baseUrl, ELDER_Z);
    const { alerts } = await (
      await fetch(`${baseUrl}/api/care-alerts`, { headers: ADMIN_HEADERS })
    ).json();
    const aId = alerts.find((a) => a.elderId === ELDER_A).id;
    const zId = alerts.find((a) => a.elderId === ELDER_Z).id;

    const forbidden = await fetch(`${baseUrl}/api/care-alerts/${zId}/status`, {
      method: "PATCH",
      headers: { ...CG1_HEADERS, "Content-Type": "application/json" },
      body: JSON.stringify({ status: "acknowledged" }),
    });
    assert.equal(forbidden.status, 403);

    const allowed = await fetch(`${baseUrl}/api/care-alerts/${aId}/status`, {
      method: "PATCH",
      headers: { ...CG1_HEADERS, "Content-Type": "application/json" },
      body: JSON.stringify({ status: "acknowledged" }),
    });
    const allowedBody = await allowed.json();
    assert.equal(allowed.status, 200);
    assert.equal(allowedBody.alert.status, "acknowledged");
  } finally {
    server.close();
  }
});

test("caregiver: 仍受 authN 擋門（無 token → 401 missing_admin_token，先於 scope）", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetch(`${baseUrl}/api/care-alerts`); // 無 Authorization
    const body = await res.json();
    assert.equal(res.status, 401);
    assert.deepEqual(body, { ok: false, error: "missing_admin_token" });
  } finally {
    server.close();
  }
});

test("非共享 / 無效 idToken → 401 invalid_session（不放行、不退化 super_admin）", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    await postNotify(baseUrl, ELDER_A);
    const res = await fetch(`${baseUrl}/api/care-alerts`, {
      headers: { Authorization: "Bearer forged-token-not-in-stub" },
    });
    const body = await res.json();
    assert.equal(res.status, 401);
    assert.deepEqual(body, { ok: false, error: "invalid_session" });
  } finally {
    server.close();
  }
});

test("caregiver: GET /api/admin/elders/:elderId 跨住民 → 403", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetch(`${baseUrl}/api/admin/elders/${ELDER_Z}`, {
      headers: CG1_HEADERS,
    });
    assert.equal(res.status, 403);
    assert.deepEqual(await res.json(), { success: false, error: "forbidden" });
  } finally {
    server.close();
  }
});

test("caregiver: GET /api/admin/elders 只回授權住民（含空集合）", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetch(`${baseUrl}/api/admin/elders`, { headers: CG1_HEADERS });
    const body = await res.json();
    assert.equal(res.status, 200);
    assert.ok(Array.isArray(body));
    // cg-1 只授權 ELDER_A（非 seed elder），seed 長者不應出現。
    for (const row of body) {
      assert.equal(row.elderId, ELDER_A);
    }
  } finally {
    server.close();
  }
});

// --- daily-care-tasks scope（CR-0040 §14 Batch D BLOCKER → 本案修補）---

test("super_admin: GET /api/admin/daily-care-tasks 回全部住民任務", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    await postTask(baseUrl, ELDER_A, "吃藥A");
    await postTask(baseUrl, ELDER_Z, "吃藥Z");

    const res = await fetch(`${baseUrl}/api/admin/daily-care-tasks`, {
      headers: ADMIN_HEADERS,
    });
    const body = await res.json();
    assert.equal(res.status, 200);
    assert.equal(body.success, true);
    assert.equal(body.tasks.length, 2);
  } finally {
    server.close();
  }
});

test("caregiver: GET /api/admin/daily-care-tasks 只見授權住民任務（不跨住民洩漏）", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    await postTask(baseUrl, ELDER_A, "吃藥A");
    await postTask(baseUrl, ELDER_Z, "吃藥Z");

    const res = await fetch(`${baseUrl}/api/admin/daily-care-tasks`, {
      headers: CG1_HEADERS,
    });
    const body = await res.json();
    assert.equal(res.status, 200);
    assert.equal(body.tasks.length, 1);
    assert.equal(body.tasks[0].elderId, ELDER_A);
  } finally {
    server.close();
  }
});

test("caregiver: daily-care-tasks 帶跨住民 elderId → 403", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    await postTask(baseUrl, ELDER_Z, "吃藥Z");

    const res = await fetch(
      `${baseUrl}/api/admin/daily-care-tasks?elderId=${ELDER_Z}`,
      { headers: CG1_HEADERS },
    );
    assert.equal(res.status, 403);
    assert.deepEqual(await res.json(), { success: false, error: "forbidden" });
  } finally {
    server.close();
  }
});

test("caregiver: daily-care-tasks 無授權 → 空陣列（fail-closed）", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    await postTask(baseUrl, ELDER_A, "吃藥A");

    const res = await fetch(`${baseUrl}/api/admin/daily-care-tasks`, {
      headers: CG_NONE_HEADERS,
    });
    const body = await res.json();
    assert.equal(res.status, 200);
    assert.deepEqual(body.tasks, []);
  } finally {
    server.close();
  }
});

test("daily-care-tasks 無 token → 401 missing_admin_token", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetch(`${baseUrl}/api/admin/daily-care-tasks`);
    const body = await res.json();
    assert.equal(res.status, 401);
    assert.deepEqual(body, { ok: false, error: "missing_admin_token" });
  } finally {
    server.close();
  }
});
