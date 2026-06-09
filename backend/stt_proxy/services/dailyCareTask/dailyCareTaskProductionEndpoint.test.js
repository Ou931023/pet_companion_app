// CR-0057 DailyCareTask production 停用路徑端點測試（defense-in-depth + wire 契約一致）。
//
// 裁決規格（architecture-agent）：
//   - production（isJsonFallbackAllowed=false）下，daily-care 所有會出現
//     feature_unavailable_in_production 的路由 → 統一回 501。
//   - 形狀：{ success:false, error:"not_enabled", message:<白話、無工程字眼/path/stack> }。
//   - dev/test 既有行為（200/400/404）位元不變（見 careAlertAuthScopeEndpoint.test.js 等）。
//   - authz 403 優先序不可被破壞：caregiver 跨住民 daily-care admin 在 store 呼叫前就 403；
//     501 只在 authz 通過後由 store 訊號觸發（super_admin）。
//
// production 切換沿用既有慣例：require 時 NODE_ENV=test（fail-fast no-op），
// 再於單一請求前後暫時切 production，finally 還原。

const assert = require("node:assert/strict");
const { test, beforeEach, afterEach } = require("node:test");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "dct_prod_ep_"));
process.env.DAILY_CARE_TASKS_DATA_FILE = path.join(tmpDir, "daily_care_tasks.json");
process.env.DAILY_CARE_TASK_SUBMISSIONS_DATA_FILE = path.join(
  tmpDir,
  "daily_care_task_submissions.json",
);
process.env.ADMIN_API_TOKEN = "test-admin-token";
process.env.NODE_ENV = "test";
process.env.OPENAI_API_KEY = "";
process.env.PGVECTOR_ENABLED = "false";
delete process.env.DATABASE_URL;
delete process.env.TELEGRAM_BOT_TOKEN;

const app = require("../../server");
const authz = require("../admin/authorizationService");
const adminAuth = require("../admin/adminAuthContext");

const ADMIN_HEADERS = { Authorization: "Bearer test-admin-token" };
const CG1_HEADERS = { Authorization: "Bearer cg-1-id-token" };

const ELDER_A = "11111111-1111-1111-1111-111111111111";
const ELDER_Z = "99999999-9999-9999-9999-999999999999";

// stub firebaseAdmin：idToken → firebase_uid。
function firebaseStub() {
  const map = { "cg-1-id-token": "fb-cg-1" };
  return {
    isConfigured: () => true,
    verifyIdToken: async (token) => (map[token] ? { uid: map[token] } : null),
  };
}

// 共用 mock pg：cg-1（caregiver）授權 [ELDER_A]，未授權 ELDER_Z。
function sharedMockPg() {
  const usersByUid = { "fb-cg-1": { id: "cg-1", role: "caregiver" } };
  const linksByCaregiver = { "cg-1": [ELDER_A] };
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
  adminAuth.setFirebaseAdminForTest(firebaseStub());
  const pg = sharedMockPg();
  adminAuth.setPgForTest(pg);
  authz.setPgForTest(pg);
});

afterEach(() => {
  adminAuth.setFirebaseAdminForTest(null);
  adminAuth.setPgForTest(null);
  authz.setPgForTest(null);
});

function startServer() {
  return new Promise((resolve) => {
    const server = app.listen(0, "127.0.0.1", () => resolve(server));
  });
}

async function fetchInProduction(url, init) {
  const originalNodeEnv = process.env.NODE_ENV;
  const originalAppEnv = process.env.APP_ENV;
  try {
    process.env.NODE_ENV = "production";
    process.env.APP_ENV = "production";
    const r = await fetch(url, init);
    const raw = await r.text();
    let body = null;
    try {
      body = JSON.parse(raw);
    } catch {
      body = null;
    }
    return { status: r.status, body, raw };
  } finally {
    process.env.NODE_ENV = originalNodeEnv;
    if (originalAppEnv === undefined) delete process.env.APP_ENV;
    else process.env.APP_ENV = originalAppEnv;
  }
}

function assertDailyCareDisabled(res) {
  assert.equal(res.status, 501);
  assert.ok(res.body && typeof res.body === "object");
  assert.equal(res.body.success, false);
  assert.equal(res.body.error, "not_enabled");
  assert.equal(typeof res.body.message, "string");
  assert.ok(res.body.message.length > 0);
  assert.ok(!res.raw.includes("feature_unavailable_in_production"));
  for (const banned of ["stack", ".json", "/Users", "/var", "demo", "Demo", "JSON"]) {
    assert.ok(!res.raw.includes(banned), `response 不應含 "${banned}"：${res.raw}`);
  }
}

test("production GET /api/daily-care-tasks → 501 not_enabled，不讀 JSON / 不回 demo", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetchInProduction(
      `${baseUrl}/api/daily-care-tasks?elderId=${ELDER_A}`,
      {},
    );
    assertDailyCareDisabled(res);
  } finally {
    server.close();
  }
});

test("production POST /api/daily-care-tasks → 501 not_enabled", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetchInProduction(`${baseUrl}/api/daily-care-tasks`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ elderId: ELDER_A, title: "吃藥", taskType: "medication" }),
    });
    assertDailyCareDisabled(res);
  } finally {
    server.close();
  }
});

test("production POST /api/daily-care-tasks/:id/submit → 501 not_enabled（非 500）", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    // getDailyCareTaskById 在 production 先 throw，故無需真上傳照片即應 501。
    const res = await fetchInProduction(`${baseUrl}/api/daily-care-tasks/any-id/submit`, {
      method: "POST",
    });
    assertDailyCareDisabled(res);
  } finally {
    server.close();
  }
});

test("production PATCH /api/daily-care-tasks/:id/status → 501 not_enabled", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetchInProduction(`${baseUrl}/api/daily-care-tasks/any-id/status`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ status: "completed" }),
    });
    assertDailyCareDisabled(res);
  } finally {
    server.close();
  }
});

test("production GET /api/daily-care-tasks/proof/:id → 501 not_enabled", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetchInProduction(
      `${baseUrl}/api/daily-care-tasks/proof/any-submission`,
      {},
    );
    assertDailyCareDisabled(res);
  } finally {
    server.close();
  }
});

// authz 403 優先序：caregiver 跨住民（帶非授權 elderId）→ 仍 403（store 未被呼叫）。
test("production + caregiver 跨住民 admin daily-care → 仍 403（authz 先於 501）", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetchInProduction(
      `${baseUrl}/api/admin/daily-care-tasks?elderId=${ELDER_Z}`,
      { headers: CG1_HEADERS },
    );
    assert.equal(res.status, 403);
    assert.deepEqual(res.body, { success: false, error: "forbidden" });
  } finally {
    server.close();
  }
});

// super_admin 通過 authz 後，store 訊號觸發 → 501。
test("production + super_admin admin daily-care → authz 通過後 501 not_enabled", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetchInProduction(`${baseUrl}/api/admin/daily-care-tasks`, {
      headers: ADMIN_HEADERS,
    });
    assertDailyCareDisabled(res);
  } finally {
    server.close();
  }
});

// authN 仍先於一切：admin daily-care 無 token → 401。
test("production admin daily-care 無 token → 仍 401 missing_admin_token", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetchInProduction(`${baseUrl}/api/admin/daily-care-tasks`, {});
    assert.equal(res.status, 401);
    assert.deepEqual(res.body, { ok: false, error: "missing_admin_token" });
  } finally {
    server.close();
  }
});
