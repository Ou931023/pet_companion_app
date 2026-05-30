// Care Alert 持久化 store。
//
// 把 /api/care-alerts/notify 收到的 CareAlert 存成本機 JSON 檔（沿用專案既有
// data/*.json 檔案模式），供長照管理者網頁（caregiver_web）日後查詢。
//
// 注意：
// - data/care_alerts.json 屬 runtime data，不進版控。
// - 寫入失敗只記 log、回傳 {success:false}，絕不丟例外讓 server crash。
// - 測試請以 options.filePath 或 env CARE_ALERTS_DATA_FILE 指向 temp 檔，
//   避免污染正式 data。

const path = require("path");
const fs = require("fs/promises");
const { randomUUID } = require("crypto");

const DEFAULT_DATA_FILE = path.join(__dirname, "..", "data", "care_alerts.json");

function resolveFile(explicit) {
  return explicit || process.env.CARE_ALERTS_DATA_FILE || DEFAULT_DATA_FILE;
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

async function saveAlert(payload = {}, options = {}) {
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

async function listAlerts(options = {}) {
  const filePath = resolveFile(options.filePath);
  const alerts = await readAll(filePath);
  let result = alerts;
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

async function getAlertById(id, options = {}) {
  const filePath = resolveFile(options.filePath);
  const alerts = await readAll(filePath);
  return alerts.find((a) => a.id === id) || null;
}

const VALID_STATUSES = ["new", "acknowledged", "resolved"];

async function updateAlertStatus(id, status, options = {}) {
  if (!VALID_STATUSES.includes(status)) {
    return { success: false, error: "invalid_status" };
  }
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

module.exports = {
  saveAlert,
  listAlerts,
  getAlertById,
  updateAlertStatus,
  normalizeAlert,
  normalizeRiskLevel,
  RISK_LEVEL_LABELS,
  VALID_STATUSES,
};
