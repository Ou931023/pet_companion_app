// CR-0044：caregiver_web super_admin-only provisioning UI 靜態回歸測試。
//
// caregiver_web 為原生 JS（依賴 document/window），無 DOM 測試環境；
// 比照本資料夾其他測試以「來源靜態檢查」確保：
//   - super_admin 顯示「照護人員管理」「住民授權指派」兩入口；caregiver 不顯示。
//   - provisioning API 一律用 super_admin token（adminAuthHeaders / adminJsonHeaders），
//     不用 caregiver scoped helper；caregiver 模式不發送這些 management API request。
//   - 401 / 403 / 空狀態文案正確。
//   - 建立 caregiver / assignment 成功後刷新列表。
//   - 不使用假資料、不在 console 顯示 token。
//   - 授權角色 select 採後端真值 primary | secondary | viewer。
//
// 執行：node --test caregiver_web/caregiver_provisioning_ui.test.js

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const appJs = fs.readFileSync(path.join(__dirname, "app.js"), "utf8");
const indexHtml = fs.readFileSync(path.join(__dirname, "index.html"), "utf8");

function bodyOf(name, span) {
  const idx = appJs.indexOf(name);
  assert.ok(idx >= 0, `應有 ${name}`);
  return appJs.slice(idx, idx + (span || 1200));
}

// #1 + #3：兩入口存在於 nav（super_admin 預設可見）。
test("index.html 提供照護人員管理 / 住民授權指派兩個入口", () => {
  assert.ok(indexHtml.includes('id="tab-caregivers"'), "應有照護人員管理分頁入口");
  assert.ok(indexHtml.includes('id="tab-assignments"'), "應有住民授權指派分頁入口");
  assert.ok(indexHtml.includes("照護人員管理"), "應標示照護人員管理");
  assert.ok(indexHtml.includes("住民授權指派"), "應標示住民授權指派");
  assert.ok(indexHtml.includes('id="view-caregivers"'), "應有照護人員管理 view");
  assert.ok(indexHtml.includes('id="view-assignments"'), "應有住民授權指派 view");
});

// #2 + #4：caregiver 模式隱藏兩入口（與既有 users/products/orders 一致）。
test("caregiver 模式隱藏兩個 super_admin-only 入口", () => {
  const body = bodyOf("function applyAuthModeUi", 600);
  assert.ok(body.includes("elCG && elCG.tab"), "applyAuthModeUi 應切換照護人員管理入口可見性");
  assert.ok(body.includes("elAS && elAS.tab"), "applyAuthModeUi 應切換住民授權指派入口可見性");
  assert.ok(body.includes("caregiver"), "依 caregiver 模式隱藏 super_admin-only 入口");
  // caregiver 模式停在這兩頁時切回 alerts。
  assert.ok(body.includes('"caregivers"'), "caregiver 模式應從照護人員管理切回照護提醒");
  assert.ok(body.includes('"assignments"'), "caregiver 模式應從住民授權指派切回照護提醒");
});

// #5：建立 / 載入 caregiver 用 super_admin token header，且不用 caregiver scoped helper。
test("照護人員管理一律使用 super_admin token header", () => {
  const load = bodyOf("function loadCaregivers", 1400);
  assert.ok(load.includes("adminAuthHeaders()"), "loadCaregivers 應用 adminAuthHeaders");
  assert.ok(!load.includes("authHeaders()"), "loadCaregivers 不可用 caregiver scoped authHeaders");
  const submit = bodyOf("function submitCaregiverForm", 1800);
  assert.ok(submit.includes("adminJsonHeaders()"), "建立 / 編輯 caregiver 應用 adminJsonHeaders");
  assert.ok(!submit.includes("authJsonHeaders()"), "建立 caregiver 不可用 caregiver scoped helper");
});

// #6：建立 / 載入 assignment 用 super_admin token header。
test("住民授權指派一律使用 super_admin token header", () => {
  const load = bodyOf("function loadAssignments", 1400);
  assert.ok(load.includes("adminAuthHeaders()"), "loadAssignments 應用 adminAuthHeaders");
  assert.ok(!load.includes("authHeaders()"), "loadAssignments 不可用 caregiver scoped authHeaders");
  const submit = bodyOf("function submitProvisioning", 1000);
  assert.ok(submit.includes("adminJsonHeaders()"), "provisioning 寫入應用 adminJsonHeaders");
  assert.ok(!submit.includes("authJsonHeaders()"), "provisioning 寫入不可用 caregiver scoped helper");
});

// caregiver 模式不發送 management API request（防呆）。
test("caregiver 模式不發送 provisioning management API", () => {
  const load = bodyOf("function loadCaregivers", 900);
  assert.ok(
    load.indexOf("isCaregiverMode()") >= 0 &&
      load.indexOf("isCaregiverMode()") < load.indexOf("fetch("),
    "loadCaregivers 應在 fetch 前先擋 caregiver"
  );
  const loadA = bodyOf("function loadAssignments", 900);
  assert.ok(
    loadA.indexOf("isCaregiverMode()") >= 0 &&
      loadA.indexOf("isCaregiverMode()") < loadA.indexOf("fetch("),
    "loadAssignments 應在 fetch 前先擋 caregiver"
  );
});

// #7：401 提示登入失效並停止重複請求。
test("401 顯示登入失效（sessionInvalid）", () => {
  assert.ok(appJs.includes("登入已失效，請重新登入"), "應有 401 文案");
  const load = bodyOf("function loadCaregivers", 1400);
  assert.ok(load.includes("handleSessionExpired()"), "loadCaregivers 401 應呼叫 handleSessionExpired");
  const loadA = bodyOf("function loadAssignments", 1400);
  assert.ok(loadA.includes("handleSessionExpired()"), "loadAssignments 401 應呼叫 handleSessionExpired");
});

