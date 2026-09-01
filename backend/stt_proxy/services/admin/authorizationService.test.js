const assert = require("node:assert/strict");
const { test } = require("node:test");

const authz = require("./authorizationService");

// 建一個 mock pg：回傳指定 caregiver → elder_id rows。
// 記錄收到的查詢參數，方便斷言只查到自己的 caregiverId。
function makeMockPg(linksByCaregiver, { available = true } = {}) {
  const calls = [];
  return {
    calls,
    isPostgresAvailable: async () => available,
    query: async (text, params) => {
      calls.push({ text, params });
      const caregiverId = params && params[0];
      const elderIds = linksByCaregiver[caregiverId] || [];
      return { rows: elderIds.map((elder_id) => ({ elder_id })) };
    },
  };
}

const SUPER_ADMIN = { role: authz.ROLE_SUPER_ADMIN };
const caregiver = (id) => ({ role: authz.ROLE_CAREGIVER, caregiverId: id });

test("ROLE_SUPER_ADMIN 常數存在", () => {
  assert.equal(authz.ROLE_SUPER_ADMIN, "super_admin");
});

test("resolveAuthContext 預設（無 override）回 super_admin", () => {
  const ctx = authz.resolveAuthContext({});
  assert.deepEqual(ctx, { role: "super_admin" });
});

test("resolveAuthContext 可被測試 seam 覆寫成 caregiver", () => {
  authz.setAuthContextResolverForTest(() => caregiver("cg-1"));
  try {
    const ctx = authz.resolveAuthContext({});
    assert.deepEqual(ctx, { role: "caregiver", caregiverId: "cg-1" });
  } finally {
    authz.setAuthContextResolverForTest(null);
  }
  // 還原後回 super_admin。
  assert.deepEqual(authz.resolveAuthContext({}), { role: "super_admin" });
});

test("getAuthorizedResidentIdsForCaregiver 只取自己授權的 elder", async () => {
  const pg = makeMockPg({ "cg-1": ["elder-a", "elder-b"], "cg-2": ["elder-c"] });
  const ids = await authz.getAuthorizedResidentIdsForCaregiver("cg-1", { pg });
  assert.deepEqual([...ids].sort(), ["elder-a", "elder-b"]);
  // 確認查詢帶的是自己的 caregiverId。
  assert.equal(pg.calls[0].params[0], "cg-1");
});

test("getAuthorizedResidentIdsForCaregiver 無授權 → 空集合", async () => {
  const pg = makeMockPg({ "cg-1": ["elder-a"] });
  const ids = await authz.getAuthorizedResidentIdsForCaregiver("cg-x", { pg });
  assert.equal(ids.size, 0);
});

test("getAuthorizedResidentIdsForCaregiver 缺 caregiverId → 空集合（不查 DB）", async () => {
  const pg = makeMockPg({});
  const ids = await authz.getAuthorizedResidentIdsForCaregiver(null, { pg });
  assert.equal(ids.size, 0);
  assert.equal(pg.calls.length, 0);
});

test("getAuthorizedResidentIdsForCaregiver DB 不可用 → 空集合（fail-closed，不看全部）", async () => {
  const pg = makeMockPg({ "cg-1": ["elder-a"] }, { available: false });
  const ids = await authz.getAuthorizedResidentIdsForCaregiver("cg-1", { pg });
  assert.equal(ids.size, 0);
  assert.equal(pg.calls.length, 0);
});

test("assertCanAccessResident: super_admin 一律 true（不查 DB）", async () => {
  const pg = makeMockPg({});
  const ok = await authz.assertCanAccessResident(SUPER_ADMIN, "elder-any", { pg });
  assert.equal(ok, true);
  assert.equal(pg.calls.length, 0);
});

test("assertCanAccessResident: caregiver 在授權內 → true", async () => {
  const pg = makeMockPg({ "cg-1": ["elder-a", "elder-b"] });
  const ok = await authz.assertCanAccessResident(caregiver("cg-1"), "elder-a", { pg });
  assert.equal(ok, true);
});

