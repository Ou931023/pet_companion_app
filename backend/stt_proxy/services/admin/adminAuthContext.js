// CR-0041 D1：Admin / Caregiver 身分解析中介層（路線 A：Firebase idToken 當 bearer）。
//
// 契約見 docs/CHANGE_REVIEW.md CR-0041（§6 路線 A、§8 三層 middleware、§12 紅線）
// 與 docs/AUTHORIZATION_MODEL.md。
//
// 目的：讓「caregiver 身分」真正能經正式 HTTP 觸發並驅動既有 scope 過濾
// （authorizationService），同時保留 CR-0039 的 super_admin 共享 token 行為。
//
// 身分解析（fail-closed，絕不預設 super_admin）：
//   1. 無 Authorization bearer → 401 missing_admin_token（保留 CR-0039 契約）。
//   2. bearer 字面 === ADMIN_API_TOKEN（且 env 非空）→ super_admin（共享 token，行為零變更）。
//   3. 否則當 Firebase idToken：
//        - configured（真 Firebase 或注入 stub isConfigured()=true）→ verifyIdToken；
//          失敗 → 401 invalid_session。
//        - 未 configured：production 一律拒（mockAllowed()===false → 401）；
//          非 production 允許 mock，但仍須 verifyIdToken（stub）解析出 uid，否則 401。
//        - 取得 firebase_uid → 查 users row：
//            role='caregiver'        → caregiver（caregiverId = users.id，scope=assigned_residents）
//            role∈('admin','super_admin') → super_admin（DB-backed）
//            其他（elder / 查無 row）→ 403 admin_permission_required
//
// 紅線（§12）：不把所有登入者視為 super_admin；唯一 super_admin 來源 = 共享 token 字面相符，
//   或 DB role 明確為 admin/super_admin；不 hardcode caregiver id；production 不收假 token；
//   log 不印 token / email / 敏感資料。
//
// 測試 seam（比照 sessionService / authorizationService）：
//   - setFirebaseAdminForTest(stub)：注入 { isConfigured, verifyIdToken }，免真 Firebase 金鑰。
//   - setPgForTest(mockPg)：注入 users 查詢用 pg（query(text, params) → { rows }）。
//   - buildAuthContext(req, deps) 為純 async 函式，可直接單測（免起 HTTP server）。

"use strict";

const defaultPg = require("../../db/postgres");
const defaultFirebaseAdmin = require("../auth/firebaseAdmin");
const { mockAllowed } = require("../auth/sessionService");
const { extractBearerToken } = require("./requireAdmin");

const ROLE_SUPER_ADMIN = "super_admin";
const ROLE_CAREGIVER = "caregiver";

// super_admin authContext 形狀（共享 token 路徑與 DB role=admin/super_admin 共用）。
function superAdminContext(userId = null) {
  return { role: ROLE_SUPER_ADMIN, scope: "all", userId, caregiverId: null };
}

function caregiverContext(userId) {
  return {
    role: ROLE_CAREGIVER,
    scope: "assigned_residents",
    userId,
    caregiverId: userId,
  };
}

let activePg = defaultPg;
let activeFirebaseAdmin = defaultFirebaseAdmin;

// 測試專用：注入 / 還原 pg（users 查詢）。傳 null 還原預設。
function setPgForTest(pg) {
  activePg = pg || defaultPg;
}

// 測試專用：注入 / 還原 firebaseAdmin（isConfigured / verifyIdToken）。傳 null 還原預設。
function setFirebaseAdminForTest(stub) {
  activeFirebaseAdmin = stub || defaultFirebaseAdmin;
}

// 以 firebase_uid 查 users row（id, role）。pg 不可用 / 查無 → null（fail-closed 由上層轉 403）。
async function findUserByFirebaseUid(pg, firebaseUid) {
  if (!firebaseUid) return null;
  if (pg && typeof pg.isPostgresAvailable === "function") {
    let available = false;
    try {
      available = await pg.isPostgresAvailable();
    } catch (_error) {
      available = false;
    }
    if (!available) return null;
  }
  const { rows } = await pg.query(
    "SELECT id, role FROM users WHERE firebase_uid = $1 LIMIT 1",
    [firebaseUid],
  );
  return (rows && rows[0]) || null;
}

