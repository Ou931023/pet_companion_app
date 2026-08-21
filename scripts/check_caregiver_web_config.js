#!/usr/bin/env node

// CR-0103 production guard:
// Validate caregiver_web config.js before publishing the caregiver dashboard.
// This script intentionally reads only the explicit config file path, never .env.

const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const repoRoot = path.resolve(__dirname, "..");
const defaultConfigPath = path.join(repoRoot, "caregiver_web", "config.js");
const configPath = path.resolve(process.argv[2] || defaultConfigPath);
const guardName = "check_caregiver_web_config";

function fail(message) {
  console.error(`[${guardName}] FAIL:`, message);
  process.exitCode = 1;
}

function pass(message) {
  console.log(`[${guardName}] OK:`, message);
}

function isHttpsUrl(value) {
  try {
    const url = new URL(value);
    return url.protocol === "https:";
  } catch (_) {
    return false;
  }
}

function isLocalUrl(value) {
  return /localhost|127\.0\.0\.1|0\.0\.0\.0|ngrok-free\.app|ngrok\.io/i.test(
    String(value || "")
  );
}

function hasText(value) {
  return typeof value === "string" && value.trim().length > 0;
}

function stripLineAndBlockComments(value) {
  let result = "";
  let i = 0;
  let quote = null;
  while (i < value.length) {
    const char = value[i];
    const next = value[i + 1];
    if (quote) {
      result += char;
      if (char === "\\" && i + 1 < value.length) {
        result += value[i + 1];
        i += 2;
        continue;
      }
      if (char === quote) quote = null;
      i += 1;
      continue;
    }
    if (char === '"' || char === "'" || char === "`") {
      quote = char;
      result += char;
      i += 1;
      continue;
    }
    if (char === "/" && next === "/") {
      while (i < value.length && value[i] !== "\n") i += 1;
      result += "\n";
      continue;
    }
    if (char === "/" && next === "*") {
      i += 2;
      while (i < value.length && !(value[i] === "*" && value[i + 1] === "/")) {
        if (value[i] === "\n") result += "\n";
        i += 1;
      }
      i += 2;
      continue;
    }
    result += char;
    i += 1;
  }
  return result;
}

if (!fs.existsSync(configPath)) {
  fail(
    "找不到 config.js。請複製 caregiver_web/config.example.js 為 caregiver_web/config.js 後填入正式設定。"
  );
  process.exit();
}

const source = fs.readFileSync(configPath, "utf8");
const executableSource = stripLineAndBlockComments(source);

if (/private_key|service_account|client_email|ADMIN_API_TOKEN|Bearer\s+/i.test(executableSource)) {
  fail("config.js 不可包含 Firebase Admin private key、service account、ADMIN_API_TOKEN 或 Bearer token。");
}

const sandbox = {
  window: {},
  console: {
    log() {},
    warn() {},
    error() {},
  },
};
sandbox.window.window = sandbox.window;

try {
  vm.runInNewContext(source, sandbox, {
    filename: configPath,
    timeout: 1000,
  });
} catch (error) {
  fail("config.js 無法被解析，請檢查 JavaScript 語法。");
  console.error(error.message);
  process.exit();
}

const config = sandbox.window.APP_CONFIG;
if (!config || typeof config !== "object") {
  fail("config.js 必須設定 window.APP_CONFIG 物件。");
  process.exit();
}

if (!hasText(config.apiBaseUrl)) {
  fail("window.APP_CONFIG.apiBaseUrl 必須填正式後端 HTTPS API，例如 https://your-api.example.com/api。");
} else if (!isHttpsUrl(config.apiBaseUrl)) {
  fail("apiBaseUrl 必須是 HTTPS URL。");
} else if (isLocalUrl(config.apiBaseUrl)) {
  fail("apiBaseUrl 不可使用 localhost、127.0.0.1、ngrok 或本機位址。");
} else {
  pass("apiBaseUrl 是正式 HTTPS URL。");
}

const firebase = config.firebase || config.firebaseConfig;
if (!firebase || typeof firebase !== "object") {
  fail("window.APP_CONFIG.firebase 必須填 Firebase Web app config，照護人員才能用 Email / Google 登入。");
} else {
  const requiredKeys = ["apiKey", "authDomain", "projectId", "appId"];
  for (const key of requiredKeys) {
    if (!hasText(firebase[key])) {
      fail(`firebase.${key} 不可為空。`);
    }
  }
  if (hasText(firebase.authDomain) && isLocalUrl(firebase.authDomain)) {
    fail("firebase.authDomain 不可使用 localhost / ngrok。");
  }
  if (requiredKeys.every((key) => hasText(firebase[key]))) {
    pass("Firebase Web config 必填欄位齊全。");
  }
}

const flags = config.featureFlags || {};
for (const key of ["marketplace", "dailyCareTasks"]) {
  if (typeof flags[key] !== "boolean") {
    fail(`featureFlags.${key} 必須明確填 true 或 false，避免正式版分頁狀態不清楚。`);
  }
}
if (typeof flags.marketplace === "boolean" && typeof flags.dailyCareTasks === "boolean") {
  pass("featureFlags 已明確設定。");
}

if (!process.exitCode) {
  console.log(`[${guardName}] PASS: caregiver_web production config looks deployable.`);
}
