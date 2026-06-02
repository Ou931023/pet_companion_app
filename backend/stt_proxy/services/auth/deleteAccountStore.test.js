const assert = require("node:assert/strict");
const test = require("node:test");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

// 不誤連 DB：PGVECTOR_ENABLED=false → JSON fallback。設定（非刪除）以壓過 .env。
process.env.PGVECTOR_ENABLED = "false";
delete process.env.DATABASE_URL;

const {
  createSession,
  deleteUserByFirebaseUid,
} = require("./sessionService");
const { deleteMemoriesByUserId } = require("../memory/memoryStore");
const { deleteAlertsByElderId } = require("../careAlertStoreService");

const mockAdminNotConfigured = {
  isConfigured: () => false,
  verifyIdToken: async () => null,
};

function tempStore() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "auth_delete_"));
  return {
    usersFilePath: path.join(dir, "users.json"),
    eldersFilePath: path.join(dir, "elders.json"),
  };
}

test("deleteUserByFirebaseUid：存在 → 刪 user + elder 並回被刪的 id", async () => {
  const store = tempStore();
  const created = await createSession(
    { firebaseUid: "uid-del-1", idToken: "t", provider: "mock" },
    { firebaseAdmin: mockAdminNotConfigured, ...store },
  );

  const result = await deleteUserByFirebaseUid("uid-del-1", store);

  assert.equal(result.user, 1);
  assert.equal(result.elder, 1);
  assert.equal(result.userId, created.userId);
  assert.equal(result.elderId, created.elderId);

  // 檔案內已無該 user / elder。
  const users = JSON.parse(fs.readFileSync(store.usersFilePath, "utf8"));
  const elders = JSON.parse(fs.readFileSync(store.eldersFilePath, "utf8"));
  assert.equal(users.length, 0);
  assert.equal(elders.length, 0);
});

test("deleteUserByFirebaseUid：不存在 → 全 0 / null（idempotent）", async () => {
  const store = tempStore();
  const result = await deleteUserByFirebaseUid("nope", store);
  assert.deepEqual(result, { user: 0, elder: 0, userId: null, elderId: null });
});

test("deleteUserByFirebaseUid：只刪指定 user，不動別的帳號", async () => {
  const store = tempStore();
  await createSession(
    { firebaseUid: "keep-me", idToken: "t", provider: "mock" },
    { firebaseAdmin: mockAdminNotConfigured, ...store },
  );
  await createSession(
    { firebaseUid: "delete-me", idToken: "t", provider: "mock" },
    { firebaseAdmin: mockAdminNotConfigured, ...store },
  );

  await deleteUserByFirebaseUid("delete-me", store);

  const users = JSON.parse(fs.readFileSync(store.usersFilePath, "utf8"));
  const elders = JSON.parse(fs.readFileSync(store.eldersFilePath, "utf8"));
  assert.equal(users.length, 1);
  assert.equal(users[0].firebaseUid, "keep-me");
  assert.equal(elders.length, 1);
});

test("deleteMemoriesByUserId：只刪該 userId 的記憶，其餘不受影響", async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "mem_del_"));
  const original = process.env.MEMORY_DATA_DIR;
  process.env.MEMORY_DATA_DIR = dir;
  try {
    const memories = [
      { id: 1, userId: "alice", memoryText: "a1", isActive: true },
      { id: 2, userId: "alice", memoryText: "a2", isActive: true },
      { id: 3, userId: "bob", memoryText: "b1", isActive: true },
    ];
    fs.writeFileSync(
      path.join(dir, "companion_memories.json"),
      JSON.stringify(memories, null, 2),
    );

    const removed = await deleteMemoriesByUserId("alice");
    assert.equal(removed, 2);

    const remaining = JSON.parse(
      fs.readFileSync(path.join(dir, "companion_memories.json"), "utf8"),
    );
    assert.equal(remaining.length, 1);
    assert.equal(remaining[0].userId, "bob");
  } finally {
    if (original === undefined) delete process.env.MEMORY_DATA_DIR;
    else process.env.MEMORY_DATA_DIR = original;
  }
});

test("deleteMemoriesByUserId：沒有相符 → 回 0、檔案不變", async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "mem_del2_"));
  const original = process.env.MEMORY_DATA_DIR;
  process.env.MEMORY_DATA_DIR = dir;
  try {
    fs.writeFileSync(
      path.join(dir, "companion_memories.json"),
      JSON.stringify([{ id: 1, userId: "bob" }], null, 2),
    );
    const removed = await deleteMemoriesByUserId("alice");
    assert.equal(removed, 0);
  } finally {
    if (original === undefined) delete process.env.MEMORY_DATA_DIR;
    else process.env.MEMORY_DATA_DIR = original;
  }
});

test("deleteAlertsByElderId：只刪該 elderId 的 Care Alert", async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "alert_del_"));
  const filePath = path.join(dir, "care_alerts.json");
  fs.writeFileSync(
    filePath,
    JSON.stringify(
      [
        { id: "x1", elderId: "elder-A", riskLevel: "low" },
        { id: "x2", elderId: "elder-A", riskLevel: "high" },
        { id: "x3", elderId: "elder-B", riskLevel: "low" },
        { id: "x4", elderId: null, riskLevel: "low" },
      ],
      null,
      2,
    ),
  );

  const removed = await deleteAlertsByElderId("elder-A", { filePath });
  assert.equal(removed, 2);

  const remaining = JSON.parse(fs.readFileSync(filePath, "utf8"));
  assert.equal(remaining.length, 2);
  assert.ok(remaining.every((a) => a.elderId !== "elder-A"));
});

test("deleteAlertsByElderId：elderId 為空 → 回 0、不動檔案", async () => {
  const removed = await deleteAlertsByElderId(null, {
    filePath: "/nonexistent/care_alerts.json",
  });
  assert.equal(removed, 0);
});
