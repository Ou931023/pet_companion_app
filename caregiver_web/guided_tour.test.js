// 使用說明導覽（Guided Tour）的靜態結構測試。
// 與本資料夾其他測試一致：以文字方式檢查 index.html / app.js 是否含必要結構，
// 不啟動瀏覽器（純前端 DOM 行為靠實機 / 瀏覽器驗證）。
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const appJs = fs.readFileSync(path.join(__dirname, "app.js"), "utf8");
const indexHtml = fs.readFileSync(path.join(__dirname, "index.html"), "utf8");
const stylesCss = fs.readFileSync(path.join(__dirname, "styles.css"), "utf8");

test("index.html 有「使用說明」導覽入口按鈕", () => {
  assert.ok(indexHtml.includes('id="tour-start"'), "應有 #tour-start 按鈕");
  assert.ok(indexHtml.includes("使用說明"), "按鈕文案應為使用說明");
});

test("app.js 有導覽核心函式與初始化掛載", () => {
  for (const fn of [
    "function setupGuidedTour",
    "function startTour",
    "function endTour",
    "function gotoStep",
    "TOUR_STEPS",
  ]) {
    assert.ok(appJs.includes(fn), `app.js 應包含 ${fn}`);
  }
  assert.ok(
    appJs.includes("setupGuidedTour();"),
    "init() 應呼叫 setupGuidedTour()"
  );
});

test("導覽涵蓋所有分頁（含 CR-0032 商品 / 訂單管理）", () => {
  for (const view of [
    'view: "alerts"',
    'view: "health"',
    'view: "tasks"',
    'view: "users"',
    'view: "products"',
    'view: "orders"',
  ]) {
    assert.ok(appJs.includes(view), `導覽步驟應涵蓋 ${view}`);
  }
});

test("導覽切換分頁沿用既有 showView（不另開資料流）", () => {
  assert.ok(appJs.includes("showView(step.view)"), "gotoStep 應呼叫 showView");
});

test("第一次造訪自動播放、之後記在 localStorage", () => {
  assert.ok(appJs.includes("TOUR_DONE_KEY"), "應有導覽完成旗標 key");
  assert.ok(
    appJs.includes("caregiver_tour_done"),
    "localStorage key 應為 caregiver_tour_done"
  );
});

test("styles.css 有導覽高亮與說明卡樣式", () => {
  for (const cls of [".tour-root", ".tour-spot", ".tour-tooltip", ".tour-hidden"]) {
    assert.ok(stylesCss.includes(cls), `styles.css 應包含 ${cls}`);
  }
});
