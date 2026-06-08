const assert = require("node:assert/strict");
const { test, afterEach } = require("node:test");

// CR-0041 D1：adminAuthContext 身分解析單元測試。
// 不需真 DB / 真 Firebase 金鑰：以注入 stub firebaseAdmin + mock pg 驗證解析邏輯。
// 涵蓋：無 token→401；shared token→super_admin；有效 caregiver idToken→caregiver(caregiverId)；
//      有效但 role=elder→403；查無 user→403；驗證失敗→401；未 configured + production 關 mock→401；
//      DB role=admin→super_admin（DB-backed）。

const adminAuth = require("./adminAuthContext");

const SHARED_TOKEN = "shared-super-admin-token";
const PROD_ENV = { ADMIN_API_TOKEN: SHARED_TOKEN, NODE_ENV: "production", APP_ENV: "production" };
const DEV_ENV = { ADMIN_API_TOKEN: SHARED_TOKEN, NODE_ENV: "test" };

function reqWith(authorization) {
  return { headers: authorization ? { authorization } : {} };
}

// stub firebaseAdmin：configured=true，verifyIdToken 依 token → uid 映射。
function firebaseStub(tokenToUid, { configured = true } = {}) {
  return {
    isConfigured: () => configured,
    verifyIdToken: async (token) => {
      const uid = tokenToUid[token];
      return uid ? { uid } : null;
    },
  };
}

// mock pg：firebase_uid → users row。
function mockPg(usersByUid, { available = true } = {}) {
  return {
    isPostgresAvailable: async () => available,
    query: async (_text, params) => {
      const uid = params && params[0];
      const row = usersByUid[uid];
      return { rows: row ? [row] : [] };
    },
  };
}

afterEach(() => {
  adminAuth.setFirebaseAdminForTest(null);
  adminAuth.setPgForTest(null);
});

test("無 token → 401 missing_admin_token", async () => {
  const result = await adminAuth.buildAuthContext(reqWith(null), { env: DEV_ENV });
  assert.deepEqual(result, { ok: false, status: 401, error: "missing_admin_token" });
});

test("shared token 字面相符 → super_admin（scope=all, caregiverId=null）", async () => {
  const result = await adminAuth.buildAuthContext(reqWith(`Bearer ${SHARED_TOKEN}`), {
    env: DEV_ENV,
  });
  assert.equal(result.ok, true);
  assert.deepEqual(result.authContext, {
    role: "super_admin",
    scope: "all",
    userId: null,
    caregiverId: null,
  });
});

test("ADMIN_API_TOKEN 為空時，空 bearer 不得成為 super_admin（fail-closed）", async () => {
  // 空 token 已先被 missing_admin_token 擋；此處驗 env 無 ADMIN_API_TOKEN 時，
  // 任意 token 不會字面相符 → 走 Firebase 路徑（未 configured + 非 production mock + 無 stub → 401）。
  const result = await adminAuth.buildAuthContext(reqWith("Bearer anything"), {
    env: { NODE_ENV: "test" },
    firebaseAdmin: firebaseStub({}, { configured: false }),
    pg: mockPg({}),
  });
  assert.equal(result.ok, false);
  assert.equal(result.status, 401);
  assert.equal(result.error, "invalid_session");
});

test("有效 caregiver idToken → caregiver(caregiverId = users.id)", async () => {
  const result = await adminAuth.buildAuthContext(reqWith("Bearer cg-token"), {
    env: DEV_ENV,
    firebaseAdmin: firebaseStub({ "cg-token": "fb-cg-1" }),
    pg: mockPg({ "fb-cg-1": { id: "cg-1", role: "caregiver" } }),
  });
  assert.equal(result.ok, true);
  assert.deepEqual(result.authContext, {
    role: "caregiver",
    scope: "assigned_residents",
    userId: "cg-1",
    caregiverId: "cg-1",
  });
});

