const assert = require("node:assert/strict");
const test = require("node:test");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

// 確保不會誤連 DB：把 PGVECTOR_ENABLED 設成 false，postgres.isPostgresAvailable() 直接回 false、
// 走 JSON fallback。用「設定」而非「刪除」，因 dotenv 不覆寫既有 env，可壓過本機 .env 的值。
process.env.PGVECTOR_ENABLED = "false";
delete process.env.DATABASE_URL;

const { createSession } = require("./sessionService");

function tempStore() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "auth_session_"));
  return {
    usersFilePath: path.join(dir, "users.json"),
    eldersFilePath: path.join(dir, "elders.json"),
  };
}

// 未 configured 的 firebaseAdmin stub（走 mock 模式）。
const mockAdminNotConfigured = {
  isConfigured: () => false,
  verifyIdToken: async () => null,
};

test("新使用者（mock 模式）建立 elder + user，回 isNewUser=true / authMode=mock / pending / 60 天後 deadline", async () => {
  const store = tempStore();
  const before = Date.now();
  const result = await createSession(
    {
      firebaseUid: "uid-new-1",
      idToken: "any-non-empty",
      email: "a@example.com",
      displayName: "阿嬤",
      provider: "mock",
    },
    { firebaseAdmin: mockAdminNotConfigured, ...store },
  );

  assert.equal(result.success, true);
  assert.equal(result.isNewUser, true);
  assert.equal(result.authMode, "mock");
  assert.equal(result.role, "elder");
  assert.equal(result.bindingStatus, "pending");
  assert.ok(result.userId, "userId should be set");
  assert.ok(result.elderId, "elderId should be set");

  // bindingDeadline 約為 now + 60 天（容忍 ±2 天）。
  const deadline = new Date(result.bindingDeadline).getTime();
  const expected = before + 60 * 24 * 60 * 60 * 1000;
  const tolerance = 2 * 24 * 60 * 60 * 1000;
  assert.ok(
    Math.abs(deadline - expected) < tolerance,
    `bindingDeadline ~ now+60d (got ${result.bindingDeadline})`,
  );

  // JSON store 應實際寫入一筆 user + 一筆 elder。
  const users = JSON.parse(fs.readFileSync(store.usersFilePath, "utf8"));
  const elders = JSON.parse(fs.readFileSync(store.eldersFilePath, "utf8"));
  assert.equal(users.length, 1);
  assert.equal(elders.length, 1);
  assert.equal(users[0].firebaseUid, "uid-new-1");
  assert.equal(users[0].elderId, elders[0].id);
});

test("既有 firebaseUid 回相同 userId / elderId 且 isNewUser=false", async () => {
  const store = tempStore();
  const first = await createSession(
    { firebaseUid: "uid-repeat", idToken: "t1", provider: "mock" },
    { firebaseAdmin: mockAdminNotConfigured, ...store },
  );
  const second = await createSession(
    { firebaseUid: "uid-repeat", idToken: "t2", provider: "mock" },
    { firebaseAdmin: mockAdminNotConfigured, ...store },
  );

  assert.equal(first.isNewUser, true);
  assert.equal(second.isNewUser, false);
  assert.equal(second.userId, first.userId);
  assert.equal(second.elderId, first.elderId);

  // 不應重複建立。
  const users = JSON.parse(fs.readFileSync(store.usersFilePath, "utf8"));
  assert.equal(users.length, 1);
});

test("firebase 模式 token 無效回 invalid_id_token（不建立任何資料）", async () => {
  const store = tempStore();
  const adminConfiguredRejects = {
    isConfigured: () => true,
    verifyIdToken: async () => null, // 模擬驗證失敗
  };
  const result = await createSession(
    { firebaseUid: "uid-bad", idToken: "bad-token", provider: "google" },
    { firebaseAdmin: adminConfiguredRejects, ...store },
  );
  assert.equal(result.success, false);
  assert.equal(result.error, "invalid_id_token");

  // 不應寫入任何 user。
  assert.equal(fs.existsSync(store.usersFilePath), false);
});

test("firebase 模式 token 有效，以 decoded.uid 為權威建立使用者，authMode=firebase", async () => {
  const store = tempStore();
  const adminConfiguredOk = {
    isConfigured: () => true,
    // 即使 client 傳 firebaseUid=spoof，也以 decoded.uid 為準。
    verifyIdToken: async () => ({ uid: "verified-uid" }),
  };
  const result = await createSession(
    { firebaseUid: "spoof", idToken: "good-token", provider: "google" },
    { firebaseAdmin: adminConfiguredOk, ...store },
  );
  assert.equal(result.success, true);
  assert.equal(result.authMode, "firebase");
  assert.equal(result.isNewUser, true);

  const users = JSON.parse(fs.readFileSync(store.usersFilePath, "utf8"));
  assert.equal(users[0].firebaseUid, "verified-uid");
});

test("缺 firebaseUid / idToken 回對應 missing 錯誤", async () => {
  const store = tempStore();
  const r1 = await createSession(
    { idToken: "t", provider: "mock" },
    { firebaseAdmin: mockAdminNotConfigured, ...store },
  );
  assert.equal(r1.success, false);
  assert.equal(r1.error, "missing_firebase_uid");

  const r2 = await createSession(
    { firebaseUid: "u", provider: "mock" },
    { firebaseAdmin: mockAdminNotConfigured, ...store },
  );
  assert.equal(r2.success, false);
  assert.equal(r2.error, "missing_id_token");
});

test("未 configured 且 AUTH_ALLOW_MOCK=false 時，無法驗證回 invalid_id_token", async () => {
  const store = tempStore();
  const original = process.env.AUTH_ALLOW_MOCK;
  process.env.AUTH_ALLOW_MOCK = "false";
  try {
    const result = await createSession(
      { firebaseUid: "uid-x", idToken: "t", provider: "mock" },
      { firebaseAdmin: mockAdminNotConfigured, ...store },
    );
    assert.equal(result.success, false);
    assert.equal(result.error, "invalid_id_token");
  } finally {
    if (original === undefined) delete process.env.AUTH_ALLOW_MOCK;
    else process.env.AUTH_ALLOW_MOCK = original;
  }
});
