const assert = require("node:assert/strict");
const { test } = require("node:test");

const {
  normalizeAppEnv,
  isProduction,
  resolveListenHost,
  isCrawlerRefreshEnabled,
  parseBoolean,
  validateProductionEnv,
  isJsonFallbackAllowed,
  describeMaskedConfig,
  FEATURE_UNAVAILABLE_IN_PRODUCTION,
  FeatureUnavailableInProductionError,
  isFeatureUnavailableError,
  maskSecret,
  maskEmail,
  maskPhone,
  maskDatabaseUrl,
} = require("./env");

// 一組「production 必要設定齊全」的基底，供各案抽掉單一變數測 missing。
function fullProdEnv(overrides = {}) {
  return {
    APP_ENV: "production",
    DATABASE_URL: "postgres://u:p@db:5432/app",
    OPENAI_API_KEY: "sk-live-abcdef1234",
    CORS_ALLOWED_ORIGINS: "https://app.example.com",
    GOOGLE_APPLICATION_CREDENTIALS: "/run/secrets/firebase.json",
    ADMIN_API_TOKEN: "admin-token-xyz",
    ...overrides,
  };
}

test("normalizeAppEnv：APP_ENV 優先，否則由 NODE_ENV 對映", () => {
  assert.equal(normalizeAppEnv({ APP_ENV: "staging", NODE_ENV: "production" }), "staging");
  assert.equal(normalizeAppEnv({ NODE_ENV: "production" }), "production");
  assert.equal(normalizeAppEnv({ NODE_ENV: "development" }), "development");
  assert.equal(normalizeAppEnv({}), "development");
});

test("normalizeAppEnv：NODE_ENV=test 永不解析為 production", () => {
  assert.equal(normalizeAppEnv({ NODE_ENV: "test" }), "development");
  // 即使 APP_ENV=production，test 環境也降為 development。
  assert.equal(normalizeAppEnv({ NODE_ENV: "test", APP_ENV: "production" }), "development");
  assert.equal(isProduction({ NODE_ENV: "test", APP_ENV: "production" }), false);
});

test("resolveListenHost：production 預設綁容器網卡，dev 預設只綁本機", () => {
  assert.equal(resolveListenHost({ APP_ENV: "production" }), "0.0.0.0");
  assert.equal(resolveListenHost({ APP_ENV: "development" }), "127.0.0.1");
  assert.equal(
    resolveListenHost({ APP_ENV: "production", HOST: "10.1.2.3" }),
    "10.1.2.3",
  );
});

test("isCrawlerRefreshEnabled：production 關閉資料建置端點", () => {
  assert.equal(isCrawlerRefreshEnabled({ APP_ENV: "production" }), false);
  assert.equal(isCrawlerRefreshEnabled({ APP_ENV: "development" }), true);
  assert.equal(isCrawlerRefreshEnabled({ NODE_ENV: "test" }), true);
});

test("parseBoolean：只有 'true' / '1' 視為 true", () => {
  assert.equal(parseBoolean("true"), true);
  assert.equal(parseBoolean("TRUE"), true);
  assert.equal(parseBoolean(" 1 "), true);
  assert.equal(parseBoolean(true), true);
  assert.equal(parseBoolean("false"), false);
  assert.equal(parseBoolean("0"), false);
  assert.equal(parseBoolean(""), false);
  assert.equal(parseBoolean(undefined), false);
  assert.equal(parseBoolean("yes"), false);
});

test("validateProductionEnv：非 production（含 test）一律 ok、no missing", () => {
  assert.deepEqual(validateProductionEnv({ NODE_ENV: "test" }), { ok: true, missing: [] });
  assert.deepEqual(validateProductionEnv({ APP_ENV: "development" }), { ok: true, missing: [] });
  // NODE_ENV=test 即使缺所有設定也不視為 production。
  assert.deepEqual(
    validateProductionEnv({ NODE_ENV: "test", APP_ENV: "production" }),
    { ok: true, missing: [] },
  );
});

test("validateProductionEnv：齊全時 ok", () => {
  assert.deepEqual(validateProductionEnv(fullProdEnv()), { ok: true, missing: [] });
});

test("validateProductionEnv：production 缺 DATABASE_URL → missing", () => {
  const env = fullProdEnv();
  delete env.DATABASE_URL;
  const result = validateProductionEnv(env);
  assert.equal(result.ok, false);
  assert.ok(result.missing.includes("DATABASE_URL"));
});

test("validateProductionEnv：production 缺 OPENAI_API_KEY → missing", () => {
  const env = fullProdEnv();
  delete env.OPENAI_API_KEY;
  const result = validateProductionEnv(env);
  assert.equal(result.ok, false);
  assert.ok(result.missing.includes("OPENAI_API_KEY"));
});

test("validateProductionEnv：production 缺 CORS（新名與別名皆空）→ missing", () => {
  const env = fullProdEnv();
  delete env.CORS_ALLOWED_ORIGINS;
  const result = validateProductionEnv(env);
  assert.equal(result.ok, false);
  assert.ok(result.missing.includes("CORS_ALLOWED_ORIGINS"));
});