// 純 async 身分解析。回 { ok:true, authContext } 或 { ok:false, status, error }。
// deps（皆可選，預設取模組級 active*）：{ firebaseAdmin, pg, env }。
async function buildAuthContext(req, deps = {}) {
  const firebaseAdmin = deps.firebaseAdmin || activeFirebaseAdmin;
  const pg = deps.pg || activePg;
  const env = deps.env || process.env;

  const token = extractBearerToken(req && req.headers && req.headers.authorization);
  if (!token) {
    return { ok: false, status: 401, error: "missing_admin_token" };
  }

  // 1. 共享 super_admin token（字面相符且 env 非空）→ super_admin（CR-0039 行為零變更）。
  const expected = (env.ADMIN_API_TOKEN || "").toString();
  if (expected && token === expected) {
    return { ok: true, authContext: superAdminContext() };
  }

  // 2. 當作 Firebase idToken 解析 caregiver / DB-admin。
  let configured = false;
  try {
    configured = firebaseAdmin.isConfigured();
  } catch (_error) {
    configured = false;
  }

  let firebaseUid = null;
  if (configured) {
    const decoded = await firebaseAdmin.verifyIdToken(token);
    if (!decoded || !decoded.uid) {
      return { ok: false, status: 401, error: "invalid_session" };
    }
    firebaseUid = decoded.uid;
  } else {
    // 未 configured：production 一律關 mock（CR-0034 B2）→ 拒絕；非 production 才允許。
    if (!mockAllowed(env)) {
      return { ok: false, status: 401, error: "invalid_session" };
    }
    // mock 仍須由（stub）verifyIdToken 解析出 uid，且下面仍須查得真實 users row。
    const decoded = await firebaseAdmin.verifyIdToken(token);
    if (!decoded || !decoded.uid) {
      return { ok: false, status: 401, error: "invalid_session" };
    }
    firebaseUid = decoded.uid;
  }

  const user = await findUserByFirebaseUid(pg, firebaseUid);
  if (!user) {
    // 已驗證身分但非授權角色（或查無 / DB 不可用）→ 403（fail-closed，非 super_admin）。
    return { ok: false, status: 403, error: "admin_permission_required" };
  }
  const role = (user.role || "").toString();
  if (role === ROLE_CAREGIVER) {
    return { ok: true, authContext: caregiverContext(user.id) };
  }
  if (role === "admin" || role === ROLE_SUPER_ADMIN) {
    return { ok: true, authContext: superAdminContext(user.id) };
  }
  // elder / 其他角色：已驗證但無管理權限 → 403。
  return { ok: false, status: 403, error: "admin_permission_required" };
}

// Express 中介層：解析身分掛到 req.authContext，fail-closed（401/403）。
// 取代「caregiver-or-admin」路由的 requireAdmin（super_admin-only 路由續用 requireAdmin）。
function resolveAdminAuthContext(req, res, next) {
  Promise.resolve()
    .then(() => buildAuthContext(req))
    .then((result) => {
      if (!result.ok) {
        return res.status(result.status).json({ ok: false, error: result.error });
      }
      req.authContext = result.authContext;
      return next();
    })
    .catch((error) => {
      // 例外（DB 連線錯等）一律 fail-closed，絕不放行成 super_admin；log 不印 token。
      console.error("[admin-auth] resolve failed", {
        error: (error && error.message) || error,
      });
      return res.status(401).json({ ok: false, error: "invalid_session" });
    });
}

module.exports = {
  ROLE_SUPER_ADMIN,
  ROLE_CAREGIVER,
  resolveAdminAuthContext,
  buildAuthContext,
  superAdminContext,
  caregiverContext,
  setPgForTest,
  setFirebaseAdminForTest,
};
