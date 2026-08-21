#!/usr/bin/env node

// CR-0103 Render/static deploy helper.
// Builds caregiver_web_dist and injects runtime config from deployment env vars.
// It deliberately excludes local config.js/runtime-config.js before generating
// fresh files, so local-only config is never copied into the hosted artifact.
// app-config.generated.js is also written to the source folder because some
// static hosts keep publishing the source folder after a Blueprint update.

const fs = require("node:fs");
const path = require("node:path");

const sourceDir = __dirname;
const distDir = path.join(__dirname, "..", "caregiver_web_dist");
const generatedFileName = "app-config.generated.js";
const runtimeOutputPath = path.join(distDir, "runtime-config.js");
const generatedDistOutputPath = path.join(distDir, generatedFileName);
const generatedSourceOutputPath = path.join(sourceDir, generatedFileName);
const compatibilityOutputPath = path.join(distDir, "config.js");
const sourceIndexPath = path.join(sourceDir, "index.html");
const distIndexPath = path.join(distDir, "index.html");
const excludedPublishFiles = new Set([
  "config.js",
  "runtime-config.js",
  generatedFileName,
]);

function envValue(name) {
  const value = process.env[name];
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function requiredEnv(name) {
  const value = envValue(name);
  if (value == null) {
    throw new Error(
      `[caregiver-web-build-config] Missing required Render env var: ${name}`
    );
  }
  return value;
}

function boolEnv(name, fallback) {
  const value = envValue(name);
  if (value == null) return fallback;
  if (/^(1|true|yes|on)$/i.test(value)) return true;
  if (/^(0|false|no|off)$/i.test(value)) return false;
  throw new Error(`${name} must be true or false`);
}

function jsonString(value) {
  return JSON.stringify(value);
}

const config = {
  apiBaseUrl:
    envValue("CAREGIVER_WEB_API_BASE_URL") ||
    envValue("API_BASE_URL") ||
    "https://ai-companion-api-rdjv.onrender.com/api",
  firebase: {
    apiKey: requiredEnv("CAREGIVER_WEB_FIREBASE_API_KEY"),
    authDomain: requiredEnv("CAREGIVER_WEB_FIREBASE_AUTH_DOMAIN"),
    projectId: requiredEnv("CAREGIVER_WEB_FIREBASE_PROJECT_ID"),
    appId: requiredEnv("CAREGIVER_WEB_FIREBASE_APP_ID"),
  },
  featureFlags: {
    marketplace: boolEnv("CAREGIVER_WEB_MARKETPLACE_ENABLED", true),
    dailyCareTasks: boolEnv("CAREGIVER_WEB_DAILY_CARE_TASKS_ENABLED", true),
  },
};

console.log("[caregiver-web-build-config] env summary (masked)", {
  apiBaseUrl: config.apiBaseUrl,
  firebaseApiKey: "set",
  firebaseAuthDomain: "set",
  firebaseProjectId: "set",
  firebaseAppId: "set",
  marketplace: config.featureFlags.marketplace,
  dailyCareTasks: config.featureFlags.dailyCareTasks,
});

const source = `// Generated at deploy time by caregiver_web/build_config_from_env.js.
// Do not edit in git.
window.APP_CONFIG = ${jsonString(config, null, 2)};
`;

function injectConfigIntoIndex(indexPath) {
  const html = fs.readFileSync(indexPath, "utf8");
  const injected = html.replace(
    /window\.APP_CONFIG\s*=\s*window\.APP_CONFIG\s*\|\|\s*\{[\s\S]*?\n\s*\};/,
    `window.APP_CONFIG = window.APP_CONFIG || ${jsonString(config, null, 2)};`
  );
  if (injected === html) {
    throw new Error(`Could not inject APP_CONFIG into ${indexPath}`);
  }
  fs.writeFileSync(indexPath, injected, { encoding: "utf8", mode: 0o644 });
}

fs.rmSync(distDir, { recursive: true, force: true });
fs.mkdirSync(distDir, { recursive: true });
fs.cpSync(sourceDir, distDir, {
  recursive: true,
  filter: (src) => {
    const name = path.basename(src);
    return !excludedPublishFiles.has(name);
  },
});

for (const outputPath of [
  runtimeOutputPath,
  generatedDistOutputPath,
  generatedSourceOutputPath,
  compatibilityOutputPath,
]) {
  fs.writeFileSync(outputPath, source, { encoding: "utf8", mode: 0o644 });
}
injectConfigIntoIndex(sourceIndexPath);
injectConfigIntoIndex(distIndexPath);
console.log(
  "[caregiver-web-build-config] injected APP_CONFIG into index.html and wrote runtime config files mode=0644"
);
