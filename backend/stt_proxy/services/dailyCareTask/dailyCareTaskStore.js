// CR-0025 日常照護任務（Daily Care Task）持久化 store。
//
// 與既有「遊戲化 CareTask（金幣/親密度）」**完全不同的功能**，刻意用 daily care
// task 命名隔離。長者完成吃藥 / 喝水 / 運動任務後拍照上傳，AI Vision 確認後更新
// 任務狀態，管理者端可查看。
//
// 持久化策略（CR-0068 JSON→PostgreSQL 平移；比照 marketplaceStore / careAlertStoreService）：
//   - **DB-優先**：isPostgresAvailable()（要求 DATABASE_URL + PGVECTOR_ENABLED=true）為 true
//     → 走 PostgreSQL（migration 016 建 daily_care_tasks / daily_care_task_submissions 兩表）。
//   - **dev/staging（isJsonFallbackAllowed=true）且無 DB** → 走既有 data/*.json store
//     （行為零變更，保住所有現有測試與無 DB 的 Demo 機）。
//   - **production（ALLOW_JSON_FALLBACK=false）且無 DB** → 防禦性停用：read 類 throw
//     FeatureUnavailableInProductionError、envelope 類回 feature_unavailable_in_production
//     （不把 JSON 當正式資料來源）。實務上 production 一定設好 DB，此分支僅為安全網。
//   - **DB 例外**：production 不降級 JSON（read 類 throw→route 處理；envelope 類回 write_failed）；
//     dev/staging 降級 JSON。
//
// 對外函式的簽名 / 回傳形狀（camelCase）/ error 碼一律不可變：DB row（snake_case）由
// rowToTask / rowToSubmission 映射回既有 camelCase 形狀，App / caregiver_web 契約不變。
// data/*.json 皆屬 runtime data，不進版控。

const path = require("path");
const fs = require("fs/promises");
const { randomUUID } = require("crypto");

const defaultPg = require("../../db/postgres");
const {
  isJsonFallbackAllowed,
  FeatureUnavailableInProductionError,
  FEATURE_UNAVAILABLE_IN_PRODUCTION,
} = require("../../config/env");

// 注入用的 pg（預設真 postgres，測試以 setPgForTest 換 mock）。
let activePg = defaultPg;

// 測試專用：注入 / 還原 pg。mock pg 需提供：
//   - query(text, params) → { rows }
//   - isPostgresAvailable() → boolean（決定走 DB 或 JSON）
//   - （選用）getPool() → { connect() }，提供時 recordSubmission 走單一 client 交易
function setPgForTest(pg) {
  activePg = pg || defaultPg;
}

// 是否走 DB。缺 isPostgresAvailable（或拋例外）一律視為不可用 → JSON 路徑。
async function isDbAvailable(pg) {
  if (!pg || typeof pg.isPostgresAvailable !== "function") return false;
  try {
    return await pg.isPostgresAvailable();
  } catch (_error) {
    return false;
  }
}

// DB 例外只記結構化 log（不含任務 / 照片 / 對話原文）；僅 op 與 error.message。
function logDbError(op, error) {
  console.error(`[daily-care-task-store] DB ${op} failed`, {
    error: error?.message || String(error),
  });
}

const DEFAULT_TASKS_FILE = path.join(
  __dirname,
  "..",
  "..",
  "data",
  "daily_care_tasks.json",
);
const DEFAULT_SUBMISSIONS_FILE = path.join(
  __dirname,
  "..",
  "..",
  "data",
  "daily_care_task_submissions.json",
);

// 任務類型：吃藥 / 喝水 / 運動（walk 視為 exercise 的同義）。
const VALID_TASK_TYPES = new Set(["medication", "hydration", "exercise"]);
// 任務狀態機。
const VALID_TASK_STATUSES = new Set([
  "pending",
  "submitted",
  "completed",
  "needs_review",
  "rejected",
  "missed",
]);
// AI 影像驗證狀態。
const VALID_VERIFICATION_STATUSES = new Set(["passed", "uncertain", "failed"]);