test("assertCanAccessResident: caregiver 跨住民 → false（拒絕）", async () => {
  const pg = makeMockPg({ "cg-1": ["elder-a"] });
  const ok = await authz.assertCanAccessResident(caregiver("cg-1"), "elder-z", { pg });
  assert.equal(ok, false);
});

test("assertCanAccessResident: 無 context / 未知角色 → false（fail-closed）", async () => {
  const pg = makeMockPg({ "cg-1": ["elder-a"] });
  assert.equal(await authz.assertCanAccessResident(null, "elder-a", { pg }), false);
  assert.equal(
    await authz.assertCanAccessResident({ role: "unknown" }, "elder-a", { pg }),
    false,
  );
});

test("assertCanManageResident: super_admin 可寫且不查 DB", async () => {
  const pg = makeMockPg({});
  assert.equal(await authz.assertCanManageResident(SUPER_ADMIN, "elder-a", { pg }), true);
  assert.equal(pg.calls.length, 0);
});

test("assertCanManageResident: primary / secondary 可寫，viewer 固定唯讀", async () => {
  function rolePg(role) {
    return {
      isPostgresAvailable: async () => true,
      query: async (_text, params) => ({
        rows:
          params[0] === "cg-1" &&
          params[1] === "elder-a" &&
          (role === "primary" || role === "secondary")
            ? [{ role }]
            : [],
      }),
    };
  }

  assert.equal(
    await authz.assertCanManageResident(caregiver("cg-1"), "elder-a", {
      pg: rolePg("primary"),
    }),
    true,
  );
  assert.equal(
    await authz.assertCanManageResident(caregiver("cg-1"), "elder-a", {
      pg: rolePg("secondary"),
    }),
    true,
  );
  assert.equal(
    await authz.assertCanManageResident(caregiver("cg-1"), "elder-a", {
      pg: rolePg("viewer"),
    }),
    false,
  );
});

test("assertCanManageResident: 跨住民、缺 context 或 DB 不可用皆拒絕", async () => {
  const pg = {
    isPostgresAvailable: async () => false,
    query: async () => {
      throw new Error("must not query unavailable DB");
    },
  };
  assert.equal(await authz.assertCanManageResident(caregiver("cg-1"), "elder-z", { pg }), false);
  assert.equal(await authz.assertCanManageResident(null, "elder-a", { pg }), false);
});

test("filterAlertsByAuthorizedResidents: super_admin 原樣回傳（同陣列）", async () => {
  const pg = makeMockPg({});
  const alerts = [
    { id: "1", elderId: "elder-a" },
    { id: "2", elderId: "elder-z" },
    { id: "3", elderId: null },
  ];
  const out = await authz.filterAlertsByAuthorizedResidents(SUPER_ADMIN, alerts, { pg });
  assert.equal(out, alerts);
  assert.equal(pg.calls.length, 0);
});

test("filterAlertsByAuthorizedResidents: caregiver 只見授權住民", async () => {
  const pg = makeMockPg({ "cg-1": ["elder-a"] });
  const alerts = [
    { id: "1", elderId: "elder-a" },
    { id: "2", elderId: "elder-z" },
    { id: "3", elderId: null }, // 無 elderId → 過濾掉
  ];
  const out = await authz.filterAlertsByAuthorizedResidents(caregiver("cg-1"), alerts, { pg });
  assert.deepEqual(out.map((a) => a.id), ["1"]);
});

test("filterAlertsByAuthorizedResidents: caregiver 無授權 → 空陣列", async () => {
  const pg = makeMockPg({ "cg-1": ["elder-a"] });
  const alerts = [{ id: "1", elderId: "elder-a" }];
  const out = await authz.filterAlertsByAuthorizedResidents(caregiver("cg-x"), alerts, { pg });
  assert.deepEqual(out, []);
});

test("filterAlertsByAuthorizedResidents: 無 context → 空陣列（fail-closed）", async () => {
  const pg = makeMockPg({});
  const out = await authz.filterAlertsByAuthorizedResidents(null, [{ id: "1", elderId: "elder-a" }], { pg });
  assert.deepEqual(out, []);
});
