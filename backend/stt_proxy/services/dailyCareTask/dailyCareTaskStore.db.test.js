// CR-0068：dailyCareTaskStore DB 路徑單測（mock pg，不需實連 DB）。
//
// 驗：task / submission DB 路徑的 SQL / 欄位映射（snake_case row → camelCase 對外形狀）、
// recordSubmission 交易序列（BEGIN→SELECT FOR UPDATE→INSERT submission→UPDATE task→COMMIT）、
// task_not_found 會 ROLLBACK、回傳形狀與 JSON 路徑一致、production DB 例外不降級 JSON。

const assert = require("node:assert/strict");
const test = require("node:test");

const store = require("./dailyCareTaskStore");

// mock pg：available 控制 isPostgresAvailable；rowsFor 可為固定 rows 或
// (text,params)=>rows；throwOn(text,params) 回 true 時該次 query 拋例外。
// 不提供 getPool → recordSubmissionDb 走 pg.query 序列（可驗 BEGIN/COMMIT/ROLLBACK）。
function makeMockPg({ available = true, rowsFor = [], throwOn = null } = {}) {
  const calls = [];
  return {
    calls,
    isPostgresAvailable: async () => available,
    query: async (text, params) => {
      calls.push({ text, params });
      if (throwOn && throwOn(text, params)) {
        throw new Error("mock db failure");
      }
      const rows = typeof rowsFor === "function" ? rowsFor(text, params) : rowsFor;
      return { rows: rows || [] };
    },
  };
}

const prodEnv = { APP_ENV: "production" };

function taskRow(overrides = {}) {
  return {
    id: "t1",
    elder_id: "e1",
    title: "早上吃藥",
    type: "medication",
    description: "飯後一顆",
    scheduled_time: "08:00",
    due_at: null,
    status: "pending",
    proof_required: true,
    created_at: new Date("2026-06-05T08:00:00.000Z"),
    updated_at: new Date("2026-06-05T08:00:00.000Z"),
    ...overrides,
  };
}

// ---- createTask（DB 路徑）----

test("createTask DB：INSERT 欄位映射、回正規化 task（camelCase）", async () => {
  const pg = makeMockPg({ available: true, rowsFor: [] });
  const r = await store.createTask(
    { elderId: "e1", title: "吃藥", type: "walk", scheduledTime: "08:00" },
    { pg },
  );
  assert.ok(r.id);
  assert.equal(r.elderId, "e1");
  assert.equal(r.type, "exercise"); // walk → exercise
  assert.equal(r.status, "pending");
  assert.equal(r.proofRequired, true);

  const { text, params } = pg.calls[0];
  assert.match(text, /INSERT INTO daily_care_tasks/);
  assert.equal(params[0], r.id);
  assert.equal(params[1], "e1"); // elder_id
  assert.equal(params[3], "exercise"); // type
});

// ---- listTasks（DB 路徑）----

