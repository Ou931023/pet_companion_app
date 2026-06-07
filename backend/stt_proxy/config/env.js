// 集中化環境設定（CR-0034 Batch 1 / B1）。
//
// 目的：
// - 統一三環境語義 development / staging / production（不再各 service 各自 process.env 解析旗標）。
// - 提供 production 啟動 fail-fast 的「純函式」validateProductionEnv（可單測，不退出）+
//   薄包裝 assertProductionEnvOrExit（缺 → 印安全訊息 + process.exit(1)）。
// - 提供 masked logging helper，避免把 secret / email / phone / DB URL 原值寫進 log。
//
// 紅線（見 PROJECT_ARCHITECTURE.md §7.1 / §7.1.1、docs/CHANGE_REVIEW.md CR-0034）：
// - 不讀 .env 檔內容、不寫死 secret、不印任何 token/secret 值。
// - NODE_ENV=test 永不解析為 production（保 careAlertCooldown / taigiAsr 等既有行為與測試基線）。
// - fail-fast 是「啟動層」行為，不改任何 API request/response 契約。

"use strict";

const VALID_APP_ENVS = new Set(["development", "staging", "production"]);

// 安全 boolean 解析：只有 'true' / '1'（忽略大小寫與前後空白）視為 true，其餘一律 false。
// 用於 ALLOW_MOCK_SERVICES / ALLOW_JSON_FALLBACK / REQUIRE_AUTH / REQUIRE_CONSENT /
// ENABLE_VERBOSE_LOGS 等旗標，避免 'false' 字串被當真值。
function parseBoolean(value) {
  const normalized = String(value == null ? "" : value)
    .trim()
    .toLowerCase();
  return normalized === "true" || normalized === "1";
}

// 正規化環境名稱 → 'development' | 'staging' | 'production'。
// 規則：
//   1. 顯式 APP_ENV 優先（值需為三者之一，否則忽略）。
//   2. 否則由 NODE_ENV 對映：'production' → production，其餘 → development。
//   3. NODE_ENV==='test' 永不解析為 production（即使 APP_ENV=production 也降為 development）。
function normalizeAppEnv(env = process.env) {
  const source = env || {};
  const nodeEnv = String(source.NODE_ENV || "").trim().toLowerCase();
  const appEnvRaw = String(source.APP_ENV || "").trim().toLowerCase();

  let resolved;
  if (VALID_APP_ENVS.has(appEnvRaw)) {
    resolved = appEnvRaw;
  } else if (nodeEnv === "production") {
    resolved = "production";
  } else {
    resolved = "development";
  }

  // NODE_ENV=test 永不解析為 production（保護既有測試與 demo 行為）。
  if (nodeEnv === "test" && resolved === "production") {
    resolved = "development";
  }

  return resolved;
}

function isProduction(env = process.env) {
  return normalizeAppEnv(env) === "production";
}

// 取 CORS 白名單來源（新命名 CORS_ALLOWED_ORIGINS 優先，相容既有別名 ALLOWED_ORIGINS）。
function resolveCorsOrigins(env = process.env) {
  const source = env || {};
  const raw = String(
    source.CORS_ALLOWED_ORIGINS != null
      ? source.CORS_ALLOWED_ORIGINS
      : source.ALLOWED_ORIGINS || "",
  ).trim();
  return raw;
}

// Firebase 服務帳戶是否設定（擇一）：
//   - GOOGLE_APPLICATION_CREDENTIALS，或
//   - FIREBASE_PROJECT_ID + FIREBASE_CLIENT_EMAIL + FIREBASE_PRIVATE_KEY 三件組。
// 只看變數是否存在/非空，不讀內容、不印值。
function hasFirebaseServiceAccount(env = process.env) {
  const source = env || {};
  if (String(source.GOOGLE_APPLICATION_CREDENTIALS || "").trim()) return true;
  return Boolean(
    String(source.FIREBASE_PROJECT_ID || "").trim() &&
      String(source.FIREBASE_CLIENT_EMAIL || "").trim() &&
      String(source.FIREBASE_PRIVATE_KEY || "").trim(),
  );
}

function isPresent(value) {
  return Boolean(String(value == null ? "" : value).trim());
}

