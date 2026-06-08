const assert = require("node:assert/strict");
const { test, beforeEach, afterEach } = require("node:test");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

// CR-0043 B4：caregiver / resident-caregiver-link provisioning 路由 HTTP 測試（任務 §8.1 #1–#12）。
//
// 全部 super_admin-only（requireAdmin，共享 ADMIN_API_TOKEN）：
//   - caregiver 持有效 idToken 也進不來（requireAdmin 只認字面 token → 403）。
//   - 無 token → 401。
// 端到端 scope refresh：建 link → caregiver 看得到 alert → 停用 link → 看不到（authorizationService 未改）。
// inactive caregiver 讀 scoped API → 403（adminAuthContext 停用閘）。
//
// 全程 mock pg（users / elders / resident_caregiver_links）+ stub firebaseAdmin（caregiver idToken）。
// care_alerts 走 JSON 暫存檔（careAlertStore，無 PG）。不對真 DB / 真 Firebase。

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "cg_prov_ep_"));
process.env.CARE_ALERTS_DATA_FILE = path.join(tmp, "care_alerts.json");
process.env.ELDERS_DATA_FILE = path.join(tmp, "elders.json");
process.env.USERS_DATA_FILE = path.join(tmp, "users.json");
process.env.NODE_ENV = "test";
process.env.ADMIN_API_TOKEN = "test-admin-token";

const app = require("../../server");
const adminAuth = require("./adminAuthContext");
const authz = require("./authorizationService");
const caregiverProvisioning = require("./caregiverProvisioningService");
const linkProvisioning = require("./residentLinkProvisioningService");
const auditLog = require("../auditLogService");
// CR-0045 B2：/notify 改掛 requireResidentCaller；seeding alert 需帶 resident idToken。
const {
  installResidentCallerStub,
} = require("../auth/residentCallerContext.testsupport");

delete process.env.TELEGRAM_BOT_TOKEN;
delete process.env.TELEGRAM_CARE_CHAT_ID;

const ADMIN_HEADERS = { Authorization: "Bearer test-admin-token" };
const CG_HEADERS = { Authorization: "Bearer cg-1-id-token" };
const ELDER_A = "11111111-1111-1111-1111-111111111111";
const ELDER_Z = "99999999-9999-9999-9999-999999999999";

// idToken → firebase_uid。
function firebaseStub() {
  const map = { "cg-1-id-token": "fb-cg-1" };
  return {
    isConfigured: () => true,
    verifyIdToken: async (token) => (map[token] ? { uid: map[token] } : null),
  };
}