test("有效 idToken 但 role=admin → super_admin（DB-backed，帶 userId）", async () => {
  const result = await adminAuth.buildAuthContext(reqWith("Bearer admin-token"), {
    env: DEV_ENV,
    firebaseAdmin: firebaseStub({ "admin-token": "fb-admin" }),
    pg: mockPg({ "fb-admin": { id: "admin-1", role: "admin" } }),
  });
  assert.equal(result.ok, true);
  assert.deepEqual(result.authContext, {
    role: "super_admin",
    scope: "all",
    userId: "admin-1",
    caregiverId: null,
  });
});

test("有效 idToken 但 role=elder → 403 admin_permission_required（不得成 super_admin）", async () => {
  const result = await adminAuth.buildAuthContext(reqWith("Bearer elder-token"), {
    env: DEV_ENV,
    firebaseAdmin: firebaseStub({ "elder-token": "fb-elder" }),
    pg: mockPg({ "fb-elder": { id: "elder-1", role: "elder" } }),
  });
  assert.deepEqual(result, { ok: false, status: 403, error: "admin_permission_required" });
});

test("驗過 idToken 但查無 users row → 403（fail-closed）", async () => {
  const result = await adminAuth.buildAuthContext(reqWith("Bearer ghost-token"), {
    env: DEV_ENV,
    firebaseAdmin: firebaseStub({ "ghost-token": "fb-ghost" }),
    pg: mockPg({}),
  });
  assert.deepEqual(result, { ok: false, status: 403, error: "admin_permission_required" });
});

test("Firebase 驗證失敗（configured） → 401 invalid_session", async () => {
  const result = await adminAuth.buildAuthContext(reqWith("Bearer bad-token"), {
    env: DEV_ENV,
    firebaseAdmin: firebaseStub({ "good-token": "fb-1" }), // bad-token 不在映射 → null
    pg: mockPg({ "fb-1": { id: "u1", role: "caregiver" } }),
  });
  assert.deepEqual(result, { ok: false, status: 401, error: "invalid_session" });
});

test("production + 未 configured Firebase → 關 mock → 401（不收假 token）", async () => {
  const result = await adminAuth.buildAuthContext(reqWith("Bearer fake-caregiver-token"), {
    env: PROD_ENV,
    firebaseAdmin: firebaseStub({ "fake-caregiver-token": "fb-x" }, { configured: false }),
    pg: mockPg({ "fb-x": { id: "u-x", role: "caregiver" } }),
  });
  assert.deepEqual(result, { ok: false, status: 401, error: "invalid_session" });
});

test("DB 不可用 → caregiver 解析 fail-closed → 403（不退化成 super_admin）", async () => {
  const result = await adminAuth.buildAuthContext(reqWith("Bearer cg-token"), {
    env: DEV_ENV,
    firebaseAdmin: firebaseStub({ "cg-token": "fb-cg-1" }),
    pg: mockPg({ "fb-cg-1": { id: "cg-1", role: "caregiver" } }, { available: false }),
  });
  assert.deepEqual(result, { ok: false, status: 403, error: "admin_permission_required" });
});

// --- CR-0043 B3：inactive 停用閘（migration 014 users.status） ---

test("CR-0043: inactive caregiver → 403 admin_permission_required（即時失效）", async () => {
  const result = await adminAuth.buildAuthContext(reqWith("Bearer cg-token"), {
    env: DEV_ENV,
    firebaseAdmin: firebaseStub({ "cg-token": "fb-cg-1" }),
    pg: mockPg({ "fb-cg-1": { id: "cg-1", role: "caregiver", status: "inactive" } }),
  });
  assert.deepEqual(result, { ok: false, status: 403, error: "admin_permission_required" });
});

test("CR-0043: active caregiver（status='active'）→ 照舊解析為 caregiver", async () => {
  const result = await adminAuth.buildAuthContext(reqWith("Bearer cg-token"), {
    env: DEV_ENV,
    firebaseAdmin: firebaseStub({ "cg-token": "fb-cg-1" }),
    pg: mockPg({ "fb-cg-1": { id: "cg-1", role: "caregiver", status: "active" } }),
  });
  assert.equal(result.ok, true);
  assert.equal(result.authContext.role, "caregiver");
  assert.equal(result.authContext.caregiverId, "cg-1");
});

