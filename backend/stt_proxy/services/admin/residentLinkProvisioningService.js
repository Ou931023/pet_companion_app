// CR-0043 B2：Resident-Caregiver Link provisioning service（super_admin-only 端點背後的資料層）。
//
// 契約見 docs/CHANGE_REVIEW.md CR-0043（§3 裁決 5/6、§4 影響、§11 紅線）
// 與 docs/CAREGIVER_PROVISIONING.md。
//
// 職責：建立 / 列出 / 改 role / 停用「resident_caregiver_links」（CR-0040 migration 013）。
//
// 狀態詞彙映射（§3 #5 裁決）：
//   - DB 維持 `active`/`revoked`（對齊 migration 013 + authorizationService 查詢 + 唯一索引）。
//   - provisioning API **對外**以 `active`/`inactive` 呈現。停用 = UPDATE status='revoked'、revoked_at=NOW()。
//   - authorizationService.js **零改動**：新增 active link → 立即可見；停用（→revoked）→ 自動排除。
//
// role 詞彙（§3、任務 B2）：對齊 migration 013 既有值 **primary | secondary | viewer**（以 013 為準）。
//   「backup」概念 = secondary（接受 'backup' 作 alias → 正規化為 'secondary'，見 CAREGIVER_PROVISIONING.md）。
//
// 建立前置檢查：resident(elder) 與 caregiver(user role='caregiver') 須**存在**；同 caregiver+elder
//   已有 active link 則不建第二筆（避免重複授權，呼應唯一索引 idx_rcl_unique_active）。
//
// 安全對外格式：id / residentId / residentName / caregiverId / caregiverName / role / status(active|inactive)
//   / createdAt / updatedAt。不回 token / email 原文（名稱只取 display_name，無則 null）。
//
// pg seam：setPgForTest(pg) 注入 mock pg（query(text, params) → { rows }）。

"use strict";

const defaultPg = require("../../db/postgres");

const VALID_ROLES = new Set(["primary", "secondary", "viewer"]);
const VALID_API_STATUSES = new Set(["active", "inactive"]);

let activePg = defaultPg;

function setPgForTest(pg) {
  activePg = pg || defaultPg;
}

// role 正規化：對齊 013（primary|secondary|viewer）。'backup' → 'secondary' alias。
function normalizeRole(value) {
  const raw = (value == null ? "" : String(value)).trim().toLowerCase();
  if (!raw) return "primary"; // 預設對齊 013 DEFAULT 'primary'
  if (raw === "backup") return "secondary";
  return raw;
}

function normalizeText(value) {
  if (value == null) return null;
  const s = String(value).trim();
  return s === "" ? null : s;
}

// DB status(active|revoked) → 對外 status(active|inactive)。
function toApiStatus(dbStatus) {
  return dbStatus === "active" ? "active" : "inactive";
}

function toSafeLink(row = {}) {
  return {
    id: row.id,
    residentId: row.elder_id ?? null,
    residentName: normalizeText(row.resident_name),
    caregiverId: row.caregiver_id ?? null,
    caregiverName: normalizeText(row.caregiver_name),
    role: row.role || "primary",
    status: toApiStatus(row.status),
    createdAt: row.created_at ?? null,
    updatedAt: row.updated_at ?? null,
  };
}

function minimalCreatedLink(id, residentId, caregiverId, role) {
  return {
    id,
    residentId,
    residentName: null,
    caregiverId,
    caregiverName: null,
    role: role || "primary",
    status: "active",
    createdAt: null,
    updatedAt: null,
  };
}

const LINK_SELECT_JOIN = `
  SELECT l.id, l.elder_id, e.display_name AS resident_name,
         l.caregiver_id, u.display_name AS caregiver_name,
         l.role, l.status, l.created_at, l.updated_at
    FROM resident_caregiver_links l
    LEFT JOIN elders e ON e.id = l.elder_id
    LEFT JOIN users u ON u.id = l.caregiver_id
`;

async function getLinkById(pg, id) {
  const { rows } = await pg.query(`${LINK_SELECT_JOIN} WHERE l.id = $1 LIMIT 1`, [id]);
  const row = rows && rows[0];
  return row ? toSafeLink(row) : null;
}

// 列出所有授權關聯（含已停用），join 取 resident / caregiver 名稱。
async function listLinks(options = {}) {
  const pg = options.pg || activePg;
  const { rows } = await pg.query(`${LINK_SELECT_JOIN} ORDER BY l.created_at DESC LIMIT 500`);
  return (rows || []).map(toSafeLink);
}

async function elderExists(pg, elderId) {
  const { rows } = await pg.query("SELECT id FROM elders WHERE id = $1 LIMIT 1", [elderId]);
  return Boolean(rows && rows[0]);
}

async function caregiverExists(pg, caregiverId) {
  const { rows } = await pg.query(
    "SELECT id FROM users WHERE id = $1 AND role = 'caregiver' LIMIT 1",
    [caregiverId],
  );
  return Boolean(rows && rows[0]);
}

