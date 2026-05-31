// caregiver_web 健康分析 Dashboard 靜態回歸測試（CR-0007 Batch 4）。
//
// caregiver_web 為原生 JS（依賴 document/window），無 DOM 測試環境；
// 比照 care_alert_display.test.js 以「來源靜態檢查」確保：
//   - 健康分析分頁與六指標、五大分析區塊不被誤刪
//   - 只使用實際存在的 /api/admin/* 端點與 response 欄位（不假造欄位）
//   - 既有 Care Alert 顯示不被破壞
//
// 執行：node --test caregiver_web/admin_dashboard.test.js

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const appJs = fs.readFileSync(path.join(__dirname, "app.js"), "utf8");
const indexHtml = fs.readFileSync(path.join(__dirname, "index.html"), "utf8");

test("有『照護提醒 / 健康分析』分頁", () => {
  assert.ok(indexHtml.includes("照護提醒"), "應有照護提醒分頁");
  assert.ok(indexHtml.includes("健康分析"), "應有健康分析分頁");
  for (const id of ["tab-alerts", "tab-health", "view-alerts", "view-health"]) {
    assert.ok(indexHtml.includes(id), `index 應有 #${id}`);
    assert.ok(appJs.includes(id), `app.js 應引用 #${id}`);
  }
});

test("健康概況六指標卡齊全", () => {
  for (const label of [
    "長者總數",
    "今日活躍",
    "今日提醒",
    "高風險長者",
    "情緒異常",
    "認知退化關注",
  ]) {
    assert.ok(indexHtml.includes(label), `健康概況應含『${label}』`);
  }
  for (const id of ["ov-total", "ov-active", "ov-alerts", "ov-highrisk", "ov-emotion", "ov-cognitive"]) {
    assert.ok(indexHtml.includes(id), `應有 #${id}`);
    assert.ok(appJs.includes(id), `app.js 應更新 #${id}`);
  }
});

test("五大分析區塊標題齊全", () => {
  for (const title of [
    "生理健康分析",
    "心理健康分析",
    "情緒分析歷史",
    "遊戲認知退化指標",
    "近期照護提醒",
  ]) {
    assert.ok(indexHtml.includes(title), `應有『${title}』區塊`);
  }
  assert.ok(indexHtml.includes("長者列表"), "應有長者列表");
});

test("使用實際存在的 /api/admin/* 端點", () => {
  assert.ok(appJs.includes("/admin/overview"), "應呼叫 /admin/overview");
  assert.ok(appJs.includes("/admin/elders"), "應呼叫 /admin/elders（列表）");
  assert.ok(
    appJs.includes("/admin/elders/"),
    "應呼叫 /admin/elders/:elderId（個人分析）"
  );
});

test("overview 對應實際回傳欄位（不假造）", () => {
  for (const field of [
    "totalElders",
    "activeToday",
    "careAlertsToday",
    "highRiskElders",
    "emotionAbnormalElders",
    "cognitiveDeclineElders",
  ]) {
    assert.ok(appJs.includes(field), `overview 應用 ${field}`);
  }
});

test("生理健康對應 physio.summary / series 實際欄位", () => {
  for (const field of [
    "avgSleepHours",
    "avgDailyInteractionMinutes",
    "avgReminderCompletionRate",
    "avgMedicationCompletionRate",
    "avgWaterCompletionRate",
    "avgExerciseCompletionRate",
    "sleepQuality",
  ]) {
    assert.ok(appJs.includes(field), `physio 應用 ${field}`);
  }
});

test("心理 / 情緒 / 遊戲 對應實際欄位（不假造）", () => {
  // psych
  assert.ok(appJs.includes("dominantEmotion"), "psych 應用 dominantEmotion");
  assert.ok(appJs.includes("psych"), "應讀 psych");
  // 情緒歷史
  assert.ok(appJs.includes("emotionHistory"), "應讀 emotionHistory");
  // 遊戲退化
  for (const field of ["cognitiveScore", "completionRate", "regressionFlag", "trend"]) {
    assert.ok(appJs.includes(field), `game 應用 ${field}`);
  }
});

test("長者列表對應 summaryRow 實際欄位", () => {
  for (const field of ["displayName", "lastActiveAt", "latestRiskLevel", "emotionAbnormal", "cognitiveDecline"]) {
    assert.ok(appJs.includes(field), `elder list 應用 ${field}`);
  }
});

test("high / urgent 風險在健康頁清楚可見（重用 risk 樣式）", () => {
  assert.ok(appJs.includes("riskBadge"), "應有 riskBadge");
  assert.ok(appJs.includes("riskClass"), "近期提醒應套 risk class");
  assert.ok(appJs.includes("health-alert"), "應有 health-alert 區塊");
});

test("既有 Care Alert 顯示未被破壞（loadAlerts / triggerSummary 仍在）", () => {
  assert.ok(appJs.includes("loadAlerts"), "仍保留 loadAlerts");
  assert.ok(appJs.includes("triggerSummary"), "仍保留 triggerSummary 顯示");
  assert.ok(indexHtml.includes("照護提醒列表"), "仍保留照護提醒列表");
  assert.ok(indexHtml.includes("長者關懷管理中心"), "header 標題不變");
});
