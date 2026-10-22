const assert = require("node:assert/strict");
const { test, after, mock } = require("node:test");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

// require server 前把 runtime data 導到 temp，絕不污染正式 data/*.json。
process.env.CARE_ALERTS_DATA_FILE = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), "care_alerts_demo_flow_")),
  "care_alerts.json",
);
process.env.NODE_ENV = "test";
// 預設關閉 cooldown，讓基本觸發測試彼此獨立；需要時於個別測試啟用。
delete process.env.CARE_ALERT_TELEGRAM_COOLDOWN_ENABLED;
delete process.env.CARE_ALERT_TELEGRAM_COOLDOWN_MS;

// CR-0039：Care Alert 讀取 / 狀態變更路由掛了 requireAdmin。
process.env.ADMIN_API_TOKEN = "test-admin-token";

// Install before server (and its DB-first services) loads. Never inspect inherited
// DATABASE_URL: both persistence and audit use explicit offline seams instead.
let poolIoAttempts = 0;
const poolGuard = mock.method(require("pg"), "Pool", function () {
  // Legacy db/pool.js constructs a pool eagerly. Replace construction entirely;
  // even accidental calls through that path can never reach the real driver.
  const rejectIo = () => {
    poolIoAttempts += 1;
    throw new Error("PostgreSQL IO forbidden in care-alert demo tests");
  };
  return { query: rejectIo, connect: rejectIo, on() { return this; }, async end() {} };
});
// Other routes in this file also write status audit logs through defaultPg.
// Keep their availability probes offline before destructured imports are loaded.
const availabilityGuard = mock.method(require("../db/postgres"), "isPostgresAvailable", async () => false);
const careAlertStore = require("./careAlertStoreService");
const notificationLog = require("./notificationLogService");
const pgCalls = { store: 0, audit: 0, query: 0 };
function offlinePg(kind) {
  return {
    async isPostgresAvailable() { pgCalls[kind] += 1; return false; },
    async query() {
      pgCalls.query += 1;
      throw new Error("SQL forbidden in care-alert demo tests");
    },
  };
}
careAlertStore.setPgForTest(offlinePg("store"));
notificationLog.setPgForTest(offlinePg("audit"));
after(() => {
  careAlertStore.setPgForTest(null);
  notificationLog.setPgForTest(null);
  availabilityGuard.mock.restore();
  poolGuard.mock.restore();
  assert.equal(poolIoAttempts, 0, "no PG query or connection may be attempted");
  assert.equal(pgCalls.query, 0, "no SQL may be issued");
});

const app = require("../server");
const { resetCooldown } = require("./careAlertCooldown");

// require server 會載入 .env（可能含真 Telegram token）；清掉以確保不真的外送。
delete process.env.TELEGRAM_BOT_TOKEN;
delete process.env.TELEGRAM_CARE_CHAT_ID;

// CR-0039：admin 授權 header（讀取 / 狀態變更路由）。
const ADMIN_HEADERS = { Authorization: "Bearer test-admin-token" };

// CR-0045 B2：/notify 掛 requireResidentCaller；安裝 resident-caller stub 並帶 token。
const { installResidentCallerStub } = require("./auth/residentCallerContext.testsupport");
installResidentCallerStub({
  "res-token": {
    uid: "fb-res",
    userId: "user-res",
    elderId: "11111111-1111-1111-1111-111111111111",
  },
});

function startServer() {
  return new Promise((resolve) => {
    const server = app.listen(0, "127.0.0.1", () => resolve(server));
  });
}

function baseBody(over) {
  return Object.assign(
    {
      riskLevel: "urgent",
      riskLevelLabel: "緊急",
      category: "other",
      categoryLabel: "其他",
      triggerSummary: "對話中偵測到需要關心的狀況",
      transcriptSnippet: "我最近好痛苦撐不下去",
      createdAt: "2026-05-31T10:00:00.000",
      source: "companion_analysis",
    },
    over || {},
  );
}

// 攔截對 Telegram 的外連並計數；其餘 fetch（client→本機 server）照常走。
function installTelegramSpy() {
  const realFetch = global.fetch;
  const calls = [];
  process.env.TELEGRAM_BOT_TOKEN = "test-token";
  process.env.TELEGRAM_CARE_CHAT_ID = "123456";
  global.fetch = async (url, options) => {
    if (typeof url === "string" && url.includes("api.telegram.org")) {
      calls.push(JSON.parse(options.body));
      return { ok: true, status: 200, json: async () => ({ ok: true }) };
    }
    return realFetch(url, options);
  };
  return {
    calls,
    restore() {
      global.fetch = realFetch;
      delete process.env.TELEGRAM_BOT_TOKEN;
      delete process.env.TELEGRAM_CARE_CHAT_ID;
    },
  };
}

