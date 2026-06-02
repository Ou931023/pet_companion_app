// CR-0025 日常照護任務（Daily Care Task）持久化 store。
//
// 與既有「遊戲化 CareTask（金幣/親密度）」**完全不同的功能**，刻意用 daily care
// task 命名隔離。長者完成吃藥 / 喝水 / 運動任務後拍照上傳，AI Vision 確認後更新
// 任務狀態，管理者端可查看。
//
// 沿用專案既有 data/*.json 檔案模式（careAlertStoreService 風格）：
// - data/daily_care_tasks.json、data/daily_care_task_submissions.json 屬 runtime
//   data，不進版控。
// - 讀失敗（含檔案不存在）視為空清單，不丟例外讓 server crash。
// - 測試以 options.tasksFilePath / submissionsFilePath 或 env 指向 temp 檔。

const path = require("path");
const fs = require("fs/promises");
const { randomUUID } = require("crypto");

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

async function createTask(payload = {}, options = {}) {
  const filePath = resolveTasksFile(options);
  const task = normalizeTask(payload);
  const tasks = await readAll(filePath);
  tasks.push(task);
  await writeAll(filePath, tasks);
  return task;
}

async function listTasks(options = {}) {
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

async function getTaskById(id, options = {}) {
  const filePath = resolveTasksFile(options);
  const tasks = await readAll(filePath);
  return tasks.find((t) => t.id === id) || null;
}

async function updateTaskStatus(id, status, options = {}) {
  if (!VALID_TASK_STATUSES.has(status)) {
    return { success: false, error: "invalid_status" };
  }
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

// 記錄一筆完成證明 submission，並依 AI 驗證結果更新對應任務狀態。
// 回傳 { success, task, submission }。
async function recordSubmission(taskId, payload = {}, options = {}) {
  const task = await getTaskById(taskId, options);
  if (!task) {
    return { success: false, error: "task_not_found" };
  }

  const verification = normalizeVerification(payload.verification);
  const nextTaskStatus = taskStatusForVerification(verification.verificationStatus);

  const submission = {
    id: payload.id || randomUUID(),
    taskId,
    elderId: task.elderId,
    // 安全本機路徑（runtime，不進版控）；可為 null（例如缺檔仍記錄）。
    proofImagePath: payload.proofImagePath ?? null,
    submittedAt: nowIso(),
    // submission 自身狀態跟著任務走（completed / needs_review）。
    status: nextTaskStatus,
    verification,
    note: payload.note ?? "",
  };

  const submissionsFile = resolveSubmissionsFile(options);
  const submissions = await readAll(submissionsFile);
  submissions.push(submission);
  await writeAll(submissionsFile, submissions);

  await updateTaskStatus(taskId, nextTaskStatus, options);
  const updatedTask = await getTaskById(taskId, options);

  return { success: true, task: updatedTask, submission };
}

async function listSubmissionsByTaskId(taskId, options = {}) {
  const submissionsFile = resolveSubmissionsFile(options);
  const submissions = await readAll(submissionsFile);
  return submissions.filter((s) => s.taskId === taskId);
}

async function getSubmissionById(submissionId, options = {}) {
  const submissionsFile = resolveSubmissionsFile(options);
  const submissions = await readAll(submissionsFile);
  return submissions.find((s) => s.id === submissionId) || null;
}

// 管理者端：列出所有任務，附上每筆任務「最新一次」的 submission（含 AI 結果）。
async function listTasksForAdmin(options = {}) {
  const tasks = await listTasks(options);
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
};
