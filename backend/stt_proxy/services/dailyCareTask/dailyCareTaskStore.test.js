const assert = require("node:assert/strict");
const test = require("node:test");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const store = require("./dailyCareTaskStore");

function tempFiles() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "daily_care_task_"));
  return {
    tasksFilePath: path.join(dir, "daily_care_tasks.json"),
    submissionsFilePath: path.join(dir, "daily_care_task_submissions.json"),
  };
}

test("createTask + listTasks + getTaskById", async () => {
  const opts = tempFiles();
  const created = await store.createTask(
    {
      elderId: "elder-1",
      title: "早上吃藥",
      type: "medication",
      scheduledTime: "08:00",
    },
    opts,
  );
  assert.equal(created.status, "pending");
  assert.equal(created.type, "medication");
  assert.equal(created.proofRequired, true);
  assert.ok(created.id);

  const list = await store.listTasks({ elderId: "elder-1", ...opts });
  assert.equal(list.length, 1);
  assert.equal(list[0].title, "早上吃藥");

  // 別的長者看不到。
  const other = await store.listTasks({ elderId: "elder-2", ...opts });
  assert.equal(other.length, 0);

  const fetched = await store.getTaskById(created.id, opts);
  assert.equal(fetched.id, created.id);
});

test("normalizeTask：walk → exercise；未知 type → medication", async () => {
  const opts = tempFiles();
  const walk = await store.createTask(
    { title: "散步", type: "walk", elderId: "e" },
    opts,
  );
  assert.equal(walk.type, "exercise");
  const weird = await store.createTask(
    { title: "x", type: "nonsense", elderId: "e" },
    opts,
  );
  assert.equal(weird.type, "medication");
});

test("updateTaskStatus：無效狀態 / 找不到 / 成功", async () => {
  const opts = tempFiles();
  const t = await store.createTask({ title: "喝水", type: "hydration", elderId: "e" }, opts);

  const bad = await store.updateTaskStatus(t.id, "weird_status", opts);
  assert.equal(bad.success, false);
  assert.equal(bad.error, "invalid_status");

  const missing = await store.updateTaskStatus("nope", "completed", opts);
  assert.equal(missing.success, false);
  assert.equal(missing.error, "not_found");

  const ok = await store.updateTaskStatus(t.id, "completed", opts);
  assert.equal(ok.success, true);
  assert.equal(ok.task.status, "completed");
});

test("recordSubmission passed → 任務 completed", async () => {
  const opts = tempFiles();
  const t = await store.createTask({ title: "吃藥", type: "medication", elderId: "e" }, opts);
  const result = await store.recordSubmission(
    t.id,
    {
      proofImagePath: "/tmp/fake.jpg",
      verification: {
        verificationStatus: "passed",
        confidence: 0.9,
        reason: "看起來有藥盒",
        detectedObjects: ["藥盒"],
        reviewRequired: false,
      },
    },
    opts,
  );
  assert.equal(result.success, true);
  assert.equal(result.task.status, "completed");
  assert.equal(result.submission.status, "completed");
  assert.equal(result.submission.verification.verificationStatus, "passed");
});

test("recordSubmission uncertain → 任務 needs_review", async () => {
  const opts = tempFiles();
  const t = await store.createTask({ title: "喝水", type: "hydration", elderId: "e" }, opts);
  const result = await store.recordSubmission(
    t.id,
    { verification: { verificationStatus: "uncertain", confidence: 0.3 } },
    opts,
  );
  assert.equal(result.task.status, "needs_review");
  assert.equal(result.submission.verification.reviewRequired, true);
});

test("recordSubmission failed → 任務 needs_review（避免誤判，不自動 rejected）", async () => {
  const opts = tempFiles();
  const t = await store.createTask({ title: "運動", type: "exercise", elderId: "e" }, opts);
  const result = await store.recordSubmission(
    t.id,
    { verification: { verificationStatus: "failed", confidence: 0.8 } },
    opts,
  );
  assert.equal(result.task.status, "needs_review");
});

test("recordSubmission：任務不存在 → task_not_found", async () => {
  const opts = tempFiles();
  const result = await store.recordSubmission("nope", { verification: {} }, opts);
  assert.equal(result.success, false);
  assert.equal(result.error, "task_not_found");
});

test("listTasksForAdmin：附最新 submission + submissionCount", async () => {
  const opts = tempFiles();
  const t = await store.createTask({ title: "吃藥", type: "medication", elderId: "e" }, opts);
  await store.recordSubmission(
    t.id,
    { verification: { verificationStatus: "uncertain", confidence: 0.2 } },
    opts,
  );
  await store.recordSubmission(
    t.id,
    {
      verification: {
        verificationStatus: "passed",
        confidence: 0.9,
        detectedObjects: ["藥包"],
      },
    },
    opts,
  );

  const admin = await store.listTasksForAdmin({ elderId: "e", ...opts });
  assert.equal(admin.length, 1);
  assert.equal(admin[0].submissionCount, 2);
  assert.ok(admin[0].latestSubmission);
  assert.ok(admin[0].latestSubmission.verification);
});

// ---- CR-0034 B2 / CR-0042 blocker：production JSON-only guard ----
// 用 options.env 注入 production 語義（NODE_ENV=test 恆為 dev，不影響其他測試）。
const PROD = { env: { APP_ENV: "production" } };

test("production：createTask 拋具名錯誤、不寫檔", async () => {
  const opts = tempFiles();
  await assert.rejects(
    () => store.createTask({ title: "吃藥", type: "medication" }, { ...opts, ...PROD }),
    /feature_unavailable_in_production/,
  );
  assert.equal(fs.existsSync(opts.tasksFilePath), false);
});

test("production：read 類函式一律拋具名錯誤", async () => {
  const opts = tempFiles();
  await assert.rejects(
    () => store.listTasks({ ...opts, ...PROD }),
    /feature_unavailable_in_production/,
  );
  await assert.rejects(
    () => store.getTaskById("x", { ...opts, ...PROD }),
    /feature_unavailable_in_production/,
  );
  await assert.rejects(
    () => store.recordSubmission("x", {}, { ...opts, ...PROD }),
    /feature_unavailable_in_production/,
  );
  await assert.rejects(
    () => store.getSubmissionById("x", { ...opts, ...PROD }),
    /feature_unavailable_in_production/,
  );
  await assert.rejects(
    () => store.listTasksForAdmin({ ...opts, ...PROD }),
    /feature_unavailable_in_production/,
  );
});

test("production：updateTaskStatus 回 feature_unavailable_in_production envelope", async () => {
  const opts = tempFiles();
  const r = await store.updateTaskStatus("x", "completed", { ...opts, ...PROD });
  assert.deepEqual(r, { success: false, error: "feature_unavailable_in_production" });
});
