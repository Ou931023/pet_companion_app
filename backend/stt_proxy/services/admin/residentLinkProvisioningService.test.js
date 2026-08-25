const assert = require("node:assert/strict");
const { test, afterEach } = require("node:test");

// CR-0043 B2：residentLinkProvisioningService 單元測試（mock pg，無真 DB）。
// 涵蓋：列出（join 名稱、status 映射 active/inactive）/ 建立（存在性檢查、重複 active 防止、role 正規化）/
//      改 role / 停用映射（inactive→DB revoked）/ 啟用 / invalid id / not_found。

const svc = require("./residentLinkProvisioningService");

// 具狀態 mock pg：模擬 elders / users / resident_caregiver_links，依 SQL 形狀路由。
function makeMockPg({ elders = [], users = [], links = [] } = {}) {
  let seq = links.length;
  const state = { elders, users, links: links.map((l) => ({ ...l })) };

  function joinRow(l) {
    const e = state.elders.find((x) => x.id === l.elder_id);
    const u = state.users.find((x) => x.id === l.caregiver_id);
    return {
      id: l.id,
      elder_id: l.elder_id,
      resident_name: e ? e.display_name : null,
      caregiver_id: l.caregiver_id,
      caregiver_name: u ? u.display_name : null,
      role: l.role,
      status: l.status,
      created_at: l.created_at,
      updated_at: l.updated_at,
    };
  }

  return {
    state,
    isPostgresAvailable: async () => true,
    query: async (text, params = []) => {
      const sql = text.replace(/\s+/g, " ").trim();

      if (/^SELECT id FROM elders WHERE id = \$1/i.test(sql)) {
        const hit = state.elders.find((e) => e.id === params[0]);
        return { rows: hit ? [{ id: hit.id }] : [] };
      }
      if (/^SELECT id FROM users WHERE id = \$1 AND role = 'caregiver'/i.test(sql)) {
        const hit = state.users.find((u) => u.id === params[0] && u.role === "caregiver");
        return { rows: hit ? [{ id: hit.id }] : [] };
      }
      if (/SELECT id FROM resident_caregiver_links WHERE elder_id = \$1 AND caregiver_id = \$2 AND status = 'active'/i.test(sql)) {
        const hit = state.links.find(
          (l) => l.elder_id === params[0] && l.caregiver_id === params[1] && l.status === "active",
        );
        return { rows: hit ? [{ id: hit.id }] : [] };
      }
      if (/^INSERT INTO resident_caregiver_links/i.test(sql)) {
        const [elder_id, caregiver_id, role] = params;
        const row = {
          id: `link-${++seq}`,
          elder_id,
          caregiver_id,
          role,
          status: "active",
          created_at: new Date(Date.now() + seq).toISOString(),
          updated_at: null,
          revoked_at: null,
        };
        state.links.push(row);
        return { rows: [{ id: row.id }] };
      }
      if (/^UPDATE resident_caregiver_links SET role = \$2/i.test(sql)) {
        const row = state.links.find((l) => l.id === params[0]);
        if (!row) return { rows: [] };
        row.role = params[1];
        row.updated_at = new Date().toISOString();
        return { rows: [{ id: row.id }] };
      }
      if (/^UPDATE resident_caregiver_links SET status = \$2/i.test(sql)) {
        const row = state.links.find((l) => l.id === params[0]);
        if (!row) return { rows: [] };
        row.status = params[1];
        row.updated_at = new Date().toISOString();
        row.revoked_at = params[1] === "revoked" ? new Date().toISOString() : null;
        return { rows: [{ id: row.id }] };
      }
      // join select by id
      if (/FROM resident_caregiver_links l/i.test(sql) && /WHERE l\.id = \$1/i.test(sql)) {
        const row = state.links.find((l) => l.id === params[0]);
        return { rows: row ? [joinRow(row)] : [] };
      }
      // list join
      if (/FROM resident_caregiver_links l/i.test(sql) && /ORDER BY l\.created_at DESC/i.test(sql)) {
        const rows = [...state.links]
          .sort((a, b) => String(b.created_at).localeCompare(String(a.created_at)))
          .map(joinRow);
        return { rows };
      }
      return { rows: [] };
    },
  };
}

const ELDER_A = { id: "elder-a", display_name: "陳阿嬤" };
const CG_1 = { id: "cg-1", display_name: "護理師A", role: "caregiver" };

afterEach(() => svc.setPgForTest(null));

test("createLink：成功建立 active link，回 join 名稱與對外 status=active", async () => {
  const pg = makeMockPg({ elders: [ELDER_A], users: [CG_1] });
  const r = await svc.createLink({ residentId: "elder-a", caregiverId: "cg-1", role: "primary" }, { pg });
  assert.equal(r.ok, true);
  assert.equal(r.link.residentId, "elder-a");
  assert.equal(r.link.residentName, "陳阿嬤");
  assert.equal(r.link.caregiverId, "cg-1");
  assert.equal(r.link.caregiverName, "護理師A");
  assert.equal(r.link.role, "primary");
  assert.equal(r.link.status, "active");
});

