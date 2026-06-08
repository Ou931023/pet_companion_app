// CR-0045 B1：長者端（resident self）caller 身分解析中介層。
//
// 契約見 docs/CHANGE_REVIEW.md CR-0045（§5 六項裁決、§7 批次、§11 紅線）
// 與 docs/AUTHORIZATION_MODEL.md §8。
//
// 目的：讓 `POST /api/care-alerts/notify`（長者端 App 從 Realtime 對話建立 Care Alert +
// 觸發 Telegram 的核心路徑）能驗證 caller，且由 token 權威推導 elderId 蓋寫在 alert 上
// （server-authoritative，防偽造；順帶修復既有 elderId=null 缺口）。
//
// 與 adminAuthContext.js（CR-0041）的關係：
//   - 重用相同 primitive 模式（firebaseAdmin verify、mockAllowed() production 守門、
//     CR-0043 status 停用閘、setFirebaseAdminForTest / setPgForTest test seam）。
//   - 但語意不同：此模組解析「長者本人」（role=resident），輸出 elderId（users.elder_id）；
//     adminAuthContext 解析 caregiver / super_admin。為避免動到 adminAuthContext 的
//     SELECT（其既有測試以精確 regex `SELECT id, role, status FROM users` 比對，且 CR-0041
//     測試為 byte-identical 回歸守門），本模組自帶 findUserByFirebaseUid（SELECT 多取 elder_id），
//     不抽共用、不改 adminAuthContext。
//
// 身分解析（fail-closed）：
//   1. 無 Authorization bearer → 401 missing_resident_token。
//   2. 當作 Firebase idToken：
//        - configured（真 Firebase 或注入 stub isConfigured()=true）→ verifyIdToken；
//          失敗 → 401 invalid_session。
//        - 未 configured：production（mockAllowed()===false）一律拒 → 401 invalid_session；
//          非 production 允許 mock，但仍須 verifyIdToken（stub）解析出 uid，否則 401。
//   3. 取得 firebase_uid → 查 users row（id, role, status, elder_id）：
//        - 查無 row：
//            production（mockAllowed()===false）→ 403 resident_not_linked（fail-closed，恆走真 row）。
//            dev/test（mockAllowed()===true，dev-only seam）→ 由 verified uid 推導 scoping elderId
//              （長者 demo 常跑無 DB / JSON 模式，要求真 row 會打斷 demo；對齊 Flutter
//               AuthController 以 session.elderId 逐帳號隔離）。**此寬鬆僅限 mockAllowed**。
//        - status==='inactive'（CR-0043 停用閘）→ 403 resident_inactive。
//        - elder_id 為 null → 403 resident_not_linked（無 elder 綁定者不可建 alert）。
//        - 否則 → resident context { userId, firebaseUid, elderId, role:'resident', isSuperAdmin:false }。
//
// 紅線（§11）：production 不放行未驗證 caller、不收 fake token、不 hardcode resident、
//   log 不印 token；dev seam 僅在 mockAllowed 生效，production 恆 false。

"use strict";

const defaultPg = require("../../db/postgres");
const defaultFirebaseAdmin = require("./firebaseAdmin");
const { mockAllowed } = require("./sessionService");
const { extractBearerToken } = require("../admin/requireAdmin");

const ROLE_RESIDENT = "resident";

function residentContext({ userId, firebaseUid, elderId }) {
  return {
    userId: userId ?? null,
    firebaseUid,
    elderId,
    role: ROLE_RESIDENT,
    isSuperAdmin: false,
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

// 以 firebase_uid 查 users row（id, role, status, elder_id）。pg 不可用 / 查無 → null。
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
    "SELECT id, role, status, elder_id FROM users WHERE firebase_uid = $1 LIMIT 1",
    [firebaseUid],
  );
  return (rows && rows[0]) || null;
}

// 純 async 身分解析。回 { ok:true, authContext } 或 { ok:false, status, error }。
// deps（皆可選，預設取模組級 active*）：{ firebaseAdmin, pg, env }。
async function resolveResidentCallerContext(req, deps = {}) {
  const firebaseAdmin = deps.firebaseAdmin || activeFirebaseAdmin;
  const pg = deps.pg || activePg;
  const env = deps.env || process.env;

  const token = extractBearerToken(req && req.headers && req.headers.authorization);
  if (!token) {
    return { ok: false, status: 401, error: "missing_resident_token" };
  }

  // 當作 Firebase idToken 解析出 firebase_uid。
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
    const decoded = await firebaseAdmin.verifyIdToken(token);
    if (!decoded || !decoded.uid) {
      return { ok: false, status: 401, error: "invalid_session" };
    }
    firebaseUid = decoded.uid;
  }

  const user = await findUserByFirebaseUid(pg, firebaseUid);
  if (!user) {
    // production：已驗證身分但查無 users row（未 provision）→ 403（fail-closed，恆走真 row）。
    if (!mockAllowed(env)) {
      return { ok: false, status: 403, error: "resident_not_linked" };
    }
    // dev-only seam（明列差異）：mockAllowed 且無 DB row → 由 verified uid 推導 scoping elderId，
    // 讓無 DB / JSON 模式的長者 demo 仍能建 alert。嚴禁洩入 production（mockAllowed 恆 false）。
    return {
      ok: true,
      authContext: residentContext({ userId: null, firebaseUid, elderId: firebaseUid }),
    };
  }

  // CR-0043：停用閘（fail-closed）。inactive 帳號不可建 alert。
  //   NULL / 缺值（舊 row、未跑 migration）→ 視為 active（向後相容）。
  const status = user.status == null ? "active" : String(user.status);
  if (status === "inactive") {
    return { ok: false, status: 403, error: "resident_inactive" };
  }

  const elderId = user.elder_id == null ? null : String(user.elder_id);
  if (!elderId) {
    // 無 elder 綁定者不可建 alert（fail-closed）。
    return { ok: false, status: 403, error: "resident_not_linked" };
  }

  return {
    ok: true,
    authContext: residentContext({ userId: user.id, firebaseUid, elderId }),
  };
}

// Express 中介層：解析 resident caller 掛到 req.residentCaller，fail-closed（401/403）。
// 回應形狀沿用 /notify 的 { success:false, error }（與 invalid_payload 一致）；不外洩 token /
// Firebase error detail / stack。
function requireResidentCaller(req, res, next) {
  Promise.resolve()
    .then(() => resolveResidentCallerContext(req))
    .then((result) => {
      if (!result.ok) {
        return res.status(result.status).json({ success: false, error: result.error });
      }
      req.residentCaller = result.authContext;
      return next();
    })
    .catch((error) => {
      // 例外（DB 連線錯等）一律 fail-closed；log 不印 token。
      console.error("[resident-auth] resolve failed", {
        error: (error && error.message) || error,
      });
      return res.status(401).json({ success: false, error: "invalid_session" });
    });
}

module.exports = {
  ROLE_RESIDENT,
  resolveResidentCallerContext,
  requireResidentCaller,
  residentContext,
  setPgForTest,
  setFirebaseAdminForTest,
};
