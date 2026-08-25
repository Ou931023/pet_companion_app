const assert = require("node:assert/strict");
const { test, afterEach } = require("node:test");

// CR-0043 B2：caregiverProvisioningService 單元測試（mock pg，無真 DB / 真 Firebase）。
// 涵蓋：列出（只 caregiver、安全欄位、不回敏感）/ 建立（email 必填 + 全域唯一）/
//      路線 B pending（firebaseUid=null）/ 更新（綁 firebaseUid、email 改動唯一）/
//      停用（active|inactive、invalid_status）/ not_found / invalid id。

const svc = require("./caregiverProvisioningService");

// 具狀態的 mock pg：以記憶體模擬 users 表，依 SQL 形狀路由。
function makeMockPg(seedUsers = []) {
  let seq = seedUsers.length;
  const users = seedUsers.map((u) => ({ ...u }));
  return {
    users,
    isPostgresAvailable: async () => true,
    query: async (text, params = []) => {
      const sql = text.replace(/\s+/g, " ").trim();

      // email 佔用檢查
      if (/^SELECT id FROM users WHERE LOWER\(email\) = \$1/i.test(sql)) {
        const email = params[0];
        const excludeId = params[1];
        const hit = users.find(
          (u) => (u.email || "").toLowerCase() === email && u.id !== excludeId,
        );
        return { rows: hit ? [{ id: hit.id }] : [] };
      }

      // Firebase UID 佔用檢查
      if (/^SELECT id FROM users WHERE firebase_uid = \$1/i.test(sql)) {
        const firebaseUid = params[0];
        const excludeId = params[1];
        const hit = users.find(
          (u) => u.firebase_uid === firebaseUid && u.id !== excludeId,
        );
        return { rows: hit ? [{ id: hit.id }] : [] };
      }

      // 列出 caregivers
      if (/FROM users WHERE role = 'caregiver'/i.test(sql) && /ORDER BY created_at DESC/i.test(sql)) {
        const rows = users
          .filter((u) => u.role === "caregiver")
          .sort((a, b) => String(b.created_at).localeCompare(String(a.created_at)));
        return { rows: rows.map((u) => ({ ...u })) };
      }

      // INSERT caregiver
      if (/^INSERT INTO users/i.test(sql)) {
        const [email, displayName, firebaseUid] = params;
        const row = {
          id: `cg-${++seq}`,
          email,
          display_name: displayName,
          role: "caregiver",
          status: "active",
          firebase_uid: firebaseUid,
          created_at: new Date(Date.now() + seq).toISOString(),
          updated_at: null,
        };
        users.push(row);
        return { rows: [{ ...row }] };
      }

      // UPDATE caregiver（status 或一般欄位）
      if (/^UPDATE users SET/i.test(sql)) {
        const isStatus = /SET status = \$2/i.test(sql);
        const id = isStatus ? params[0] : params[params.length - 1];
        const row = users.find((u) => u.id === id && u.role === "caregiver");
        if (!row) return { rows: [] };
        if (isStatus) {
          row.status = params[1];
        } else {
          // 依 SET 子句順序套用（與 service 動態組裝順序一致）
          let p = 0;
          if (/display_name = \$/i.test(sql)) row.display_name = params[p++];
          if (/email = \$/i.test(sql)) row.email = params[p++];
          if (/firebase_uid = \$/i.test(sql)) row.firebase_uid = params[p++];
        }
        row.updated_at = new Date().toISOString();
        return { rows: [{ ...row }] };
      }

      return { rows: [] };
    },
  };
}

afterEach(() => svc.setPgForTest(null));

test("listCaregivers 只回 role=caregiver，且只含安全欄位（不回 password_hash/provider_user_id/token）", async () => {
  const pg = makeMockPg([
    {
      id: "cg-1",
      email: "nurse@clinic.org",
      display_name: "護理師A",
      role: "caregiver",
      status: "active",
      firebase_uid: "fb-1",
      created_at: "2026-06-01T00:00:00Z",
      updated_at: null,
      password_hash: "SHOULD_NOT_LEAK",
      provider_user_id: "PUID_SECRET",
    },
    { id: "e-1", email: "elder@x.org", role: "elder", status: "active", created_at: "2026-06-02T00:00:00Z" },
  ]);
  const list = await svc.listCaregivers({ pg });
  assert.equal(list.length, 1);
  const c = list[0];
  assert.equal(c.id, "cg-1");
  assert.equal(c.role, "caregiver");
  assert.equal(c.status, "active");
  assert.equal(c.firebaseUid, "fb-1");
  assert.equal(c.emailMasked, "nu***@clinic.org");
  const blob = JSON.stringify(list);
  for (const s of ["SHOULD_NOT_LEAK", "PUID_SECRET", "password_hash", "provider_user_id"]) {
    assert.ok(!blob.includes(s), `不可外漏：${s}`);
  }
});

test("createCaregiver：email 必填", async () => {
  svc.setPgForTest(makeMockPg());
  const r = await svc.createCaregiver({ displayName: "無email" });
  assert.deepEqual(r, { ok: false, error: "email_required" });
});

test("createCaregiver：成功建立 active caregiver，回安全欄位、emailMasked", async () => {
  const pg = makeMockPg();
  const r = await svc.createCaregiver(
    { email: "New.Nurse@Clinic.org", displayName: "新護理師", firebaseUid: "fb-new" },
    { pg },
  );
  assert.equal(r.ok, true);
  assert.equal(r.caregiver.role, "caregiver");
  assert.equal(r.caregiver.status, "active");
  assert.equal(r.caregiver.firebaseUid, "fb-new");
  // email 正規化為小寫後遮蔽
  assert.equal(r.caregiver.emailMasked, "ne***@clinic.org");
  assert.ok(!("email" in r.caregiver), "不回原始 email 欄位（只 emailMasked）");
});