test("createLink：缺欄位 → invalid_payload", async () => {
  const pg = makeMockPg({ elders: [ELDER_A], users: [CG_1] });
  const r = await svc.createLink({ residentId: "elder-a" }, { pg });
  assert.deepEqual(r, { ok: false, error: "invalid_payload" });
});

test("createLink：resident 不存在 → resident_not_found", async () => {
  const pg = makeMockPg({ elders: [], users: [CG_1] });
  const r = await svc.createLink({ residentId: "ghost", caregiverId: "cg-1" }, { pg });
  assert.deepEqual(r, { ok: false, error: "resident_not_found" });
});

test("createLink：caregiver 不存在（或非 caregiver 角色）→ caregiver_not_found", async () => {
  const pg = makeMockPg({ elders: [ELDER_A], users: [{ id: "u-elder", role: "elder" }] });
  const r = await svc.createLink({ residentId: "elder-a", caregiverId: "u-elder" }, { pg });
  assert.deepEqual(r, { ok: false, error: "caregiver_not_found" });
});

test("createLink：同 caregiver+elder 已有 active link → 不建第二筆（link_exists）", async () => {
  const pg = makeMockPg({
    elders: [ELDER_A],
    users: [CG_1],
    links: [
      { id: "link-1", elder_id: "elder-a", caregiver_id: "cg-1", role: "primary", status: "active", created_at: "2026-06-01T00:00:00Z", updated_at: null, revoked_at: null },
    ],
  });
  const r = await svc.createLink({ residentId: "elder-a", caregiverId: "cg-1" }, { pg });
  assert.deepEqual(r, { ok: false, error: "link_exists" });
  assert.equal(pg.state.links.length, 1, "不應新增第二筆");
});

test("createLink：DB unique violation → link_exists（競態下仍回可理解錯誤）", async () => {
  const pg = makeMockPg({ elders: [ELDER_A], users: [CG_1] });
  const originalQuery = pg.query;
  pg.query = async (text, params) => {
    if (/^INSERT INTO resident_caregiver_links/i.test(text.replace(/\s+/g, " ").trim())) {
      const err = new Error("duplicate key value violates unique constraint");
      err.code = "23505";
      err.constraint = "idx_rcl_unique_active";
      throw err;
    }
    return originalQuery(text, params);
  };
  const r = await svc.createLink({ residentId: "elder-a", caregiverId: "cg-1" }, { pg });
  assert.deepEqual(r, { ok: false, error: "link_exists" });
});

test("createLink：前置查詢遇到 UUID 格式錯誤 → invalid_payload", async () => {
  const pg = makeMockPg({ elders: [ELDER_A], users: [CG_1] });
  const originalQuery = pg.query;
  pg.query = async (text, params) => {
    if (/^SELECT id FROM elders WHERE id = \$1/i.test(text.replace(/\s+/g, " ").trim())) {
      const err = new Error("invalid input syntax for type uuid");
      err.code = "22P02";
      throw err;
    }
    return originalQuery(text, params);
  };
  const r = await svc.createLink({ residentId: "陳奶奶", caregiverId: "cg-1" }, { pg });
  assert.deepEqual(r, { ok: false, error: "invalid_payload" });
});

test("createLink：建立成功但 join 補資料失敗時仍回最小安全 link", async () => {
  const pg = makeMockPg({ elders: [ELDER_A], users: [CG_1] });
  const originalQuery = pg.query;
  pg.query = async (text, params) => {
    const sql = text.replace(/\s+/g, " ").trim();
    if (/FROM resident_caregiver_links l/i.test(sql) && /WHERE l\.id = \$1/i.test(sql)) {
      const err = new Error("column e.display_name does not exist");
      err.code = "42703";
      throw err;
    }
    return originalQuery(text, params);
  };
  const r = await svc.createLink({ residentId: "elder-a", caregiverId: "cg-1", role: "primary" }, { pg });
  assert.equal(r.ok, true);
  assert.equal(r.link.residentId, "elder-a");
  assert.equal(r.link.caregiverId, "cg-1");
  assert.equal(r.link.role, "primary");
  assert.equal(r.link.status, "active");
});

test("provisioningErrorFromDb：schema 未就緒錯誤轉成 database_schema_not_ready", () => {
  assert.equal(svc.provisioningErrorFromDb({ code: "42P01" }), "database_schema_not_ready");
  assert.equal(svc.provisioningErrorFromDb({ code: "42703" }), "database_schema_not_ready");
});