async function activeLinkExists(pg, elderId, caregiverId) {
  const { rows } = await pg.query(
    `SELECT id FROM resident_caregiver_links
      WHERE elder_id = $1 AND caregiver_id = $2 AND status = 'active' LIMIT 1`,
    [elderId, caregiverId],
  );
  return Boolean(rows && rows[0]);
}

function provisioningErrorFromDb(error) {
  if (!error) return null;
  if (error.code === "22P02") {
    return "invalid_payload";
  }
  if (error.code === "42P01" || error.code === "42703") {
    return "database_schema_not_ready";
  }
  if (error.code === "23503") {
    const blob = `${error.constraint || ""} ${error.detail || ""} ${error.message || ""}`;
    if (/caregiver/i.test(blob) || /user/i.test(blob)) return "caregiver_not_found";
    if (/elder|resident/i.test(blob)) return "resident_not_found";
    return "invalid_payload";
  }
  if (error.code !== "23505") return null;
  const blob = `${error.constraint || ""} ${error.detail || ""} ${error.message || ""}`;
  if (/resident_caregiver_links|elder_id|caregiver_id|unique/i.test(blob)) {
    return "link_exists";
  }
  return "create_failed";
}

// 建立授權關聯。
//   input: { residentId(必填), caregiverId(必填), role? }
//   回 { ok:true, link } / { ok:false, error }
//     （invalid_payload | resident_not_found | caregiver_not_found | invalid_role | link_exists）。
async function createLink(input = {}, options = {}) {
  const pg = options.pg || activePg;
  const residentId = normalizeText(input.residentId);
  const caregiverId = normalizeText(input.caregiverId);
  try {
    if (!residentId || !caregiverId) {
      return { ok: false, error: "invalid_payload" };
    }
    const role = normalizeRole(input.role);
    if (!VALID_ROLES.has(role)) {
      return { ok: false, error: "invalid_role" };
    }
    if (!(await elderExists(pg, residentId))) {
      return { ok: false, error: "resident_not_found" };
    }
    if (!(await caregiverExists(pg, caregiverId))) {
      return { ok: false, error: "caregiver_not_found" };
    }
    if (await activeLinkExists(pg, residentId, caregiverId)) {
      // 已有 active 關聯 → 不建第二筆（避免重複授權，呼應唯一索引）。
      return { ok: false, error: "link_exists" };
    }
    const { rows } = await pg.query(
      `INSERT INTO resident_caregiver_links (elder_id, caregiver_id, role, status)
         VALUES ($1, $2, $3, 'active')
       RETURNING id`,
      [residentId, caregiverId, role],
    );
    const newId = rows && rows[0] && rows[0].id;
    if (!newId) return { ok: false, error: "create_failed" };
    let link = null;
    try {
      link = await getLinkById(pg, newId);
    } catch (_error) {
      link = null;
    }
    return {
      ok: true,
      link: link || minimalCreatedLink(newId, residentId, caregiverId, role),
    };
  } catch (error) {
    const mapped = provisioningErrorFromDb(error);
    if (mapped) return { ok: false, error: mapped };
    throw error;
  }
}

// 改 role。回 { ok:true, link } / { ok:false, error }（invalid_role | not_found）。
async function updateLinkRole(id, role, options = {}) {
  const pg = options.pg || activePg;
  if (!id) return { ok: false, error: "not_found" };
  const next = normalizeRole(role);
  if (!VALID_ROLES.has(next)) {
    return { ok: false, error: "invalid_role" };
  }
  const { rows } = await pg.query(
    `UPDATE resident_caregiver_links SET role = $2, updated_at = NOW()
      WHERE id = $1 RETURNING id`,
    [id, next],
  );
  if (!(rows && rows[0])) return { ok: false, error: "not_found" };
  const link = await getLinkById(pg, id);
  return { ok: true, link };
}

// 設定關聯狀態（對外 active|inactive；DB 映射 active|revoked）。
//   停用 → status='revoked'、revoked_at=NOW()；啟用 → status='active'、revoked_at=NULL。
//   回 { ok:true, link } / { ok:false, error }（invalid_status | not_found）。
async function setLinkStatus(id, status, options = {}) {
  const pg = options.pg || activePg;
  if (!id) return { ok: false, error: "not_found" };
  const apiStatus = normalizeText(status);
  if (!apiStatus || !VALID_API_STATUSES.has(apiStatus)) {
    return { ok: false, error: "invalid_status" };
  }
  const dbStatus = apiStatus === "active" ? "active" : "revoked";
  const { rows } = await pg.query(
    `UPDATE resident_caregiver_links
        SET status = $2,
            updated_at = NOW(),
            revoked_at = CASE WHEN $2 = 'revoked' THEN NOW() ELSE NULL END
      WHERE id = $1 RETURNING id`,
    [id, dbStatus],
  );
  if (!(rows && rows[0])) return { ok: false, error: "not_found" };
  const link = await getLinkById(pg, id);
  return { ok: true, link };
}

module.exports = {
  VALID_ROLES,
  listLinks,
  createLink,
  updateLinkRole,
  setLinkStatus,
  toSafeLink,
  normalizeRole,
  provisioningErrorFromDb,
  setPgForTest,
};
