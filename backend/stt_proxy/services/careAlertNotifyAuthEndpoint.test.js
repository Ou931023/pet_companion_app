const assert = require("node:assert/strict");
const { test, beforeEach, afterEach } = require("node:test");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

// CR-0045 B2：/api/care-alerts/notify caller 驗證 + server 權威推導 elderId 的 HTTP 層測試
// （任務 §7.1 #1–#12）。比照 careAlertAuthScopeEndpoint.test.js：mock pg + stub firebaseAdmin +
// Telegram spy。不接真 DB / 真 Firebase。
//
// 紅線驗證：未授權請求「不建立 Care Alert」且「不觸發 Telegram」；授權 high/urgent 仍通知；
// cooldown 仍生效；low 仍不推；response 不含 token / sensitive。

process.env.CARE_ALERTS_DATA_FILE = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), "care_alerts_notify_auth_")),
  "care_alerts.json",
);
process.env.NODE_ENV = "test";
process.env.ADMIN_API_TOKEN = "test-admin-token";

const app = require("../server");
const { installResidentCallerStub } = require("./auth/residentCallerContext.testsupport");
const { resetCooldown } = require("./careAlertCooldown");

// require server 會載入 .env（可能含真 Telegram token）；清掉以確保絕不真的外送。
delete process.env.TELEGRAM_BOT_TOKEN;
delete process.env.TELEGRAM_CARE_CHAT_ID;

const ADMIN_HEADERS = { Authorization: "Bearer test-admin-token" };
const ELDER_A = "11111111-1111-1111-1111-111111111111";
const ELDER_B = "22222222-2222-2222-2222-222222222222";

// resident A / B：各持自己的 idToken，token → uid → users.elder_id。
const RES_A = { Authorization: "Bearer res-a-token" };
const RES_B = { Authorization: "Bearer res-b-token" };

let restoreResident = null;

beforeEach(() => {
  process.env.CARE_ALERTS_DATA_FILE = path.join(
    fs.mkdtempSync(path.join(os.tmpdir(), "care_alerts_notify_auth_")),
    "care_alerts.json",
  );
  resetCooldown();
  restoreResident = installResidentCallerStub({
    "res-a-token": { uid: "fb-res-a", userId: "user-a", elderId: ELDER_A },
    "res-b-token": { uid: "fb-res-b", userId: "user-b", elderId: ELDER_B },
  });
});

afterEach(() => {
  if (restoreResident) restoreResident();
  restoreResident = null;
});

function startServer() {
  return new Promise((resolve) => {
    const server = app.listen(0, "127.0.0.1", () => resolve(server));
  });
}

const baseBody = {
  riskLevel: "urgent",
  riskLevelLabel: "緊急",
  category: "other",
  categoryLabel: "其他",
  triggerSummary: "對話中偵測到需要關心的狀況",
  transcriptSnippet: "我昨天晚上都睡不好",
  createdAt: "2026-05-29T10:00:00.000Z",
  source: "companion_analysis",
};

function postNotify(baseUrl, headers, overrides = {}) {
  return fetch(`${baseUrl}/api/care-alerts/notify`, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: JSON.stringify({ ...baseBody, ...overrides }),
  });
}

// 攔截 Telegram 外連並計數（其餘 fetch 照常）。
function installTelegramSpy() {
  const realFetch = global.fetch;
  const calls = [];
  process.env.TELEGRAM_BOT_TOKEN = "test-token";
  process.env.TELEGRAM_CARE_CHAT_ID = "123456";
  global.fetch = async (url, options) => {
    if (typeof url === "string" && url.includes("api.telegram.org")) {
      calls.push(options && options.body);
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

async function listAlerts(baseUrl) {
  const res = await fetch(`${baseUrl}/api/care-alerts`, { headers: ADMIN_HEADERS });
  return (await res.json()).alerts || [];
}

// #1 無 Authorization → 401
test("#1 無 Authorization header → 401（不建立 alert）", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await postNotify(baseUrl, {});
    assert.equal(res.status, 401);
    assert.deepEqual(await listAlerts(baseUrl), []);
  } finally {
    server.close();
  }
});

// #2 invalid token → 401
test("#2 無效 idToken → 401（不建立 alert）", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await postNotify(baseUrl, { Authorization: "Bearer forged-token" });
    assert.equal(res.status, 401);
    assert.deepEqual(await listAlerts(baseUrl), []);
  } finally {
    server.close();
  }
});

