// CR-0032 Marketplace 端點整合測試。
// 以 temp data 檔隔離，啟動真實 Express app（不 mock 主流程），
// 走完整流程：管理端新增商品 → 長者端看到 → 建立訂單 → 管理端看到訂單 → 改狀態。

const assert = require("node:assert/strict");
const test = require("node:test");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "marketplace_ep_"));
process.env.MARKETPLACE_PRODUCTS_DATA_FILE = path.join(tmpDir, "products.json");
process.env.MARKETPLACE_ORDERS_DATA_FILE = path.join(tmpDir, "orders.json");
process.env.ADMIN_API_TOKEN = "test-admin-token";
process.env.NODE_ENV = "test";
process.env.OPENAI_API_KEY = "";
process.env.PGVECTOR_ENABLED = "false";
delete process.env.DATABASE_URL;
delete process.env.TELEGRAM_BOT_TOKEN;

const app = require("../../server");

const ADMIN_HEADERS = {
  "Content-Type": "application/json",
  Authorization: "Bearer test-admin-token",
};

function startServer() {
  return new Promise((resolve) => {
    const server = app.listen(0, "127.0.0.1", () => resolve(server));
  });
}

async function getJson(baseUrl, route, headers = {}) {
  const r = await fetch(`${baseUrl}${route}`, { headers });
  return { status: r.status, body: await r.json() };
}

async function send(baseUrl, method, route, body, headers) {
  const r = await fetch(`${baseUrl}${route}`, {
    method,
    headers: headers || { "Content-Type": "application/json" },
    body: body == null ? undefined : JSON.stringify(body),
  });
  return { status: r.status, body: await r.json() };
}

test("管理端新增商品需要 admin token，缺 token 被擋", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await send(baseUrl, "POST", "/api/admin/marketplace/products", {
      name: "防滑沐浴椅",
    });
    assert.equal(res.status, 401);
  } finally {
    server.close();
  }
});

test("完整 Demo 流程：上架 → 長者端看到 → 下單 → 管理端查訂單 → 改狀態", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;

    // 1. 管理端新增兩筆同中心商品。
    const p1 = await send(
      baseUrl,
      "POST",
      "/api/admin/marketplace/products",
      {
        name: "防滑沐浴椅",
        center_id: "c-anxin",
        center_name: "安心長照中心",
        category: "照護用品",
        price: 1800,
        stock: 12,
        commission_rate: 0.1,
        status: "active",
      },
      ADMIN_HEADERS,
    );
    assert.equal(p1.status, 200);
    assert.equal(p1.body.ok, true);

    const p2 = await send(
      baseUrl,
      "POST",
      "/api/admin/marketplace/products",
      {
        name: "助行器",
        center_id: "c-anxin",
        center_name: "安心長照中心",
        category: "復健輔具",
        price: 2500,
        stock: 6,
        commission_rate: 0.1,
        status: "active",
      },
      ADMIN_HEADERS,
    );
    assert.equal(p2.status, 200);

    // 2. 長者端看得到（公開、預設只回 active）。
    const list = await getJson(baseUrl, "/api/marketplace/products");
    assert.equal(list.status, 200);
    assert.equal(list.body.ok, true);
    assert.equal(list.body.products.length, 2);

    // 3. 長者端建立訂單。
    const order = await send(baseUrl, "POST", "/api/marketplace/orders", {
      userId: "u-elder",
      elderName: "陳奶奶",
      deliveryNote: "白天在家",
      items: [
        { productId: p1.body.product.id, quantity: 1 },
        { productId: p2.body.product.id, quantity: 2 },
      ],
    });
    assert.equal(order.status, 200);
    assert.equal(order.body.ok, true);
    assert.equal(order.body.order.total_amount, 6800);
    assert.equal(order.body.order.commission_amount, 680);
    assert.equal(order.body.order.center_revenue, 6120);
    assert.equal(order.body.order.status, "pending");
    const orderId = order.body.order.id;

    // 4. 管理端查訂單（需 token）。
    const noAuth = await getJson(baseUrl, "/api/admin/marketplace/orders");
    assert.equal(noAuth.status, 401);

    const adminList = await getJson(
      baseUrl,
      "/api/admin/marketplace/orders",
      { Authorization: "Bearer test-admin-token" },
    );
    assert.equal(adminList.status, 200);
    assert.ok(adminList.body.orders.some((o) => o.id === orderId));

    // 5. 改訂單狀態 + 填配送備註。
    const patched = await send(
      baseUrl,
      "PATCH",
      `/api/admin/marketplace/orders/${orderId}/status`,
      { status: "confirmed", deliveryNote: "明天上午送達" },
      ADMIN_HEADERS,
    );
    assert.equal(patched.status, 200);
    assert.equal(patched.body.order.status, "confirmed");
    assert.equal(patched.body.order.delivery_note, "明天上午送達");
  } finally {
    server.close();
  }
});

test("缺貨商品下單被擋（400），且不影響既有 API", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const p = await send(
      baseUrl,
      "POST",
      "/api/admin/marketplace/products",
      {
        name: "限量輔具",
        center_id: "c-anxin",
        center_name: "安心長照中心",
        category: "復健輔具",
        price: 999,
        stock: 1,
        commission_rate: 0.1,
        status: "active",
      },
      ADMIN_HEADERS,
    );
    const order = await send(baseUrl, "POST", "/api/marketplace/orders", {
      userId: "u-elder",
      items: [{ productId: p.body.product.id, quantity: 5 }],
    });
    assert.equal(order.status, 400);
    assert.equal(order.body.ok, false);
    assert.equal(order.body.error, "insufficient_stock");

    // 既有健康檢查端點仍正常（沒被破壞）。
    const health = await fetch(`${baseUrl}/health`);
    assert.equal(health.status, 200);
  } finally {
    server.close();
  }
});
