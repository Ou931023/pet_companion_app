// 登入 session 核心邏輯（CR-0006 Batch 1）。
//
// 流程（契約見 PROJECT_ARCHITECTURE.md §10.2）：
//   輸入 { firebaseUid, idToken, email, displayName, provider, photoUrl }
//   1. 決定 authMode：
//      - firebaseAdmin.isConfigured() 為 true → 正式模式，驗 idToken；
//        token 無效 → 回 { success:false, error:'invalid_id_token' }（endpoint 轉 401）。
//        驗證成功則以 decoded.uid 為準（覆蓋傳入 firebaseUid）。
//      - 未 configured（或 AUTH_ALLOW_MOCK !== 'false'）→ mock 模式，採信傳入 firebaseUid。
//   2. upsert：已有該 firebase_uid → 回既有 userId/elderId（isNewUser=false）；
//      否則建立 elder + user，binding_status='pending'、
//      binding_deadline = now + BINDING_DEADLINE_DAYS（預設 60）。
//   3. 回 { success, userId, elderId, role, bindingStatus, bindingDeadline, isNewUser, authMode }。
//
// 儲存層：Postgres 優先、失敗 fallback JSON store（比照 services/memory/memoryStore.js）。
// JSON fallback 檔：data/users.json、data/elders.json（runtime、不進 git）。
// 測試可用 options.filePaths 或 env USERS_DATA_FILE / ELDERS_DATA_FILE 指向 temp 檔，
// 並可用 options.firebaseAdmin 注入 stub，達到「不需真 DB、不需真 Firebase 金鑰」即可單測。

const fs = require("fs/promises");
const path = require("path");
const { randomUUID } = require("crypto");

const postgres = require("../../db/postgres");
const defaultFirebaseAdmin = require("./firebaseAdmin");

const DEFAULT_USERS_FILE = path.join(__dirname, "..", "..", "data", "users.json");
const DEFAULT_ELDERS_FILE = path.join(__dirname, "..", "..", "data", "elders.json");

const VALID_PROVIDERS = new Set(["email", "google", "apple", "mock"]);
const DEFAULT_ROLE = "elder";
const DEFAULT_BINDING_STATUS = "pending";

function bindingDeadlineDays() {
  const parsed = Number(process.env.BINDING_DEADLINE_DAYS);
  if (!Number.isFinite(parsed) || parsed <= 0) return 60;
  return Math.trunc(parsed);
}

function resolveUsersFile(options = {}) {
  return (
    options.usersFilePath ||
    process.env.USERS_DATA_FILE ||
    DEFAULT_USERS_FILE
  );
}

function resolveEldersFile(options = {}) {
  return (
    options.eldersFilePath ||
    process.env.ELDERS_DATA_FILE ||
    DEFAULT_ELDERS_FILE
  );
}

// AUTH_ALLOW_MOCK 預設 true；只有顯式設成字串 "false" 才關閉 mock。
function mockAllowed() {
  return String(process.env.AUTH_ALLOW_MOCK ?? "true").toLowerCase() !== "false";
}

function normalizeProvider(provider) {
  const raw = (provider || "").toString().trim().toLowerCase();
  if (VALID_PROVIDERS.has(raw)) return raw;
  return "mock";
}

function nowIso() {
  return new Date().toISOString();
}

function deadlineIso() {
  const date = new Date();
  date.setDate(date.getDate() + bindingDeadlineDays());
  return date.toISOString();
}

// ---- JSON fallback 讀寫 ----

