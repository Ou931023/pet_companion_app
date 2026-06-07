// 敏感操作稽核 log（CR-P2B Batch 3）。
//
// 對應 DB migration db/migrations/012_create_notification_audit_logs.sql 的
// audit_logs 表，與 PROJECT_ARCHITECTURE.md §6.1 契約。
//
// 用途：敏感操作須寫一列（對映 CLAUDE.md §9.13）。最小範圍先涵蓋三類：
//   - 帳號刪除          action='account_delete'      （/api/auth/delete）
//   - Care Alert 狀態變更 action='care_alert_status_change'（PATCH /api/care-alerts/:id/status）
//   - consent 寫入       action='consent_record'       （POST /api/consent）
//
// 設計選擇：**DB-only-best-effort**（與 notificationLogService 一致）。
//   稽核 log 失敗絕不可拖垮主流程（刪除 / 狀態變更 / 同意本身已成功）。
//   - DB 可用 → 寫 audit_logs。
//   - DB 不可用 / 無 DATABASE_URL → 略過，回 { success:false, skipped:true }，不丟例外。
//   - 寫入例外 → 只 logError（不含敏感欄位）後回 { success:false }，**絕不丟例外**。
//
// PII 紅線（§9.14）：
//   - actor_id / target_id 只放**非 PII 明碼識別**（user_id / firebase uid / alert id）；
//     **絕不放** email / ip / token / 對話原文。
//   - metadata 只放**結構化非敏感**欄位（如 from/to status、刪除計數）；
//     **禁放** 原文 / email / ip / token。本 service 不檢查 metadata 內容——
//     由呼叫端負責只帶結構化非敏感欄位（見各接入點註解）。

const defaultPg = require("../db/postgres");

// 預設用真實 Postgres；測試可用 setPgForTest / options.pg 注入 mock pool。
let activePg = defaultPg;

// 測試專用：注入 / 還原 pg。mock pool 需提供：
//   - query(text, params) → { rows }
//   - isPostgresAvailable() → boolean（決定是否寫入）
function setPgForTest(pg) {
  activePg = pg || defaultPg;
}

// 是否走 DB。缺 isPostgresAvailable（或拋例外）一律視為不可用 → 略過寫入。
async function isDbAvailable(pg) {
  if (!pg || typeof pg.isPostgresAvailable !== "function") return false;
  try {
    return await pg.isPostgresAvailable();
  } catch (_error) {
    return false;
  }
}

// 只記結構化 log：絕不輸出 metadata / PII / token；僅 op 與 error.message。
function logError(op, error) {
  console.error(
    `[audit-log] ${op} failed (best-effort, ignored)`,
    { error: error?.message || String(error) },
  );
}

function strOrNull(value) {
  if (value == null) return null;
  const s = String(value).trim();
  return s === "" ? null : s;
}

// metadata → JSONB 安全值：只接受可序列化的 plain object，序列化失敗 → null。
function normalizeMetadata(value) {
  if (value == null) return null;
  if (typeof value !== "object" || Array.isArray(value)) return null;
  try {
    // 經 JSON 往返確保無不可序列化值；pg 會自行把 object 編成 jsonb。
    return JSON.parse(JSON.stringify(value));
  } catch (_error) {
    return null;
  }
}

// 寫入一筆敏感操作稽核 log。
// input（白名單，其餘欄位一律忽略）：
//   { actorType, actorId, action, targetType, targetId, outcome, metadata }
// 回 { success:true } / { success:false } / { success:false, skipped:true }。
// **絕不丟例外**——寫入失敗只 logError，確保不拖垮主流程。
async function logAudit(input = {}, options = {}) {
  const pg = options.pg || activePg;
  try {
    if (!(await isDbAvailable(pg))) {
      return { success: false, skipped: true };
    }
    const action = strOrNull(input.action) || "";
    const metadata = normalizeMetadata(input.metadata);
    await pg.query(
      `INSERT INTO audit_logs (
         actor_type, actor_id, action, target_type, target_id, outcome, metadata
       ) VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb)`,
      [
        strOrNull(input.actorType), // $1  elder | caregiver | system
        strOrNull(input.actorId), // $2  非 PII 明碼識別，可空
        action, // $3
        strOrNull(input.targetType), // $4
        strOrNull(input.targetId), // $5
        strOrNull(input.outcome), // $6  success | failed
        metadata == null ? null : JSON.stringify(metadata), // $7  結構化非敏感
      ],
    );
    return { success: true };
  } catch (error) {
    // best-effort：稽核寫入失敗絕不拖垮主流程。
    logError("logAudit", error);
    return { success: false };
  }
}

module.exports = {
  logAudit,
  // 測試 / 工具用
  setPgForTest,
  normalizeMetadata,
};
