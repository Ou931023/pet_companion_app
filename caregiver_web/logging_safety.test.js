// caregiver_web logging 安全守護測試（CR-0047 Batch 4）。
//
// 目的：守護「管理端原始碼不會把 token / Authorization / 機敏 payload
// 透過 console 輸出到瀏覽器 console」。caregiver_web 為原生 JS，
// 無 DOM 測試環境，故以「來源靜態檢查」比照既有測試慣例
// （參見 config_api_base.test.js）。
//
// 執行：node --test caregiver_web/logging_safety.test.js

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const appJs = fs.readFileSync(path.join(__dirname, "app.js"), "utf8");

// 移除 // 與 /* */ 註解，避免「註解中提到 console / token」誤判。
function stripComments(src) {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/(^|[^:])\/\/[^\n]*/g, "$1");
}

const appCode = stripComments(appJs);

test("app.js 程式碼完全不使用 console.*（不輸出任何瀏覽器 console）", () => {
  const matches = appCode.match(/console\s*\.\s*\w+/g) || [];
  assert.deepEqual(
    matches,
    [],
    `app.js 不應出現 console.*，實際出現：${matches.join(", ")}`
  );
});

test("app.js 不以 console 印出 token / Authorization / Bearer", () => {
  // 任一行同時出現 console 與 token/authorization/bearer 即視為風險。
  const riskyLines = appCode
    .split("\n")
    .filter(
      (line) =>
        /console\s*\.\s*\w+/.test(line) &&
        /(token|authorization|bearer)/i.test(line)
    );
  assert.deepEqual(
    riskyLines,
    [],
    `app.js 不應以 console 輸出 token/Authorization：${riskyLines.join(" | ")}`
  );
});

test("app.js 401/403 處理不把 raw token 輸出到 console", () => {
  // 確認權限不足分支（已知存在）不夾帶 console 輸出 token。
  assert.ok(
    appCode.includes("沒有權限") || appCode.includes("forbidden"),
    "app.js 應有沒有權限/forbidden 的處理分支"
  );
  // 在含 401 / 403 的行附近不應有 console 印 token。
  const lines = appCode.split("\n");
  lines.forEach((line, idx) => {
    if (/\b(401|403)\b/.test(line)) {
      const window = lines.slice(idx, idx + 5).join("\n");
      assert.ok(
        !(/console\s*\.\s*\w+/.test(window) && /token|bearer/i.test(window)),
        `401/403 分支附近不應 console 輸出 token（行 ${idx + 1}）`
      );
    }
  });
});