async function readJsonArray(filePath) {
  try {
    const raw = await fs.readFile(filePath, "utf8");
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch (error) {
    if (error && error.code !== "ENOENT") {
      console.error("[auth-store] read failed, treating as empty", {
        error: error.message,
      });
    }
    return [];
  }
}

async function writeJsonArray(filePath, rows) {
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  await fs.writeFile(filePath, JSON.stringify(rows, null, 2), "utf8");
}

// 把儲存層（DB row 或 JSON 物件）正規化成回傳形狀。
function toSessionResult(user, { isNewUser, authMode }) {
  return {
    success: true,
    userId: user.id,
    elderId: user.elder_id ?? user.elderId,
    role: user.role || DEFAULT_ROLE,
    bindingStatus: user.binding_status ?? user.bindingStatus ?? DEFAULT_BINDING_STATUS,
    bindingDeadline: user.binding_deadline ?? user.bindingDeadline ?? null,
    isNewUser,
    authMode,
  };
}

// ---- Postgres upsert ----

async function findUserByFirebaseUidPostgres(firebaseUid) {
  const result = await postgres.query(
    `SELECT id, elder_id, role, binding_status, binding_deadline
     FROM users
     WHERE firebase_uid = $1
     LIMIT 1`,
    [firebaseUid],
  );
  return result.rows[0] || null;
}

async function createUserPostgres(input) {
  const elderResult = await postgres.query(
    `INSERT INTO elders (display_name)
     VALUES ($1)
     RETURNING id`,
    [input.displayName || null],
  );
  const elderId = elderResult.rows[0].id;

  const userResult = await postgres.query(
    `INSERT INTO users (
       firebase_uid, elder_id, role, email, display_name,
       auth_provider, provider_user_id, binding_status, binding_deadline, updated_at
     ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9, NOW())
     RETURNING id, elder_id, role, binding_status, binding_deadline`,
    [
      input.firebaseUid,
      elderId,
      DEFAULT_ROLE,
      input.email || null,
      input.displayName || null,
      input.provider,
      input.providerUserId || null,
      DEFAULT_BINDING_STATUS,
      input.bindingDeadline,
    ],
  );
  return userResult.rows[0];
}

async function upsertPostgres(input, authMode) {
  const existing = await findUserByFirebaseUidPostgres(input.firebaseUid);
  if (existing) {
    return toSessionResult(existing, { isNewUser: false, authMode });
  }
  const created = await createUserPostgres(input);
  return toSessionResult(created, { isNewUser: true, authMode });
}

// ---- JSON upsert ----

async function upsertJson(input, authMode, options) {
  const usersFile = resolveUsersFile(options);
  const eldersFile = resolveEldersFile(options);

  const users = await readJsonArray(usersFile);
  const existing = users.find((u) => u.firebaseUid === input.firebaseUid);
  if (existing) {
    return toSessionResult(existing, { isNewUser: false, authMode });
  }

  const elders = await readJsonArray(eldersFile);
  const elderId = randomUUID();
  const createdAt = nowIso();
  elders.push({
    id: elderId,
    displayName: input.displayName || null,
    birthYear: null,
    gender: null,
    createdAt,
  });
  await writeJsonArray(eldersFile, elders);

  const user = {
    id: randomUUID(),
    firebaseUid: input.firebaseUid,
    elderId,
    role: DEFAULT_ROLE,
    email: input.email || null,
    emailVerified: false,
    displayName: input.displayName || null,
    authProvider: input.provider,
    providerUserId: input.providerUserId || null,
    bindingStatus: DEFAULT_BINDING_STATUS,
    bindingDeadline: input.bindingDeadline,
    createdAt,
    verifiedAt: null,
    updatedAt: createdAt,
  };
  users.push(user);
  await writeJsonArray(usersFile, users);

  return toSessionResult(user, { isNewUser: true, authMode });
}

// ---- 入口 ----

// 建立或取回登入 session。
// input: { firebaseUid, idToken, email, displayName, provider, photoUrl }
// options: { firebaseAdmin, usersFilePath, eldersFilePath }（皆為測試/注入用，可省略）
async function createSession(input = {}, options = {}) {
  const firebaseAdmin = options.firebaseAdmin || defaultFirebaseAdmin;

  const idToken = typeof input.idToken === "string" ? input.idToken.trim() : "";
  let firebaseUid =
    typeof input.firebaseUid === "string" ? input.firebaseUid.trim() : "";
  const provider = normalizeProvider(input.provider);

  // 缺必填：firebaseUid / idToken。
  if (!firebaseUid) {
    return { success: false, error: "missing_firebase_uid" };
  }
  if (!idToken) {
    return { success: false, error: "missing_id_token" };
  }

  // 決定 authMode：configured 走正式驗證；否則（且允許 mock）走 mock。
  let authMode;
  const configured = (() => {
    try {
      return firebaseAdmin.isConfigured();
    } catch (_) {
      return false;
    }
  })();

  if (configured) {
    const decoded = await firebaseAdmin.verifyIdToken(idToken);
    if (!decoded || !decoded.uid) {
      return { success: false, error: "invalid_id_token" };
    }
    // 以驗證後的 uid 為權威，避免 client 偽造 firebaseUid。
    firebaseUid = decoded.uid;
    authMode = "firebase";
  } else {
    if (!mockAllowed()) {
      // 未設定 Firebase 又強制關閉 mock：無法驗證，回 401 語義。
      return { success: false, error: "invalid_id_token" };
    }
    authMode = "mock";
  }

  const upsertInput = {
    firebaseUid,
    email: typeof input.email === "string" ? input.email.trim() || null : null,
    displayName:
      typeof input.displayName === "string"
        ? input.displayName.trim() || null
        : null,
    provider,
    providerUserId:
      typeof input.providerUserId === "string"
        ? input.providerUserId.trim() || null
        : null,
    bindingDeadline: deadlineIso(),
  };

  // Postgres 優先、失敗 fallback JSON（比照 memoryStore 模式）。
  if (await postgres.isPostgresAvailable()) {
    try {
      return await upsertPostgres(upsertInput, authMode);
    } catch (error) {
      console.error(
        "[auth-store] postgres upsert failed, falling back to json",
        error?.message || error,
      );
    }
  }
  return upsertJson(upsertInput, authMode, options);
}

// ---- 刪除帳號（CR-0024）----

async function deleteUserByFirebaseUidPostgres(firebaseUid) {
  const found = await postgres.query(
    `SELECT id, elder_id FROM users WHERE firebase_uid = $1 LIMIT 1`,
    [firebaseUid],
  );
  const row = found.rows[0];
  if (!row) {
    return { user: 0, elder: 0, userId: null, elderId: null };
  }
  const userId = row.id;
  const elderId = row.elder_id;
  const userDel = await postgres.query(`DELETE FROM users WHERE id = $1`, [userId]);
  let elderDel = { rowCount: 0 };
  if (elderId != null) {
    elderDel = await postgres.query(`DELETE FROM elders WHERE id = $1`, [elderId]);
  }
  return {
    user: userDel.rowCount,
    elder: elderDel.rowCount,
    userId,
    elderId,
  };
}

async function deleteUserByFirebaseUidJson(firebaseUid, options) {
  const usersFile = resolveUsersFile(options);
  const eldersFile = resolveEldersFile(options);

  const users = await readJsonArray(usersFile);
  const existing = users.find((u) => u.firebaseUid === firebaseUid);
  if (!existing) {
    return { user: 0, elder: 0, userId: null, elderId: null };
  }
  const userId = existing.id;
  const elderId = existing.elderId ?? existing.elder_id ?? null;

  const remainingUsers = users.filter((u) => u.firebaseUid !== firebaseUid);
  await writeJsonArray(usersFile, remainingUsers);

  let elderRemoved = 0;
  if (elderId != null) {
    const elders = await readJsonArray(eldersFile);
    const remainingElders = elders.filter((e) => e.id !== elderId);
    elderRemoved = elders.length - remainingElders.length;
    if (elderRemoved > 0) {
      await writeJsonArray(eldersFile, remainingElders);
    }
  }

  return {
    user: users.length - remainingUsers.length,
    elder: elderRemoved,
    userId,
    elderId,
  };
}

// 以 firebaseUid 刪除 user + 對應 elder（1:1）。
// 回傳 { user, elder, userId, elderId }（刪除筆數 + 被刪 user 的 id/elderId，
// 供呼叫端再去刪該 userId/elderId 的記憶與 Care Alert）。
// 找不到 → 全 0 / null（idempotent）。Postgres 優先、失敗 fallback JSON。
async function deleteUserByFirebaseUid(firebaseUid, options = {}) {
  const uid = typeof firebaseUid === "string" ? firebaseUid.trim() : "";
  if (!uid) return { user: 0, elder: 0, userId: null, elderId: null };

  if (await postgres.isPostgresAvailable()) {
    try {
      return await deleteUserByFirebaseUidPostgres(uid);
    } catch (error) {
      console.error(
        "[auth-store] postgres delete failed, falling back to json",
        error?.message || error,
      );
    }
  }
  return deleteUserByFirebaseUidJson(uid, options);
}

module.exports = {
  createSession,
  deleteUserByFirebaseUid,
  // 測試/工具用
  bindingDeadlineDays,
  mockAllowed,
  normalizeProvider,
};