test("provisioningErrorFromDb：UUID 格式錯誤轉成 invalid_payload", () => {
  assert.equal(svc.provisioningErrorFromDb({ code: "22P02" }), "invalid_payload");
});

test("createLink：role 'backup' → 正規化為 secondary（對齊 013）", async () => {
  const pg = makeMockPg({ elders: [ELDER_A], users: [CG_1] });
  const r = await svc.createLink({ residentId: "elder-a", caregiverId: "cg-1", role: "backup" }, { pg });
  assert.equal(r.ok, true);
  assert.equal(r.link.role, "secondary");
});

test("createLink：非法 role → invalid_role", async () => {
  const pg = makeMockPg({ elders: [ELDER_A], users: [CG_1] });
  const r = await svc.createLink({ residentId: "elder-a", caregiverId: "cg-1", role: "owner" }, { pg });
  assert.deepEqual(r, { ok: false, error: "invalid_role" });
});

test("listLinks：含已停用，status 對外映射（active/inactive）", async () => {
  const pg = makeMockPg({
    elders: [ELDER_A],
    users: [CG_1],
    links: [
      { id: "link-1", elder_id: "elder-a", caregiver_id: "cg-1", role: "primary", status: "active", created_at: "2026-06-02T00:00:00Z", updated_at: null, revoked_at: null },
      { id: "link-2", elder_id: "elder-a", caregiver_id: "cg-1", role: "viewer", status: "revoked", created_at: "2026-06-01T00:00:00Z", updated_at: null, revoked_at: "2026-06-01T01:00:00Z" },
    ],
  });
  const list = await svc.listLinks({ pg });
  assert.equal(list.length, 2);
  const byId = Object.fromEntries(list.map((l) => [l.id, l]));
  assert.equal(byId["link-1"].status, "active");
  assert.equal(byId["link-2"].status, "inactive"); // revoked → 對外 inactive
});

test("setLinkStatus：停用 → DB status=revoked、對外 inactive；authorizationService 自動排除", async () => {
  const pg = makeMockPg({
    elders: [ELDER_A],
    users: [CG_1],
    links: [
      { id: "link-1", elder_id: "elder-a", caregiver_id: "cg-1", role: "primary", status: "active", created_at: "2026-06-01T00:00:00Z", updated_at: null, revoked_at: null },
    ],
  });
  const r = await svc.setLinkStatus("link-1", "inactive", { pg });
  assert.equal(r.ok, true);
  assert.equal(r.link.status, "inactive");
  assert.equal(pg.state.links[0].status, "revoked", "DB 端應為 revoked（對齊 013 + authorizationService 查詢）");
  assert.ok(pg.state.links[0].revoked_at, "revoked_at 應設值");
});

test("setLinkStatus：重新啟用 → DB status=active、revoked_at 清空", async () => {
  const pg = makeMockPg({
    elders: [ELDER_A],
    users: [CG_1],
    links: [
      { id: "link-1", elder_id: "elder-a", caregiver_id: "cg-1", role: "primary", status: "revoked", created_at: "2026-06-01T00:00:00Z", updated_at: null, revoked_at: "2026-06-01T01:00:00Z" },
    ],
  });
  const r = await svc.setLinkStatus("link-1", "active", { pg });
  assert.equal(r.ok, true);
  assert.equal(r.link.status, "active");
  assert.equal(pg.state.links[0].status, "active");
  assert.equal(pg.state.links[0].revoked_at, null);
});

test("setLinkStatus：非法狀態 → invalid_status", async () => {
  const pg = makeMockPg({ links: [{ id: "link-1", elder_id: "elder-a", caregiver_id: "cg-1", role: "primary", status: "active", created_at: "2026-06-01T00:00:00Z" }] });
  const r = await svc.setLinkStatus("link-1", "revoked", { pg });
  assert.deepEqual(r, { ok: false, error: "invalid_status" });
});

test("setLinkStatus：不存在 → not_found", async () => {
  const pg = makeMockPg({});
  const r = await svc.setLinkStatus("ghost", "inactive", { pg });
  assert.deepEqual(r, { ok: false, error: "not_found" });
});

test("updateLinkRole：改 role → 成功；不存在 → not_found", async () => {
  const pg = makeMockPg({
    elders: [ELDER_A],
    users: [CG_1],
    links: [
      { id: "link-1", elder_id: "elder-a", caregiver_id: "cg-1", role: "primary", status: "active", created_at: "2026-06-01T00:00:00Z", updated_at: null, revoked_at: null },
    ],
  });
  const ok = await svc.updateLinkRole("link-1", "viewer", { pg });
  assert.equal(ok.ok, true);
  assert.equal(ok.link.role, "viewer");

  const miss = await svc.updateLinkRole("ghost", "viewer", { pg });
  assert.deepEqual(miss, { ok: false, error: "not_found" });
});
