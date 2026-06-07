const assert = require("node:assert/strict");
const { test } = require("node:test");

const { logNotification, VALID_OUTCOMES } = require("./notificationLogService");

// mock pg：available 控制 isPostgresAvailable；throwOnQuery 模擬寫入例外；
// throwOnAvailable 模擬可用性查詢自身拋例外。記錄所有 query 呼叫供斷言。
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

test("logNotification：DB 可用時 INSERT 欄位映射正確（結構化白名單）", async () => {
  const pg = makeMockPg({ available: true });
  const result = await logNotification(
    {
      alertId: "11111111-1111-1111-1111-111111111111",
      elderId: "22222222-2222-2222-2222-222222222222",
      channel: "telegram",
      riskLevel: "urgent",
      outcome: "sent",
    },
    { pg },
  );
  assert.deepEqual(result, { success: true });
  assert.equal(pg.calls.length, 1);
  const { text, params } = pg.calls[0];
  assert.match(text, /INSERT INTO notification_logs/);
  assert.equal(params[0], "11111111-1111-1111-1111-111111111111"); // alert_id
  assert.equal(params[1], "22222222-2222-2222-2222-222222222222"); // elder_id
  assert.equal(params[2], "telegram"); // channel
  assert.equal(params[3], "urgent"); // risk_level
  assert.equal(params[4], "sent"); // outcome
  assert.equal(params[5], null); // error_code
  assert.equal(params[6], null); // http_status
});

test("logNotification：failed 帶 errorCode / httpStatus", async () => {
  const pg = makeMockPg({ available: true });
  await logNotification(
    {
      alertId: null,
      elderId: null,
      riskLevel: "high",
      outcome: "failed",
      errorCode: "telegram_send_failed",
      httpStatus: 429,
    },
    { pg },
  );
  const { params } = pg.calls[0];
  assert.equal(params[2], "telegram"); // channel 預設
  assert.equal(params[4], "failed");
  assert.equal(params[5], "telegram_send_failed");
  assert.equal(params[6], 429);
});

test("logNotification：channel 預設 telegram、httpStatus 非數字 → null", async () => {
  const pg = makeMockPg({ available: true });
  await logNotification(
    { outcome: "skipped_cooldown", httpStatus: "not-a-number" },
    { pg },
  );
  const { params } = pg.calls[0];
  assert.equal(params[2], "telegram");
  assert.equal(params[6], null);
});

test("logNotification：只寫白名單欄位——誤帶 transcriptSnippet / chatId / token 不外洩", async () => {
  const pg = makeMockPg({ available: true });
  await logNotification(
    {
      alertId: "aa",
      elderId: "bb",
      riskLevel: "high",
      outcome: "sent",
      // 以下敏感欄位即使誤帶也絕不可進 DB：
      transcriptSnippet: "我昨天晚上都睡不好",
      chatId: "123456789",
      botToken: "secret-token",
      url: "https://api.telegram.org/botXXX/sendMessage",
      email: "elder@example.com",
      ip: "203.0.113.7",
    },
    { pg },
  );
  const { text, params } = pg.calls[0];
  // SQL 文字不含任何敏感欄位名
  assert.doesNotMatch(text, /transcript|snippet|chat_id|token|url|email|ip\b/i);
  // 參數陣列僅 7 個結構化值，且不含任何敏感字串
  assert.equal(params.length, 7);
  const serialized = JSON.stringify(params);
  assert.doesNotMatch(serialized, /睡不好/);
  assert.doesNotMatch(serialized, /123456789/);
  assert.doesNotMatch(serialized, /secret-token/);
  assert.doesNotMatch(serialized, /telegram\.org/);
  assert.doesNotMatch(serialized, /elder@example\.com/);
  assert.doesNotMatch(serialized, /203\.0\.113\.7/);
});

test("logNotification：DB 不可用 → 略過寫入、回 skipped、不丟例外、不打 query", async () => {
  const pg = makeMockPg({ available: false });
  const result = await logNotification({ outcome: "sent" }, { pg });
  assert.deepEqual(result, { success: false, skipped: true });
  assert.equal(pg.calls.length, 0);
});

test("logNotification：缺 isPostgresAvailable 的 pg → 視為不可用、略過", async () => {
  const pg = { query: async () => ({ rows: [] }) };
  const result = await logNotification({ outcome: "sent" }, { pg });
  assert.deepEqual(result, { success: false, skipped: true });
});

test("logNotification：寫入例外 → 回 {success:false}，絕不丟例外", async () => {
  const pg = makeMockPg({ available: true, throwOnQuery: new Error("db down") });
  const result = await logNotification({ outcome: "sent" }, { pg });
  assert.deepEqual(result, { success: false });
});

test("logNotification：isPostgresAvailable 自身拋例外 → 視為不可用、不丟例外", async () => {
  const pg = makeMockPg({ throwOnAvailable: new Error("conn refused") });
  const result = await logNotification({ outcome: "sent" }, { pg });
  assert.deepEqual(result, { success: false, skipped: true });
});

test("VALID_OUTCOMES 涵蓋三結局四值", () => {
  assert.ok(VALID_OUTCOMES.has("sent"));
  assert.ok(VALID_OUTCOMES.has("failed"));
  assert.ok(VALID_OUTCOMES.has("skipped_low_risk"));
  assert.ok(VALID_OUTCOMES.has("skipped_cooldown"));
});