test("listTasks DB：elderId / status 過濾、ORDER BY scheduled_time、row→task 映射", async () => {
  const pg = makeMockPg({ available: true, rowsFor: [taskRow()] });
  const list = await store.listTasks({ pg, elderId: "e1", status: "pending" });
  assert.equal(list.length, 1);
  const t = list[0];
  assert.equal(t.id, "t1");
  assert.equal(t.elderId, "e1");
  assert.equal(t.scheduledTime, "08:00");
  assert.equal(t.createdAt, "2026-06-05T08:00:00.000Z"); // Date → ISO
  // 回傳形狀（key 集合）需與 JSON 路徑 normalizeTask 一致。
  assert.deepEqual(
    Object.keys(t).sort(),
    Object.keys(store.normalizeTask({ title: "x" })).sort(),
  );

  const { text, params } = pg.calls[0];
  assert.match(text, /SELECT \* FROM daily_care_tasks/);
  assert.match(text, /elder_id = \$1/);
  assert.match(text, /status = \$2/);
  assert.match(text, /ORDER BY NULLIF\(scheduled_time/);
  assert.equal(params[0], "e1");
  assert.equal(params[1], "pending");
});

// ---- getTaskById（DB 路徑）----

test("getTaskById DB：找到映射、找不到回 null", async () => {
  const found = makeMockPg({ available: true, rowsFor: [taskRow()] });
  const t = await store.getTaskById("t1", { pg: found });
  assert.equal(t.id, "t1");
  assert.match(found.calls[0].text, /WHERE id = \$1/);

  const missing = makeMockPg({ available: true, rowsFor: [] });
  assert.equal(await store.getTaskById("nope", { pg: missing }), null);
});

// ---- updateTaskStatus（DB 路徑）----

test("updateTaskStatus DB：UPDATE RETURNING；invalid_status 不打 DB；not_found", async () => {
  const pg = makeMockPg({
    available: true,
    rowsFor: [taskRow({ status: "completed" })],
  });
  const r = await store.updateTaskStatus("t1", "completed", { pg });
  assert.equal(r.success, true);
  assert.equal(r.task.status, "completed");
  assert.match(pg.calls[0].text, /UPDATE daily_care_tasks SET status = \$2/);

  const bad = makeMockPg({ available: true });
  const r2 = await store.updateTaskStatus("t1", "weird", { pg: bad });
  assert.deepEqual(r2, { success: false, error: "invalid_status" });
  assert.equal(bad.calls.length, 0);

  const missing = makeMockPg({ available: true, rowsFor: [] });
  const nf = await store.updateTaskStatus("nope", "completed", { pg: missing });
  assert.deepEqual(nf, { success: false, error: "not_found" });
});

// ---- recordSubmission（DB 交易路徑）----

function submitTxRows(taskRowValue) {
  return (text) => {
    if (/SELECT \* FROM daily_care_tasks WHERE id = \$1 FOR UPDATE/.test(text)) {
      return taskRowValue ? [taskRowValue] : [];
    }
    if (/UPDATE daily_care_tasks SET status/.test(text)) {
      return [taskRowValue ? { ...taskRowValue, status: "completed" } : taskRow()];
    }
    return [];
  };
}

test("recordSubmission DB：交易序列 BEGIN→SELECT FOR UPDATE→INSERT→UPDATE→COMMIT；passed→completed", async () => {
  const pg = makeMockPg({ available: true, rowsFor: submitTxRows(taskRow()) });
  const r = await store.recordSubmission(
    "t1",
    {
      proofImagePath: "/tmp/fake.jpg",
      verification: {
        verificationStatus: "passed",
        confidence: 0.9,
        detectedObjects: ["藥盒"],
      },
    },
    { pg },
  );
  assert.equal(r.success, true);
  assert.equal(r.task.status, "completed");
  assert.equal(r.submission.status, "completed");
  assert.equal(r.submission.verification.verificationStatus, "passed");
  assert.equal(r.submission.taskId, "t1");

  const texts = pg.calls.map((c) => c.text.trim());
  assert.equal(texts[0], "BEGIN");
  assert.match(pg.calls[1].text, /SELECT \* FROM daily_care_tasks WHERE id = \$1 FOR UPDATE/);
  assert.match(pg.calls[2].text, /INSERT INTO daily_care_task_submissions/);
  assert.match(pg.calls[3].text, /UPDATE daily_care_tasks SET status/);
  assert.equal(texts[texts.length - 1], "COMMIT");
});

test("recordSubmission DB：uncertain → needs_review", async () => {
  const pg = makeMockPg({
    available: true,
    rowsFor: (text) => {
      if (/SELECT \* FROM daily_care_tasks WHERE id = \$1 FOR UPDATE/.test(text)) {
        return [taskRow()];
      }
      if (/UPDATE daily_care_tasks SET status/.test(text)) {
        return [taskRow({ status: "needs_review" })];
      }
      return [];
    },
  });
  const r = await store.recordSubmission(
    "t1",
    { verification: { verificationStatus: "uncertain", confidence: 0.3 } },
    { pg },
  );
  assert.equal(r.task.status, "needs_review");
  assert.equal(r.submission.verification.reviewRequired, true);
});

test("recordSubmission DB：任務不存在 → ROLLBACK + task_not_found（不 INSERT）", async () => {
  const pg = makeMockPg({ available: true, rowsFor: submitTxRows(null) });
  const r = await store.recordSubmission("nope", { verification: {} }, { pg });
  assert.deepEqual(r, { success: false, error: "task_not_found" });
  const texts = pg.calls.map((c) => c.text.trim());
  assert.ok(texts.includes("ROLLBACK"));
  assert.ok(!texts.includes("COMMIT"));
  assert.ok(!pg.calls.some((c) => /INSERT INTO daily_care_task_submissions/.test(c.text)));
});

// ---- listSubmissionsByTaskId / getSubmissionById（DB 路徑）----

function submissionRow(overrides = {}) {
  return {
    id: "s1",
    task_id: "t1",
    elder_id: "e1",
    proof_image_path: "/tmp/p.jpg",
    submitted_at: new Date("2026-06-05T09:00:00.000Z"),
    status: "completed",
    verification_json: {
      verificationStatus: "passed",
      confidence: 0.9,
      reason: "看起來有藥盒",
      detectedObjects: ["藥盒"],
      reviewRequired: false,
    },
    note: "",
    ...overrides,
  };
}

test("listSubmissionsByTaskId DB：row→submission 映射、verification_json 還原", async () => {
  const pg = makeMockPg({ available: true, rowsFor: [submissionRow()] });
  const list = await store.listSubmissionsByTaskId("t1", { pg });
  assert.equal(list.length, 1);
  assert.equal(list[0].id, "s1");
  assert.equal(list[0].taskId, "t1");
  assert.equal(list[0].submittedAt, "2026-06-05T09:00:00.000Z");
  assert.equal(list[0].verification.verificationStatus, "passed");
  assert.deepEqual(list[0].verification.detectedObjects, ["藥盒"]);
  assert.match(pg.calls[0].text, /WHERE task_id = \$1/);
});

test("getSubmissionById DB：verification_json 為字串也能解析；找不到回 null", async () => {
  const found = makeMockPg({
    available: true,
    rowsFor: [submissionRow({ verification_json: JSON.stringify(submissionRow().verification_json) })],
  });
  const s = await store.getSubmissionById("s1", { pg: found });
  assert.equal(s.id, "s1");
  assert.equal(s.verification.verificationStatus, "passed");

  const missing = makeMockPg({ available: true, rowsFor: [] });
  assert.equal(await store.getSubmissionById("nope", { pg: missing }), null);
});

// ---- listTasksForAdmin（DB 路徑）----

test("listTasksForAdmin DB：附最新 submission + submissionCount", async () => {
  const pg = makeMockPg({
    available: true,
    rowsFor: (text) => {
      if (/SELECT \* FROM daily_care_tasks/.test(text)) return [taskRow()];
      if (/SELECT \* FROM daily_care_task_submissions WHERE task_id = ANY/.test(text)) {
        return [
          submissionRow({ id: "s2", submitted_at: new Date("2026-06-05T10:00:00.000Z") }),
          submissionRow({ id: "s1", submitted_at: new Date("2026-06-05T09:00:00.000Z") }),
        ];
      }
      return [];
    },
  });
  const admin = await store.listTasksForAdmin({ pg, elderId: "e1" });
  assert.equal(admin.length, 1);
  assert.equal(admin[0].submissionCount, 2);
  assert.ok(admin[0].latestSubmission);
  assert.equal(admin[0].latestSubmission.id, "s2"); // 最新（submitted_at DESC 第一筆）
});

// ---- production DB 例外（不降級 JSON）----

test("createTask：production DB 例外 → throw（不降級 JSON）", async () => {
  const pg = makeMockPg({ available: true, throwOn: () => true });
  await assert.rejects(
    () => store.createTask({ title: "吃藥" }, { pg, env: prodEnv }),
    (err) => {
      assert.ok(!/feature_unavailable_in_production/.test(err.message || ""));
      return true;
    },
  );
});

test("updateTaskStatus：production DB 例外 → write_failed（不降級 JSON）", async () => {
  const pg = makeMockPg({ available: true, throwOn: () => true });
  const r = await store.updateTaskStatus("t1", "completed", { pg, env: prodEnv });
  assert.deepEqual(r, { success: false, error: "write_failed" });
});

test("recordSubmission：production DB 例外 → ROLLBACK 後 throw（不降級 JSON）", async () => {
  const pg = makeMockPg({
    available: true,
    throwOn: (text) => /INSERT INTO daily_care_task_submissions/.test(text),
    rowsFor: submitTxRows(taskRow()),
  });
  await assert.rejects(
    () => store.recordSubmission("t1", { verification: {} }, { pg, env: prodEnv }),
    /mock db failure/,
  );
  assert.ok(pg.calls.map((c) => c.text.trim()).includes("ROLLBACK"));
});
