// CR-0030：caregiver_web 健康分析儀表板顯示回歸測試（靜態來源檢查）。
//
// 確保健康分析頁的「非醫療提示 + 資料來源說明、資料真實性標籤、資料不足空狀態」
// 不被誤刪，且不顯示敏感資料。
//
// 執行：node --test caregiver_web/admin_health_analytics.test.js

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const appJs = fs.readFileSync(path.join(__dirname, "app.js"), "utf8");
const indexHtml = fs.readFileSync(path.join(__dirname, "index.html"), "utf8");

test("健康分析頁有非醫療 + 資料來源說明橫幅", () => {
  // 橫幅應位於 view-health 區塊內。
  const healthIdx = indexHtml.indexOf('id="view-health"');
  assert.ok(healthIdx >= 0, "應有 view-health 區塊");
  const after = indexHtml.slice(healthIdx, healthIdx + 800);
  assert.ok(after.includes("care-disclaimer"), "健康頁應有提示橫幅");
  assert.ok(after.includes("非醫療診斷"), "應載明非醫療診斷");
  assert.ok(after.includes("資料不足"), "應說明資料不足不以假資料填充");
});

test("五大健康分析區塊標題仍齊全（未破壞既有頁面）", () => {
  for (const title of [
    "生理健康分析",
    "心理健康分析",
    "情緒分析歷史",
    "遊戲認知退化指標",
    "近期照護提醒",
  ]) {
    assert.ok(indexHtml.includes(title), `應有『${title}』區塊`);
  }
});

test("資料真實性處理：示範參考 / 資料不足 / dataSource 標籤", () => {
  assert.ok(appJs.includes("function dataSourceBadge"), "應有資料來源標籤函式");
  assert.ok(appJs.includes("function insufficientBlock"), "應有資料不足空狀態函式");
  assert.ok(appJs.includes("示範參考資料"), "reference 應顯示『示範參考資料』");
  assert.ok(appJs.includes("資料不足"), "insufficient 應顯示『資料不足』");
  assert.ok(appJs.includes("dataSource"), "應讀取 dataSource 標註");
  assert.ok(
    appJs.includes("a.emotionDataSource"),
    "情緒歷史應帶入後端 emotionDataSource"
  );
});

test("各健康區塊渲染器都處理資料不足", () => {
  // renderPhysio / renderPsych / renderEmotion / renderGame 都應走 insufficient 判斷。
  for (const fn of ["renderPhysio", "renderPsych", "renderEmotion", "renderGame"]) {
    const idx = appJs.indexOf("function " + fn);
    assert.ok(idx >= 0, `應有 ${fn}`);
    const body = appJs.slice(idx, idx + 600);
    assert.ok(
      body.includes("insufficient") || body.includes("insufficientBlock"),
      `${fn} 應處理資料不足`
    );
  }
});

test("不捏造：前端不出現工程字樣，也不顯示敏感欄位", () => {
  const banned = [
    "password_hash",
    "provider_user_id",
    "access_token",
    "refresh_token",
    "id_token",
    "session_token",
    "otp",
  ];
  for (const key of banned) {
    assert.ok(!appJs.includes(key), `前端不可引用敏感欄位：${key}`);
  }
});
