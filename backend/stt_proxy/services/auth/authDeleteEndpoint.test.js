const assert = require("node:assert/strict");
const test = require("node:test");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

// 所有 store 導到 temp，避免污染正式 data；並確保不誤連 DB。
// 必須在 require server 之前設好（server 啟動時讀 env）。
const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "auth_delete_ep_"));
process.env.USERS_DATA_FILE = path.join(tmpDir, "users.json");
process.env.ELDERS_DATA_FILE = path.join(tmpDir, "elders.json");
process.env.MEMORY_DATA_DIR = tmpDir;
process.env.CARE_ALERTS_DATA_FILE = path.join(tmpDir, "care_alerts.json");
process.env.PGVECTOR_ENABLED = "false";
delete process.env.DATABASE_URL;
process.env.NODE_ENV = "test";

const app = require("../../server");

function startServer() {
  return new Promise((resolve) => {
    const server = app.listen(0, "127.0.0.1", () => resolve(server));
  });
}

async function post(baseUrl, route, body) {
  const response = await fetch(`${baseUrl}${route}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  return { status: response.status, body: await response.json() };
}

test("POST /api/auth/delete 缺欄位回 400 invalid_payload", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const { status, body } = await post(baseUrl, "/api/auth/delete", {
      firebaseUid: "u-only",
    });
    assert.equal(status, 400);
    assert.deepEqual(body, { success: false, error: "invalid_payload" });
  } finally {
    server.close();
  }
});

test("POST /api/auth/delete 找不到 user → idempotent 200（deleted 全 0）", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const { status, body } = await post(baseUrl, "/api/auth/delete", {
      firebaseUid: "never-existed",
      idToken: "any-non-empty",
    });
    assert.equal(status, 200);
    assert.equal(body.success, true);
    assert.deepEqual(body.deleted, {
      user: 0,
      elder: 0,
      memories: 0,
      careAlerts: 0,
    });
  } finally {
    server.close();
  }
});

test("POST /api/auth/delete mock 模式 → 連同記憶 / Care Alert 一併刪除", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;

    // 1. 建立帳號。
    const created = await post(baseUrl, "/api/auth/session", {
      firebaseUid: "uid-full-del",
      idToken: "any-non-empty",
      provider: "mock",
      displayName: "刪除測試長者",
    });
    assert.equal(created.status, 200);
    const { userId, elderId } = created.body;

    // 2. 為該 user / elder 種一筆記憶 + 一筆 Care Alert（也夾雜別人的，驗證不誤刪）。
    fs.writeFileSync(
      path.join(tmpDir, "companion_memories.json"),
      JSON.stringify(
        [
          { id: 1, userId, memoryText: "我喜歡散步", isActive: true },
          { id: 2, userId: "someone-else", memoryText: "別人的", isActive: true },
        ],
        null,
        2,
      ),
    );
    fs.writeFileSync(
      path.join(tmpDir, "care_alerts.json"),
      JSON.stringify(
        [
          { id: "a1", elderId, riskLevel: "high" },
          { id: "a2", elderId: "other-elder", riskLevel: "low" },
        ],
        null,
        2,
      ),
    );

    // 3. 刪除帳號。
    const deleted = await post(baseUrl, "/api/auth/delete", {
      firebaseUid: "uid-full-del",
      idToken: "any-non-empty",
    });
    assert.equal(deleted.status, 200);
    assert.equal(deleted.body.success, true);
    assert.deepEqual(deleted.body.deleted, {
      user: 1,
      elder: 1,
      memories: 1,
      careAlerts: 1,
    });

    // 4. 別人的資料完好。
    const memories = JSON.parse(
      fs.readFileSync(path.join(tmpDir, "companion_memories.json"), "utf8"),
    );
    assert.equal(memories.length, 1);
    assert.equal(memories[0].userId, "someone-else");

    const alerts = JSON.parse(
      fs.readFileSync(path.join(tmpDir, "care_alerts.json"), "utf8"),
    );
    assert.equal(alerts.length, 1);
    assert.equal(alerts[0].elderId, "other-elder");

    // 5. 再刪一次 → idempotent（user 已不在）。
    const again = await post(baseUrl, "/api/auth/delete", {
      firebaseUid: "uid-full-del",
      idToken: "any-non-empty",
    });
    assert.equal(again.body.deleted.user, 0);
  } finally {
    server.close();
  }
});