// 統一 stateful mock pg：服務 users / elders / resident_caregiver_links 的所有查詢形狀。
function makeUnifiedPg({ elders = [], users = [], links = [] } = {}) {
  let cgSeq = 0;
  let linkSeq = 0;
  const state = {
    elders: elders.map((e) => ({ ...e })),
    users: users.map((u) => ({ ...u })),
    links: links.map((l) => ({ ...l })),
  };

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

      // adminAuthContext：firebase_uid → users row（含 status）。
      if (/SELECT id, role, status FROM users WHERE firebase_uid = \$1/i.test(sql)) {
        const u = state.users.find((x) => x.firebase_uid === params[0]);
        return { rows: u ? [{ id: u.id, role: u.role, status: u.status }] : [] };
      }

      // authorizationService：caregiver → 授權 elder_id（active）。
      if (/SELECT elder_id FROM resident_caregiver_links WHERE caregiver_id = \$1 AND status = 'active'/i.test(sql)) {
        const rows = state.links
          .filter((l) => l.caregiver_id === params[0] && l.status === "active")
          .map((l) => ({ elder_id: l.elder_id }));
        return { rows };
      }

      // caregiverProvisioning：email 佔用
      if (/^SELECT id FROM users WHERE LOWER\(email\) = \$1/i.test(sql)) {
        const email = params[0];
        const excludeId = params[1];
        const hit = state.users.find(
          (u) => (u.email || "").toLowerCase() === email && u.id !== excludeId,
        );
        return { rows: hit ? [{ id: hit.id }] : [] };
      }
      // caregiverProvisioning：list
      if (/FROM users WHERE role = 'caregiver'/i.test(sql) && /ORDER BY created_at DESC/i.test(sql)) {
        const rows = state.users
          .filter((u) => u.role === "caregiver")
          .sort((a, b) => String(b.created_at).localeCompare(String(a.created_at)))
          .map((u) => ({ ...u }));
        return { rows };
      }
      // caregiverProvisioning：insert
      if (/^INSERT INTO users/i.test(sql)) {
        const [email, displayName, firebaseUid] = params;
        const row = {
          id: `cg-${++cgSeq}`,
          email,
          display_name: displayName,
          role: "caregiver",
          status: "active",
          firebase_uid: firebaseUid,
          created_at: new Date(Date.now() + cgSeq).toISOString(),
          updated_at: null,
        };
        state.users.push(row);
        return { rows: [{ ...row }] };
      }
      // caregiverProvisioning：update（status 或一般欄位）
      if (/^UPDATE users SET/i.test(sql)) {
        const isStatus = /SET status = \$2/i.test(sql);
        const id = isStatus ? params[0] : params[params.length - 1];
        const row = state.users.find((u) => u.id === id && u.role === "caregiver");
        if (!row) return { rows: [] };
        if (isStatus) {
          row.status = params[1];
        } else {
          let p = 0;
          if (/display_name = \$/i.test(sql)) row.display_name = params[p++];
          if (/email = \$/i.test(sql)) row.email = params[p++];
          if (/firebase_uid = \$/i.test(sql)) row.firebase_uid = params[p++];
        }
        row.updated_at = new Date().toISOString();
        return { rows: [{ ...row }] };
      }

      // linkProvisioning：existence checks
      if (/^SELECT id FROM elders WHERE id = \$1/i.test(sql)) {
        const e = state.elders.find((x) => x.id === params[0]);
        return { rows: e ? [{ id: e.id }] : [] };
      }
      if (/^SELECT id FROM users WHERE id = \$1 AND role = 'caregiver'/i.test(sql)) {
        const u = state.users.find((x) => x.id === params[0] && x.role === "caregiver");
        return { rows: u ? [{ id: u.id }] : [] };
      }
      if (/SELECT id FROM resident_caregiver_links WHERE elder_id = \$1 AND caregiver_id = \$2 AND status = 'active'/i.test(sql)) {
        const l = state.links.find(
          (x) => x.elder_id === params[0] && x.caregiver_id === params[1] && x.status === "active",
        );
        return { rows: l ? [{ id: l.id }] : [] };
      }
      if (/^INSERT INTO resident_caregiver_links/i.test(sql)) {
        const [elder_id, caregiver_id, role] = params;
        const row = {
          id: `link-${++linkSeq}`,
          elder_id,
          caregiver_id,
          role,
          status: "active",
          created_at: new Date(Date.now() + linkSeq).toISOString(),
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
      if (/FROM resident_caregiver_links l/i.test(sql) && /WHERE l\.id = \$1/i.test(sql)) {
        const row = state.links.find((l) => l.id === params[0]);
        return { rows: row ? [joinRow(row)] : [] };
      }
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

// 稽核捕捉 pg（讓 logAudit 實際寫入並可斷言）。
let auditWrites = [];
let restoreResident = null;
function makeAuditPg() {
  return {
    isPostgresAvailable: async () => true,
    query: async (text, params) => {
      auditWrites.push({ text, params });
      return { rows: [] };
    },
  };
}

let unifiedPg;

beforeEach(() => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "cg_prov_ep_"));
  process.env.CARE_ALERTS_DATA_FILE = path.join(dir, "care_alerts.json");
  auditWrites = [];
  unifiedPg = makeUnifiedPg({ elders: [{ id: ELDER_A, display_name: "陳阿嬤" }] });
  adminAuth.setFirebaseAdminForTest(firebaseStub());
  adminAuth.setPgForTest(unifiedPg);
  authz.setPgForTest(unifiedPg);
  caregiverProvisioning.setPgForTest(unifiedPg);
  linkProvisioning.setPgForTest(unifiedPg);
  auditLog.setPgForTest(makeAuditPg());
  restoreResident = installResidentCallerStub({
    "res-a-token": { uid: "fb-res-a", userId: "user-res-a", elderId: ELDER_A },
    "res-z-token": { uid: "fb-res-z", userId: "user-res-z", elderId: ELDER_Z },
  });
});

