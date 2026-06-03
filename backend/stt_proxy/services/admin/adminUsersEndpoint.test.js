// CR-0029：GET /api/admin/users endpoint 測試（比照 adminEndpoint.test.js 風格）。
// 覆蓋 401（無 token）、403（token 錯）、200（token 對 + PG mock）、500（查詢失敗）。
// 用 mock 取代 postgres.query，不連真 DB、不走 JSON fallback。

const assert = require("node:assert/strict");
const { test, mock } = require("node:test");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

// 隔離資料檔，避免 server 載入時觸碰正式 data。
const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "admin_users_ep_"));
process.env.ELDERS_DATA_FILE = path.join(tmpDir, "elders.json");
process.env.USERS_DATA_FILE = path.join(tmpDir, "users.json");
process.env.CARE_ALERTS_DATA_FILE = path.join(tmpDir, "care_alerts.json");
process.env.NODE_ENV = "test";
process.env.ADMIN_API_TOKEN = "test-admin-token";
delete process.env.TELEGRAM_BOT_TOKEN;
delete process.env.TELEGRAM_CARE_CHAT_ID;

const app = require("../../server");
const postgres = require("../../db/postgres");

function startServer() {
  return new Promise((resolve) => {
    const server = app.listen(0, "127.0.0.1", () => resolve(server));
  });
}

// 含敏感欄位的假 row，用來證明 API 會把它們過濾掉。
const FAKE_ROW = {
  id: "0f1f1a6e-2c4a-4f1d-9b4e-123456789abc",
  display_name: "王小明",
  email: "wang@gmail.com",
  auth_provider: "google",
  email_verified: true,
  created_at: "2026-06-01T10:20:00.000Z",
  last_login_at: "2026-06-02T09:30:00.000Z",
  password_hash: "SHOULD_NOT_LEAK",
  provider_user_id: "google-uid-999",
  firebase_uid: "fb-uid-111",
  access_token: "AT_SECRET",
  refresh_token: "RT_SECRET",
  id_token: "IDT_SECRET",
  verification_token_hash: "VTH_SECRET",
  reset_password_token: "RESET_SECRET",
  otp: "000000",
  session_token: "SESSION_SECRET",
};

const SENSITIVE_STRINGS = [
  "password_hash",
  "provider_user_id",
  "firebase_uid",
  "access_token",
  "refresh_token",
  "id_token",
  "verification_token",
  "reset_password_token",
  "otp",
  "session_token",
  "SHOULD_NOT_LEAK",
  "google-uid-999",
  "fb-uid-111",
  "AT_SECRET",
  "RT_SECRET",
  "wang@gmail.com",
];

test("GET /api/admin/users 無 Authorization → 401 missing_admin_token", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetch(`${baseUrl}/api/admin/users`);
    const body = await res.json();
    assert.equal(res.status, 401);
    assert.equal(body.ok, false);
    assert.equal(body.error, "missing_admin_token");
  } finally {
    server.close();
  }
});

test("GET /api/admin/users token 錯誤 → 403 admin_permission_required", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetch(`${baseUrl}/api/admin/users`, {
      headers: { Authorization: "Bearer wrong-token" },
    });
    const body = await res.json();
    assert.equal(res.status, 403);
    assert.equal(body.ok, false);
    assert.equal(body.error, "admin_permission_required");
  } finally {
    server.close();
  }
});

test("GET /api/admin/users token 正確 → 200，從 PG 查詢、遮蔽 email、過濾敏感欄位", async () => {
  mock.method(postgres, "query", async () => ({ rows: [FAKE_ROW] }));
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetch(`${baseUrl}/api/admin/users`, {
      headers: { Authorization: "Bearer test-admin-token" },
    });
    const body = await res.json();
    assert.equal(res.status, 200);
    assert.equal(body.ok, true);
    assert.equal(body.users.length, 1);

    const user = body.users[0];
    // 安全欄位齊全
    for (const key of [
      "id",
      "displayName",
      "emailMasked",
      "authProvider",
      "emailVerified",
      "createdAt",
      "lastLoginAt",
    ]) {
      assert.ok(key in user, `回傳應含安全欄位 ${key}`);
    }
    assert.equal(user.emailMasked, "wa***@gmail.com");
    assert.equal(user.authProvider, "google");
    assert.equal(user.emailVerified, true);

    // 絕不外漏任何敏感欄位 / 值
    const blob = JSON.stringify(body);
    for (const s of SENSITIVE_STRINGS) {
      assert.ok(!blob.includes(s), `response 不可包含敏感字串：${s}`);
    }
  } finally {
    server.close();
    mock.restoreAll();
  }
});

test("GET /api/admin/users 查詢失敗 → 500 failed_to_load_users（無 JSON fallback）", async () => {
  mock.method(postgres, "query", async () => {
    throw new Error("PostgreSQL is not configured");
  });
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetch(`${baseUrl}/api/admin/users`, {
      headers: { Authorization: "Bearer test-admin-token" },
    });
    const body = await res.json();
    assert.equal(res.status, 500);
    assert.equal(body.ok, false);
    assert.equal(body.error, "failed_to_load_users");
    // 不可把 stack trace / 原始錯誤丟回前端
    assert.ok(!JSON.stringify(body).toLowerCase().includes("postgresql"));
  } finally {
    server.close();
    mock.restoreAll();
  }
});
