// CR-0043 B2：Caregiver 帳號 provisioning service（super_admin-only 端點背後的資料層）。
//
// 契約見 docs/CHANGE_REVIEW.md CR-0043（§3 裁決 1/2/6、§4 影響、§11 紅線）
// 與 docs/CAREGIVER_PROVISIONING.md。
//
// 職責：建立 / 列出 / 修改 / 停用「caregiver 帳號」（users.role='caregiver'）。
//   - 路線 B（§3 #2）：建立時 firebase_uid 可為 null（pending record）；之後 super_admin 顯式以
//     updateCaregiver 設 firebaseUid 完成綁定。不做 email 自動認領（FU-CR-0043a）。不明文密碼
//     （users 無 password 欄，全程 Firebase）。
//   - status（migration 014）：active|inactive。對外 / DB 同詞彙（與 link 的 active/revoked 不同）。
//   - email：app-level 全域唯一檢查（§13 FU：未加 DB unique index 以免衝撞既有 elder email，
//     誠實標註存在競態窗口；super_admin-only 低併發可接受）。
//
// 安全對外格式（§3 #6、§4）：只回 id / email(遮蔽) / displayName / role / status / firebaseUid /
//   createdAt / updatedAt。**絕不回** password_hash / provider_user_id / 任何 token。
//   沿用 adminUsersService 的 maskEmail / deriveDisplayName 模式。
//
// pg seam（比照 adminAuthContext / authorizationService）：setPgForTest(pg) 注入 mock pg
//   （query(text, params) → { rows }）。預設走真實 postgres。

"use strict";

const defaultPg = require("../../db/postgres");
const { maskEmail, deriveDisplayName } = require("./adminUsersService");

const ROLE_CAREGIVER = "caregiver";
const VALID_STATUSES = new Set(["active", "inactive"]);

let activePg = defaultPg;

// 測試專用：注入 / 還原 pg。傳 null 還原預設。
function setPgForTest(pg) {
  activePg = pg || defaultPg;
}

// 將 DB row 轉成「只含安全欄位」的對外格式（第二層保護：即便 SQL 誤選敏感欄位也不外漏）。
function toSafeCaregiver(row = {}) {
  return {
    id: row.id,
    displayName: deriveDisplayName(row),
    emailMasked: maskEmail(row.email),
    role: row.role || ROLE_CAREGIVER,
    status: row.status || "active",
    // firebaseUid：路線 B 綁定識別。非 token / 非密碼，super_admin 需據此確認綁定狀態。
    firebaseUid: row.firebase_uid ?? null,
    createdAt: row.created_at ?? null,
    updatedAt: row.updated_at ?? null,
  };
}

function normalizeEmail(value) {
  if (value == null) return "";
  return String(value).trim().toLowerCase();
}

function normalizeText(value) {
  if (value == null) return null;
  const s = String(value).trim();
  return s === "" ? null : s;
}

// 同一 email 是否已被任一 user 佔用（全域，排除 excludeId）。
async function emailTaken(pg, email, excludeId = null) {
  const params = [email];
  let sql = "SELECT id FROM users WHERE LOWER(email) = $1";
  if (excludeId != null) {
    params.push(excludeId);
    sql += " AND id <> $2";
  }
  sql += " LIMIT 1";
  const { rows } = await pg.query(sql, params);
  return Boolean(rows && rows[0]);
}

// 同一 Firebase UID 是否已被任一 user 佔用（全域，排除 excludeId）。
async function firebaseUidTaken(pg, firebaseUid, excludeId = null) {
  if (!firebaseUid) return false;
  const params = [firebaseUid];
  let sql = "SELECT id FROM users WHERE firebase_uid = $1";
  if (excludeId != null) {
    params.push(excludeId);
    sql += " AND id <> $2";
  }
  sql += " LIMIT 1";
  const { rows } = await pg.query(sql, params);
  return Boolean(rows && rows[0]);
}

function provisioningErrorFromDb(error) {
  if (!error || error.code !== "23505") return null;
  const blob = `${error.constraint || ""} ${error.detail || ""} ${error.message || ""}`;
  if (/firebase_uid/i.test(blob)) return "firebase_uid_exists";
  if (/email/i.test(blob)) return "email_exists";
  return "create_failed";
}

// 列出所有 caregiver（role='caregiver'），回安全欄位。
async function listCaregivers(options = {}) {
  const pg = options.pg || activePg;
  const { rows } = await pg.query(
    `SELECT id, email, display_name, role, status, firebase_uid, created_at, updated_at
       FROM users
      WHERE role = 'caregiver'
      ORDER BY created_at DESC
      LIMIT 200`,
  );
  return (rows || []).map(toSafeCaregiver);
}

