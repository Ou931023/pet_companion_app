const assert = require("node:assert/strict");
const { test, beforeEach, after } = require("node:test");

process.env.NODE_ENV = "test";
// 強制 mock-auth 模式，讓本機是否設定 Firebase 不影響非 401 測試（401 測試另以
// monkeypatch firebaseAdmin 模擬 configured + token 無效）。設定 process.env 屬
// 執行期記憶體變更，不觸碰 .env 檔。
delete process.env.GOOGLE_APPLICATION_CREDENTIALS;
delete process.env.FIREBASE_PROJECT_ID;
delete process.env.FIREBASE_CLIENT_EMAIL;
delete process.env.FIREBASE_PRIVATE_KEY;
process.env.AUTH_ALLOW_MOCK = "true";

const app = require("../server");
const consentStore = require("./consentStoreService");
const firebaseAdmin = require("./auth/firebaseAdmin");
firebaseAdmin._resetForTest();

// require server 會載入 .env（可能含真實 token）。清掉與本測試無關的外部依賴，
// 確保測試「絕不」真的觸發外部服務。
delete process.env.TELEGRAM_BOT_TOKEN;
delete process.env.TELEGRAM_CARE_CHAT_ID;

// 每個測試用全新 mock pool，避免互相污染。
let mockPg;
function installMockPg(rowsFor, throwError) {
  const calls = [];
  mockPg = {
    calls,
    query: async (text, params) => {
      calls.push({ text, params });
      if (throwError) throw throwError;
      const rows = typeof rowsFor === "function" ? rowsFor(text, params) : rowsFor;
      return { rows: rows || [] };
    },
  };
  consentStore.setPgForTest(mockPg);
  return mockPg;
}

beforeEach(() => {
  installMockPg([]);
});

after(() => {
  consentStore.setPgForTest(null); // 還原為真實 pg
});

function startServer() {
  return new Promise((resolve) => {
    const server = app.listen(0, "127.0.0.1", () => resolve(server));
  });
}

function postConsent(baseUrl, body) {
  return fetch(`${baseUrl}/api/consent`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

test("POST /api/consent 成功 → 200，record 不含 ip / userAgent，但 DB 有落 PII", async () => {
  installMockPg([
    {
      id: "rec-1",
      consent_type: "privacy_terms",
      consent_version: "1.0.0",
      action: "granted",
      agreed_at: "2026-06-08T00:00:00.000Z",
    },
  ]);
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await postConsent(baseUrl, {
      firebaseUid: "uid-1",
      consentType: "privacy_terms",
      consentVersion: "1.0.0",
      action: "granted",
    });
    const body = await res.json();
    assert.equal(res.status, 200);
    assert.equal(body.success, true);
    assert.equal(body.record.id, "rec-1");
    assert.equal(body.record.consentType, "privacy_terms");
    // PII 不回顯
    assert.ok(!("ip" in body.record));
    assert.ok(!("userAgent" in body.record));
    const raw = JSON.stringify(body);
    assert.doesNotMatch(raw, /"ip"/);
    assert.doesNotMatch(raw, /userAgent|user_agent/);

    // DB 端有落 ip / user_agent（後端從 req 擷取，$11 / $12）
    const { params } = mockPg.calls[0];
    assert.ok(params[10] != null && String(params[10]).length > 0); // ip
  } finally {
    server.close();
  }
});

test("POST /api/consent 缺 consentVersion → 400 invalid_payload，未打 DB", async () => {
  const pg = installMockPg([]);
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await postConsent(baseUrl, {
      firebaseUid: "uid-1",
      consentType: "privacy_terms",
    });
    const body = await res.json();
    assert.equal(res.status, 400);
    assert.equal(body.success, false);
    assert.equal(body.error, "invalid_payload");
    assert.equal(pg.calls.length, 0);
  } finally {
    server.close();
  }
});

test("POST /api/consent DB 失敗 → 500 consent_failed，不回 stack trace", async () => {
  installMockPg([], new Error("db exploded with secret path /var/secret"));
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await postConsent(baseUrl, {
      firebaseUid: "uid-1",
      consentType: "privacy_terms",
      consentVersion: "1.0.0",
    });
    const body = await res.json();
    assert.equal(res.status, 500);
    assert.equal(body.success, false);
    assert.equal(body.error, "consent_failed");
    // 不外洩例外細節
    assert.doesNotMatch(JSON.stringify(body), /secret|stack|exploded/i);
  } finally {
    server.close();
  }
});

test("POST /api/consent firebase configured 且 token 無效 → 401 invalid_id_token", async () => {
  const origIsConfigured = firebaseAdmin.isConfigured;
  const origVerify = firebaseAdmin.verifyIdToken;
  firebaseAdmin.isConfigured = () => true;
  firebaseAdmin.verifyIdToken = async () => null; // 模擬驗證失敗
  const pg = installMockPg([]);
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await postConsent(baseUrl, {
      firebaseUid: "uid-1",
      idToken: "bad-token",
      consentType: "privacy_terms",
      consentVersion: "1.0.0",
    });
    const body = await res.json();
    assert.equal(res.status, 401);
    assert.equal(body.success, false);
    assert.equal(body.error, "invalid_id_token");
    assert.equal(pg.calls.length, 0); // 驗證失敗不應寫 DB
  } finally {
    server.close();
    firebaseAdmin.isConfigured = origIsConfigured;
    firebaseAdmin.verifyIdToken = origVerify;
  }
});

test("GET /api/consent?userId= → 200 current/history，遮蔽 PII", async () => {
  installMockPg([
    {
      id: "h2",
      consent_type: "privacy_terms",
      consent_version: "2.0.0",
      action: "granted",
      agreed_at: "2026-06-08T00:00:00.000Z",
      withdrawn_at: null,
    },
    {
      id: "h1",
      consent_type: "privacy_terms",
      consent_version: "1.0.0",
      action: "granted",
      agreed_at: "2026-06-07T00:00:00.000Z",
      withdrawn_at: null,
    },
  ]);
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetch(
      `${baseUrl}/api/consent?userId=11111111-1111-1111-1111-111111111111`,
    );
    const body = await res.json();
    assert.equal(res.status, 200);
    assert.equal(body.success, true);
    assert.equal(body.current.length, 1); // 同 type 只留最新
    assert.equal(body.current[0].consentVersion, "2.0.0");
    assert.equal(body.history.length, 2);
    const raw = JSON.stringify(body);
    assert.doesNotMatch(raw, /"ip"/);
    assert.doesNotMatch(raw, /userAgent|user_agent/);
  } finally {
    server.close();
  }
});

test("GET /api/consent 無識別參數 → 400 invalid_payload", async () => {
  const pg = installMockPg([]);
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetch(`${baseUrl}/api/consent`);
    const body = await res.json();
    assert.equal(res.status, 400);
    assert.equal(body.success, false);
    assert.equal(body.error, "invalid_payload");
    assert.equal(pg.calls.length, 0);
  } finally {
    server.close();
  }
});

test("GET /api/consent DB 失敗 → 500 consent_failed", async () => {
  installMockPg([], new Error("db down"));
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetch(
      `${baseUrl}/api/consent?userId=11111111-1111-1111-1111-111111111111`,
    );
    const body = await res.json();
    assert.equal(res.status, 500);
    assert.equal(body.success, false);
    assert.equal(body.error, "consent_failed");
  } finally {
    server.close();
  }
});
