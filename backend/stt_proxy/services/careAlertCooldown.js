// Care Alert Telegram 防洗版 cooldown（CR-0003 Batch 1）。
//
// 純 in-memory（process 記憶體），不寫入任何 runtime data / 檔案。
// 目的：同一類 alert 在 cooldown 期間只成功推播一次 Telegram，避免短時間洗版。
//
// 設定（環境變數，可關閉 / 調整）：
//   CARE_ALERT_TELEGRAM_COOLDOWN_ENABLED  設為 "false"/"0" 可關閉；預設啟用
//                                         （NODE_ENV=test 時預設關閉，避免污染其他端點測試）
//   CARE_ALERT_TELEGRAM_COOLDOWN_MS       冷卻毫秒，預設 600000（10 分鐘）；測試可用短值（如 1000）
//
// 所有查詢 / 設定函式都接受 options（enabled / cooldownMs / nowMs）以便單元測試注入，
// 不依賴真實時鐘與環境變數。

const DEFAULT_COOLDOWN_MS = 10 * 60 * 1000;

// key -> 上次「成功推播」的時間戳（ms）。
const lastSentAt = new Map();

function envBool(name) {
  const v = process.env[name];
  if (v === undefined || v === "") return undefined;
  return v !== "false" && v !== "0";
}

function isCooldownEnabled(options = {}) {
  if (typeof options.enabled === "boolean") return options.enabled;
  const env = envBool("CARE_ALERT_TELEGRAM_COOLDOWN_ENABLED");
  if (env !== undefined) return env;
  // 預設：非測試環境啟用；測試環境預設關閉。
  return process.env.NODE_ENV !== "test";
}

function cooldownMs(options = {}) {
  if (Number.isFinite(options.cooldownMs) && options.cooldownMs >= 0) {
    return options.cooldownMs;
  }
  const env = Number(process.env.CARE_ALERT_TELEGRAM_COOLDOWN_MS);
  if (Number.isFinite(env) && env >= 0) return env;
  return DEFAULT_COOLDOWN_MS;
}

function nowMsOf(options = {}) {
  return Number.isFinite(options.nowMs) ? options.nowMs : Date.now();
}

// 是否可推播（peek，不改變狀態）。cooldown 關閉時一律可推。
function canSendTelegram(key, options = {}) {
  if (!isCooldownEnabled(options)) return true;
  const last = lastSentAt.get(key);
  if (last === undefined) return true;
  return nowMsOf(options) - last >= cooldownMs(options);
}

// 記錄一次「成功推播」，開始冷卻。cooldown 關閉時不記錄。
function markTelegramSent(key, options = {}) {
  if (!isCooldownEnabled(options)) return;
  lastSentAt.set(key, nowMsOf(options));
}

// 測試用：清空 cooldown 狀態。
function resetCooldown() {
  lastSentAt.clear();
}

module.exports = {
  canSendTelegram,
  markTelegramSent,
  resetCooldown,
  isCooldownEnabled,
  cooldownMs,
  DEFAULT_COOLDOWN_MS,
};
