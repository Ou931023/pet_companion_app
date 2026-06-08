const assert = require("node:assert/strict");
const { test, beforeEach, afterEach } = require("node:test");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

// CR-0040 Batch C：care-alert + admin analytics 路由的授權範圍過濾端點測試。
// 紅線驗證：super_admin（共享 ADMIN_API_TOKEN）行為零變更；caregiver authContext（測試 seam）
// 才觸發過濾 / 403。requireAdmin 仍在最前面擋門。

process.env.CARE_ALERTS_DATA_FILE = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), "care_alerts_scope_")),
  "care_alerts.json",
);
process.env.NODE_ENV = "test";
process.env.ADMIN_API_TOKEN = "test-admin-token";

const app = require("../server");
const authz = require("./admin/authorizationService");

// require server 會載入 .env（含真實 Telegram token）→ 清掉確保測試絕不真的發 Telegram。
delete process.env.TELEGRAM_BOT_TOKEN;
delete process.env.TELEGRAM_CARE_CHAT_ID;

const ADMIN_HEADERS = { Authorization: "Bearer test-admin-token" };

const ELDER_A = "11111111-1111-1111-1111-111111111111";
const ELDER_Z = "99999999-9999-9999-9999-999999999999";

// mock pg：caregiver cg-1 只被授權 ELDER_A。
function mockPgForCaregiver(authorizedElderIds) {
  return {
    isPostgresAvailable: async () => true,
    query: async (_text, params) => {
      const caregiverId = params && params[0];
      if (caregiverId !== "cg-1") return { rows: [] };
      return { rows: authorizedElderIds.map((elder_id) => ({ elder_id })) };
    },
  };
}

function asCaregiver() {
  authz.setAuthContextResolverForTest(() => ({
    role: authz.ROLE_CAREGIVER,
    caregiverId: "cg-1",
  }));
  authz.setPgForTest(mockPgForCaregiver([ELDER_A]));
}

beforeEach(() => {
  process.env.CARE_ALERTS_DATA_FILE = path.join(
    fs.mkdtempSync(path.join(os.tmpdir(), "care_alerts_scope_")),
    "care_alerts.json",
  );
  // 預設每個測試以 super_admin（無 override）起跑。
  authz.setAuthContextResolverForTest(null);
  authz.setPgForTest(null);
});

afterEach(() => {
  authz.setAuthContextResolverForTest(null);
  authz.setPgForTest(null);
});

function startServer() {
  return new Promise((resolve) => {
    const server = app.listen(0, "127.0.0.1", () => resolve(server));
  });
}

function postNotify(baseUrl, elderId, overrides = {}) {
  return fetch(`${baseUrl}/api/care-alerts/notify`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
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

test("super_admin: POST /api/care-alerts/notify 仍無需 auth → 200（CR-0039 回歸）", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await postNotify(baseUrl, ELDER_A);
    assert.equal(res.status, 200);
  } finally {
    server.close();
  }
});

// --- caregiver scoped（測試 seam）---

test("caregiver: GET /api/care-alerts 只見授權住民", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    // 以 super_admin（預設 null override）建立兩筆，再切 caregiver 讀。
    await postNotify(baseUrl, ELDER_A);
    await postNotify(baseUrl, ELDER_Z);

    asCaregiver();
    const res = await fetch(`${baseUrl}/api/care-alerts`, { headers: ADMIN_HEADERS });
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

    authz.setAuthContextResolverForTest(() => ({
      role: authz.ROLE_CAREGIVER,
      caregiverId: "cg-none",
    }));
    authz.setPgForTest(mockPgForCaregiver([ELDER_A])); // cg-none 不在 mock → 空

    const res = await fetch(`${baseUrl}/api/care-alerts`, { headers: ADMIN_HEADERS });
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

    asCaregiver();
    const forbidden = await fetch(`${baseUrl}/api/care-alerts/${zId}`, { headers: ADMIN_HEADERS });
    assert.equal(forbidden.status, 403);
    assert.deepEqual(await forbidden.json(), { success: false, error: "forbidden" });

    const allowed = await fetch(`${baseUrl}/api/care-alerts/${aId}`, { headers: ADMIN_HEADERS });
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

    asCaregiver();
    const forbidden = await fetch(`${baseUrl}/api/care-alerts/${zId}/status`, {
      method: "PATCH",
      headers: { ...ADMIN_HEADERS, "Content-Type": "application/json" },
      body: JSON.stringify({ status: "acknowledged" }),
    });
    assert.equal(forbidden.status, 403);

    const allowed = await fetch(`${baseUrl}/api/care-alerts/${aId}/status`, {
      method: "PATCH",
      headers: { ...ADMIN_HEADERS, "Content-Type": "application/json" },
      body: JSON.stringify({ status: "acknowledged" }),
    });
    const allowedBody = await allowed.json();
    assert.equal(allowed.status, 200);
    assert.equal(allowedBody.alert.status, "acknowledged");
  } finally {
    server.close();
  }
});

test("caregiver: 仍受 requireAdmin 擋門（無 token → 401，先於 scope）", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    asCaregiver();
    const res = await fetch(`${baseUrl}/api/care-alerts`); // 無 Authorization
    const body = await res.json();
    assert.equal(res.status, 401);
    assert.deepEqual(body, { ok: false, error: "missing_admin_token" });
  } finally {
    server.close();
  }
});

test("caregiver: GET /api/admin/elders/:elderId 跨住民 → 403", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    asCaregiver();
    const res = await fetch(`${baseUrl}/api/admin/elders/${ELDER_Z}`, {
      headers: ADMIN_HEADERS,
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
    asCaregiver();
    const res = await fetch(`${baseUrl}/api/admin/elders`, { headers: ADMIN_HEADERS });
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