async function postNotify(baseUrl, body) {
  const res = await fetch(`${baseUrl}/api/care-alerts/notify`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: "Bearer res-token" },
    body: JSON.stringify(body),
  });
  return { status: res.status, body: await res.json() };
}

test("explicit Telegram rejection permits retry; only success starts cooldown", async (t) => {
  const envKeys = [
    "CARE_ALERTS_DATA_FILE", "CARE_ALERT_TELEGRAM_COOLDOWN_ENABLED",
    "CARE_ALERT_TELEGRAM_COOLDOWN_MS", "TELEGRAM_BOT_TOKEN", "TELEGRAM_CARE_CHAT_ID",
  ];
  const previousEnv = Object.fromEntries(envKeys.map((key) => [key, process.env[key]]));
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "care_alert_retry_"));
  let server;
  const realFetch = global.fetch;
  const calls = [];
  const blocked = [];
  const pgBefore = { ...pgCalls };
  resetCooldown();
  try {
    process.env.CARE_ALERTS_DATA_FILE = path.join(tempDir, "alerts.json");
    process.env.CARE_ALERT_TELEGRAM_COOLDOWN_ENABLED = "true";
    process.env.CARE_ALERT_TELEGRAM_COOLDOWN_MS = "60000";
    process.env.TELEGRAM_BOT_TOKEN = "test-token";
    process.env.TELEGRAM_CARE_CHAT_ID = "123456";
    // Fixed time makes the cooldown assertion independent of machine speed.
    t.mock.method(Date, "now", () => 1800000000000);
    server = await startServer();
    const base = `http://127.0.0.1:${server.address().port}`;
    t.mock.method(global, "fetch", async (url, options) => {
      if (url === "https://api.telegram.org/bottest-token/sendMessage") {
        calls.push(JSON.parse(options.body));
        // A definite HTTP rejection, not a timeout or unknown delivery outcome.
        return calls.length === 1
          ? { ok: false, status: 400 }
          : { ok: true, status: 200 };
      }
      if (url === `${base}/api/care-alerts/notify`) return realFetch(url, options);
      blocked.push(String(url));
      throw new Error("Unexpected network request blocked by test");
    });
    const body = baseBody({ riskLevel: "urgent", source: "explicit_rejection_retry" });
    const first = await postNotify(base, body);
    assert.equal(first.status, 200);
    assert.equal(first.body.success, false);
    assert.equal(first.body.error, "telegram_send_failed");
    assert.equal(first.body.status, 400);
    assert.equal(calls.length, 1);

    const retry = await postNotify(base, body);
    assert.equal(retry.status, 200);
    assert.equal(retry.body.success, true);
    assert.equal(calls.length, 2, "explicit rejection must not consume cooldown");
    assert.deepEqual(calls[1], calls[0]);

    const third = await postNotify(base, body);
    assert.equal(third.status, 200);
    assert.equal(third.body.success, true);
    assert.equal(third.body.telegram, "skipped_cooldown");
    assert.equal(calls.length, 2, "successful retry must start cooldown");
    assert.deepEqual(blocked, []);
    assert.equal(pgCalls.store - pgBefore.store, 3, "all three requests use offline persistence");
    assert.equal(pgCalls.audit - pgBefore.audit, 3, "all three outcomes use offline audit");
    assert.equal(pgCalls.query, 0);
    assert.equal(poolIoAttempts, 0);
  } finally {
    if (server) await new Promise((resolve) => server.close(resolve));
    t.mock.restoreAll();
    resetCooldown();
    for (const key of envKeys) {
      if (previousEnv[key] === undefined) delete process.env[key];
      else process.env[key] = previousEnv[key];
    }
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
});

test("#1 high 風險會觸發 Telegram 推播（訊息含 triggerSummary 與四級 label）", async () => {
  resetCooldown();
  const spy = installTelegramSpy();
  const server = await startServer();
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    const r = await postNotify(
      base,
      baseBody({
        riskLevel: "high",
        riskLevelLabel: "需通知",
        triggerSummary: "長者多次提到睡不好且情緒低落，建議家人今天主動關心。",
      }),
    );
    assert.equal(r.status, 200);
    assert.equal(r.body.success, true);
    assert.equal(spy.calls.length, 1, "high 應推一次 Telegram");
    assert.ok(spy.calls[0].text.includes("需通知"));
    assert.ok(spy.calls[0].text.includes("長者多次提到睡不好"));
  } finally {
    server.close();
    spy.restore();
  }
});

