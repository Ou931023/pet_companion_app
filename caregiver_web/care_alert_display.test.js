// caregiver_web 顯示回歸測試（CR-0003 Batch 3）。
//
// caregiver_web 為原生 JS（依賴 document/window），無 DOM 測試環境；
// 此處以「來源靜態檢查」確保關鍵顯示元素不被誤刪：
//   - triggerSummary 在 list 與 detail 都有顯示
//   - 風險四級中文 label 齊全
//   - 狀態流程文字（新提醒 / 已查看 / 已處理）與操作按鈕清楚
//
// 執行：node --test caregiver_web/care_alert_display.test.js

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const appJs = fs.readFileSync(path.join(__dirname, "app.js"), "utf8");
const indexHtml = fs.readFileSync(path.join(__dirname, "index.html"), "utf8");

test("#5 list 與 detail 都顯示 triggerSummary", () => {
  // list 卡片摘要 + detail「摘要」列都引用 triggerSummary
  assert.ok(appJs.includes("triggerSummary"), "app.js 應引用 triggerSummary");
  assert.ok(appJs.includes("card-summary"), "list 應有摘要區塊");
  assert.ok(appJs.includes("摘要"), "detail 應有『摘要』列");
});

test("風險四級中文 label 齊全", () => {
  for (const label of ["一般", "持續觀察", "需通知", "緊急"]) {
    assert.ok(appJs.includes(label), `RISK_LABELS 應含「${label}」`);
  }
});

test("#6 狀態流程文字與操作按鈕清楚（new → acknowledged → resolved）", () => {
  for (const label of ["新提醒", "已查看", "已處理"]) {
    assert.ok(appJs.includes(label), `STATUS_LABELS 應含「${label}」`);
  }
  assert.ok(appJs.includes("標記為已查看"), "應有『標記為已查看』按鈕");
  assert.ok(appJs.includes("標記為已處理"), "應有『標記為已處理』按鈕");
  assert.ok(appJs.includes("此提醒已處理"), "resolved 應顯示『此提醒已處理』");
});

test("篩選下拉提供四級選項", () => {
  for (const label of ["需通知", "持續觀察"]) {
    assert.ok(indexHtml.includes(label), `風險篩選應含「${label}」`);
  }
});