test("createCaregiver：路線 B pending（firebaseUid 省略 → null）", async () => {
  const pg = makeMockPg();
  const r = await svc.createCaregiver({ email: "pending@clinic.org" }, { pg });
  assert.equal(r.ok, true);
  assert.equal(r.caregiver.firebaseUid, null);
  assert.equal(r.caregiver.status, "active");
});

test("createCaregiver：重複 email → email_exists（全域唯一，含既有 elder email）", async () => {
  const pg = makeMockPg([
    { id: "e-1", email: "dup@x.org", role: "elder", status: "active", created_at: "2026-06-01T00:00:00Z" },
  ]);
  const r = await svc.createCaregiver({ email: "DUP@x.org", displayName: "撞email" }, { pg });
  assert.deepEqual(r, { ok: false, error: "email_exists" });
});

test("createCaregiver：重複 Firebase UID → firebase_uid_exists（全域唯一，含既有 elder）", async () => {
  const pg = makeMockPg([
    { id: "e-1", email: "elder@x.org", role: "elder", status: "active", firebase_uid: "fb-used", created_at: "2026-06-01T00:00:00Z" },
  ]);
  const r = await svc.createCaregiver(
    { email: "new@clinic.org", displayName: "撞 UID", firebaseUid: "fb-used" },
    { pg },
  );
  assert.deepEqual(r, { ok: false, error: "firebase_uid_exists" });
});

test("updateCaregiver：綁定 firebaseUid（路線 B）", async () => {
  const pg = makeMockPg([
    { id: "cg-1", email: "p@x.org", display_name: "pending", role: "caregiver", status: "active", firebase_uid: null, created_at: "2026-06-01T00:00:00Z" },
  ]);
  const r = await svc.updateCaregiver("cg-1", { firebaseUid: "fb-bound" }, { pg });
  assert.equal(r.ok, true);
  assert.equal(r.caregiver.firebaseUid, "fb-bound");
});

test("updateCaregiver：重複 Firebase UID → firebase_uid_exists（排除自身）", async () => {
  const pg = makeMockPg([
    { id: "cg-1", email: "a@x.org", role: "caregiver", status: "active", firebase_uid: null, created_at: "2026-06-01T00:00:00Z" },
    { id: "cg-2", email: "b@x.org", role: "caregiver", status: "active", firebase_uid: "fb-used", created_at: "2026-06-02T00:00:00Z" },
  ]);
  const r = await svc.updateCaregiver("cg-1", { firebaseUid: "fb-used" }, { pg });
  assert.deepEqual(r, { ok: false, error: "firebase_uid_exists" });
});

test("updateCaregiver：email 改動仍須唯一 → email_exists", async () => {
  const pg = makeMockPg([
    { id: "cg-1", email: "a@x.org", role: "caregiver", status: "active", created_at: "2026-06-01T00:00:00Z" },
    { id: "cg-2", email: "b@x.org", role: "caregiver", status: "active", created_at: "2026-06-02T00:00:00Z" },
  ]);
  const r = await svc.updateCaregiver("cg-1", { email: "b@x.org" }, { pg });
  assert.deepEqual(r, { ok: false, error: "email_exists" });
});

test("updateCaregiver：改自己 email 為同值（排除自身）→ 成功", async () => {
  const pg = makeMockPg([
    { id: "cg-1", email: "a@x.org", role: "caregiver", status: "active", created_at: "2026-06-01T00:00:00Z" },
  ]);
  const r = await svc.updateCaregiver("cg-1", { email: "a@x.org", displayName: "改名" }, { pg });
  assert.equal(r.ok, true);
  assert.equal(r.caregiver.displayName, "改名");
});

test("updateCaregiver：無任何欄位 → invalid_payload", async () => {
  const pg = makeMockPg([
    { id: "cg-1", email: "a@x.org", role: "caregiver", status: "active", created_at: "2026-06-01T00:00:00Z" },
  ]);
  const r = await svc.updateCaregiver("cg-1", {}, { pg });
  assert.deepEqual(r, { ok: false, error: "invalid_payload" });
});

test("updateCaregiver：不存在 / 非 caregiver → not_found", async () => {
  const pg = makeMockPg([]);
  const r = await svc.updateCaregiver("nope", { displayName: "x" }, { pg });
  assert.deepEqual(r, { ok: false, error: "not_found" });
});

test("setCaregiverStatus：停用（inactive）", async () => {
  const pg = makeMockPg([
    { id: "cg-1", email: "a@x.org", role: "caregiver", status: "active", created_at: "2026-06-01T00:00:00Z" },
  ]);
  const r = await svc.setCaregiverStatus("cg-1", "inactive", { pg });
  assert.equal(r.ok, true);
  assert.equal(r.caregiver.status, "inactive");
});

test("setCaregiverStatus：非法狀態 → invalid_status", async () => {
  const pg = makeMockPg([
    { id: "cg-1", email: "a@x.org", role: "caregiver", status: "active", created_at: "2026-06-01T00:00:00Z" },
  ]);
  const r = await svc.setCaregiverStatus("cg-1", "deleted", { pg });
  assert.deepEqual(r, { ok: false, error: "invalid_status" });
});

test("setCaregiverStatus：不存在 → not_found", async () => {
  const pg = makeMockPg([]);
  const r = await svc.setCaregiverStatus("ghost", "inactive", { pg });
  assert.deepEqual(r, { ok: false, error: "not_found" });
});
