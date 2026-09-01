// Production logging redaction / PII de-identification（CR-0047 B1）。
//
// 目的：
// - 在 `config/env.js` 既有 mask primitive 之上，補「物件層 / 錯誤層」遮蔽，
//   讓 backend log 不外洩 token / secret / email / phone / DATABASE_URL /
//   完整對話 / Care Alert summary·reason / 第三方 SDK 原始錯誤 payload。
//
// 設計原則（見 docs/CHANGE_REVIEW.md CR-0047 §6 裁決 1/2）：
// - **delegate `config/env.js` 既有 primitive，不重造 masking 規則**
//   （maskSecret / maskEmail / maskPhone / maskDatabaseUrl 是單一來源）。
// - production vs dev 差異**只在自由文字截斷長度 / 是否附 stack**；
//   **secret/token/key/DATABASE_URL/email/phone 兩環境恆遮蔽**。
// - 純函式、不 mutate 入參（redactObject 回新物件）、防循環參照與過深遞迴。
// - 本檔只負責「輸出內容遮蔽」，**不改任何 try/catch 控制流 / return / throw**。

"use strict";

const {
  maskSecret,
  maskEmail,
  maskPhone,
  maskDatabaseUrl,
  isProduction,
} = require("../../config/env");

// 自由文字（transcript / summary / reason 等敏感內容）截斷長度。
// 即使 dev/staging 也只保留**短前綴**作為除錯線索，確保完整對話 / 摘要永不落 log。
const PROD_FREETEXT_LIMIT = 0; // production：敏感自由文字一律 [REDACTED]，不留前綴。
const DEV_FREETEXT_LIMIT = 64; // dev/staging：僅保留前 64 字作為除錯提示。
const PROD_STRING_LIMIT = 200; // production：一般字串上限。
const DEV_STRING_LIMIT = 1000; // dev/staging：一般字串上限。

const MAX_DEPTH = 6;
const REDACTED = "[REDACTED]";

// 敏感 key 分類（一律以小寫比對 key 名稱；精確比對，不做 substring 以免誤傷）。
const TOKEN_KEYS = new Set([
  "token",
  "accesstoken",
  "idtoken",
  "refreshtoken",
  "authorization",
  "apikey",
  "key",
  "secret",
  "password",
  "telegramtoken",
  "telegrambottoken",
  "openaiapikey",
  "bottoken",
]);
const EMAIL_KEYS = new Set(["email"]);
const PHONE_KEYS = new Set(["phone", "phonenumber"]);
const DBURL_KEYS = new Set(["databaseurl", "database_url"]);
// 弱識別子 / 行為識別子：直接遮蔽（不保留值）。
const OPAQUE_KEYS = new Set([
  "chatid",
  "chat_id",
  "userid",
  "user_id",
  "elderid",
  "elder_id",
  "caregiverid",
  "caregiver_id",
  "firebaseuid",
  "firebase_uid",
  "petname",
  "pet_name",
]);
// 自由文字內容（對話 / 摘要 / 風險原因）：截斷 + 標記。
const FREETEXT_KEYS = new Set([
  "transcript",
  "message",
  "conversation",
  "memory",
  "reason",
  "summary",
  "usertext",
  "aireply",
  "originalusertext",
]);

function freetextLimit() {
  return isProduction() ? PROD_FREETEXT_LIMIT : DEV_FREETEXT_LIMIT;
}

function stringLimit() {
  return isProduction() ? PROD_STRING_LIMIT : DEV_STRING_LIMIT;
}

// ---- 單值 redaction（delegate env.js primitive；語意別名供呼叫端清楚）----

function redactToken(value) {
  return maskSecret(value);
}

function redactEmail(value) {
  return maskEmail(value);
}

function redactPhone(value) {
  return maskPhone(value);
}

function redactDatabaseUrl(value) {
  return maskDatabaseUrl(value);
}

// 截斷自由文字（對話 / 摘要 / reason）。production limit=0 → 直接 [REDACTED]。
function truncateFreetext(value) {
  const s = String(value == null ? "" : value);
  if (!s) return s;
  const limit = freetextLimit();
  if (limit <= 0) return REDACTED;
  if (s.length <= limit) return s;
  return `${s.slice(0, limit)}…[truncated]`;
}

// 截斷一般長字串（非敏感 key，但避免整包 body 落 log）。
function truncateString(value) {
  const s = String(value == null ? "" : value);
  const limit = stringLimit();
  if (s.length <= limit) return s;
  return `${s.slice(0, limit)}…[truncated:${s.length}]`;
}

