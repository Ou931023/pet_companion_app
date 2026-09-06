const assert = require("node:assert/strict");
const test = require("node:test");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

// store 導到 temp、強制無 OPENAI_API_KEY（submit 走 needs_review 路徑，不打真 API）。
// 必須在 require server 之前設好。
const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "daily_care_ep_"));
process.env.DAILY_CARE_TASKS_DATA_FILE = path.join(tmpDir, "tasks.json");
process.env.DAILY_CARE_TASK_SUBMISSIONS_DATA_FILE = path.join(
  tmpDir,
  "submissions.json",
);
process.env.OPENAI_API_KEY = "";
process.env.PGVECTOR_ENABLED = "false";
delete process.env.DATABASE_URL;
process.env.NODE_ENV = "test";
// CR-0039：/api/admin/daily-care-tasks 掛了 requireAdmin。
process.env.ADMIN_API_TOKEN = "test-admin-token";

const app = require("../../server");
const residentAuth = require("../auth/residentCallerContext");

function residentToken(elderId) {
  return `resident-token:${elderId}`;
}

function residentHeaders(elderId) {
  return { Authorization: `Bearer ${residentToken(elderId)}` };
}

residentAuth.setFirebaseAdminForTest({
  isConfigured: () => true,
  verifyIdToken: async (token) => {
    if (!String(token).startsWith("resident-token:")) return null;
    return { uid: `firebase:${String(token).slice("resident-token:".length)}` };
  },
});
residentAuth.setPgForTest({
  isPostgresAvailable: async () => true,
  query: async (_text, params) => {
    const uid = String(params?.[0] || "");
    if (!uid.startsWith("firebase:")) return { rows: [] };
    const elderId = uid.slice("firebase:".length);
    return {
      rows: [{ id: `user:${elderId}`, role: "resident", status: "active", elder_id: elderId }],
    };
  },
});

// CR-0039：admin 授權 header。
const ADMIN_HEADERS = { Authorization: "Bearer test-admin-token" };

function startServer() {
  return new Promise((resolve) => {
    const server = app.listen(0, "127.0.0.1", () => resolve(server));
  });
}

async function getJson(baseUrl, route, headers = {}) {
  const r = await fetch(`${baseUrl}${route}`, { headers });
  return { status: r.status, body: await r.json() };
}

