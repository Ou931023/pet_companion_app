// caregiver_web API base URL 設定回歸測試（CR-0034 Batch 4）。
//
// caregiver_web 為原生 JS（依賴 document/window），無 DOM 測試環境；
// 此處以「來源靜態檢查」確保 API base URL 為可配置、且不把 localhost
// 硬編為正式預設。
//
// 執行：node --test caregiver_web/config_api_base.test.js

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const appJs = fs.readFileSync(path.join(__dirname, "app.js"), "utf8");
const indexHtml = fs.readFileSync(path.join(__dirname, "index.html"), "utf8");
const configExample = fs.readFileSync(
  path.join(__dirname, "config.example.js"),
  "utf8"
);

test("DEFAULT_API_BASE 不是 localhost / 127.0.0.1（無 localhost 正式預設）", () => {
  const match = appJs.match(/var\s+DEFAULT_API_BASE\s*=\s*"([^"]*)"/);
  assert.ok(match, "app.js 應定義 DEFAULT_API_BASE 常數");
  const value = match[1];
  assert.ok(
    !/127\.0\.0\.1|localhost/.test(value),
    `DEFAULT_API_BASE 不應硬編 localhost，實際為 ${value}`
  );
  assert.equal(value, "/api", "DEFAULT_API_BASE 應為同源相對路徑 /api");
});

test("getApiBase 會讀取 window.APP_CONFIG.apiBaseUrl 作為部署設定來源", () => {
  assert.ok(
    appJs.includes("window.APP_CONFIG"),
    "app.js 應讀取 window.APP_CONFIG"
  );
  assert.ok(
    appJs.includes("apiBaseUrl"),
    "app.js 應讀取 APP_CONFIG.apiBaseUrl"
  );
  assert.ok(
    appJs.includes("function configuredApiBase"),
    "app.js 應有 configuredApiBase 解析注入設定"
  );
});

test("index.html 提供 APP_CONFIG 注入點，且不以 localhost 為正式預設", () => {
  assert.ok(
    indexHtml.includes("window.APP_CONFIG"),
    "index.html 應有 window.APP_CONFIG 設定點"
  );
  // 注入區塊預設 apiBaseUrl 為 null（同源相對路徑），非 localhost。
  assert.ok(
    /window\.APP_CONFIG\s*=\s*window\.APP_CONFIG\s*\|\|\s*\{\s*apiBaseUrl:\s*null\s*\}/.test(
      indexHtml
    ),
    "index.html 注入預設 apiBaseUrl 應為 null"
  );
});

test("config.example.js 提供部署設定範本（apiBaseUrl）", () => {
  assert.ok(
    configExample.includes("window.APP_CONFIG"),
    "config.example.js 應設定 window.APP_CONFIG"
  );
  assert.ok(
    configExample.includes("apiBaseUrl"),
    "config.example.js 應包含 apiBaseUrl 欄位"
  );
});