function resolveTasksFile(options = {}) {
  return (
    options.tasksFilePath ||
    process.env.DAILY_CARE_TASKS_DATA_FILE ||
    DEFAULT_TASKS_FILE
  );
}

function resolveSubmissionsFile(options = {}) {
  return (
    options.submissionsFilePath ||
    process.env.DAILY_CARE_TASK_SUBMISSIONS_DATA_FILE ||
    DEFAULT_SUBMISSIONS_FILE
  );
}

async function readAll(filePath) {
  try {
    const raw = await fs.readFile(filePath, "utf8");
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch (error) {
    if (error && error.code !== "ENOENT") {
      console.error("[daily-care-task-store] read failed, treating as empty", {
        error: error.message,
      });
    }
    return [];
  }
}

async function writeAll(filePath, rows) {
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  await fs.writeFile(filePath, JSON.stringify(rows, null, 2), "utf8");
}

function normalizeType(type) {
  const raw = (type || "").toString().trim().toLowerCase();
  if (raw === "walk") return "exercise"; // 散步歸入運動。
  return VALID_TASK_TYPES.has(raw) ? raw : "medication";
}

function nowIso() {
  return new Date().toISOString();
}

// Date → ISO 字串（DB 取回 TIMESTAMPTZ 為 Date）；字串 / null 原樣回。
function toIso(value) {
  if (value == null) return null;
  if (value instanceof Date) return value.toISOString();
  return value;
}

function safeParseJson(value) {
  if (value == null) return {};
  if (typeof value !== "string") return value;
  try {
    return JSON.parse(value);
  } catch (_error) {
    return {};
  }
}

// 從外部 payload 萃取要保存的任務欄位，補上 id / 狀態 / 時間。
function normalizeTask(payload = {}) {
  const createdAt = nowIso();
  const status = VALID_TASK_STATUSES.has(payload.status)
    ? payload.status
    : "pending";
  return {
    id: payload.id || randomUUID(),
    elderId: payload.elderId ?? null,
    title: payload.title ?? "",
    type: normalizeType(payload.type),
    description: payload.description ?? "",
    scheduledTime: payload.scheduledTime ?? "", // "HH:mm" 顯示用。
    dueAt: payload.dueAt ?? null, // ISO，逾時判斷用。
    status,
    // 預設需要照片證明（吃藥/喝水/運動都要拍照）。
    proofRequired: payload.proofRequired !== false,
    createdAt,
    updatedAt: createdAt,
  };
}

// DB row（snake_case）→ 對外 task 形狀（camelCase，與 normalizeTask 一致）。
function rowToTask(row) {
  return {
    id: row.id,
    elderId: row.elder_id ?? null,
    title: row.title ?? "",
    type: normalizeType(row.type),
    description: row.description ?? "",
    scheduledTime: row.scheduled_time ?? "",
    dueAt: toIso(row.due_at),
    status: VALID_TASK_STATUSES.has(row.status) ? row.status : "pending",
    proofRequired: row.proof_required != null ? Boolean(row.proof_required) : true,
    createdAt: toIso(row.created_at),
    updatedAt: toIso(row.updated_at),
  };
}

// DB row（snake_case）→ 對外 submission 形狀（camelCase）。
function rowToSubmission(row) {
  return {
    id: row.id,
    taskId: row.task_id,
    elderId: row.elder_id ?? null,
    proofImagePath: row.proof_image_path ?? null,
    submittedAt: toIso(row.submitted_at),
    status: row.status ?? "needs_review",
    verification: normalizeVerification(safeParseJson(row.verification_json)),
    note: row.note ?? "",
  };
}

// 把 AI 驗證結果（passed/uncertain/failed）對應到任務狀態。
// 只有 passed 才自動完成；uncertain / failed 一律送人工查看（避免誤判，也避免
// 假裝 AI 已確認）。
function taskStatusForVerification(verificationStatus) {
  switch (verificationStatus) {
    case "passed":
      return "completed";
    case "failed":
    case "uncertain":
    default:
      return "needs_review";
  }
}

function normalizeVerification(verification = {}) {
  const status = VALID_VERIFICATION_STATUSES.has(verification.verificationStatus)
    ? verification.verificationStatus
    : "uncertain";
  const confidence = Number(verification.confidence);
  return {
    verificationStatus: status,
    confidence: Number.isFinite(confidence) ? confidence : 0,
    reason: verification.reason ?? "",
    detectedObjects: Array.isArray(verification.detectedObjects)
      ? verification.detectedObjects
      : [],
    reviewRequired:
      verification.reviewRequired != null
        ? Boolean(verification.reviewRequired)
        : status !== "passed",
  };
}

// ===================================================================
// JSON 路徑（dev/staging fallback；不含 production 阻擋，由 wrapper 控制）
// ===================================================================

async function createTaskJson(payload, options) {
  const filePath = resolveTasksFile(options);
  const task = normalizeTask(payload);
  const tasks = await readAll(filePath);
  tasks.push(task);
  await writeAll(filePath, tasks);
  return task;
}

async function listTasksJson(options) {
  const filePath = resolveTasksFile(options);
  let tasks = await readAll(filePath);
  if (options.elderId != null) {
    tasks = tasks.filter((t) => t.elderId === options.elderId);
  }
  if (options.status) {
    tasks = tasks.filter((t) => t.status === options.status);
  }
  // 依預定時間排序（空字串排後面），穩定顯示。
  return [...tasks].sort((a, b) =>
    String(a.scheduledTime || "~").localeCompare(String(b.scheduledTime || "~")),
  );
}

async function getTaskByIdJson(id, options) {
  const filePath = resolveTasksFile(options);
  const tasks = await readAll(filePath);
  return tasks.find((t) => t.id === id) || null;
}

async function updateTaskStatusJson(id, status, options) {
  const filePath = resolveTasksFile(options);
  const tasks = await readAll(filePath);
  const index = tasks.findIndex((t) => t.id === id);
  if (index === -1) {
    return { success: false, error: "not_found" };
  }
  tasks[index] = { ...tasks[index], status, updatedAt: nowIso() };
  await writeAll(filePath, tasks);
  return { success: true, task: tasks[index] };
}

async function recordSubmissionJson(taskId, payload, options) {
  const task = await getTaskByIdJson(taskId, options);
  if (!task) {
    return { success: false, error: "task_not_found" };
  }

  const verification = normalizeVerification(payload.verification);
  const nextTaskStatus = taskStatusForVerification(verification.verificationStatus);

  const submission = {
    id: payload.id || randomUUID(),
    taskId,
    elderId: task.elderId,
    proofImagePath: payload.proofImagePath ?? null,
    submittedAt: nowIso(),
    status: nextTaskStatus,
    verification,
    note: payload.note ?? "",
  };

  const submissionsFile = resolveSubmissionsFile(options);
  const submissions = await readAll(submissionsFile);
  submissions.push(submission);
  await writeAll(submissionsFile, submissions);

  await updateTaskStatusJson(taskId, nextTaskStatus, options);
  const updatedTask = await getTaskByIdJson(taskId, options);

  return { success: true, task: updatedTask, submission };
}

async function listSubmissionsByTaskIdJson(taskId, options) {
  const submissionsFile = resolveSubmissionsFile(options);
  const submissions = await readAll(submissionsFile);
  return submissions.filter((s) => s.taskId === taskId);
}

async function getSubmissionByIdJson(submissionId, options) {
  const submissionsFile = resolveSubmissionsFile(options);
  const submissions = await readAll(submissionsFile);
  return submissions.find((s) => s.id === submissionId) || null;
}

async function listTasksForAdminJson(options) {
  const tasks = await listTasksJson(options);
  const submissionsFile = resolveSubmissionsFile(options);
  const submissions = await readAll(submissionsFile);

  return tasks.map((task) => {
    const taskSubs = submissions
      .filter((s) => s.taskId === task.id)
      .sort((a, b) =>
        String(b.submittedAt).localeCompare(String(a.submittedAt)),
      );
    const latest = taskSubs[0] || null;
    return {
      ...task,
      latestSubmission: latest,
      submissionCount: taskSubs.length,
    };
  });
}

// ===================================================================
// DB 路徑（PostgreSQL；migration 016）
// ===================================================================

async function createTaskDb(pg, payload) {
  const task = normalizeTask(payload);
  await pg.query(
    `INSERT INTO daily_care_tasks
       (id, elder_id, title, type, description, scheduled_time, due_at,
        status, proof_required, created_at, updated_at)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)`,
    [
      task.id,
      task.elderId,
      task.title,
      task.type,
      task.description,
      task.scheduledTime,
      task.dueAt,
      task.status,
      task.proofRequired,
      task.createdAt,
      task.updatedAt,
    ],
  );
  return task;
}

async function listTasksDb(pg, options) {
  const where = [];
  const params = [];
  if (options.elderId != null) {
    params.push(options.elderId);
    where.push(`elder_id = $${params.length}`);
  }
  if (options.status) {
    params.push(options.status);
    where.push(`status = $${params.length}`);
  }
  let sql = `SELECT * FROM daily_care_tasks`;
  if (where.length > 0) sql += ` WHERE ${where.join(" AND ")}`;
  // 依預定時間排序（空字串 / NULL 排後面），created_at 為穩定 tiebreak。
  sql += ` ORDER BY NULLIF(scheduled_time, '') ASC NULLS LAST, created_at ASC`;
  const result = await pg.query(sql, params);
  return (result.rows || []).map(rowToTask);
}

async function getTaskByIdDb(pg, id) {
  const result = await pg.query(
    `SELECT * FROM daily_care_tasks WHERE id = $1`,
    [id],
  );
  const row = (result.rows || [])[0];
  return row ? rowToTask(row) : null;
}

async function updateTaskStatusDb(pg, id, status) {
  const result = await pg.query(
    `UPDATE daily_care_tasks SET status = $2, updated_at = NOW()
     WHERE id = $1 RETURNING *`,
    [id, status],
  );
  const row = (result.rows || [])[0];
  if (!row) return { success: false, error: "not_found" };
  return { success: true, task: rowToTask(row) };
}

// 單一 transaction：鎖任務列驗證存在 → INSERT submission → UPDATE 任務狀態 → COMMIT。
// 真 pool（有 getPool）以單一 client 跑交易；mock pg（僅 query）以 query 序列驗證。
async function recordSubmissionDb(pg, taskId, payload) {
  const pool = typeof pg.getPool === "function" ? pg.getPool() : null;
  const client = pool ? await pool.connect() : null;
  const run = client ? (t, p) => client.query(t, p) : (t, p) => pg.query(t, p);
  let began = false;
  try {
    await run("BEGIN");
    began = true;

    const sel = await run(
      `SELECT * FROM daily_care_tasks WHERE id = $1 FOR UPDATE`,
      [taskId],
    );
    const taskRow = (sel.rows || [])[0];
    if (!taskRow) {
      await run("ROLLBACK");
      return { success: false, error: "task_not_found" };
    }

    const verification = normalizeVerification(payload.verification);
    const nextTaskStatus = taskStatusForVerification(
      verification.verificationStatus,
    );
    const submissionId = payload.id || randomUUID();
    const submittedAt = nowIso();
    const elderId = taskRow.elder_id ?? null;

    await run(
      `INSERT INTO daily_care_task_submissions
         (id, task_id, elder_id, proof_image_path, submitted_at, status, verification_json, note)
       VALUES ($1,$2,$3,$4,$5,$6,$7::jsonb,$8)`,
      [
        submissionId,
        taskId,
        elderId,
        payload.proofImagePath ?? null,
        submittedAt,
        nextTaskStatus,
        JSON.stringify(verification),
        payload.note ?? "",
      ],
    );

    const upd = await run(
      `UPDATE daily_care_tasks SET status = $2, updated_at = NOW()
       WHERE id = $1 RETURNING *`,
      [taskId, nextTaskStatus],
    );

    await run("COMMIT");

    const updatedTask = rowToTask((upd.rows || [])[0]);
    const submission = {
      id: submissionId,
      taskId,
      elderId,
      proofImagePath: payload.proofImagePath ?? null,
      submittedAt,
      status: nextTaskStatus,
      verification,
      note: payload.note ?? "",
    };
    return { success: true, task: updatedTask, submission };
  } catch (error) {
    if (began) {
      try {
        await run("ROLLBACK");
      } catch (_rollbackError) {
        // ROLLBACK 失敗只忽略（連線可能已壞），原始錯誤往上拋。
      }
    }
    throw error;
  } finally {
    if (client && typeof client.release === "function") client.release();
  }
}

async function listSubmissionsByTaskIdDb(pg, taskId) {
  const result = await pg.query(
    `SELECT * FROM daily_care_task_submissions WHERE task_id = $1
     ORDER BY submitted_at DESC`,
    [taskId],
  );
  return (result.rows || []).map(rowToSubmission);
}

async function getSubmissionByIdDb(pg, submissionId) {
  const result = await pg.query(
    `SELECT * FROM daily_care_task_submissions WHERE id = $1`,
    [submissionId],
  );
  const row = (result.rows || [])[0];
  return row ? rowToSubmission(row) : null;
}

async function listTasksForAdminDb(pg, options) {
  const tasks = await listTasksDb(pg, options);
  if (tasks.length === 0) return [];
  const ids = tasks.map((t) => t.id);
  const result = await pg.query(
    `SELECT * FROM daily_care_task_submissions WHERE task_id = ANY($1)
     ORDER BY submitted_at DESC`,
    [ids],
  );
  const byTask = new Map();
  for (const row of result.rows || []) {
    const sub = rowToSubmission(row);
    if (!byTask.has(sub.taskId)) byTask.set(sub.taskId, []);
    byTask.get(sub.taskId).push(sub);
  }
  return tasks.map((task) => {
    const subs = byTask.get(task.id) || [];
    return {
      ...task,
      latestSubmission: subs[0] || null,
      submissionCount: subs.length,
    };
  });
}

// ===================================================================
// 對外 wrapper（DB-優先 + JSON 降級 + production 防禦停用）
// ===================================================================

async function createTask(payload = {}, options = {}) {
  const pg = options.pg || activePg;
  const fallbackAllowed = isJsonFallbackAllowed(options.env || process.env);
  if (await isDbAvailable(pg)) {
    try {
      return await createTaskDb(pg, payload);
    } catch (error) {
      logDbError("createTask", error);
      if (!fallbackAllowed) throw error;
    }
  } else if (!fallbackAllowed) {
    throw new FeatureUnavailableInProductionError();
  }
  return createTaskJson(payload, options);
}

async function listTasks(options = {}) {
  const pg = options.pg || activePg;
  const fallbackAllowed = isJsonFallbackAllowed(options.env || process.env);
  if (await isDbAvailable(pg)) {
    try {
      return await listTasksDb(pg, options);
    } catch (error) {
      logDbError("listTasks", error);
      if (!fallbackAllowed) throw error;
    }
  } else if (!fallbackAllowed) {
    throw new FeatureUnavailableInProductionError();
  }
  return listTasksJson(options);
}

async function getTaskById(id, options = {}) {
  const pg = options.pg || activePg;
  const fallbackAllowed = isJsonFallbackAllowed(options.env || process.env);
  if (await isDbAvailable(pg)) {
    try {
      return await getTaskByIdDb(pg, id);
    } catch (error) {
      logDbError("getTaskById", error);
      if (!fallbackAllowed) throw error;
    }
  } else if (!fallbackAllowed) {
    throw new FeatureUnavailableInProductionError();
  }
  return getTaskByIdJson(id, options);
}

async function updateTaskStatus(id, status, options = {}) {
  if (!VALID_TASK_STATUSES.has(status)) {
    return { success: false, error: "invalid_status" };
  }
  const pg = options.pg || activePg;
  const fallbackAllowed = isJsonFallbackAllowed(options.env || process.env);
  if (await isDbAvailable(pg)) {
    try {
      return await updateTaskStatusDb(pg, id, status);
    } catch (error) {
      logDbError("updateTaskStatus", error);
      if (!fallbackAllowed) return { success: false, error: "write_failed" };
    }
  } else if (!fallbackAllowed) {
    return { success: false, error: FEATURE_UNAVAILABLE_IN_PRODUCTION };
  }
  return updateTaskStatusJson(id, status, options);
}

async function recordSubmission(taskId, payload = {}, options = {}) {
  const pg = options.pg || activePg;
  const fallbackAllowed = isJsonFallbackAllowed(options.env || process.env);
  if (await isDbAvailable(pg)) {
    try {
      return await recordSubmissionDb(pg, taskId, payload);
    } catch (error) {
      logDbError("recordSubmission", error);
      if (!fallbackAllowed) throw error;
    }
  } else if (!fallbackAllowed) {
    throw new FeatureUnavailableInProductionError();
  }
  return recordSubmissionJson(taskId, payload, options);
}

async function listSubmissionsByTaskId(taskId, options = {}) {
  const pg = options.pg || activePg;
  const fallbackAllowed = isJsonFallbackAllowed(options.env || process.env);
  if (await isDbAvailable(pg)) {
    try {
      return await listSubmissionsByTaskIdDb(pg, taskId);
    } catch (error) {
      logDbError("listSubmissionsByTaskId", error);
      if (!fallbackAllowed) throw error;
    }
  } else if (!fallbackAllowed) {
    throw new FeatureUnavailableInProductionError();
  }
  return listSubmissionsByTaskIdJson(taskId, options);
}

async function getSubmissionById(submissionId, options = {}) {
  const pg = options.pg || activePg;
  const fallbackAllowed = isJsonFallbackAllowed(options.env || process.env);
  if (await isDbAvailable(pg)) {
    try {
      return await getSubmissionByIdDb(pg, submissionId);
    } catch (error) {
      logDbError("getSubmissionById", error);
      if (!fallbackAllowed) throw error;
    }
  } else if (!fallbackAllowed) {
    throw new FeatureUnavailableInProductionError();
  }
  return getSubmissionByIdJson(submissionId, options);
}

async function listTasksForAdmin(options = {}) {
  const pg = options.pg || activePg;
  const fallbackAllowed = isJsonFallbackAllowed(options.env || process.env);
  if (await isDbAvailable(pg)) {
    try {
      return await listTasksForAdminDb(pg, options);
    } catch (error) {
      logDbError("listTasksForAdmin", error);
      if (!fallbackAllowed) throw error;
    }
  } else if (!fallbackAllowed) {
    throw new FeatureUnavailableInProductionError();
  }
  return listTasksForAdminJson(options);
}

module.exports = {
  createTask,
  listTasks,
  getTaskById,
  updateTaskStatus,
  recordSubmission,
  listSubmissionsByTaskId,
  getSubmissionById,
  listTasksForAdmin,
  normalizeTask,
  normalizeVerification,
  taskStatusForVerification,
  VALID_TASK_TYPES,
  VALID_TASK_STATUSES,
  VALID_VERIFICATION_STATUSES,
  // 測試 / 工具用：注入 mock pg。
  setPgForTest,
};