test("#2 urgent 風險會觸發 Telegram 推播", async () => {
  resetCooldown();
  const spy = installTelegramSpy();
  const server = await startServer();
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    const r = await postNotify(base, baseBody({ riskLevel: "urgent" }));
    assert.equal(r.body.success, true);
    assert.equal(spy.calls.length, 1, "urgent 應推一次 Telegram");
    assert.ok(spy.calls[0].text.includes("緊急"));
  } finally {
    server.close();
    spy.restore();
  }
});

test("#3 medium 風險不觸發 Telegram，但仍持久化供 caregiver_web 查看", async () => {
  resetCooldown();
  const spy = installTelegramSpy();
  const server = await startServer();
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    const r = await postNotify(
      base,
      baseBody({
        riskLevel: "medium",
        riskLevelLabel: "持續觀察",
        transcriptSnippet: "最近都睡不好",
      }),
    );
    assert.equal(r.status, 200);
    assert.equal(r.body.success, true);
    assert.equal(r.body.telegram, "skipped_low_risk");
    assert.equal(spy.calls.length, 0, "medium 不應推 Telegram");

    const list = await fetch(`${base}/api/care-alerts`, {
      headers: ADMIN_HEADERS,
    }).then((x) => x.json());
    assert.ok(
      list.alerts.some((a) => a.riskLevel === "medium"),
      "medium alert 仍應存入 store",
    );
  } finally {
    server.close();
    spy.restore();
  }
});

test("low 風險同樣不觸發 Telegram", async () => {
  resetCooldown();
  const spy = installTelegramSpy();
  const server = await startServer();
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    const r = await postNotify(
      base,
      baseBody({ riskLevel: "low", riskLevelLabel: "一般", transcriptSnippet: "今天去散步" }),
    );
    assert.equal(r.body.success, true);
    assert.equal(r.body.telegram, "skipped_low_risk");
    assert.equal(spy.calls.length, 0);
  } finally {
    server.close();
    spy.restore();
  }
});

test("#6 alert status 可從 new → acknowledged → resolved", async () => {
  resetCooldown();
  const spy = installTelegramSpy();
  const server = await startServer();
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    await postNotify(base, baseBody({ riskLevel: "urgent" }));
    const list = await fetch(`${base}/api/care-alerts?limit=1`, {
      headers: ADMIN_HEADERS,
    }).then((x) => x.json());
    const id = list.alerts[0].id;
    assert.equal(list.alerts[0].status, "new");

    const ack = await fetch(`${base}/api/care-alerts/${id}/status`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json", ...ADMIN_HEADERS },
      body: JSON.stringify({ status: "acknowledged" }),
    }).then((x) => x.json());
    assert.equal(ack.success, true);
    assert.equal(ack.alert.status, "acknowledged");
    assert.ok(ack.alert.acknowledgedAt);

    const resolved = await fetch(`${base}/api/care-alerts/${id}/status`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json", ...ADMIN_HEADERS },
      body: JSON.stringify({ status: "resolved" }),
    }).then((x) => x.json());
    assert.equal(resolved.success, true);
    assert.equal(resolved.alert.status, "resolved");
    assert.ok(resolved.alert.resolvedAt);
  } finally {
    server.close();
    spy.restore();
  }
});

test("#4(整合) cooldown 啟用時，冷卻期內重複 urgent 不重複推播", async () => {
  resetCooldown();
  process.env.CARE_ALERT_TELEGRAM_COOLDOWN_ENABLED = "true";
  process.env.CARE_ALERT_TELEGRAM_COOLDOWN_MS = "60000";
  const spy = installTelegramSpy();
  const server = await startServer();
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    const first = await postNotify(base, baseBody({ riskLevel: "urgent", source: "cooldown_demo" }));
    const second = await postNotify(base, baseBody({ riskLevel: "urgent", source: "cooldown_demo" }));
    assert.equal(first.body.success, true);
    assert.equal(spy.calls.length, 1, "第一次 urgent 應推播");
    assert.equal(second.body.success, true);
    assert.equal(second.body.telegram, "skipped_cooldown");
    assert.equal(spy.calls.length, 1, "冷卻期內第二次不應再推");
  } finally {
    server.close();
    spy.restore();
    delete process.env.CARE_ALERT_TELEGRAM_COOLDOWN_ENABLED;
    delete process.env.CARE_ALERT_TELEGRAM_COOLDOWN_MS;
    resetCooldown();
  }
});