// #3 valid token 無 users row（test/mock 語意：dev seam 由 uid 推導 → 200）
test("#3 valid token 無 users row（dev mock 語意）→ 200 由 uid 推導 scoping", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    // 安裝一個只 verify 出 uid、但 pg 無對應 row 的 caller。
    if (restoreResident) restoreResident();
    const residentCaller = require("./auth/residentCallerContext");
    residentCaller.setFirebaseAdminForTest({
      isConfigured: () => true,
      verifyIdToken: async (t) => (t === "no-row-token" ? { uid: "fb-no-row" } : null),
    });
    residentCaller.setPgForTest({
      isPostgresAvailable: async () => true,
      query: async () => ({ rows: [] }),
    });
    restoreResident = () => {
      residentCaller.setFirebaseAdminForTest(null);
      residentCaller.setPgForTest(null);
    };

    const res = await postNotify(baseUrl, { Authorization: "Bearer no-row-token" });
    assert.equal(res.status, 200);
    const alerts = await listAlerts(baseUrl);
    assert.equal(alerts.length, 1);
    assert.equal(alerts[0].elderId, "fb-no-row"); // dev seam：uid 當 scoping elderId
  } finally {
    server.close();
  }
});

// #4 valid resident 建自己的 alert → 200 + 成功契約不變 + elderId 蓋為 token 推導
test("#4 valid resident 建自己的 alert → 200（成功契約不變，elderId=token 推導）", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    // body 不送 elderId，server 填 token 推導。
    const res = await postNotify(baseUrl, RES_A);
    const body = await res.json();
    assert.equal(res.status, 200);
    // Telegram 未設定 → telegram_not_configured（成功狀態碼與形狀不變）。
    assert.equal(body.success, false);
    assert.equal(body.error, "telegram_not_configured");
    const alerts = await listAlerts(baseUrl);
    assert.equal(alerts.length, 1);
    assert.equal(alerts[0].elderId, ELDER_A);
  } finally {
    server.close();
  }
});

// #5 resident A 帶 resident B elderId → 403 forbidden_resident（不建立 alert）
test("#5 resident A 偽造 resident B elderId → 403 forbidden_resident（不建立 alert）", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await postNotify(baseUrl, RES_A, { elderId: ELDER_B });
    const body = await res.json();
    assert.equal(res.status, 403);
    assert.deepEqual(body, { success: false, error: "forbidden_resident" });
    assert.deepEqual(await listAlerts(baseUrl), []);
  } finally {
    server.close();
  }
});

// #5b resident 帶自己的 elderId（相符）→ 200 放行
test("#5b resident 帶自己的 elderId（相符）→ 200 放行", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await postNotify(baseUrl, RES_A, { elderId: ELDER_A });
    assert.equal(res.status, 200);
    const alerts = await listAlerts(baseUrl);
    assert.equal(alerts.length, 1);
    assert.equal(alerts[0].elderId, ELDER_A);
  } finally {
    server.close();
  }
});

// #6 未授權請求不建立 Care Alert（綜合 #1/#2/#5 已覆蓋；此處再確認 spy 視角）
test("#6 未授權請求不觸發 Telegram（high/urgent 但無 auth → 0 次外連）", async () => {
  const spy = installTelegramSpy();
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await postNotify(baseUrl, {}); // 無 auth
    assert.equal(res.status, 401);
    assert.equal(spy.calls.length, 0, "未授權不可觸發 Telegram");
    assert.deepEqual(await listAlerts(baseUrl), []);
  } finally {
    spy.restore();
    server.close();
  }
});

// #7 forged token 也不觸發 Telegram
test("#7 偽造 token 不觸發 Telegram（0 次外連）", async () => {
  const spy = installTelegramSpy();
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await postNotify(baseUrl, { Authorization: "Bearer forged" });
    assert.equal(res.status, 401);
    assert.equal(spy.calls.length, 0);
  } finally {
    spy.restore();
    server.close();
  }
});

// #8 high/urgent 授權請求仍觸發通知
test("#8 high/urgent 授權請求仍觸發 Telegram（1 次外連）", async () => {
  const spy = installTelegramSpy();
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await postNotify(baseUrl, RES_A, { riskLevel: "urgent" });
    const body = await res.json();
    assert.equal(res.status, 200);
    assert.deepEqual(body, { success: true });
    assert.equal(spy.calls.length, 1, "授權 high/urgent 應觸發一次通知");
  } finally {
    spy.restore();
    server.close();
  }
});