test("validateProductionEnv：CORS 相容別名 ALLOWED_ORIGINS 視為已設", () => {
  const env = fullProdEnv();
  delete env.CORS_ALLOWED_ORIGINS;
  env.ALLOWED_ORIGINS = "https://app.example.com";
  const result = validateProductionEnv(env);
  assert.equal(result.ok, true);
});

test("validateProductionEnv：Firebase 三件組可替代 GOOGLE_APPLICATION_CREDENTIALS", () => {
  const env = fullProdEnv();
  delete env.GOOGLE_APPLICATION_CREDENTIALS;
  env.FIREBASE_PROJECT_ID = "proj";
  env.FIREBASE_CLIENT_EMAIL = "svc@proj.iam.gserviceaccount.com";
  env.FIREBASE_PRIVATE_KEY = "-----BEGIN PRIVATE KEY-----xxx";
  assert.equal(validateProductionEnv(env).ok, true);

  // 三件組缺一 → missing Firebase。
  delete env.FIREBASE_PRIVATE_KEY;
  const result = validateProductionEnv(env);
  assert.equal(result.ok, false);
  assert.ok(result.missing.includes("FIREBASE_SERVICE_ACCOUNT"));
});

test("validateProductionEnv：缺 ADMIN_API_TOKEN → missing", () => {
  const env = fullProdEnv();
  delete env.ADMIN_API_TOKEN;
  const result = validateProductionEnv(env);
  assert.equal(result.ok, false);
  assert.ok(result.missing.includes("ADMIN_API_TOKEN"));
});

test("validateProductionEnv：啟用 Telegram（有 chat id）卻缺 bot token → missing", () => {
  const env = fullProdEnv({ TELEGRAM_CARE_CHAT_ID: "12345" });
  const result = validateProductionEnv(env);
  assert.equal(result.ok, false);
  assert.ok(result.missing.includes("TELEGRAM_BOT_TOKEN"));

  // 補上 token 後通過。
  const ok = validateProductionEnv(
    fullProdEnv({ TELEGRAM_CARE_CHAT_ID: "12345", TELEGRAM_BOT_TOKEN: "bot-token" }),
  );
  assert.equal(ok.ok, true);
});

test("validateProductionEnv：production 顯式打開不安全旗標 → 拒絕", () => {
  assert.equal(validateProductionEnv(fullProdEnv({ ALLOW_JSON_FALLBACK: "true" })).ok, false);
  assert.equal(validateProductionEnv(fullProdEnv({ ALLOW_MOCK_SERVICES: "true" })).ok, false);
  assert.equal(validateProductionEnv(fullProdEnv({ REQUIRE_AUTH: "false" })).ok, false);
  // 安全值不影響。
  assert.equal(validateProductionEnv(fullProdEnv({ REQUIRE_AUTH: "true" })).ok, true);
});

test("maskSecret：不外洩完整 secret", () => {
  const secret = "sk-live-supersecretvalue9876";
  const masked = maskSecret(secret);
  assert.ok(!masked.includes(secret));
  assert.ok(!masked.includes("supersecret"));
  assert.equal(masked, "sk-***9876");
  // 過短 secret 完全遮蔽。
  assert.equal(maskSecret("short"), "***");
  assert.equal(maskSecret(""), "");
});

test("maskEmail：保留前 2 碼與網域、不外洩完整 local part", () => {
  const email = "ouyoulun@example.com";
  const masked = maskEmail(email);
  assert.ok(!masked.includes(email));
  assert.ok(!masked.includes("ouyoulun"));
  assert.equal(masked, "ou***@example.com");
});

test("maskPhone：不外洩完整號碼", () => {
  const phone = "0912345789";
  const masked = maskPhone(phone);
  assert.ok(!masked.includes(phone));
  assert.equal(masked, "0912***789");
});

test("maskDatabaseUrl：只保留 scheme", () => {
  const url = "postgres://user:pass@host:5432/appdb";
  const masked = maskDatabaseUrl(url);
  assert.ok(!masked.includes(url));
  assert.ok(!masked.includes("pass"));
  assert.ok(!masked.includes("host"));
  assert.equal(masked, "postgres://***");
});

// ---- CR-0034 B2：isJsonFallbackAllowed ----

test("isJsonFallbackAllowed：非 production 一律允許", () => {
  assert.equal(isJsonFallbackAllowed({ NODE_ENV: "development" }), true);
  assert.equal(isJsonFallbackAllowed({ APP_ENV: "staging" }), true);
  assert.equal(isJsonFallbackAllowed({ NODE_ENV: "test" }), true);
  // NODE_ENV=test 即使 APP_ENV=production 也視為 dev → 允許（保護既有測試基線）。
  assert.equal(
    isJsonFallbackAllowed({ NODE_ENV: "test", APP_ENV: "production" }),
    true,
  );
});