afterEach(() => {
  adminAuth.setFirebaseAdminForTest(null);
  adminAuth.setPgForTest(null);
  authz.setPgForTest(null);
  caregiverProvisioning.setPgForTest(null);
  linkProvisioning.setPgForTest(null);
  auditLog.setPgForTest(null);
  if (restoreResident) restoreResident();
  restoreResident = null;
});

function startServer() {
  return new Promise((resolve) => {
    const server = app.listen(0, "127.0.0.1", () => resolve(server));
  });
}

function jsonHeaders(h) {
  return { ...h, "Content-Type": "application/json" };
}

async function settleAudit() {
  // auditProvisioning 是 fire-and-forget；給 microtask/timer 機會落地後再斷言。
  await new Promise((r) => setTimeout(r, 40));
}

function postNotify(baseUrl, elderId) {
  const tokens = { [ELDER_A]: "res-a-token", [ELDER_Z]: "res-z-token" };
  return fetch(`${baseUrl}/api/care-alerts/notify`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${tokens[elderId]}`,
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
    }),
  });
}

// 建一個已綁定 fb-cg-1 的 active caregiver（走 POST pending → PATCH bind = 路線 B）。
async function provisionBoundCaregiver(baseUrl) {
  const created = await (
    await fetch(`${baseUrl}/api/admin/caregivers`, {
      method: "POST",
      headers: jsonHeaders(ADMIN_HEADERS),
      body: JSON.stringify({ email: "nurse@clinic.org", displayName: "護理師A" }),
    })
  ).json();
  const id = created.caregiver.id;
  await fetch(`${baseUrl}/api/admin/caregivers/${id}`, {
    method: "PATCH",
    headers: jsonHeaders(ADMIN_HEADERS),
    body: JSON.stringify({ firebaseUid: "fb-cg-1" }),
  });
  return id;
}

// #1
test("caregiver idToken 呼叫管理 API → 403（requireAdmin 只認共享 token）", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetch(`${baseUrl}/api/admin/caregivers`, { headers: CG_HEADERS });
    const body = await res.json();
    assert.equal(res.status, 403);
    assert.equal(body.error, "admin_permission_required");
  } finally {
    server.close();
  }
});

// #2
test("無 token → 401 missing_admin_token", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetch(`${baseUrl}/api/admin/caregivers`);
    const body = await res.json();
    assert.equal(res.status, 401);
    assert.equal(body.error, "missing_admin_token");
  } finally {
    server.close();
  }
});

// #3 + #10 + #11
test("super_admin 建立 caregiver → 201；寫 audit；回應不含 token / 敏感欄位", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetch(`${baseUrl}/api/admin/caregivers`, {
      method: "POST",
      headers: jsonHeaders(ADMIN_HEADERS),
      body: JSON.stringify({ email: "Nurse@Clinic.org", displayName: "護理師A" }),
    });
    const body = await res.json();
    assert.equal(res.status, 201);
    assert.equal(body.ok, true);
    assert.equal(body.caregiver.role, "caregiver");
    assert.equal(body.caregiver.status, "active");
    assert.equal(body.caregiver.firebaseUid, null); // pending（路線 B）
    assert.equal(body.caregiver.emailMasked, "nu***@clinic.org");

    const blob = JSON.stringify(body);
    for (const s of ["password_hash", "provider_user_id", "Nurse@Clinic.org", "test-admin-token"]) {
      assert.ok(!blob.includes(s), `回應不得含敏感字串：${s}`);
    }

    await settleAudit();
    const write = auditWrites.find((w) => w.params && w.params[2] === "caregiver_create");
    assert.ok(write, "應寫入 caregiver_create 稽核");
    assert.equal(write.params[0], "super_admin"); // actorType
    assert.equal(write.params[1], null); // actorId（共享 token 無 per-actor）
    const metaBlob = String(write.params[6] || "");
    for (const s of ["Nurse@Clinic.org", "test-admin-token", "fb-"]) {
      assert.ok(!metaBlob.includes(s), `audit metadata 不得含 PII/token：${s}`);
    }
  } finally {
    server.close();
  }
});

// #4
test("重複 email → 409 email_exists", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    await fetch(`${baseUrl}/api/admin/caregivers`, {
      method: "POST",
      headers: jsonHeaders(ADMIN_HEADERS),
      body: JSON.stringify({ email: "dup@clinic.org" }),
    });
    const res = await fetch(`${baseUrl}/api/admin/caregivers`, {
      method: "POST",
      headers: jsonHeaders(ADMIN_HEADERS),
      body: JSON.stringify({ email: "DUP@clinic.org" }),
    });
    const body = await res.json();
    assert.equal(res.status, 409);
    assert.equal(body.error, "email_exists");
  } finally {
    server.close();
  }
});

// #5
test("super_admin 建立 link → 201", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const cgId = await provisionBoundCaregiver(baseUrl);
    const res = await fetch(`${baseUrl}/api/admin/resident-caregiver-links`, {
      method: "POST",
      headers: jsonHeaders(ADMIN_HEADERS),
      body: JSON.stringify({ residentId: ELDER_A, caregiverId: cgId, role: "primary" }),
    });
    const body = await res.json();
    assert.equal(res.status, 201);
    assert.equal(body.ok, true);
    assert.equal(body.link.residentId, ELDER_A);
    assert.equal(body.link.caregiverId, cgId);
    assert.equal(body.link.status, "active");
  } finally {
    server.close();
  }
});

// #6
test("重複 active link → 409 link_exists，不建第二筆", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const cgId = await provisionBoundCaregiver(baseUrl);
    const make = () =>
      fetch(`${baseUrl}/api/admin/resident-caregiver-links`, {
        method: "POST",
        headers: jsonHeaders(ADMIN_HEADERS),
        body: JSON.stringify({ residentId: ELDER_A, caregiverId: cgId }),
      });
    const first = await make();
    assert.equal(first.status, 201);
    const second = await make();
    assert.equal(second.status, 409);
    assert.equal((await second.json()).error, "link_exists");
    assert.equal(unifiedPg.state.links.length, 1, "不應新增第二筆 active link");
  } finally {
    server.close();
  }
});

// #7（端到端 scope refresh）
test("建 link → caregiver 看得到 alert；停用 link → 看不到（authorizationService 未改仍成立）", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const cgId = await provisionBoundCaregiver(baseUrl);
    await postNotify(baseUrl, ELDER_A);
    await postNotify(baseUrl, ELDER_Z);

    const linkRes = await (
      await fetch(`${baseUrl}/api/admin/resident-caregiver-links`, {
        method: "POST",
        headers: jsonHeaders(ADMIN_HEADERS),
        body: JSON.stringify({ residentId: ELDER_A, caregiverId: cgId }),
      })
    ).json();
    const linkId = linkRes.link.id;

    // 綁定後 caregiver 只見授權住民 ELDER_A。
    let body = await (
      await fetch(`${baseUrl}/api/care-alerts`, { headers: CG_HEADERS })
    ).json();
    assert.equal(body.alerts.length, 1);
    assert.equal(body.alerts[0].elderId, ELDER_A);

    // 停用 link（DELETE = soft-disable / revoked）。
    const del = await fetch(`${baseUrl}/api/admin/resident-caregiver-links/${linkId}`, {
      method: "DELETE",
      headers: ADMIN_HEADERS,
    });
    assert.equal(del.status, 200);
    assert.equal((await del.json()).link.status, "inactive");

    // 立即看不到（scope refresh）。
    body = await (await fetch(`${baseUrl}/api/care-alerts`, { headers: CG_HEADERS })).json();
    assert.deepEqual(body.alerts, []);
  } finally {
    server.close();
  }
});

// #8
test("inactive caregiver 讀 scoped API → 403（adminAuthContext 停用閘即時生效）", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const cgId = await provisionBoundCaregiver(baseUrl);
    await fetch(`${baseUrl}/api/admin/resident-caregiver-links`, {
      method: "POST",
      headers: jsonHeaders(ADMIN_HEADERS),
      body: JSON.stringify({ residentId: ELDER_A, caregiverId: cgId }),
    });
    // active 時可讀。
    let res = await fetch(`${baseUrl}/api/care-alerts`, { headers: CG_HEADERS });
    assert.equal(res.status, 200);

    // 停用 caregiver。
    const sres = await fetch(`${baseUrl}/api/admin/caregivers/${cgId}/status`, {
      method: "PATCH",
      headers: jsonHeaders(ADMIN_HEADERS),
      body: JSON.stringify({ status: "inactive" }),
    });
    assert.equal(sres.status, 200);

    // 即時失效 → 403。
    res = await fetch(`${baseUrl}/api/care-alerts`, { headers: CG_HEADERS });
    assert.equal(res.status, 403);
  } finally {
    server.close();
  }
});

// #9
test("super_admin 看全部 caregiver / link 清單", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const cgId = await provisionBoundCaregiver(baseUrl);
    await fetch(`${baseUrl}/api/admin/resident-caregiver-links`, {
      method: "POST",
      headers: jsonHeaders(ADMIN_HEADERS),
      body: JSON.stringify({ residentId: ELDER_A, caregiverId: cgId }),
    });
    const cgs = await (
      await fetch(`${baseUrl}/api/admin/caregivers`, { headers: ADMIN_HEADERS })
    ).json();
    assert.equal(cgs.ok, true);
    assert.equal(cgs.caregivers.length, 1);

    const links = await (
      await fetch(`${baseUrl}/api/admin/resident-caregiver-links`, { headers: ADMIN_HEADERS })
    ).json();
    assert.equal(links.ok, true);
    assert.equal(links.links.length, 1);
    assert.equal(links.links[0].status, "active");
  } finally {
    server.close();
  }
});

// #12
test("建立 link 帶不存在 resident → 404 resident_not_found", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const cgId = await provisionBoundCaregiver(baseUrl);
    const res = await fetch(`${baseUrl}/api/admin/resident-caregiver-links`, {
      method: "POST",
      headers: jsonHeaders(ADMIN_HEADERS),
      body: JSON.stringify({ residentId: ELDER_Z, caregiverId: cgId }),
    });
    assert.equal(res.status, 404);
    assert.equal((await res.json()).error, "resident_not_found");
  } finally {
    server.close();
  }
});

test("建立 link 帶不存在 caregiver → 404 caregiver_not_found", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetch(`${baseUrl}/api/admin/resident-caregiver-links`, {
      method: "POST",
      headers: jsonHeaders(ADMIN_HEADERS),
      body: JSON.stringify({ residentId: ELDER_A, caregiverId: "ghost-cg" }),
    });
    assert.equal(res.status, 404);
    assert.equal((await res.json()).error, "caregiver_not_found");
  } finally {
    server.close();
  }
});

test("PATCH caregiver status 非法值 → 400 invalid_status", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const cgId = await provisionBoundCaregiver(baseUrl);
    const res = await fetch(`${baseUrl}/api/admin/caregivers/${cgId}/status`, {
      method: "PATCH",
      headers: jsonHeaders(ADMIN_HEADERS),
      body: JSON.stringify({ status: "deleted" }),
    });
    assert.equal(res.status, 400);
    assert.equal((await res.json()).error, "invalid_status");
  } finally {
    server.close();
  }
});

test("link 路由全部擋 caregiver idToken（403）與無 token（401）", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const forbidden = await fetch(`${baseUrl}/api/admin/resident-caregiver-links`, {
      headers: CG_HEADERS,
    });
    assert.equal(forbidden.status, 403);
    const unauth = await fetch(`${baseUrl}/api/admin/resident-caregiver-links`);
    assert.equal(unauth.status, 401);
  } finally {
    server.close();
  }
});