test("CR-0043: status 欄缺值 / NULL（舊 row）→ 視為 active（向後相容）", async () => {
  const nullStatus = await adminAuth.buildAuthContext(reqWith("Bearer cg-token"), {
    env: DEV_ENV,
    firebaseAdmin: firebaseStub({ "cg-token": "fb-cg-1" }),
    pg: mockPg({ "fb-cg-1": { id: "cg-1", role: "caregiver", status: null } }),
  });
  assert.equal(nullStatus.ok, true);
  assert.equal(nullStatus.authContext.role, "caregiver");

  // 完全沒有 status 欄位（migration 014 未跑）→ 一樣視為 active。
  const noField = await adminAuth.buildAuthContext(reqWith("Bearer cg-token"), {
    env: DEV_ENV,
    firebaseAdmin: firebaseStub({ "cg-token": "fb-cg-1" }),
    pg: mockPg({ "fb-cg-1": { id: "cg-1", role: "caregiver" } }),
  });
  assert.equal(noField.ok, true);
  assert.equal(noField.authContext.role, "caregiver");
});

test("CR-0043: inactive DB-admin → 403（閘對 DB-admin 亦適用，更安全）", async () => {
  const result = await adminAuth.buildAuthContext(reqWith("Bearer admin-token"), {
    env: DEV_ENV,
    firebaseAdmin: firebaseStub({ "admin-token": "fb-admin" }),
    pg: mockPg({ "fb-admin": { id: "admin-1", role: "admin", status: "inactive" } }),
  });
  assert.deepEqual(result, { ok: false, status: 403, error: "admin_permission_required" });
});

test("CR-0043: 共享 super_admin token 不查 DB → 不受 status 閘影響", async () => {
  const result = await adminAuth.buildAuthContext(reqWith(`Bearer ${SHARED_TOKEN}`), {
    env: DEV_ENV,
    // 即便注入會回 inactive 的 pg，也不該被觸碰（共享 token 早退）。
    firebaseAdmin: firebaseStub({}),
    pg: mockPg({}),
  });
  assert.equal(result.ok, true);
  assert.equal(result.authContext.role, "super_admin");
});

test("resolveAdminAuthContext 中介層：成功 → 掛 req.authContext + next()", async () => {
  adminAuth.setFirebaseAdminForTest(firebaseStub({ "cg-token": "fb-cg-1" }));
  adminAuth.setPgForTest(mockPg({ "fb-cg-1": { id: "cg-1", role: "caregiver" } }));
  process.env.ADMIN_API_TOKEN = SHARED_TOKEN;

  const req = reqWith("Bearer cg-token");
  let nextCalled = false;
  const res = {
    statusCode: null,
    body: null,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(payload) {
      this.body = payload;
      return this;
    },
  };
  await new Promise((resolve) => {
    adminAuth.resolveAdminAuthContext(req, res, () => {
      nextCalled = true;
      resolve();
    });
    // 若中介層走錯誤路徑（不呼叫 next），給個微小逃生：用 setImmediate 解析。
    setImmediate(() => resolve());
  });
  assert.equal(nextCalled, true);
  assert.equal(req.authContext.role, "caregiver");
  assert.equal(req.authContext.caregiverId, "cg-1");
});

test("resolveAdminAuthContext 中介層：無 token → 401 missing_admin_token", async () => {
  const req = reqWith(null);
  const res = {
    statusCode: null,
    body: null,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(payload) {
      this.body = payload;
      return this;
    },
  };
  await new Promise((resolve) => {
    adminAuth.resolveAdminAuthContext(req, res, () => resolve());
    setImmediate(() => resolve());
  });
  assert.equal(res.statusCode, 401);
  assert.deepEqual(res.body, { ok: false, error: "missing_admin_token" });
});