async function postJson(baseUrl, route, body) {
  const r = await fetch(`${baseUrl}${route}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...residentHeaders(body.elderId),
    },
    body: JSON.stringify(body),
  });
  return { status: r.status, body: await r.json() };
}

async function patchJson(baseUrl, route, body) {
  const r = await fetch(`${baseUrl}${route}`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json", ...ADMIN_HEADERS },
    body: JSON.stringify(body),
  });
  return { status: r.status, body: await r.json() };
}

async function submitPhoto(baseUrl, taskId, elderId) {
  const fd = new FormData();
  // 最小 JPEG header bytes，當作假照片。
  const bytes = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10]);
  fd.append("photo", new Blob([bytes], { type: "image/jpeg" }), "proof.jpg");
  const r = await fetch(`${baseUrl}/api/daily-care-tasks/${taskId}/submit`, {
    method: "POST",
    headers: residentHeaders(elderId),
    body: fd,
  });
  return { status: r.status, body: await r.json() };
}

test("GET /api/daily-care-tasks 一開始為空", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const { status, body } = await getJson(
      baseUrl,
      "/api/daily-care-tasks?elderId=elder-ep-empty",
      residentHeaders("elder-ep-empty"),
    );
    assert.equal(status, 200);
    assert.equal(body.success, true);
    assert.deepEqual(body.tasks, []);
  } finally {
    server.close();
  }
});

test("長者任務 API 無 token 一律拒絕，且 elderId 由 token 決定", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const unauthenticated = await getJson(
      baseUrl,
      "/api/daily-care-tasks?elderId=someone-else",
    );
    assert.equal(unauthenticated.status, 401);

    const created = await postJson(baseUrl, "/api/daily-care-tasks", {
      elderId: "resident-owner",
      title: "安全範圍測試",
      type: "hydration",
    });
    assert.equal(created.status, 200);
    assert.equal(created.body.task.elderId, "resident-owner");

    const forged = await fetch(`${baseUrl}/api/daily-care-tasks`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        ...residentHeaders("resident-owner"),
      },
      body: JSON.stringify({
        elderId: "forged-resident",
        title: "不可跨住民",
        type: "medication",
      }),
    });
    const forgedBody = await forged.json();
    assert.equal(forged.status, 200);
    assert.equal(forgedBody.task.elderId, "resident-owner");

    const crossResidentSubmit = await submitPhoto(
      baseUrl,
      created.body.task.id,
      "different-resident",
    );
    assert.equal(crossResidentSubmit.status, 403);
    assert.equal(crossResidentSubmit.body.error, "forbidden");
  } finally {
    server.close();
  }
});

test("POST 建立任務 → GET 列表取得", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const created = await postJson(baseUrl, "/api/daily-care-tasks", {
      elderId: "elder-ep-1",
      title: "早上吃藥",
      type: "medication",
      scheduledTime: "08:00",
    });
    assert.equal(created.status, 200);
    assert.equal(created.body.task.status, "pending");

    const list = await getJson(
      baseUrl,
      "/api/daily-care-tasks?elderId=elder-ep-1",
      residentHeaders("elder-ep-1"),
    );
    assert.equal(list.body.tasks.length, 1);
    assert.equal(list.body.tasks[0].title, "早上吃藥");
  } finally {
    server.close();
  }
});

test("POST 建立缺 title → 400 invalid_payload", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const { status, body } = await postJson(baseUrl, "/api/daily-care-tasks", {
      elderId: "e",
      type: "medication",
    });
    assert.equal(status, 400);
    assert.equal(body.error, "invalid_payload");
  } finally {
    server.close();
  }
});

test("POST submit 上傳照片（無 AI key）→ needs_review，不 crash、不 fake passed", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const created = await postJson(baseUrl, "/api/daily-care-tasks", {
      elderId: "elder-ep-2",
      title: "喝水",
      type: "hydration",
    });
    const taskId = created.body.task.id;

    const submitted = await submitPhoto(baseUrl, taskId, "elder-ep-2");
    assert.equal(submitted.status, 200);
    assert.equal(submitted.body.task.status, "needs_review");
    assert.equal(
      submitted.body.submission.verification.verificationStatus,
      "uncertain",
    );
    assert.equal(submitted.body.submission.verification.reviewRequired, true);
    assert.notEqual(submitted.body.task.status, "completed");
    assert.equal(Object.hasOwn(submitted.body.submission, "proofImagePath"), false);
    assert.equal(Object.hasOwn(submitted.body.submission, "proofImageBytes"), false);

    const proof = await fetch(
      `${baseUrl}/api/daily-care-tasks/proof/${submitted.body.submission.id}`,
      { headers: ADMIN_HEADERS },
    );
    assert.equal(proof.status, 200);
    assert.equal(proof.headers.get("content-type"), "image/jpeg");
    assert.deepEqual(
      Buffer.from(await proof.arrayBuffer()),
      Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10]),
    );
  } finally {
    server.close();
  }
});

test("POST submit 到不存在的任務 → 404", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const { status, body } = await submitPhoto(
      baseUrl,
      "no-such-task",
      "elder-ep-missing",
    );
    assert.equal(status, 404);
    assert.equal(body.error, "task_not_found");
  } finally {
    server.close();
  }
});

test("PATCH 更新任務狀態 → completed", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const created = await postJson(baseUrl, "/api/daily-care-tasks", {
      elderId: "elder-ep-3",
      title: "運動",
      type: "exercise",
    });
    const taskId = created.body.task.id;

    const patched = await patchJson(
      baseUrl,
      `/api/daily-care-tasks/${taskId}/status`,
      { status: "completed" },
    );
    assert.equal(patched.status, 200);
    assert.equal(patched.body.task.status, "completed");

    const badStatus = await patchJson(
      baseUrl,
      `/api/daily-care-tasks/${taskId}/status`,
      { status: "weird" },
    );
    assert.equal(badStatus.status, 400);
  } finally {
    server.close();
  }
});

test("GET /api/admin/daily-care-tasks → 任務含最新 submission 與 AI 結果", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const created = await postJson(baseUrl, "/api/daily-care-tasks", {
      elderId: "elder-ep-admin",
      title: "吃藥",
      type: "medication",
    });
    const taskId = created.body.task.id;
    await submitPhoto(baseUrl, taskId, "elder-ep-admin");

    const admin = await getJson(
      baseUrl,
      "/api/admin/daily-care-tasks?elderId=elder-ep-admin",
      ADMIN_HEADERS,
    );
    assert.equal(admin.status, 200);
    assert.equal(admin.body.tasks.length, 1);
    const t = admin.body.tasks[0];
    assert.equal(t.status, "needs_review");
    assert.ok(t.latestSubmission);
    assert.equal(
      t.latestSubmission.verification.verificationStatus,
      "uncertain",
    );
    assert.equal(typeof t.latestSubmission.verification.confidence, "number");
  } finally {
    server.close();
  }
});