// #9 cooldown 仍生效（同 source+riskLevel 第二次略過）
test("#9 cooldown 仍生效（授權第二次同類 → skipped_cooldown，0 次新外連）", async () => {
  const originalEnabled = process.env.CARE_ALERT_TELEGRAM_COOLDOWN_ENABLED;
  process.env.CARE_ALERT_TELEGRAM_COOLDOWN_ENABLED = "true";
  const spy = installTelegramSpy();
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const first = await postNotify(baseUrl, RES_A, { source: "cooldown_demo" });
    assert.equal((await first.json()).success, true);
    const second = await postNotify(baseUrl, RES_A, { source: "cooldown_demo" });
    const secondBody = await second.json();
    assert.equal(second.status, 200);
    assert.equal(secondBody.telegram, "skipped_cooldown");
    assert.equal(spy.calls.length, 1, "cooldown 期內只送一次");
  } finally {
    spy.restore();
    if (originalEnabled === undefined) delete process.env.CARE_ALERT_TELEGRAM_COOLDOWN_ENABLED;
    else process.env.CARE_ALERT_TELEGRAM_COOLDOWN_ENABLED = originalEnabled;
    server.close();
  }
});

// #10 low risk 授權仍依原規則不推播
test("#10 low risk 授權 → skipped_low_risk（不推 Telegram，但仍持久化）", async () => {
  const spy = installTelegramSpy();
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await postNotify(baseUrl, RES_A, { riskLevel: "low", riskLevelLabel: "一般" });
    const body = await res.json();
    assert.equal(res.status, 200);
    assert.deepEqual(body, { success: true, telegram: "skipped_low_risk" });
    assert.equal(spy.calls.length, 0);
    const alerts = await listAlerts(baseUrl);
    assert.equal(alerts.length, 1);
    assert.equal(alerts[0].elderId, ELDER_A);
  } finally {
    spy.restore();
    server.close();
  }
});

// #11 production 不接受 fake token（未 configured + production → 401）
test("#11 production 不接受 fake token（未 configured firebase → 401，不建立 alert）", async () => {
  const originalNodeEnv = process.env.NODE_ENV;
  const originalAppEnv = process.env.APP_ENV;
  const originalAllowMock = process.env.AUTH_ALLOW_MOCK;
  if (restoreResident) restoreResident();
  const residentCaller = require("./auth/residentCallerContext");
  // 未 configured（無真 Firebase 憑證），verify 仍能解 uid（但 production 應在此之前就拒）。
  residentCaller.setFirebaseAdminForTest({
    isConfigured: () => false,
    verifyIdToken: async () => ({ uid: "fb-fake" }),
  });
  residentCaller.setPgForTest({
    isPostgresAvailable: async () => true,
    query: async () => ({ rows: [{ id: "u", role: "resident", status: "active", elder_id: ELDER_A }] }),
  });
  const server = await startServer();
  try {
    process.env.NODE_ENV = "production";
    process.env.APP_ENV = "production";
    delete process.env.AUTH_ALLOW_MOCK;
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await postNotify(baseUrl, { Authorization: "Bearer fake-prod-token" });
    assert.equal(res.status, 401);
    // alert 不應建立（listAlerts 需 NODE_ENV 不影響；先還原再查）。
  } finally {
    process.env.NODE_ENV = originalNodeEnv;
    if (originalAppEnv === undefined) delete process.env.APP_ENV;
    else process.env.APP_ENV = originalAppEnv;
    if (originalAllowMock === undefined) delete process.env.AUTH_ALLOW_MOCK;
    else process.env.AUTH_ALLOW_MOCK = originalAllowMock;
    residentCaller.setFirebaseAdminForTest(null);
    residentCaller.setPgForTest(null);
    restoreResident = null;
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    assert.deepEqual(await listAlerts(baseUrl), []);
    server.close();
  }
});

// #12 response 不含 token / sensitive（401/403 錯誤 body 僅 {success,error}）
test("#12 錯誤回應不外洩 token / Firebase detail / stack", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const unauth = await postNotify(baseUrl, { Authorization: "Bearer super-secret-token-xyz" });
    const unauthText = await unauth.text();
    assert.equal(unauth.status, 401);
    assert.ok(!unauthText.includes("super-secret-token-xyz"), "回應不可含 token");
    assert.ok(!/stack|Error:|firebase/i.test(unauthText), "回應不可含 stack / Firebase detail");

    const forbidden = await postNotify(baseUrl, RES_A, { elderId: ELDER_B });
    const forbiddenBody = await forbidden.json();
    assert.deepEqual(forbiddenBody, { success: false, error: "forbidden_resident" });
  } finally {
    server.close();
  }
});
