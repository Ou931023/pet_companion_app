// CR-0025 caregiver_web 日常任務追蹤 view 靜態回歸測試。
//
// caregiver_web 為原生 JS（依賴 document/window），無 DOM 測試環境；
// 比照 admin_dashboard.test.js 以「來源靜態檢查」確保：
//   - 日常任務分頁與統計、任務列表、AI 結果欄位不被誤刪
//   - 使用實際存在的 /api/admin/daily-care-tasks 端點
//   - 後端連不到時顯示白話錯誤（不假裝有資料）
//   - 既有照護提醒 / 健康分析顯示不被破壞
//
// 執行：node --test caregiver_web/daily_care_task_dashboard.test.js

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const appJs = fs.readFileSync(path.join(__dirname, "app.js"), "utf8");
const indexHtml = fs.readFileSync(path.join(__dirname, "index.html"), "utf8");
const configExample = fs.readFileSync(
  path.join(__dirname, "config.example.js"),
  "utf8",
);

test("有『日常任務』分頁與 view 容器", () => {
  assert.ok(indexHtml.includes("日常任務"), "index 應有日常任務分頁");
  for (const id of ["tab-tasks", "view-tasks", "task-list", "tasks-filter"]) {
    assert.ok(indexHtml.includes(id), `index 應有 #${id}`);
    assert.ok(appJs.includes(id), `app.js 應引用 #${id}`);
  }
});

test("任務統計五張卡齊全", () => {
  for (const label of ["今日任務", "已完成", "未完成", "等待查看", "已逾時"]) {
    assert.ok(indexHtml.includes(label), `統計應含『${label}』`);
  }
  for (const id of [
    "task-stat-total",
    "task-stat-completed",
    "task-stat-pending",
    "task-stat-review",
    "task-stat-missed",
  ]) {
    assert.ok(indexHtml.includes(id), `應有 #${id}`);
    assert.ok(appJs.includes(id), `app.js 應更新 #${id}`);
  }
});

test("使用實際存在的 /api/admin/daily-care-tasks 端點", () => {
  assert.ok(
    appJs.includes("/daily-care-tasks"),
    "應呼叫 /admin/daily-care-tasks",
  );
  assert.ok(appJs.includes("loadDailyTasks"), "應有 loadDailyTasks 載入函式");
});

test("任務列表顯示狀態文案與 AI 判斷結果", () => {
  for (const label of ["待完成", "已完成", "等待查看", "未通過", "已逾時"]) {
    assert.ok(appJs.includes(label), `狀態文案應含『${label}』`);
  }
  // AI 結果欄位：判斷狀態、信心分數、原因、照片查看入口。
  assert.ok(appJs.includes("AI 判斷"), "應顯示 AI 判斷狀態");
  assert.ok(appJs.includes("信心"), "應顯示 AI 信心分數");
  assert.ok(appJs.includes("原因"), "應顯示 AI 原因");
  assert.ok(appJs.includes("查看照片"), "應有照片證明查看入口");
  assert.ok(appJs.includes("verification"), "應讀取 submission.verification");
});

test("照片驗證結果以照護者可讀摘要呈現", () => {
  assert.ok(appJs.includes("照片驗證摘要"), "應有照片驗證摘要標題");
  assert.ok(appJs.includes("需要照護者確認"), "應標明是否需要人工確認");
  assert.ok(appJs.includes("暫不需人工確認"), "通過時應清楚標明暫不需人工確認");
  assert.ok(appJs.includes("辨識內容"), "應顯示 AI 辨識到的內容");
  assert.ok(appJs.includes("detectedObjects"), "應讀取 detectedObjects");
  assert.ok(appJs.includes("reviewRequired"), "應讀取 reviewRequired");
  assert.ok(appJs.includes("task-verification-card"), "應用卡片方式呈現驗證資訊");
});

test("AI 判斷文案不宣稱藥物 / 劑量正確（安全界線）", () => {
  // 只檢查實際輸出（字串 / HTML），剔除 // 註解行，避免把「安全界線」說明本身誤判。
  const appCode = appJs
    .split("\n")
    .filter((line) => !line.trim().startsWith("//"))
    .join("\n");
  for (const forbidden of ["劑量正確", "藥物正確", "確認你真的吃", "放心服用"]) {
    assert.ok(!appCode.includes(forbidden), `不應出現『${forbidden}』`);
  }
  // 改用安全標籤（只描述照片是否相符）。
  assert.ok(appJs.includes("照片相符"), "AI 通過用『照片相符』而非藥物正確");
  assert.ok(appJs.includes("需人工確認"), "不確定用『需人工確認』");
});

test("後端連不到時顯示白話錯誤且不假裝有資料", () => {
  assert.ok(appJs.includes(".catch("), "loadDailyTasks 應處理連線錯誤");
  assert.ok(appJs.includes("連不到後端"), "應有白話的連線失敗提示");
});

test("狀態篩選選項齊全", () => {
  for (const value of [
    'value="pending"',
    'value="completed"',
    'value="needs_review"',
    'value="missed"',
    'value="rejected"',
  ]) {
    assert.ok(indexHtml.includes(value), `篩選應有 ${value}`);
  }
});

test("CR-0056：今日任務分頁能力保留但受 featureFlags 控制（預設隱藏）", () => {
  // 能力 / 結構不刪：tab-tasks / view-tasks 仍在（上方既有測試已涵蓋）。
  // 旗標預設關：config.example.js 的 featureFlags.dailyCareTasks 預設 false。
  assert.ok(configExample.includes("featureFlags"), "config 範本應有 featureFlags");
  assert.ok(
    /dailyCareTasks\s*:\s*false/.test(configExample),
    "dailyCareTasks 旗標預設應為 false（正式版隱藏入口）",
  );
  // app.js 以 featureEnabled('dailyCareTasks') 決定是否隱藏今日任務分頁入口。
  assert.ok(appJs.includes("function featureEnabled"), "應有 featureEnabled 旗標判斷");
  assert.ok(appJs.includes("function applyFeatureFlags"), "應有 applyFeatureFlags");
  assert.ok(
    appJs.includes('featureEnabled("dailyCareTasks")'),
    "應依 dailyCareTasks 旗標隱藏分頁",
  );
  assert.ok(
    appJs.includes("hideTabButton(elT && elT.tabTasks)"),
    "dailyCareTasks 關閉時應隱藏今日任務分頁按鈕",
  );
  // 只隱藏入口、不刪後端呼叫：loadDailyTasks / /daily-care-tasks 仍在（上方測試已驗證）。
});

test("既有照護提醒 / 健康分析分頁未被破壞", () => {
  for (const id of ["tab-alerts", "tab-health", "view-alerts", "view-health"]) {
    assert.ok(indexHtml.includes(id), `index 仍應有 #${id}`);
  }
  assert.ok(appJs.includes("loadAlerts"), "仍應有 loadAlerts");
  assert.ok(appJs.includes("loadHealthOverview"), "仍應有 loadHealthOverview");
});
