// CR-0040 Batch B：Resident-Caregiver Authorization Service。
//
// 契約見 docs/CHANGE_REVIEW.md CR-0040（§3 路線 B、§5 schema、§10 Batch B、§12 紅線）。
//
// 目的：在「不重寫整個 auth」（caregiver 個別登入 = Audit §12 #5，本案外）的前提下，
// 讓「依授權住民過濾資料」成為已存在、已測、可獨立回滾的機制（修 P0-2 scope 層），
// 並把共享 ADMIN_API_TOKEN 由「token 即全看」的意外行為，明確命名為 super_admin 角色
// （full scope）→ 部分修 P1-2。
//
// 角色分界：
//   - super_admin：requireAdmin 已驗過的共享 ADMIN_API_TOKEN 持有者 → full scope（行為零變更）。
//   - caregiver  ：只能存取 resident_caregiver_links 內 status='active' 的授權 elder（resident）。
//
// 重要紅線（§12）：
//   - production 唯一可解析的身分 = ADMIN_API_TOKEN → super_admin。
//   - caregiver 身分解析（resolveAuthContext 回傳 caregiver）只在「未來有 per-caregiver 登入」
//     或「測試注入 seam」時發生；嚴禁 production 可用的假 caregiver token / hardcode / demo seed。
//   - 不 hardcode elder / caregiver id；區分「已驗證」與「有權限」。
//
// pg seam：比照 careAlertStoreService 的 setPgForTest(pg)。測試以 mock pg 注入授權 rows。

const defaultPg = require("../../db/postgres");

// 角色常數。
const ROLE_SUPER_ADMIN = "super_admin";
const ROLE_CAREGIVER = "caregiver";

// 預設用真實 Postgres；測試可用 setPgForTest 注入 mock pool。
let activePg = defaultPg;

// 測試專用：auth context resolver 覆寫 seam。
// production 永遠為 null → resolveAuthContext 只會回 super_admin（見下）。
let authContextResolverOverride = null;

// 測試專用：注入 / 還原 pg。mock pool 需提供 query(text, params) → { rows }；
// 可選提供 isPostgresAvailable() → boolean（缺則視為可用，方便 mock-only-query）。
function setPgForTest(pg) {
  activePg = pg || defaultPg;
}

// 測試專用：注入 / 還原 auth context resolver（驗 caregiver scoped 路徑）。
// 這是測試 seam，永遠無法經 HTTP 觸發 → 不構成 production 可用的假 caregiver 身分。
function setAuthContextResolverForTest(fn) {
  authContextResolverOverride = typeof fn === "function" ? fn : null;
}

// 由 request 解析 auth context。
// requireAdmin 已在路由最前面驗過共享 ADMIN_API_TOKEN（fail-closed），故能走到這裡者
// 即為合法 admin → super_admin（full scope，行為零變更）。
// per-caregiver 真實身分解析 = Audit §12 #5（後續 CR）；在那之前 production 只認 super_admin。
// 測試可用 setAuthContextResolverForTest 注入 caregiver context 驗 scoped 路徑。
function resolveAuthContext(req) {
  if (authContextResolverOverride) {
    return authContextResolverOverride(req);
  }
  return { role: ROLE_SUPER_ADMIN };
}

function isSuperAdmin(authContext) {
  return !!authContext && authContext.role === ROLE_SUPER_ADMIN;
}

function isCaregiver(authContext) {
  return !!authContext && authContext.role === ROLE_CAREGIVER;
}

// 取某 caregiver 被授權的 elder（resident）id 集合（status='active'）。
// fail-closed：caregiverId 缺、或 DB 不可用 → 回空集合（caregiver 看不到任何住民，
// 絕不退化成「看全部」）。不 hardcode 任何 id。
async function getAuthorizedResidentIdsForCaregiver(caregiverId, options = {}) {
  const pg = options.pg || activePg;
  if (!caregiverId) return new Set();

  if (pg && typeof pg.isPostgresAvailable === "function") {
    let available = false;
    try {
      available = await pg.isPostgresAvailable();
    } catch (_error) {
      available = false;
    }
    if (!available) return new Set();
  }

  const { rows } = await pg.query(
    "SELECT elder_id FROM resident_caregiver_links WHERE caregiver_id = $1 AND status = 'active'",
    [caregiverId],
  );
  return new Set(
    (rows || []).map((row) => row.elder_id).filter((value) => value != null),
  );
}

// 判斷 authContext 是否可存取指定 residentId（elder_id）。
//   - super_admin → 一律 true（行為零變更）。
//   - caregiver   → 須在授權集合內。
//   - 其它 / 無 context → false（區分「已驗證」與「有權限」，fail-closed）。
// 路由可將 false 轉為 403。
async function assertCanAccessResident(authContext, residentId, options = {}) {
  if (isSuperAdmin(authContext)) return true;
  if (!isCaregiver(authContext)) return false;
  if (residentId == null) return false;
  const authorized = await getAuthorizedResidentIdsForCaregiver(
    authContext.caregiverId,
    options,
  );
  return authorized.has(residentId);
}

// 可寫入住民照護狀態的角色只有 primary / secondary。viewer 固定唯讀；
// super_admin 維持 full scope。以單筆 active link 查詢避免把 read scope 誤當 write scope。
async function assertCanManageResident(authContext, residentId, options = {}) {
  if (isSuperAdmin(authContext)) return true;
  if (!isCaregiver(authContext) || !authContext.caregiverId || residentId == null) {
    return false;
  }
  const pg = options.pg || activePg;
  if (pg && typeof pg.isPostgresAvailable === "function") {
    try {
      if (!(await pg.isPostgresAvailable())) return false;
    } catch (_) {
      return false;
    }
  }
  const { rows } = await pg.query(
    `SELECT role
     FROM resident_caregiver_links
     WHERE caregiver_id = $1
       AND elder_id = $2
       AND status = 'active'
       AND role IN ('primary', 'secondary')
     LIMIT 1`,
    [authContext.caregiverId, residentId],
  );
  return Array.isArray(rows) && rows.length > 0;
}

// 依授權住民過濾 Care Alert 清單。
//   - super_admin → 原樣回傳（同參考，行為零變更）。
//   - caregiver   → 只留授權 elderId 的 alert（alert.elderId 為 null 者一律過濾掉）。
//   - 其它 / 無 context → 空陣列（fail-closed）。
async function filterAlertsByAuthorizedResidents(authContext, alerts, options = {}) {
  if (isSuperAdmin(authContext)) return alerts;
  if (!Array.isArray(alerts)) return [];
  if (!isCaregiver(authContext)) return [];
  const authorized = await getAuthorizedResidentIdsForCaregiver(
    authContext.caregiverId,
    options,
  );
  return alerts.filter(
    (alert) => alert && alert.elderId != null && authorized.has(alert.elderId),
  );
}

module.exports = {
  ROLE_SUPER_ADMIN,
  ROLE_CAREGIVER,
  resolveAuthContext,
  isSuperAdmin,
  isCaregiver,
  getAuthorizedResidentIdsForCaregiver,
  assertCanAccessResident,
  assertCanManageResident,
  filterAlertsByAuthorizedResidents,
  setPgForTest,
  setAuthContextResolverForTest,
};
