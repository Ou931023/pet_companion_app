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
const configGuard = fs.readFileSync(
  path.join(__dirname, "..", "scripts", "check_caregiver_web_config.js"),
  "utf8"
);
const configBuilder = fs.readFileSync(
  path.join(__dirname, "build_config_from_env.js"),
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
  // CR-0064：caregiver_web 為獨立 Render Static Site，正式預設指向獨立後端 URL
  //（非同源 /api）。CR-0065 起此區塊另帶 featureFlags，故不再要求剛好 `{ apiBaseUrl: null }`。
  // 安全底線不變：正式預設不可寫 localhost / 127.0.0.1。
  var injectMatch = indexHtml.match(
    /window\.APP_CONFIG\s*=\s*window\.APP_CONFIG\s*\|\|\s*\{[\s\S]*?\}/
  );
  assert.ok(injectMatch, "index.html 應有 window.APP_CONFIG 預設注入區塊");
  var baseMatch = injectMatch[0].match(/apiBaseUrl:\s*("([^"]*)"|null)/);
  assert.ok(baseMatch, "注入區塊應含 apiBaseUrl 預設值（https 後端 URL 或 null）");
  var baseValue = baseMatch[2] != null ? baseMatch[2] : "";
  assert.ok(
    !/localhost|127\.0\.0\.1/.test(baseValue),
    "index.html 正式預設不可使用 localhost / 127.0.0.1"
  );
  assert.ok(
    baseMatch[1] === "null" || /^https:\/\//.test(baseValue),
    "正式預設 apiBaseUrl 應為 null 或 https 後端 URL"
  );
  assert.equal(
    baseValue,
    "https://ai-companion-api-rdjv.onrender.com/api",
    "caregiver_web 正式預設應指向目前 production 後端"
  );
  assert.ok(
    indexHtml.includes('<script src="./app-config.generated.js"></script>') &&
      indexHtml.includes('<script src="./runtime-config.js"></script>') &&
      indexHtml.includes('<script src="./config.js"></script>'),
    "index.html 應先載入 deploy-time app-config.generated.js/runtime-config.js，並保留本機 config.js 備援"
  );
  assert.ok(
    indexHtml.includes("20260821-cr0103"),
    "app.js cache bust 應更新，避免 Render/瀏覽器吃舊版"
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

test("config.example.js 提供 Firebase Web login 設定範本且不放後端私鑰", () => {
  assert.ok(configExample.includes("firebase"), "應包含 firebase 設定區");
  for (const key of ["apiKey", "authDomain", "projectId", "appId"]) {
    assert.ok(configExample.includes(key), `應列出 Firebase Web config 欄位 ${key}`);
  }
  assert.ok(
    configExample.includes("不是後端 service account 私鑰"),
    "應說明 Firebase web apiKey 不是 service account 私鑰"
  );
  assert.ok(
    !/private_key"\s*:/.test(configExample) &&
      !/client_email"\s*:/.test(configExample),
    "範本不可放 Firebase Admin service account 欄位"
  );
});

test("CR-0103：提供 caregiver_web production config 自動檢查腳本", () => {
  assert.ok(
    configGuard.includes("check_caregiver_web_config"),
    "應提供 caregiver_web config 檢查腳本"
  );
  assert.ok(
    configGuard.includes("caregiver_web/config.js"),
    "檢查腳本預設應指向 caregiver_web/config.js"
  );
  assert.ok(
    configGuard.includes("apiBaseUrl") &&
      configGuard.includes("firebase") &&
      configGuard.includes("featureFlags"),
    "檢查腳本應驗證 API、Firebase 與 feature flags"
  );
  assert.ok(
    configGuard.includes("private_key") &&
      configGuard.includes("ADMIN_API_TOKEN") &&
      configGuard.includes("Bearer"),
    "檢查腳本應阻擋後端 secret / token"
  );
});

test("CR-0103：Render build 可由 env 產生 caregiver_web_dist/config.js", () => {
  assert.ok(
    configBuilder.includes("CAREGIVER_WEB_API_BASE_URL") &&
      configBuilder.includes("CAREGIVER_WEB_FIREBASE_API_KEY") &&
      configBuilder.includes("CAREGIVER_WEB_FIREBASE_AUTH_DOMAIN") &&
      configBuilder.includes("CAREGIVER_WEB_FIREBASE_PROJECT_ID") &&
      configBuilder.includes("CAREGIVER_WEB_FIREBASE_APP_ID"),
    "config builder 應使用 caregiver_web 專用環境變數"
  );
  assert.ok(
    configBuilder.includes("ai-companion-api-rdjv.onrender.com/api"),
    "config builder fallback 應指向新 production 後端"
  );
  assert.ok(
    configBuilder.includes("CAREGIVER_WEB_MARKETPLACE_ENABLED") &&
      configBuilder.includes("CAREGIVER_WEB_DAILY_CARE_TASKS_ENABLED"),
    "config builder 應明確處理 production feature flags"
  );
  assert.ok(
    configBuilder.includes("runtime-config.js") &&
      configBuilder.includes("app-config.generated.js") &&
      configBuilder.includes("config.js") &&
      configBuilder.includes("caregiver_web_dist") &&
      configBuilder.includes("generatedSourceOutputPath") &&
      configBuilder.includes("excludedPublishFiles") &&
      configBuilder.includes("mode=0644"),
    "config builder 應產生可公開的 source/dist runtime config，並排除本機 config 後保留相容輸出"
  );
});