// 在自由錯誤訊息中遮蔽嵌入的 secret / email / phone
// （防第三方 SDK 把 key 或 PII 塞進 error.message）。
function scrubSensitiveInText(text) {
  let s = String(text == null ? "" : text);
  if (!s) return s;
  // OpenAI 風格金鑰 sk-xxxx / sk-proj-xxxx。
  s = s.replace(/sk-[A-Za-z0-9_-]{8,}/g, (m) => maskSecret(m));
  // Bearer <token>。
  s = s.replace(/Bearer\s+[A-Za-z0-9._\-]+/gi, "Bearer " + REDACTED);
  // JWT（三段 base64url）。
  s = s.replace(
    /\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b/g,
    REDACTED,
  );
  // email。
  s = s.replace(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g, (m) =>
    maskEmail(m),
  );
  return s;
}

// 依 key 名稱決定遮蔽策略；回傳 { handled, value }。
function redactByKey(key, value) {
  const k = String(key || "").toLowerCase();
  if (TOKEN_KEYS.has(k)) {
    return { handled: true, value: value == null || value === "" ? value : REDACTED };
  }
  if (DBURL_KEYS.has(k)) {
    return { handled: true, value: redactDatabaseUrl(value) };
  }
  if (EMAIL_KEYS.has(k)) {
    return { handled: true, value: redactEmail(value) };
  }
  if (PHONE_KEYS.has(k)) {
    return { handled: true, value: redactPhone(value) };
  }
  if (OPAQUE_KEYS.has(k)) {
    return { handled: true, value: value == null || value === "" ? value : REDACTED };
  }
  if (FREETEXT_KEYS.has(k)) {
    return { handled: true, value: truncateFreetext(value) };
  }
  return { handled: false, value: undefined };
}

// 遞迴遮蔽物件 / 陣列。**不 mutate 入參**（回新結構）。防循環參照與過深遞迴。
function redactObject(value, _depth = 0, _seen = new WeakSet()) {
  if (value == null) return value;

  if (typeof value === "string") {
    return truncateString(value);
  }
  if (typeof value === "number" || typeof value === "boolean") {
    return value;
  }
  if (typeof value === "bigint") {
    return value.toString();
  }
  if (typeof value === "function" || typeof value === "symbol") {
    return `[${typeof value}]`;
  }

  // Error 物件 → safe message（不含 stack）。
  if (value instanceof Error) {
    return safeErrorMessage(value);
  }

  if (_depth >= MAX_DEPTH) {
    return "[Object: max depth]";
  }
  if (typeof value === "object") {
    if (_seen.has(value)) return "[Circular]";
    _seen.add(value);

    if (Array.isArray(value)) {
      return value.map((item) => redactObject(item, _depth + 1, _seen));
    }

    const out = {};
    for (const key of Object.keys(value)) {
      const byKey = redactByKey(key, value[key]);
      if (byKey.handled) {
        out[key] = byKey.value;
      } else {
        out[key] = redactObject(value[key], _depth + 1, _seen);
      }
    }
    return out;
  }

  return value;
}

// 只回 error 的安全摘要：code / 遮蔽過的 message。**不含 stack / request body /
// 完整 error 物件 / token**。message 本身再過 secret/PII 遮蔽。
function safeErrorMessage(error) {
  if (error == null) return "";
  if (typeof error === "string") return scrubSensitiveInText(truncateString(error));

  const code =
    error && error.code != null && error.code !== "" ? String(error.code) : "";
  const rawMessage =
    error && error.message != null ? String(error.message) : "";
  const message = scrubSensitiveInText(truncateString(rawMessage));

  if (code && message) return `${code}: ${message}`;
  if (code) return code;
  if (message) return message;
  // 沒有 code/message 也**不**落回完整 error 物件（避免 stack/payload 外洩）。
  return "error";
}

// log 附帶物件套 redactObject（production 走完整遮蔽 + 截斷）。
function safeLogPayload(payload) {
  if (payload == null) return payload;
  if (typeof payload !== "object") {
    return typeof payload === "string" ? truncateString(payload) : payload;
  }
  return redactObject(payload);
}

module.exports = {
  redactToken,
  redactEmail,
  redactPhone,
  redactDatabaseUrl,
  redactObject,
  safeErrorMessage,
  safeLogPayload,
  // 常數匯出供測試 / 呼叫端參考。
  REDACTED,
};
