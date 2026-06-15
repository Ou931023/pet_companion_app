const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

// CR-0086：長者狀態分析頁前端靜態檢查（與既有 *.test.js 同模式：讀原始碼斷言子字串）。

const appJs = fs.readFileSync(path.join(__dirname, "app.js"), "utf8");
const indexHtml = fs.readFileSync(path.join(__dirname, "index.html"), "utf8");

test("導覽列有『長者狀態分析』分頁，且有對應 view 區塊", () => {
  assert.ok(indexHtml.includes('id="tab-analytics"'), "應有 tab-analytics 按鈕");
  assert.ok(indexHtml.includes("長者狀態分析"), "分頁文字應為長者狀態分析");
  assert.ok(indexHtml.includes('id="view-analytics"'), "應有 view-analytics 區塊");
});

test("分析頁有非醫療 + 資料來源說明橫幅（誠實標註）", () => {
  const idx = indexHtml.indexOf('id="view-analytics"');
  assert.ok(idx >= 0);
  const after = indexHtml.slice(idx, idx + 1200);
  assert.ok(after.includes("care-disclaimer"), "分析頁應有提示橫幅");
  assert.ok(after.includes("並非醫療診斷"), "需標明非醫療診斷");
  assert.ok(after.includes("資料不足"), "需說明資料不足不以假資料填充");
});

test("有長者選擇器 + 區間選擇器", () => {
  assert.ok(indexHtml.includes('id="analytics-elder"'), "應有長者選擇器");
  assert.ok(indexHtml.includes('id="analytics-range"'), "應有區間選擇器");
});

test("分析資料走 /api/caregiver/analytics，且為 caregiver-capable（authHeaders 非 admin-only）", () => {
  assert.ok(appJs.includes("/caregiver/analytics"), "應呼叫 /api/caregiver/analytics");
  assert.ok(appJs.includes("loadResidentAnalytics"), "應有載入分析函式");
  // 長者選擇器沿用 /elders（後端依授權住民過濾），用 authHeaders（含 caregiver token）。
  const fn = appJs.slice(appJs.indexOf("function loadAnalyticsElders"));
  assert.ok(/adminUrl\("\/elders"\)/.test(fn), "選擇器應呼叫 /elders");
  assert.ok(fn.includes("authHeaders()"), "應用 authHeaders（caregiver-capable）");
});

test("showView 納入 analytics，懶載入只在切到分頁時觸發", () => {
  assert.ok(/analytics:\s*\{\s*view:\s*elAN\.view/.test(appJs), "showView 應含 analytics 項目");
  assert.ok(appJs.includes('name === "analytics" && !analyticsLoaded'), "應懶載入");
});

test("空狀態 / 401 / 403 友善提示（不顯示工程字串）", () => {
  assert.ok(appJs.includes("近期沒有警示紀錄"), "警示空狀態白話");
  assert.ok(appJs.includes("目前尚無足夠遊戲紀錄"), "遊戲資料不足白話");
  assert.ok(appJs.includes("後台尚未串接"), "寵物無來源空狀態白話");
  // 沿用既有友善常數處理 401/403。
  const fn = appJs.slice(appJs.indexOf("function loadResidentAnalytics"));
  assert.ok(fn.includes("SESSION_EXPIRED_MSG"), "401 用 session 過期文案");
  assert.ok(fn.includes("FORBIDDEN_MSG"), "403 用權限不足文案");
});

test("不捏造：前端不出現工程 / 敏感字樣", () => {
  const banned = [
    "password",
    "password_hash",
    "provider_user_id",
    "access_token",
    "refresh_token",
    "id_token",
    "session_token",
  ];
  for (const key of banned) {
    assert.ok(!appJs.includes(key), `前端不可引用敏感欄位：${key}`);
  }
});