test("isJsonFallbackAllowed：production 預設不允許，僅顯式 true 才允許", () => {
  assert.equal(isJsonFallbackAllowed({ APP_ENV: "production" }), false);
  assert.equal(
    isJsonFallbackAllowed({ APP_ENV: "production", ALLOW_JSON_FALLBACK: "false" }),
    false,
  );
  // 顯式 true 才允許（但實務上 validateProductionEnv 會對此 fail-fast）。
  assert.equal(
    isJsonFallbackAllowed({ APP_ENV: "production", ALLOW_JSON_FALLBACK: "true" }),
    true,
  );
});

// ---- CR-0034 B2：FeatureUnavailableInProductionError ----

test("FeatureUnavailableInProductionError：帶具名 code，預設訊息為錯誤碼", () => {
  const err = new FeatureUnavailableInProductionError();
  assert.ok(err instanceof Error);
  assert.equal(err.code, FEATURE_UNAVAILABLE_IN_PRODUCTION);
  assert.equal(err.message, FEATURE_UNAVAILABLE_IN_PRODUCTION);
  assert.equal(FEATURE_UNAVAILABLE_IN_PRODUCTION, "feature_unavailable_in_production");
});

// ---- CR-0057：isFeatureUnavailableError（HTTP 邊界用來把內部碼映為 501 not_enabled）----

test("isFeatureUnavailableError：throw 型（FeatureUnavailableInProductionError，帶 code）", () => {
  const err = new FeatureUnavailableInProductionError();
  assert.equal(isFeatureUnavailableError(err), true);
  // 任意帶相同 code 的物件也視為命中。
  assert.equal(isFeatureUnavailableError({ code: FEATURE_UNAVAILABLE_IN_PRODUCTION }), true);
});

test("isFeatureUnavailableError：return 型（{ ok/success:false, error })", () => {
  assert.equal(
    isFeatureUnavailableError({ ok: false, error: FEATURE_UNAVAILABLE_IN_PRODUCTION }),
    true,
  );
  assert.equal(
    isFeatureUnavailableError({ success: false, error: FEATURE_UNAVAILABLE_IN_PRODUCTION }),
    true,
  );
});

test("isFeatureUnavailableError：一般 error / 其他結果不誤判", () => {
  assert.equal(isFeatureUnavailableError(new Error("boom")), false);
  assert.equal(isFeatureUnavailableError({ ok: false, error: "invalid_payload" }), false);
  assert.equal(isFeatureUnavailableError({ success: false, error: "not_found" }), false);
  assert.equal(isFeatureUnavailableError({ ok: true }), false);
  assert.equal(isFeatureUnavailableError(null), false);
  assert.equal(isFeatureUnavailableError(undefined), false);
  assert.equal(isFeatureUnavailableError("feature_unavailable_in_production"), false);
});

// ---- CR-0034 B2：describeMaskedConfig（啟動摘要絕不外洩完整值）----

test("describeMaskedConfig：所有敏感值皆遮蔽、未設定顯示 (unset)", () => {
  const env = {
    APP_ENV: "production",
    DATABASE_URL: "postgres://user:supersecretpass@db.internal:5432/app",
    OPENAI_API_KEY: "sk-live-abcdef1234567890",
    TELEGRAM_BOT_TOKEN: "123456:AAroundsecretbotvalue",
    TELEGRAM_CARE_CHAT_ID: "987654",
    FIREBASE_CLIENT_EMAIL: "service@my-proj.iam.gserviceaccount.com",
    ADMIN_API_TOKEN: "admin-token-supersecret-value",
  };
  const desc = describeMaskedConfig(env);
  const flat = JSON.stringify(desc);
  // 絕不出現任何完整敏感原值。
  assert.ok(!flat.includes("supersecretpass"));
  assert.ok(!flat.includes("db.internal"));
  assert.ok(!flat.includes("sk-live-abcdef1234567890"));
  assert.ok(!flat.includes("AAroundsecretbotvalue"));
  assert.ok(!flat.includes("admin-token-supersecret-value"));
  assert.ok(!flat.includes("service@my-proj"));
  // chat id 只回是否設定，不回值。
  assert.ok(!flat.includes("987654"));
  assert.equal(desc.telegramCareChatId, "(set)");
  assert.equal(desc.appEnv, "production");
  assert.equal(desc.jsonFallbackAllowed, false);
  assert.equal(desc.databaseUrl, "postgres://***");
  assert.equal(desc.firebaseClientEmail, "se***@my-proj.iam.gserviceaccount.com");
});

test("describeMaskedConfig：未設定的敏感值顯示 (unset)，不誤印空字串", () => {
  const desc = describeMaskedConfig({ NODE_ENV: "development" });
  assert.equal(desc.databaseUrl, "(unset)");
  assert.equal(desc.openaiApiKey, "(unset)");
  assert.equal(desc.telegramBotToken, "(unset)");
  assert.equal(desc.telegramCareChatId, "(unset)");
  assert.equal(desc.adminApiToken, "(unset)");
  assert.equal(desc.appEnv, "development");
  assert.equal(desc.jsonFallbackAllowed, true);
});
