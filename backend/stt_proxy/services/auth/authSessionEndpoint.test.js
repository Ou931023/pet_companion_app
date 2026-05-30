const assert = require("node:assert/strict");
const test = require("node:test");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

// 將 auth JSON store 導到 temp，避免污染正式 data；並確保不誤連 DB。
const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "auth_session_ep_"));
process.env.USERS_DATA_FILE = path.join(tmpDir, "users.json");
process.env.ELDERS_DATA_FILE = path.join(tmpDir, "elders.json");
// 確保不誤連 DB：PGVECTOR_ENABLED=false → JSON fallback。設定（非刪除）以壓過 .env。
process.env.PGVECTOR_ENABLED = "false";
delete process.env.DATABASE_URL;
process.env.NODE_ENV = "test";

const app = require("../../server");

function startServer() {
  return new Promise((resolve) => {
    const server = app.listen(0, "127.0.0.1", () => resolve(server));
  });
}

test("POST /api/auth/session 缺欄位回 400 invalid_payload", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const response = await fetch(`${baseUrl}/api/auth/session`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ firebaseUid: "u-only" }), // 缺 idToken
    });
    const body = await response.json();
    assert.equal(response.status, 400);
    assert.deepEqual(body, { success: false, error: "invalid_payload" });
  } finally {
    server.close();
  }
});

test("POST /api/auth/session mock 模式成功回 200（authMode=mock、新使用者）", async () => {
  // 無 firebase 金鑰（未 npm install / 未設 env）→ 走 mock。
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const response = await fetch(`${baseUrl}/api/auth/session`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        firebaseUid: "uid-ep-1",
        idToken: "any-non-empty",
        provider: "mock",
        displayName: "測試長者",
      }),
    });
    const body = await response.json();
    assert.equal(response.status, 200);
    assert.equal(body.success, true);
    assert.equal(body.authMode, "mock");
    assert.equal(body.isNewUser, true);
    assert.equal(body.role, "elder");
    assert.equal(body.bindingStatus, "pending");
    assert.ok(body.userId);
    assert.ok(body.elderId);
    assert.ok(body.bindingDeadline);
  } finally {
    server.close();
  }
});

test("POST /api/auth/session 無法驗證時回 401 invalid_id_token（mock 關閉、無金鑰）", async () => {
  const original = process.env.AUTH_ALLOW_MOCK;
  process.env.AUTH_ALLOW_MOCK = "false"; // 強制不走 mock；又無 Firebase 金鑰 → 無法驗證
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const response = await fetch(`${baseUrl}/api/auth/session`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        firebaseUid: "uid-ep-2",
        idToken: "bad-token",
        provider: "google",
      }),
    });
    const body = await response.json();
    assert.equal(response.status, 401);
    assert.deepEqual(body, { success: false, error: "invalid_id_token" });
  } finally {
    if (original === undefined) delete process.env.AUTH_ALLOW_MOCK;
    else process.env.AUTH_ALLOW_MOCK = original;
    server.close();
  }
});
