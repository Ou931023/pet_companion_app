// Care Alert 持久化 store（CR-P2A Batch 2/3：DB-優先 + JSON fallback）。
//
// 把 /api/care-alerts/notify 收到的 CareAlert 持久化，供長照管理者網頁
// （caregiver_web）日後查詢。
//
// 持久化策略（見 PROJECT_ARCHITECTURE.md §5.3）：
//   - **DB-優先**：isPostgresAvailable() 為 true → 走 PostgreSQL（migration 011 的
//     care_alerts / care_alert_status_events 兩表）。
//   - **JSON fallback**：DB 例外 → logError（不含原文 / PII / token）後降級走既有
//     JSON 路徑，確保 /notify 不因 DB 故障失敗（Care Alert 是可降級的營運資料，
//     與 consent 的 DB-only 刻意不同）。
//   - **無 DATABASE_URL / DB 不可用** → 直接走 JSON，行為與 DB 化前完全一致
//     （所有現有測試與無 DB 的 Demo 機）。
//   - **不自動遷移、不雙寫**：既有 care_alerts.json 舊資料不匯入 DB、不 JSON↔DB
//     雙寫；歷史資料留在 JSON 路徑，啟用 DB 後新資料進 DB。
//
// 對外 5 函式（saveAlert / listAlerts / getAlertById / updateAlertStatus /
// deleteAlertsByElderId）的簽章與回傳形狀與 DB 化前**完全一致**。
//
// 注意：
// - data/care_alerts.json 屬 runtime data，不進版控。
// - 寫入失敗只記 log、回傳 {success:false}，絕不丟例外讓 server crash。
// - 測試請以 options.filePath 或 env CARE_ALERTS_DATA_FILE 指向 temp 檔，
//   避免污染正式 data；DB 路徑以 options.pg / setPgForTest 注入 mock pool。

const path = require("path");
const fs = require("fs/promises");
const { randomUUID } = require("crypto");

const defaultPg = require("../db/postgres");

const DEFAULT_DATA_FILE = path.join(__dirname, "..", "data", "care_alerts.json");

// 預設用真實 Postgres；測試可用 setPgForTest 注入 mock pool。
let activePg = defaultPg;

// 測試專用：注入 / 還原 pg。mock pool 需提供：
//   - query(text, params) → { rows }
//   - isPostgresAvailable() → boolean（決定走 DB 或 JSON）
function setPgForTest(pg) {
  activePg = pg || defaultPg;
}

function resolveFile(explicit) {
  return explicit || process.env.CARE_ALERTS_DATA_FILE || DEFAULT_DATA_FILE;
}

// 是否走 DB。缺 isPostgresAvailable（或拋例外）一律視為不可用 → JSON 路徑，
// 確保無 DB / mock-only-query 的環境行為與今日一致。
async function isDbAvailable(pg) {
  if (!pg || typeof pg.isPostgresAvailable !== "function") return false;
  try {
    return await pg.isPostgresAvailable();
  } catch (_error) {
    return false;
  }
}

// DB 例外只記結構化 log：絕不輸出 payload / 對話原文 / transcriptSnippet / PII /
// token；僅 op 與 error.message。
function logDbError(op, error) {
  console.error(
    `[care-alert-store] DB ${op} failed, falling back to JSON`,
    { error: error?.message || String(error) },
  );
}

// ---- Care Alert 風險分級正規化（CR-0002 Batch 2）----
//
// 權威四級：low / medium / high / urgent（見 PROJECT_ARCHITECTURE.md §5.1）。
// 為向下相容，舊代碼 normal / attention 在「寫入」與「filter 比對」時都會被正規化。
const AUTHORITATIVE_RISK_LEVELS = new Set(["low", "medium", "high", "urgent"]);
const RISK_LEVEL_ALIASES = { normal: "low", attention: "medium" };
const RISK_LEVEL_LABELS = {
  low: "一般",
  medium: "持續觀察",
  high: "需通知",
  urgent: "緊急",
};

// 把任意輸入正規化為權威四級之一。
// 規則：normal→low、attention→medium、urgent→urgent、low/medium/high/urgent 原樣、
// 其餘（含空字串、未知值）→ low。大小寫與前後空白不敏感。
function normalizeRiskLevel(value) {
  const raw = (value == null ? "" : String(value)).trim().toLowerCase();
  if (AUTHORITATIVE_RISK_LEVELS.has(raw)) return raw;
  if (Object.prototype.hasOwnProperty.call(RISK_LEVEL_ALIASES, raw)) {
    return RISK_LEVEL_ALIASES[raw];
  }
  return "low";
}