// #8：403 提示權限不足（不清 token）。
test("403 顯示權限不足", () => {
  assert.ok(appJs.includes("目前帳號沒有權限查看此資料"), "應有 403 文案");
  const load = bodyOf("function loadCaregivers", 1400);
  assert.ok(load.includes("FORBIDDEN_MSG"), "loadCaregivers 403 應顯示權限不足");
  const loadA = bodyOf("function loadAssignments", 1400);
  assert.ok(loadA.includes("FORBIDDEN_MSG"), "loadAssignments 403 應顯示權限不足");
});

// #9：空 caregiver list 友善空狀態。
test("空 caregiver 清單顯示『目前尚無照護人員』", () => {
  assert.ok(appJs.includes('"目前尚無照護人員"'), "應有空 caregiver 文案常數");
  const render = bodyOf("function renderCaregivers", 500);
  assert.ok(render.includes("EMPTY_CAREGIVERS_MSG"), "renderCaregivers 空清單顯示空狀態");
});

// #10：空 assignment list 友善空狀態。
test("空 assignment 清單顯示『目前尚無住民授權指派』", () => {
  assert.ok(appJs.includes('"目前尚無住民授權指派"'), "應有空 assignment 文案常數");
  const render = bodyOf("function renderAssignments", 500);
  assert.ok(render.includes("EMPTY_ASSIGNMENTS_MSG"), "renderAssignments 空清單顯示空狀態");
});

// #11：建立 caregiver 成功後刷新列表。
test("建立 caregiver 成功後刷新列表", () => {
  const submit = bodyOf("function submitCaregiverForm", 3000);
  assert.ok(submit.includes("loadCaregivers()"), "建立成功後應呼叫 loadCaregivers 刷新");
  assert.ok(submit.includes("closeCaregiverForm()"), "建立成功後應關閉表單");
});

// #12：建立 assignment 成功後刷新列表。
test("建立 assignment 成功後刷新列表", () => {
  const submit = bodyOf("function submitAssignmentForm", 1600);
  assert.ok(submit.includes("loadAssignments()"), "建立成功後應呼叫 loadAssignments 刷新");
});

// #13：不使用假資料填 UI（select 來源為後端 API，非硬編碼）。
test("不使用假資料：select 由後端 API 帶入", () => {
  const pop = bodyOf("function populateAssignmentSelects", 3200);
  assert.ok(pop.includes('adminUrl("/elders")'), "住民 select 應來自 /admin/elders");
  assert.ok(pop.includes('adminUrl("/caregivers")'), "照護人員 select 應來自 /admin/caregivers");
  // 來源為空時清楚提示需先建立資料，不以假資料補。
  assert.ok(pop.includes("請先在「照護人員管理」新增照護人員"), "無照護人員時提示需先建立");
  assert.ok(pop.includes("確認已有住民資料"), "無住民時提示需先建立");
  // 不可硬編 caregiver / 住民識別碼作為清單來源。
  assert.ok(!/caregiversCache\s*=\s*\[\s*\{/.test(appJs), "不可硬編 caregiver 假資料");
});

// #14：不在 console / log 顯示 token；不硬編 Bearer token。
test("不在 console 顯示 token、不硬編 Bearer token", () => {
  assert.ok(!/console\.\w+\([^)]*[tT]oken/.test(appJs), "不可 console 印出 token");
  assert.ok(!/Bearer\s+[A-Za-z0-9._\-]{12,}/.test(appJs), "不可硬編碼 Bearer token");
});

// 授權角色採後端真值 primary | secondary | viewer（非任務書誤植的 backup）。
test("授權角色 select 採後端真值 primary | secondary | viewer", () => {
  assert.ok(appJs.includes("primary:") , "ROLE_LABELS 應含 primary");
  assert.ok(appJs.includes("secondary:"), "ROLE_LABELS 應含 secondary（非 backup）");
  assert.ok(appJs.includes("viewer:"), "ROLE_LABELS 應含 viewer");
  assert.ok(!/ROLE_LABELS[\s\S]{0,120}backup:/.test(appJs), "角色真值不應為 backup");
  // index.html role select 三個選項皆為後端真值。
  assert.ok(indexHtml.includes('<option value="primary">'), "role select 應有 primary");
  assert.ok(indexHtml.includes('<option value="secondary">'), "role select 應有 secondary");
  assert.ok(indexHtml.includes('<option value="viewer">'), "role select 應有 viewer");
});

// 停用提示語白話、說明影響（不工程術語）。
test("停用 caregiver / link 有白話影響提示", () => {
  assert.ok(
    appJs.includes("停用後，該照護人員將無法查看被指派住民資料。"),
    "停用 caregiver 應提示影響"
  );
  assert.ok(
    appJs.includes("停用後，該照護人員將不能再查看此住民的資料。"),
    "停用 link 應提示影響"
  );
});

// 既有 dashboard / CR-0042 載入函式未被破壞。
test("既有載入函式未被破壞", () => {
  for (const fn of [
    "function loadAlerts",
    "function loadHealthOverview",
    "function loadElderList",
    "function loadDailyTasks",
    "function loadUsers",
    "function loadOrders",
  ]) {
    assert.ok(appJs.includes(fn), `仍應保留 ${fn}`);
  }
});
