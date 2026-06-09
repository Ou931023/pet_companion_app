// CR-0032 長照商品商城管理端（商品管理 / 訂單管理）靜態結構測試。
// 與本資料夾其他測試一致：以文字方式檢查 index.html / app.js / styles.css，
// 不啟動瀏覽器。

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const appJs = fs.readFileSync(path.join(__dirname, "app.js"), "utf8");
const indexHtml = fs.readFileSync(path.join(__dirname, "index.html"), "utf8");
const stylesCss = fs.readFileSync(path.join(__dirname, "styles.css"), "utf8");
const configExample = fs.readFileSync(
  path.join(__dirname, "config.example.js"),
  "utf8",
);

test("index.html 有商品管理 / 訂單管理分頁與 view 區塊", () => {
  assert.ok(indexHtml.includes('id="tab-products"'), "應有商品管理分頁");
  assert.ok(indexHtml.includes('id="tab-orders"'), "應有訂單管理分頁");
  assert.ok(indexHtml.includes('id="view-products"'), "應有商品管理 view");
  assert.ok(indexHtml.includes('id="view-orders"'), "應有訂單管理 view");
  assert.ok(indexHtml.includes("商品管理"), "應有商品管理文案");
  assert.ok(indexHtml.includes("訂單管理"), "應有訂單管理文案");
});

test("index.html 有商品表單與訂單詳情 modal", () => {
  assert.ok(indexHtml.includes('id="product-overlay"'), "應有商品表單 modal");
  assert.ok(indexHtml.includes('id="product-form"'), "應有商品表單");
  assert.ok(indexHtml.includes('id="order-overlay"'), "應有訂單詳情 modal");
  // 商品欄位（CR-0032 §三）
  for (const id of [
    "pf-name",
    "pf-category",
    "pf-price",
    "pf-stock",
    "pf-image",
    "pf-commission",
    "pf-status",
    "pf-center-name",
  ]) {
    assert.ok(indexHtml.includes(`id="${id}"`), `應有商品欄位 ${id}`);
  }
});

test("app.js 商品管理呼叫正確 API 且帶 Admin 權杖", () => {
  assert.ok(appJs.includes("function loadProducts"), "應有 loadProducts");
  assert.ok(appJs.includes("function submitProductForm"), "應有 submitProductForm");
  assert.ok(appJs.includes("function toggleProductStatus"), "應有上下架功能");
  assert.ok(
    appJs.includes('marketplaceUrl("/products'),
    "應呼叫公開 /marketplace/products",
  );
  assert.ok(
    appJs.includes('adminUrl("/marketplace/products")'),
    "新增商品應打 /admin/marketplace/products",
  );
  assert.ok(
    appJs.includes('adminUrl("/marketplace/products/" + encodeURIComponent(id) + "/status")'),
    "上下架應打 status 端點",
  );
  assert.ok(appJs.includes("adminJsonHeaders"), "寫入應帶 Admin token headers");
  assert.ok(appJs.includes("ADMIN_TOKEN_KEY"), "權杖存 localStorage（不寫死）");
});

test("app.js 訂單管理呼叫正確 API、顯示抽成與長照中心實收", () => {
  assert.ok(appJs.includes("function loadOrders"), "應有 loadOrders");
  assert.ok(appJs.includes("function renderOrderDetail"), "應有訂單詳情渲染");
  assert.ok(appJs.includes("function updateOrderFromDetail"), "應有更新訂單狀態");
  assert.ok(
    appJs.includes('adminUrl("/marketplace/orders")'),
    "應查 /admin/marketplace/orders",
  );
  assert.ok(
    appJs.includes('adminUrl("/marketplace/orders/" + encodeURIComponent(id) + "/status")'),
    "改狀態應打 status 端點",
  );
  assert.ok(appJs.includes("平台抽成"), "詳情應顯示平台抽成");
  assert.ok(appJs.includes("長照中心實收"), "詳情應顯示長照中心實收");
});

test("app.js showView 與懶載入涵蓋商品 / 訂單", () => {
  assert.ok(appJs.includes('products: { view: elP.viewProducts'), "showView 應含 products");
  assert.ok(appJs.includes('orders: { view: elO.viewOrders'), "showView 應含 orders");
  assert.ok(appJs.includes('name === "products" && !productsLoaded'), "products 懶載入");
  assert.ok(appJs.includes('name === "orders" && !ordersLoaded'), "orders 懶載入");
});

test("styles.css 有商品 / 訂單相關樣式", () => {
  for (const cls of [".order-row", ".order-money", ".form-grid", ".btn-sm"]) {
    assert.ok(stylesCss.includes(cls), `styles.css 應包含 ${cls}`);
  }
});

test("CR-0056：marketplace 分頁能力保留但受 featureFlags 控制（預設隱藏）", () => {
  // 能力 / 結構不刪：tab 與 view 仍在（上方既有測試已涵蓋）。
  // 旗標預設關：config.example.js 的 featureFlags.marketplace 預設 false。
  assert.ok(configExample.includes("featureFlags"), "config 範本應有 featureFlags");
  assert.ok(
    /marketplace\s*:\s*false/.test(configExample),
    "marketplace 旗標預設應為 false（正式版隱藏入口）",
  );
  // app.js 以 featureEnabled('marketplace') 決定是否隱藏商品 / 訂單分頁入口。
  assert.ok(appJs.includes("function featureEnabled"), "應有 featureEnabled 旗標判斷");
  assert.ok(appJs.includes("function applyFeatureFlags"), "應有 applyFeatureFlags");
  assert.ok(
    appJs.includes('featureEnabled("marketplace")'),
    "應依 marketplace 旗標隱藏分頁",
  );
  assert.ok(
    appJs.includes("hideTabButton(elP && elP.tabProducts)") &&
      appJs.includes("hideTabButton(elO && elO.tabOrders)"),
    "marketplace 關閉時應隱藏商品 / 訂單分頁按鈕",
  );
  // 只隱藏入口、不刪後端呼叫：loadProducts / adminUrl 仍在（上方測試已驗證）。
});

test("長者端文案不外洩工程訊息（白話錯誤）", () => {
  assert.ok(
    appJs.includes("待會再重新整理看看") || appJs.includes("請稍後再試"),
    "錯誤訊息應白話",
  );
});