async function readAll(filePath) {
  try {
    const raw = await fs.readFile(filePath, "utf8");
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch (error) {
    // 檔案不存在（ENOENT）視為空清單；其它錯誤記 log 後也回空，不影響流程。
    if (error && error.code !== "ENOENT") {
      console.error("[care-alert-store] read failed, treating as empty", {
        error: error.message,
      });
    }
    return [];
  }
}

async function writeAll(filePath, alerts) {
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  await fs.writeFile(filePath, JSON.stringify(alerts, null, 2), "utf8");
}

// 從外部 payload 萃取要保存的欄位，並補上 id / receivedAt / status。
function normalizeAlert(payload = {}) {
  return {
    id: payload.id || randomUUID(),
    // CR-0008：綁定哪位長者；未帶入為 null（向下相容，舊資料缺欄位視為 null）。
    elderId: payload.elderId ?? null,
    receivedAt: new Date().toISOString(),
    status: payload.status || "new",
    // 寫入前正規化為權威四級（舊代碼 normal/attention 會被轉換；未知→low）。
    riskLevel: normalizeRiskLevel(payload.riskLevel),
    riskLevelLabel: payload.riskLevelLabel ?? "",
    category: payload.category ?? "",
    categoryLabel: payload.categoryLabel ?? "",
    triggerSummary: payload.triggerSummary ?? "",
    transcriptSnippet: payload.transcriptSnippet ?? "",
    createdAt: payload.createdAt ?? "",
    source: payload.source ?? "",
  };
}

// ---- DB 路徑共用工具 ----

// timestamptz 從 pg 取回是 JS Date；對外契約用 ISO8601 字串。
function toIso(value) {
  if (value == null) return null;
  if (value instanceof Date) return value.toISOString();
  return value;
}

// 空字串 / 空白 → null（timestamptz / text 欄位避免寫空字串）。
function emptyToNull(value) {
  if (value == null) return null;
  return String(value).trim() === "" ? null : value;
}

function strOrNull(value) {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed === "" ? null : trimmed;
}

// 把 care_alerts row 映射為對外 alert 形狀（與 normalizeAlert 後欄位一致）。
// 文字欄位 null→""、時間 Date→ISO；statusUpdatedAt / acknowledgedAt / resolvedAt
// 僅在非 null 時才帶 key（與 JSON 路徑「更新後才出現該欄位」行為一致）。
function rowToAlert(row) {
  const alert = {
    id: row.id,
    elderId: row.elder_id ?? null,
    receivedAt: toIso(row.received_at),
    status: row.status,
    riskLevel: row.risk_level,
    riskLevelLabel: row.risk_level_label ?? "",
    category: row.category ?? "",
    categoryLabel: row.category_label ?? "",
    triggerSummary: row.trigger_summary ?? "",
    transcriptSnippet: row.transcript_snippet ?? "",
    createdAt: row.created_at == null ? "" : toIso(row.created_at),
    source: row.source ?? "",
  };
  if (row.status_updated_at != null) {
    alert.statusUpdatedAt = toIso(row.status_updated_at);
  }
  if (row.acknowledged_at != null) {
    alert.acknowledgedAt = toIso(row.acknowledged_at);
  }
  if (row.resolved_at != null) {
    alert.resolvedAt = toIso(row.resolved_at);
  }
  return alert;
}

// ---- saveAlert ----

async function saveAlertDb(pg, payload) {
  const alert = normalizeAlert(payload);
  await pg.query(
    `INSERT INTO care_alerts (
       id, elder_id, received_at, status, risk_level, risk_level_label,
       category, category_label, trigger_summary, transcript_snippet,
       created_at, source
     ) VALUES ($1, $2, $3::timestamptz, $4, $5, $6, $7, $8, $9, $10, $11::timestamptz, $12)`,
    [
      alert.id, // $1
      alert.elderId, // $2
      alert.receivedAt, // $3
      alert.status, // $4
      alert.riskLevel, // $5
      emptyToNull(alert.riskLevelLabel), // $6
      emptyToNull(alert.category), // $7
      emptyToNull(alert.categoryLabel), // $8
      emptyToNull(alert.triggerSummary), // $9
      emptyToNull(alert.transcriptSnippet), // $10
      emptyToNull(alert.createdAt), // $11  payload 來源時間，可空
      emptyToNull(alert.source), // $12
    ],
  );
  // 回傳 in-memory normalizeAlert 物件 → 與 JSON 路徑形狀完全一致。
  return { success: true, alert };
}

async function saveAlertJson(payload, options) {
  const filePath = resolveFile(options.filePath);
  try {
    const alert = normalizeAlert(payload);
    const alerts = await readAll(filePath);
    alerts.push(alert);
    await writeAll(filePath, alerts);
    return { success: true, alert };
  } catch (error) {
    console.error("[care-alert-store] saveAlert failed", {
      error: error?.message || error,
    });
    return { success: false, error: "care_alert_store_write_failed" };
  }
}

async function saveAlert(payload = {}, options = {}) {
  const pg = options.pg || activePg;
  if (await isDbAvailable(pg)) {
    try {
      return await saveAlertDb(pg, payload);
    } catch (error) {
      logDbError("saveAlert", error);
      // 降級 JSON：確保 /notify 不因 DB 故障失敗。
    }
  }
  return saveAlertJson(payload, options);
}

// ---- listAlerts ----

async function listAlertsDb(pg, options) {
  const where = [];
  const params = [];
  // CR-0008：elderId 過濾——明確帶入才過濾（嚴格相等）。
  if (options.elderId != null) {
    params.push(options.elderId);
    where.push(`elder_id = $${params.length}`);
  }
  if (options.riskLevel) {
    // 查詢值先正規化為權威四級（DB 內值寫入時已正規化）。
    params.push(normalizeRiskLevel(options.riskLevel));
    where.push(`risk_level = $${params.length}`);
  }
  if (options.status) {
    params.push(options.status);
    where.push(`status = $${params.length}`);
  }
  let sql = `SELECT * FROM care_alerts`;
  if (where.length > 0) {
    sql += ` WHERE ${where.join(" AND ")}`;
  }
  // 新到舊。
  sql += ` ORDER BY received_at DESC`;
  const limit = Number(options.limit);
  if (Number.isFinite(limit) && limit > 0) {
    params.push(limit);
    sql += ` LIMIT $${params.length}`;
  }
  const result = await pg.query(sql, params);
  return (result.rows || []).map(rowToAlert);
}

async function listAlertsJson(options) {
  const filePath = resolveFile(options.filePath);
  const alerts = await readAll(filePath);
  let result = alerts;
  // CR-0008：elderId 過濾——明確帶入才過濾（嚴格 ===），未帶則回全部
  // （含舊資料缺欄位 / elderId=null）。
  if (options.elderId != null) {
    result = result.filter((a) => a.elderId === options.elderId);
  }
  if (options.riskLevel) {
    // filter 條件與資料本身都先正規化再比對，讓「用新值查也能命中舊資料
    // （含尚未轉換的舊 care_alerts.json）」、反之亦然。
    const wanted = normalizeRiskLevel(options.riskLevel);
    result = result.filter((a) => normalizeRiskLevel(a.riskLevel) === wanted);
  }
  if (options.status) {
    result = result.filter((a) => a.status === options.status);
  }
  // 新到舊：先反轉（讓最後寫入的在前）再依 receivedAt 穩定降冪排序，
  // 即使多筆 receivedAt 相同（同毫秒）也能維持「最新插入優先」。
  result = [...result]
    .reverse()
    .sort((a, b) => String(b.receivedAt).localeCompare(String(a.receivedAt)));
  const limit = Number(options.limit);
  if (Number.isFinite(limit) && limit > 0) {
    result = result.slice(0, limit);
  }
  return result;
}

async function listAlerts(options = {}) {
  const pg = options.pg || activePg;
  if (await isDbAvailable(pg)) {
    try {
      return await listAlertsDb(pg, options);
    } catch (error) {
      logDbError("listAlerts", error);
    }
  }
  return listAlertsJson(options);
}

// ---- getAlertById ----

async function getAlertByIdDb(pg, id) {
  const result = await pg.query(`SELECT * FROM care_alerts WHERE id = $1`, [id]);
  const row = (result.rows || [])[0];
  return row ? rowToAlert(row) : null;
}

async function getAlertByIdJson(id, options) {
  const filePath = resolveFile(options.filePath);
  const alerts = await readAll(filePath);
  return alerts.find((a) => a.id === id) || null;
}

async function getAlertById(id, options = {}) {
  const pg = options.pg || activePg;
  if (await isDbAvailable(pg)) {
    try {
      return await getAlertByIdDb(pg, id);
    } catch (error) {
      logDbError("getAlertById", error);
    }
  }
  return getAlertByIdJson(id, options);
}

// ---- updateAlertStatus ----

const VALID_STATUSES = ["new", "acknowledged", "resolved"];

async function updateAlertStatusDb(pg, id, status, options) {
  const now = new Date().toISOString();
  // 用 CTE 擷取舊 status（供狀態軌跡 from_status），UPDATE 後 RETURNING 新列。
  const result = await pg.query(
    `WITH prev AS (
       SELECT status AS from_status FROM care_alerts WHERE id = $1
     )
     UPDATE care_alerts ca
     SET status = $2,
         status_updated_at = $3::timestamptz,
         acknowledged_at = CASE WHEN $2 = 'acknowledged'
           THEN $3::timestamptz ELSE ca.acknowledged_at END,
         resolved_at = CASE WHEN $2 = 'resolved'
           THEN $3::timestamptz ELSE ca.resolved_at END
     FROM prev
     WHERE ca.id = $1
     RETURNING ca.*, prev.from_status`,
    [id, status, now],
  );
  const row = (result.rows || [])[0];
  if (!row) {
    // DB 為真實來源：查無此 id → not_found（不降級 JSON）。
    return { success: false, error: "not_found" };
  }
  // 狀態軌跡 append-only（誰改：actor → care_alert_status_events.source）。
  // best-effort：軌跡寫入失敗不影響 status 更新本身。
  const actor =
    strOrNull(options.actor) || strOrNull(options.source) || "caregiver_web";
  try {
    await pg.query(
      `INSERT INTO care_alert_status_events (
         alert_id, from_status, to_status, changed_at, source
       ) VALUES ($1, $2, $3, $4::timestamptz, $5)`,
      [id, row.from_status ?? null, status, now, actor],
    );
  } catch (eventError) {
    // 軌跡為 append-only best-effort：寫入失敗只記 log，不影響已成功的 status 更新。
    console.error(
      "[care-alert-store] status-event append failed (best-effort, status update kept)",
      { error: eventError?.message || String(eventError) },
    );
  }
  return { success: true, alert: rowToAlert(row) };
}

async function updateAlertStatusJson(id, status, options) {
  const filePath = resolveFile(options.filePath);
  try {
    const alerts = await readAll(filePath);
    const index = alerts.findIndex((a) => a.id === id);
    if (index === -1) {
      return { success: false, error: "not_found" };
    }
    const now = new Date().toISOString();
    const updated = { ...alerts[index], status, statusUpdatedAt: now };
    if (status === "acknowledged") updated.acknowledgedAt = now;
    if (status === "resolved") updated.resolvedAt = now;
    alerts[index] = updated;
    await writeAll(filePath, alerts);
    return { success: true, alert: updated };
  } catch (error) {
    console.error("[care-alert-store] updateAlertStatus failed", {
      error: error?.message || error,
    });
    return { success: false, error: "write_failed" };
  }
}

async function updateAlertStatus(id, status, options = {}) {
  if (!VALID_STATUSES.includes(status)) {
    return { success: false, error: "invalid_status" };
  }
  const pg = options.pg || activePg;
  if (await isDbAvailable(pg)) {
    try {
      return await updateAlertStatusDb(pg, id, status, options);
    } catch (error) {
      logDbError("updateAlertStatus", error);
      // 降級 JSON。
    }
  }
  return updateAlertStatusJson(id, status, options);
}

// ---- deleteAlertsByElderId ----

async function deleteAlertsByElderIdDb(pg, elderId) {
  // care_alert_status_events 由 FK ON DELETE CASCADE 連帶刪除。
  const result = await pg.query(
    `DELETE FROM care_alerts WHERE elder_id = $1 RETURNING id`,
    [elderId],
  );
  return (result.rows || []).length;
}

async function deleteAlertsByElderIdJson(elderId, options) {
  const filePath = resolveFile(options.filePath);
  try {
    const alerts = await readAll(filePath);
    const remaining = alerts.filter((a) => a.elderId !== elderId);
    const removed = alerts.length - remaining.length;
    if (removed > 0) {
      await writeAll(filePath, remaining);
    }
    return removed;
  } catch (error) {
    console.error("[care-alert-store] deleteAlertsByElderId failed", {
      error: error?.message || error,
    });
    return 0;
  }
}

// 刪除某位長者的所有 Care Alert（帳號刪除時清資料用）。
// 回傳實際刪除筆數；elderId 為空 / 讀寫失敗時回 0，不丟例外。
async function deleteAlertsByElderId(elderId, options = {}) {
  if (elderId == null || elderId === "") return 0;
  const pg = options.pg || activePg;
  if (await isDbAvailable(pg)) {
    try {
      return await deleteAlertsByElderIdDb(pg, elderId);
    } catch (error) {
      logDbError("deleteAlertsByElderId", error);
    }
  }
  return deleteAlertsByElderIdJson(elderId, options);
}

module.exports = {
  saveAlert,
  listAlerts,
  getAlertById,
  updateAlertStatus,
  deleteAlertsByElderId,
  normalizeAlert,
  normalizeRiskLevel,
  RISK_LEVEL_LABELS,
  VALID_STATUSES,
  // 測試 / 工具用
  setPgForTest,
};
