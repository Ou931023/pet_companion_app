const assert = require("node:assert/strict");
const { test } = require("node:test");

const { logAudit, normalizeMetadata } = require("./auditLogService");

function makeMockPg({ available = true, throwOnQuery, throwOnAvailable } = {}) {
  const calls = [];
  return {
    calls,
    isPostgresAvailable: async () => {
      if (throwOnAvailable) throw throwOnAvailable;
      return available;
    },
    query: async (text, params) => {
      calls.push({ text, params });
      if (throwOnQuery) throw throwOnQuery;
      return { rows: [] };
    },
  };
}

test("logAudit：DB 可用時 INSERT 欄位映射正確、metadata 序列化為 JSON", async () => {
  const pg = makeMockPg({ available: true });
  const result = await logAudit(
    {
      actorType: "elder",
      actorId: "user-123",
      action: "account_delete",
      targetType: "user",
      targetId: "user-123",
      outcome: "success",
      metadata: { user: 1, elder: 1, memories: 3, careAlerts: 2 },
    },
    { pg },
  );
  assert.deepEqual(result, { success: true });
  assert.equal(pg.calls.length, 1);
  const { text, params } = pg.calls[0];
  assert.match(text, /INSERT INTO audit_logs/);
  assert.equal(params[0], "elder"); // actor_type
  assert.equal(params[1], "user-123"); // actor_id
  assert.equal(params[2], "account_delete"); // action
  assert.equal(params[3], "user"); // target_type
  assert.equal(params[4], "user-123"); // target_id
  assert.equal(params[5], "success"); // outcome
  assert.equal(params[6], JSON.stringify({ user: 1, elder: 1, memories: 3, careAlerts: 2 }));
});

test("logAudit：care alert 狀態變更 metadata 僅 toStatus", async () => {
  const pg = makeMockPg({ available: true });
  await logAudit(
    {
      actorType: "caregiver",
      actorId: null,
      action: "care_alert_status_change",
      targetType: "care_alert",
      targetId: "alert-1",
      outcome: "success",
      metadata: { toStatus: "resolved" },
    },
    { pg },
  );
  const { params } = pg.calls[0];
  assert.equal(params[1], null); // actor_id nullable
  assert.equal(params[2], "care_alert_status_change");
  assert.equal(params[6], JSON.stringify({ toStatus: "resolved" }));
});

test("logAudit：metadata 為 null / 非物件 → 寫入 null（不丟例外）", async () => {
  const pg = makeMockPg({ available: true });
  await logAudit({ action: "consent_record" }, { pg });
  assert.equal(pg.calls[0].params[6], null);

  await logAudit({ action: "consent_record", metadata: "raw text" }, { pg });
  assert.equal(pg.calls[1].params[6], null); // 字串 metadata 被拒 → null
});

test("logAudit：SQL 與參數不含 PII 欄位（email / ip / token / 原文）", async () => {
  const pg = makeMockPg({ available: true });
  await logAudit(
    {
      actorType: "elder",
      actorId: "uid-abc",
      action: "consent_record",
      targetType: "consent_record",
      targetId: "rec-1",
      outcome: "success",
      metadata: { consentType: "privacy_terms", consentVersion: "1.0.0", action: "granted" },
    },
    { pg },
  );
  const { text, params } = pg.calls[0];
  assert.doesNotMatch(text, /email|\bip\b|token|transcript|user_agent/i);
  const serialized = JSON.stringify(params);
  // metadata 僅結構化欄位，無敏感值
  assert.match(serialized, /privacy_terms/); // 確認結構化欄位有寫入
  assert.doesNotMatch(serialized, /@/); // 無 email
});

test("logAudit：DB 不可用 → 略過寫入、回 skipped、不打 query", async () => {
  const pg = makeMockPg({ available: false });
  const result = await logAudit({ action: "account_delete" }, { pg });
  assert.deepEqual(result, { success: false, skipped: true });
  assert.equal(pg.calls.length, 0);
});

test("logAudit：缺 isPostgresAvailable 的 pg → 視為不可用、略過", async () => {
  const pg = { query: async () => ({ rows: [] }) };
  const result = await logAudit({ action: "account_delete" }, { pg });
  assert.deepEqual(result, { success: false, skipped: true });
});

test("logAudit：寫入例外 → 回 {success:false}，絕不丟例外", async () => {
  const pg = makeMockPg({ available: true, throwOnQuery: new Error("db down") });
  const result = await logAudit({ action: "account_delete" }, { pg });
  assert.deepEqual(result, { success: false });
});

test("logAudit：isPostgresAvailable 拋例外 → 視為不可用、不丟例外", async () => {
  const pg = makeMockPg({ throwOnAvailable: new Error("conn refused") });
  const result = await logAudit({ action: "account_delete" }, { pg });
  assert.deepEqual(result, { success: false, skipped: true });
});

test("normalizeMetadata：plain object 往返、陣列 / 字串 / null → null", () => {
  assert.deepEqual(normalizeMetadata({ a: 1 }), { a: 1 });
  assert.equal(normalizeMetadata([1, 2]), null);
  assert.equal(normalizeMetadata("x"), null);
  assert.equal(normalizeMetadata(null), null);
  assert.equal(normalizeMetadata(undefined), null);
});
