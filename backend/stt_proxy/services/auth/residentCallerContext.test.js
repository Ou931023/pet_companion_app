const assert = require("node:assert/strict");
const { test } = require("node:test");

// CR-0045 B1：resident-caller 身分解析純單元測試（不起 HTTP server、不接真 DB / 真 Firebase）。
// 注入 stub firebaseAdmin + mock pg，覆蓋 §B1 案：
//   無 token→401 / invalid token→401 / valid 無 row（production→403、dev mock→由 uid 推導）/
//   elder_id null→403 resident_not_linked / inactive→403 / context 形狀 / production 關 mock。

const {
  resolveResidentCallerContext,
} = require("./residentCallerContext");

const ELDER_A = "11111111-1111-1111-1111-111111111111";

function reqWith(token) {
  return { headers: token ? { authorization: `Bearer ${token}` } : {} };
}

// stub firebaseAdmin：configured，map token→uid。
function fbStub(map = {}, { configured = true } = {}) {
  return {
    isConfigured: () => configured,
    verifyIdToken: async (token) => (map[token] ? { uid: map[token] } : null),
  };
}

// mock pg：byUid → users row（id, role, status, elder_id）。
function pgStub(byUid = {}, { available = true } = {}) {
  return {
    isPostgresAvailable: async () => available,
    query: async (_text, params) => {
      const row = byUid[params && params[0]];
      return { rows: row ? [row] : [] };
    },
  };
}

const DEV_ENV = { NODE_ENV: "test", AUTH_ALLOW_MOCK: "true" };
const PROD_ENV = { NODE_ENV: "production" };

test("無 token → 401 missing_resident_token", async () => {
  const result = await resolveResidentCallerContext(reqWith(null), {
    firebaseAdmin: fbStub(),
    pg: pgStub(),
    env: DEV_ENV,
  });
  assert.deepEqual(result, { ok: false, status: 401, error: "missing_resident_token" });
});

test("invalid token（verify 回 null）→ 401 invalid_session", async () => {
  const result = await resolveResidentCallerContext(reqWith("forged"), {
    firebaseAdmin: fbStub({ "good-token": "uid-1" }),
    pg: pgStub(),
    env: DEV_ENV,
  });
  assert.deepEqual(result, { ok: false, status: 401, error: "invalid_session" });
});

test("valid token + 真 users row（elder_id 非 null）→ resident context 形狀正確", async () => {
  const result = await resolveResidentCallerContext(reqWith("res-1-token"), {
    firebaseAdmin: fbStub({ "res-1-token": "fb-res-1" }),
    pg: pgStub({
      "fb-res-1": { id: "user-1", role: "resident", status: "active", elder_id: ELDER_A },
    }),
    env: DEV_ENV,
  });
  assert.equal(result.ok, true);
  assert.deepEqual(result.authContext, {
    userId: "user-1",
    firebaseUid: "fb-res-1",
    elderId: ELDER_A,
    role: "resident",
    isSuperAdmin: false,
  });
});

test("valid token 無 users row（production）→ 403 resident_not_linked", async () => {
  const result = await resolveResidentCallerContext(reqWith("res-1-token"), {
    firebaseAdmin: fbStub({ "res-1-token": "fb-res-1" }),
    pg: pgStub({}), // 查無 row
    env: PROD_ENV,
  });
  assert.deepEqual(result, { ok: false, status: 403, error: "resident_not_linked" });
});

test("valid token 無 users row（dev mock）→ 由 verified uid 推導 scoping elderId", async () => {
  const result = await resolveResidentCallerContext(reqWith("res-1-token"), {
    firebaseAdmin: fbStub({ "res-1-token": "fb-res-1" }),
    pg: pgStub({}),
    env: DEV_ENV,
  });
  assert.equal(result.ok, true);
  assert.deepEqual(result.authContext, {
    userId: null,
    firebaseUid: "fb-res-1",
    elderId: "fb-res-1", // dev-only seam：以 uid 當 scoping elderId
    role: "resident",
    isSuperAdmin: false,
  });
});

test("elder_id 為 null → 403 resident_not_linked（fail-closed）", async () => {
  const result = await resolveResidentCallerContext(reqWith("res-1-token"), {
    firebaseAdmin: fbStub({ "res-1-token": "fb-res-1" }),
    pg: pgStub({
      "fb-res-1": { id: "user-1", role: "resident", status: "active", elder_id: null },
    }),
    env: DEV_ENV,
  });
  assert.deepEqual(result, { ok: false, status: 403, error: "resident_not_linked" });
});

test("inactive 帳號 → 403 resident_inactive（停用閘，先於 elder_id 判定）", async () => {
  const result = await resolveResidentCallerContext(reqWith("res-1-token"), {
    firebaseAdmin: fbStub({ "res-1-token": "fb-res-1" }),
    pg: pgStub({
      "fb-res-1": { id: "user-1", role: "resident", status: "inactive", elder_id: ELDER_A },
    }),
    env: DEV_ENV,
  });
  assert.deepEqual(result, { ok: false, status: 403, error: "resident_inactive" });
});

test("status NULL → 視為 active（向後相容）", async () => {
  const result = await resolveResidentCallerContext(reqWith("res-1-token"), {
    firebaseAdmin: fbStub({ "res-1-token": "fb-res-1" }),
    pg: pgStub({
      "fb-res-1": { id: "user-1", role: "resident", status: null, elder_id: ELDER_A },
    }),
    env: DEV_ENV,
  });
  assert.equal(result.ok, true);
  assert.equal(result.authContext.elderId, ELDER_A);
});

test("production 關 mock：未 configured + 任意 token → 401 invalid_session（不放行）", async () => {
  const result = await resolveResidentCallerContext(reqWith("any-token"), {
    firebaseAdmin: fbStub({ "any-token": "fb-x" }, { configured: false }),
    pg: pgStub({ "fb-x": { id: "u", role: "resident", status: "active", elder_id: ELDER_A } }),
    env: PROD_ENV,
  });
  assert.deepEqual(result, { ok: false, status: 401, error: "invalid_session" });
});

test("dev 未 configured 但 stub verify 解出 uid → 仍可解析（mock 守門）", async () => {
  const result = await resolveResidentCallerContext(reqWith("mock-id-token-x"), {
    firebaseAdmin: fbStub({ "mock-id-token-x": "fb-x" }, { configured: false }),
    pg: pgStub({ "fb-x": { id: "u", role: "resident", status: "active", elder_id: ELDER_A } }),
    env: DEV_ENV,
  });
  assert.equal(result.ok, true);
  assert.equal(result.authContext.elderId, ELDER_A);
});

test("pg 不可用（isPostgresAvailable=false）+ production → 403 resident_not_linked", async () => {
  const result = await resolveResidentCallerContext(reqWith("res-1-token"), {
    firebaseAdmin: fbStub({ "res-1-token": "fb-res-1" }),
    pg: pgStub(
      { "fb-res-1": { id: "u", role: "resident", status: "active", elder_id: ELDER_A } },
      { available: false },
    ),
    env: PROD_ENV,
  });
  assert.deepEqual(result, { ok: false, status: 403, error: "resident_not_linked" });
});
