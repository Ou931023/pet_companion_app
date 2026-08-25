// 長者關懷工作台靜態回歸測試。
// 確保後台第一屏是照護工作台，且支援住民 CSV 匯入與照護人員友善流程。
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const appJs = fs.readFileSync(path.join(__dirname, "app.js"), "utf8");
const indexHtml = fs.readFileSync(path.join(__dirname, "index.html"), "utf8");
const stylesCss = fs.readFileSync(path.join(__dirname, "styles.css"), "utf8");

function bodyOf(name, span) {
  const idx = appJs.indexOf(name);
  assert.ok(idx >= 0, `應有 ${name}`);
  return appJs.slice(idx, idx + (span || 1200));
}

test("第一個分頁與預設入口是工作台", () => {
  assert.ok(indexHtml.includes('id="tab-workspace"'), "應有工作台分頁");
  assert.ok(indexHtml.includes('id="view-workspace"'), "應有工作台 view");
  assert.ok(indexHtml.indexOf('id="tab-workspace"') < indexHtml.indexOf('id="tab-alerts"'));
  const init = bodyOf("function init", 5200);
  assert.ok(init.includes('showView("workspace")'), "初始化應預設顯示工作台");
});

test("工作台整合住民、提醒與日常任務資料", () => {
  assert.ok(appJs.includes("function loadWorkspace"), "應有 loadWorkspace");
  const load = bodyOf("function loadWorkspace", 2600);
  assert.ok(load.includes("fetchWorkspaceResidents"), "工作台應載入住民");
  assert.ok(load.includes("fetchWorkspaceAlerts"), "工作台應載入提醒");
  assert.ok(load.includes("fetchWorkspaceTasks"), "工作台應載入任務");
  assert.ok(load.includes("EMPTY_CAREGIVER_MSG"), "照護人員無授權時應顯示友善訊息");
});

test("管理者工作台提供 CSV 匯入住民與資料建置捷徑", () => {
  assert.ok(indexHtml.includes('id="resident-import-file"'), "應有 CSV 檔案輸入");
  assert.ok(indexHtml.includes('id="resident-import-run"'), "應有匯入按鈕");
  assert.ok(indexHtml.includes('id="workspace-open-assignment"'), "應有授權指派捷徑");
  assert.ok(indexHtml.includes('id="workspace-open-caregivers"'), "應有照護人員管理捷徑");
  const csv = bodyOf("function parseResidentCsv", 2200);
  assert.ok(csv.includes("displayname"), "CSV 支援 displayName header");
  assert.ok(csv.includes("姓名"), "CSV 支援中文姓名 header");
  const run = bodyOf("function importResidentCsv", 2400);
  assert.ok(run.includes("createResidentRecord"), "匯入應建立正式住民資料");
});

test("照護人員模式隱藏管理者資料建置區", () => {
  const apply = bodyOf("function applyAuthModeUi", 500);
  assert.ok(apply.includes("elW.adminSetup"), "應依角色切換工作台建置區");
  assert.ok(apply.includes("classList.toggle(\"hidden\", caregiver)"));
});

test("工作台有 responsive 樣式", () => {
  for (const cls of [".workspace-hero", ".workspace-grid", ".workspace-metrics", ".resident-card"]) {
    assert.ok(stylesCss.includes(cls), `styles.css 應包含 ${cls}`);
  }
});