// 純函式：驗證 production 必要環境設定。回 { ok, missing }（不退出、不印值）。
// 非 production（含 NODE_ENV=test）一律回 { ok:true, missing:[] }。
//
// production 必檢：
//   - DATABASE_URL
//   - OPENAI_API_KEY
//   - CORS_ALLOWED_ORIGINS（相容別名 ALLOWED_ORIGINS；空 → 缺）
//   - Firebase 服務帳戶（GOOGLE_APPLICATION_CREDENTIALS 或三件組）
//   - ADMIN_API_TOKEN
// production 條件必檢（功能啟用才檢）：
//   - TELEGRAM_BOT_TOKEN（設定了 TELEGRAM_CARE_CHAT_ID，視為已啟用 Telegram 通知）
//   - PGVECTOR_ENABLED=true 時須有 DATABASE_URL（已在必檢內，僅紀錄一致性）
// production 額外不安全旗標（顯式設定即拒絕啟動）：
//   - ALLOW_JSON_FALLBACK=true / ALLOW_MOCK_SERVICES=true / REQUIRE_AUTH=false
//
// 註：SESSION_SECRET / JWT_SECRET 現況未使用，暫不納入必檢（待 CR-0038），僅列 checklist。
function validateProductionEnv(env = process.env) {
  if (!isProduction(env)) {
    return { ok: true, missing: [] };
  }

  const source = env || {};
  const missing = [];

  if (!isPresent(source.DATABASE_URL)) missing.push("DATABASE_URL");
  if (!isPresent(source.OPENAI_API_KEY)) missing.push("OPENAI_API_KEY");
  if (!resolveCorsOrigins(source)) missing.push("CORS_ALLOWED_ORIGINS");
  if (!hasFirebaseServiceAccount(source)) {
    // 只列名稱，不揭露已設了哪一種；提示需設服務帳戶。
    missing.push("FIREBASE_SERVICE_ACCOUNT");
  }
  if (!isPresent(source.ADMIN_API_TOKEN)) missing.push("ADMIN_API_TOKEN");

  // 條件必檢：啟用 Telegram 通知（有 chat id）卻缺 bot token。
  if (isPresent(source.TELEGRAM_CARE_CHAT_ID) && !isPresent(source.TELEGRAM_BOT_TOKEN)) {
    missing.push("TELEGRAM_BOT_TOKEN");
  }

  // 額外不安全旗標：production 顯式打開降級 / 關閉驗證 → 拒絕啟動。
  if (parseBoolean(source.ALLOW_JSON_FALLBACK)) missing.push("ALLOW_JSON_FALLBACK_MUST_BE_FALSE");
  if (parseBoolean(source.ALLOW_MOCK_SERVICES)) missing.push("ALLOW_MOCK_SERVICES_MUST_BE_FALSE");
  if (source.REQUIRE_AUTH != null && !parseBoolean(source.REQUIRE_AUTH)) {
    missing.push("REQUIRE_AUTH_MUST_BE_TRUE");
  }

  return { ok: missing.length === 0, missing };
}

// 薄包裝：在 server 啟動段呼叫。非 production / NODE_ENV=test → no-op。
// production 且驗證不過 → 印「只含變數名稱」的安全訊息後 process.exit(1)。
function assertProductionEnvOrExit(env = process.env, logger = console) {
  if (!isProduction(env)) {
    return; // 非 production（含 test）一律 no-op，不影響既有啟動與測試。
  }

  const { ok, missing } = validateProductionEnv(env);
  if (ok) return;

  const log = logger && typeof logger.error === "function" ? logger : console;
  log.error(
    "[config] 正式環境啟動中止：缺少或設定不安全的必要環境變數（僅列名稱，未含任何值）：\n  - " +
      missing.join("\n  - ") +
      "\n請在部署環境補齊上述設定後重新啟動。",
  );
  process.exit(1);
}

// ---- masked logging helpers（供日後 log 使用，絕不外洩完整值）----

// sk-xxxxxxxxYYYY → sk-***YYYY（保留可辨識前綴與末 4 碼，其餘遮蔽）。
function maskSecret(value) {
  const s = String(value == null ? "" : value);
  if (!s) return "";
  if (s.length <= 8) return "***";
  const last4 = s.slice(-4);
  const prefix = s.startsWith("sk-") ? "sk-" : s.slice(0, 2);
  return `${prefix}***${last4}`;
}

// ouyoulun@example.com → ou***@example.com（保留 local 前 2 碼與完整網域）。
function maskEmail(value) {
  const s = String(value == null ? "" : value).trim();
  if (!s || !s.includes("@")) return s ? "***" : "";
  const [local, ...domainParts] = s.split("@");
  const domain = domainParts.join("@");
  const head = local.slice(0, 2);
  return `${head}***@${domain}`;
}

// 0912345789 → 0912***789（保留前 4 與末 3 碼，中段遮蔽）。
function maskPhone(value) {
  const s = String(value == null ? "" : value).trim();
  if (!s) return "";
  const digits = s.replace(/\D/g, "");
  if (digits.length <= 7) return "***";
  return `${digits.slice(0, 4)}***${digits.slice(-3)}`;
}

// postgres://user:pass@host:5432/db → postgres://***（只保留 scheme，其餘遮蔽）。
function maskDatabaseUrl(value) {
  const s = String(value == null ? "" : value).trim();
  if (!s) return "";
  const idx = s.indexOf("://");
  if (idx === -1) return "***";
  return `${s.slice(0, idx + 3)}***`;
}

module.exports = {
  normalizeAppEnv,
  isProduction,
  parseBoolean,
  resolveCorsOrigins,
  hasFirebaseServiceAccount,
  validateProductionEnv,
  assertProductionEnvOrExit,
  maskSecret,
  maskEmail,
  maskPhone,
  maskDatabaseUrl,
};
