// 通知稽核 log（CR-P2B Batch 2）。
//
// 對應 DB migration db/migrations/012_create_notification_audit_logs.sql 的
// notification_logs 表，與 PROJECT_ARCHITECTURE.md §6.1 契約。
//
// 用途：每次 Care Alert 通知（/api/care-alerts/notify）的三結局各寫一列：
//   sent / failed / skipped_low_risk / skipped_cooldown
// 對映 CLAUDE.md §8.7「每次通知必須寫入 notification log」、§8.10「不可靜默失敗」。
//
// 設計選擇：**DB-only-best-effort**（與 consentStoreService 的 DB-only 不同——
//   稽核 log 失敗絕不可拖垮通知主流程）。
//   - DB 可用（isPostgresAvailable() === true）→ 寫 notification_logs。
//   - DB 不可用 / 無 DATABASE_URL → 略過寫入，回 { success:false, skipped:true }，
//     不丟例外（與既有無 DB 行為一致；通知本身照常完成）。
//   - 寫入例外 → 只 logError（不含敏感欄位）後回 { success:false }，**絕不丟例外**。
//
// PII 紅線（§8.8 / §9.14）：只寫**結構化、非敏感**欄位。
//   **絕不寫**：完整對話原文 / transcriptSnippet / chat_id / bot token / URL / email / ip。
//   本 service 以白名單方式只取下列欄位，input 上其餘任何欄位一律忽略，
//   即使呼叫端誤帶 transcriptSnippet 也不會進 DB。

const defaultPg = require("../db/postgres");

// 預設用真實 Postgres；測試可用 setPgForTest / options.pg 注入 mock pool。
let activePg = defaultPg;

// 測試專用：注入 / 還原 pg。mock pool 需提供：
//   - query(text, params) → { rows }
//   - isPostgresAvailable() → boolean（決定是否寫入）
function setPgForTest(pg) {
  activePg = pg || defaultPg;
}

// outcome 權威值（與 migration 註解一致）。未知值仍寫入（保留軌跡），
// 但呼叫端應只用這四個。
const VALID_OUTCOMES = new Set([
  "sent",
  "failed",
  "skipped_low_risk",
  "skipped_cooldown",
]);

// 是否走 DB。缺 isPostgresAvailable（或拋例外）一律視為不可用 → 略過寫入。
async function isDbAvailable(pg) {
  if (!pg || typeof pg.isPostgresAvailable !== "function") return false;
  try {
    return await pg.isPostgresAvailable();
  } catch (_error) {
    return false;
  }
}

// 只記結構化 log：絕不輸出 payload / 對話原文 / PII / token；僅 op 與 error.message。
function logError(op, error) {
  console.error(
    `[notification-log] ${op} failed (best-effort, ignored)`,
    { error: error?.message || String(error) },
  );
}

function strOrNull(value) {
  if (typeof value !== "string") {
    if (value == null) return null;
    const s = String(value).trim();
    return s === "" ? null : s;
  }
  const trimmed = value.trim();
  return trimmed === "" ? null : trimmed;
}

function intOrNull(value) {
  if (value == null || value === "") return null;
  const n = Number(value);
  return Number.isFinite(n) ? Math.trunc(n) : null;
}

// 寫入一筆通知稽核 log。
// input（白名單，其餘欄位一律忽略）：
//   { alertId, elderId, channel='telegram', riskLevel, outcome,
//     errorCode, httpStatus }
// 回 { success:true } / { success:false } / { success:false, skipped:true }。
// **絕不丟例外**——寫入失敗只 logError，確保不拖垮 /notify。
async function logNotification(input = {}, options = {}) {
  const pg = options.pg || activePg;
  try {
    if (!(await isDbAvailable(pg))) {
      return { success: false, skipped: true };
    }
    // 白名單映射：明確只取結構化欄位，input 上的對話原文 / snippet / chat_id /
    // token / URL 等一律不取（即使誤帶也不入 DB）。
    const channel = strOrNull(input.channel) || "telegram";
    const outcome = strOrNull(input.outcome) || "";
    await pg.query(
      `INSERT INTO notification_logs (
         alert_id, elder_id, channel, risk_level, outcome, error_code, http_status
       ) VALUES ($1::uuid, $2::uuid, $3, $4, $5, $6, $7::int)`,
      [
        strOrNull(input.alertId), // $1
        strOrNull(input.elderId), // $2
        channel, // $3
        strOrNull(input.riskLevel), // $4
        outcome, // $5
        strOrNull(input.errorCode), // $6  僅 error code（如 telegram_send_failed），非原文 / URL
        intOrNull(input.httpStatus), // $7
      ],
    );
    return { success: true };
  } catch (error) {
    // best-effort：稽核寫入失敗絕不拖垮通知。
    logError("logNotification", error);
    return { success: false };
  }
}

module.exports = {
  logNotification,
  VALID_OUTCOMES,
  // 測試 / 工具用
  setPgForTest,
};