// 建立 caregiver 帳號。
//   input: { email(必填), displayName?, firebaseUid?(可 null=pending) }
//   回 { ok:true, caregiver } / { ok:false, error }
//   （email_required | email_exists | firebase_uid_exists）。
async function createCaregiver(input = {}, options = {}) {
  const pg = options.pg || activePg;
  const email = normalizeEmail(input.email);
  if (!email) {
    return { ok: false, error: "email_required" };
  }
  if (await emailTaken(pg, email)) {
    return { ok: false, error: "email_exists" };
  }
  const displayName = normalizeText(input.displayName);
  const firebaseUid = normalizeText(input.firebaseUid); // null=pending（路線 B）
  if (firebaseUid && (await firebaseUidTaken(pg, firebaseUid))) {
    return { ok: false, error: "firebase_uid_exists" };
  }

  let rows;
  try {
    ({ rows } = await pg.query(
      `INSERT INTO users (role, email, display_name, firebase_uid, status, email_verified)
         VALUES ('caregiver', $1, $2, $3, 'active', FALSE)
       RETURNING id, email, display_name, role, status, firebase_uid, created_at, updated_at`,
      [email, displayName, firebaseUid],
    ));
  } catch (error) {
    const mapped = provisioningErrorFromDb(error);
    if (mapped) return { ok: false, error: mapped };
    throw error;
  }
  const row = rows && rows[0];
  if (!row) return { ok: false, error: "create_failed" };
  return { ok: true, caregiver: toSafeCaregiver(row) };
}

// 修改 caregiver（displayName / email / firebaseUid）。email 改動仍須全域唯一。
//   回 { ok:true, caregiver } / { ok:false, error }
//   （invalid_payload | not_found | email_exists | firebase_uid_exists）。
async function updateCaregiver(id, input = {}, options = {}) {
  const pg = options.pg || activePg;
  if (!id) return { ok: false, error: "not_found" };

  const sets = [];
  const params = [];
  let i = 1;

  if (input.displayName !== undefined) {
    sets.push(`display_name = $${i++}`);
    params.push(normalizeText(input.displayName));
  }
  if (input.email !== undefined) {
    const email = normalizeEmail(input.email);
    if (!email) return { ok: false, error: "email_required" };
    if (await emailTaken(pg, email, id)) {
      return { ok: false, error: "email_exists" };
    }
    sets.push(`email = $${i++}`);
    params.push(email);
  }
  if (input.firebaseUid !== undefined) {
    // 路線 B 綁定：允許設為實際 uid，或清回 null（解除綁定）。
    const firebaseUid = normalizeText(input.firebaseUid);
    if (firebaseUid && (await firebaseUidTaken(pg, firebaseUid, id))) {
      return { ok: false, error: "firebase_uid_exists" };
    }
    sets.push(`firebase_uid = $${i++}`);
    params.push(firebaseUid);
  }

  if (sets.length === 0) {
    return { ok: false, error: "invalid_payload" };
  }
  sets.push("updated_at = NOW()");
  params.push(id);

  let rows;
  try {
    ({ rows } = await pg.query(
      `UPDATE users SET ${sets.join(", ")}
        WHERE id = $${i} AND role = 'caregiver'
       RETURNING id, email, display_name, role, status, firebase_uid, created_at, updated_at`,
      params,
    ));
  } catch (error) {
    const mapped = provisioningErrorFromDb(error);
    if (mapped) return { ok: false, error: mapped };
    throw error;
  }
  const row = rows && rows[0];
  if (!row) return { ok: false, error: "not_found" };
  return { ok: true, caregiver: toSafeCaregiver(row) };
}

// 設定 caregiver 啟用狀態（active|inactive）。
//   回 { ok:true, caregiver } / { ok:false, error }（invalid_status | not_found）。
async function setCaregiverStatus(id, status, options = {}) {
  const pg = options.pg || activePg;
  if (!id) return { ok: false, error: "not_found" };
  const next = normalizeText(status);
  if (!next || !VALID_STATUSES.has(next)) {
    return { ok: false, error: "invalid_status" };
  }
  const { rows } = await pg.query(
    `UPDATE users SET status = $2, updated_at = NOW()
      WHERE id = $1 AND role = 'caregiver'
     RETURNING id, email, display_name, role, status, firebase_uid, created_at, updated_at`,
    [id, next],
  );
  const row = rows && rows[0];
  if (!row) return { ok: false, error: "not_found" };
  return { ok: true, caregiver: toSafeCaregiver(row) };
}

module.exports = {
  ROLE_CAREGIVER,
  listCaregivers,
  createCaregiver,
  updateCaregiver,
  setCaregiverStatus,
  toSafeCaregiver,
  setPgForTest,
};
