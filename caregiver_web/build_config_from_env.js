#!/usr/bin/env node

// CR-0103 Render/static deploy helper.
// Generates caregiver_web/config.js from deployment environment variables.
// Do not commit the generated config.js file.

const fs = require("node:fs");
const path = require("node:path");

const outputPath = path.join(__dirname, "config.js");

function envValue(name) {
  const value = process.env[name];
  return typeof value === "string" && value.trim() ? value.trim() : null;
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
    apiKey: envValue("CAREGIVER_WEB_FIREBASE_API_KEY"),
    authDomain: envValue("CAREGIVER_WEB_FIREBASE_AUTH_DOMAIN"),
    projectId: envValue("CAREGIVER_WEB_FIREBASE_PROJECT_ID"),
    appId: envValue("CAREGIVER_WEB_FIREBASE_APP_ID"),
  },
  featureFlags: {
    marketplace: boolEnv("CAREGIVER_WEB_MARKETPLACE_ENABLED", true),
    dailyCareTasks: boolEnv("CAREGIVER_WEB_DAILY_CARE_TASKS_ENABLED", true),
  },
};

const source = `// Generated at deploy time by caregiver_web/build_config_from_env.js.
// Do not edit in git.
window.APP_CONFIG = ${jsonString(config, null, 2)};
`;

fs.writeFileSync(outputPath, source, { encoding: "utf8", mode: 0o600 });
console.log("[caregiver-web-build-config] wrote caregiver_web/config.js");
