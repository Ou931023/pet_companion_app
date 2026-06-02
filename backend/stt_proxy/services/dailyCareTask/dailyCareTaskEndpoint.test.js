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

const app = require("../../server");

function startServer() {
  return new Promise((resolve) => {
    const server = app.listen(0, "127.0.0.1", () => resolve(server));
  });
}

async function getJson(baseUrl, route) {
  const r = await fetch(`${baseUrl}${route}`);
  return { status: r.status, body: await r.json() };
}

async function postJson(baseUrl, route, body) {
  const r = await fetch(`${baseUrl}${route}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  return { status: r.status, body: await r.json() };
}

async function patchJson(baseUrl, route, body) {
  const r = await fetch(`${baseUrl}${route}`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  return { status: r.status, body: await r.json() };
}

async function submitPhoto(baseUrl, taskId) {
  const fd = new FormData();
  // 最小 JPEG header bytes，當作假照片。
  const bytes = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10]);
  fd.append("photo", new Blob([bytes], { type: "image/jpeg" }), "proof.jpg");
  const r = await fetch(`${baseUrl}/api/daily-care-tasks/${taskId}/submit`, {
    method: "POST",
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
    );
    assert.equal(status, 200);
    assert.equal(body.success, true);
    assert.deepEqual(body.tasks, []);
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

    const submitted = await submitPhoto(baseUrl, taskId);
    assert.equal(submitted.status, 200);
    assert.equal(submitted.body.task.status, "needs_review");
    assert.equal(
      submitted.body.submission.verification.verificationStatus,
      "uncertain",
    );
    assert.equal(submitted.body.submission.verification.reviewRequired, true);
    assert.notEqual(submitted.body.task.status, "completed");
  } finally {
    server.close();
  }
});

test("POST submit 到不存在的任務 → 404", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const { status, body } = await submitPhoto(baseUrl, "no-such-task");
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
    await submitPhoto(baseUrl, taskId);

    const admin = await getJson(
      baseUrl,
      "/api/admin/daily-care-tasks?elderId=elder-ep-admin",
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
