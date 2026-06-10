// CR-0066+ Marketplace production DB 路徑端點測試。
//
// 背景：商城已從 JSON-only 平移到 PostgreSQL（migration 015）。production 不再回 501
// not_enabled，而是走 DB（DATABASE_URL + PGVECTOR_ENABLED=true）正常運作。
//
// 本測試以 setPgForTest 注入「DB 可用」的 mock pg（server.js 與本檔共用同一 store
// singleton），並在 production env 下打 HTTP：驗證 marketplace 路由回 200 / {ok:true}。
// 保留「缺 admin token → 401」（authN 先於 store）。
//
// production 切換沿用既有端點測試慣例：require server 時 NODE_ENV=test（啟動 fail-fast
// no-op），再於單一請求前後暫時把 NODE_ENV/APP_ENV 切到 production，finally 還原；
// store 在「呼叫當下」讀 process.env，故路由真的會走 production（DB-required）分支。

const assert = require("node:assert/strict");
const { test } = require("node:test");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "marketplace_prod_ep_"));
process.env.MARKETPLACE_PRODUCTS_DATA_FILE = path.join(tmpDir, "products.json");
process.env.MARKETPLACE_ORDERS_DATA_FILE = path.join(tmpDir, "orders.json");
process.env.ADMIN_API_TOKEN = "test-admin-token";
process.env.NODE_ENV = "test";
process.env.OPENAI_API_KEY = "";
process.env.PGVECTOR_ENABLED = "false";
delete process.env.DATABASE_URL;
delete process.env.TELEGRAM_BOT_TOKEN;

const app = require("../../server");
const marketplaceStore = require("./marketplaceStore");

const ADMIN_HEADERS = {
  "Content-Type": "application/json",
  Authorization: "Bearer test-admin-token",
};

// 「DB 可用」mock pg：依 SQL 文字回對應 rows，使各 marketplace 路由回 {ok:true}。
// 不提供 getPool → createOrderDb 走 pg.query（BEGIN/SELECT/UPDATE/INSERT/COMMIT 序列）。
function makeServerMockPg() {
  const baseProduct = {
    id: "seed-bath-chair",
    center_id: "center-anxin",
    center_name: "安心長照中心",
    name: "防滑沐浴椅",
    description: "穩穩坐著",
    category: "照護用品",
    price: 1800,
    stock: 12,
    image_url: "",
    status: "active",
    commission_rate: "0.100",
    created_at: new Date("2026-06-01T00:00:00.000Z"),
    updated_at: new Date("2026-06-01T00:00:00.000Z"),
  };
  const baseOrder = {
    id: "order-1",
    user_id: "u-elder",
    elder_name: "陳奶奶",
    center_id: "center-anxin",
    center_name: "安心長照中心",
    items_json: [
      { product_id: "p1", product_name: "防滑沐浴椅", quantity: 1, unit_price: 1800, subtotal: 1800 },
    ],
    total_amount: 1800,
    commission_rate: "0.100",
    commission_amount: 180,
    center_revenue: 1620,
    status: "pending",
    delivery_note: "",
    created_at: new Date("2026-06-01T00:00:00.000Z"),
    updated_at: new Date("2026-06-01T00:00:00.000Z"),
  };
  return {
    isPostgresAvailable: async () => true,
    query: async (text, params) => {
      const t = text.trim();
      if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(t)) return { rows: [] };
      // ---- products ----
      if (/SELECT \* FROM marketplace_products WHERE id = ANY/.test(t)) {
        const ids = params[0] || [];
        return { rows: ids.map((id) => ({ ...baseProduct, id })) };
      }
      if (/SELECT \* FROM marketplace_products WHERE id = \$1/.test(t)) {
        return { rows: [{ ...baseProduct, id: params[0] }] };
      }
      if (/SELECT \* FROM marketplace_products/.test(t)) {
        return { rows: [baseProduct] };
      }
      if (/UPDATE marketplace_products SET stock/.test(t)) {
        return { rows: [{ id: params[0] }] };
      }
      if (/UPDATE marketplace_products SET status/.test(t)) {
        return { rows: [{ ...baseProduct, status: params[1] }] };
      }
      if (/UPDATE marketplace_products SET/.test(t)) {
        return { rows: [{ ...baseProduct, name: params[3] }] };
      }
      if (/INSERT INTO marketplace_products/.test(t)) {
        return { rows: [] };
      }
      // ---- orders ----
      if (/INSERT INTO marketplace_orders/.test(t)) {
        return {
          rows: [
            {
              id: params[0],
              user_id: params[1],
              elder_name: params[2],
              center_id: params[3],
              center_name: params[4],
              items_json: JSON.parse(params[5]),
              total_amount: params[6],
              commission_rate: String(params[7]),
              commission_amount: params[8],
              center_revenue: params[9],
              status: params[10],
              delivery_note: params[11],
              created_at: new Date("2026-06-01T00:00:00.000Z"),
              updated_at: new Date("2026-06-01T00:00:00.000Z"),
            },
          ],
        };
      }
      if (/SELECT \* FROM marketplace_orders WHERE id = \$1/.test(t)) {
        return { rows: [{ ...baseOrder, id: params[0] }] };
      }
      if (/SELECT \* FROM marketplace_orders/.test(t)) {
        return { rows: [baseOrder] };
      }
      if (/UPDATE marketplace_orders SET/.test(t)) {
        return { rows: [{ ...baseOrder, id: params[0], status: params[1] }] };
      }
      return { rows: [] };
    },
  };
}

function startServer() {
  return new Promise((resolve) => {
    const server = app.listen(0, "127.0.0.1", () => resolve(server));
  });
}

// 在 production env 下執行單一 fetch（前後還原 env），回 { status, body, raw }。
async function fetchInProduction(url, init) {
  const originalNodeEnv = process.env.NODE_ENV;
  const originalAppEnv = process.env.APP_ENV;
  try {
    process.env.NODE_ENV = "production";
    process.env.APP_ENV = "production";
    const r = await fetch(url, init);
    const raw = await r.text();
    let body = null;
    try {
      body = JSON.parse(raw);
    } catch {
      body = null;
    }
    return { status: r.status, body, raw };
  } finally {
    process.env.NODE_ENV = originalNodeEnv;
    if (originalAppEnv === undefined) delete process.env.APP_ENV;
    else process.env.APP_ENV = originalAppEnv;
  }
}

// 注入「DB 可用」mock pg 跑一個 production 請求，結束後還原 store。
async function withDbProduction(url, init) {
  marketplaceStore.setPgForTest(makeServerMockPg());
  try {
    return await fetchInProduction(url, init);
  } finally {
    marketplaceStore.setPgForTest(null);
  }
}

test("production GET /api/marketplace/products → 200 走 DB（不再 501）", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await withDbProduction(`${baseUrl}/api/marketplace/products`, {});
    assert.equal(res.status, 200);
    assert.equal(res.body.ok, true);
    assert.ok(Array.isArray(res.body.products));
    assert.ok(res.body.products.length >= 1);
  } finally {
    server.close();
  }
});

test("production GET /api/marketplace/products/:id → 200 + product", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await withDbProduction(`${baseUrl}/api/marketplace/products/seed-bath-chair`, {});
    assert.equal(res.status, 200);
    assert.equal(res.body.ok, true);
    assert.equal(res.body.product.id, "seed-bath-chair");
  } finally {
    server.close();
  }
});

test("production POST /api/marketplace/orders → 200 走 DB 交易（重算金額）", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await withDbProduction(`${baseUrl}/api/marketplace/orders`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        userId: "u-elder",
        elderName: "陳奶奶",
        items: [{ productId: "p1", quantity: 1 }],
      }),
    });
    assert.equal(res.status, 200);
    assert.equal(res.body.ok, true);
    assert.equal(res.body.order.status, "pending");
    assert.equal(res.body.order.total_amount, 1800);
  } finally {
    server.close();
  }
});

test("production POST /api/admin/marketplace/products（admin 通過）→ 200 + product", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await withDbProduction(`${baseUrl}/api/admin/marketplace/products`, {
      method: "POST",
      headers: ADMIN_HEADERS,
      body: JSON.stringify({ name: "防滑沐浴椅", price: 1800, stock: 5 }),
    });
    assert.equal(res.status, 200);
    assert.equal(res.body.ok, true);
    assert.equal(res.body.product.name, "防滑沐浴椅");
  } finally {
    server.close();
  }
});

test("production PUT /api/admin/marketplace/products/:id → 200 + product", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await withDbProduction(`${baseUrl}/api/admin/marketplace/products/seed-bath-chair`, {
      method: "PUT",
      headers: ADMIN_HEADERS,
      body: JSON.stringify({ name: "新名稱", price: 2000 }),
    });
    assert.equal(res.status, 200);
    assert.equal(res.body.ok, true);
    assert.equal(res.body.product.name, "新名稱");
  } finally {
    server.close();
  }
});

test("production PATCH /api/admin/marketplace/products/:id/status → 200 + 下架", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await withDbProduction(
      `${baseUrl}/api/admin/marketplace/products/seed-bath-chair/status`,
      {
        method: "PATCH",
        headers: ADMIN_HEADERS,
        body: JSON.stringify({ status: "inactive" }),
      },
    );
    assert.equal(res.status, 200);
    assert.equal(res.body.ok, true);
    assert.equal(res.body.product.status, "inactive");
  } finally {
    server.close();
  }
});

test("production GET /api/admin/marketplace/orders → 200 + orders", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await withDbProduction(`${baseUrl}/api/admin/marketplace/orders`, {
      headers: ADMIN_HEADERS,
    });
    assert.equal(res.status, 200);
    assert.equal(res.body.ok, true);
    assert.ok(Array.isArray(res.body.orders));
  } finally {
    server.close();
  }
});

test("production GET /api/admin/marketplace/orders/:id → 200 + order", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await withDbProduction(`${baseUrl}/api/admin/marketplace/orders/order-1`, {
      headers: ADMIN_HEADERS,
    });
    assert.equal(res.status, 200);
    assert.equal(res.body.ok, true);
    assert.equal(res.body.order.id, "order-1");
  } finally {
    server.close();
  }
});

test("production PATCH /api/admin/marketplace/orders/:id/status → 200 + 狀態更新", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await withDbProduction(
      `${baseUrl}/api/admin/marketplace/orders/order-1/status`,
      {
        method: "PATCH",
        headers: ADMIN_HEADERS,
        body: JSON.stringify({ status: "confirmed" }),
      },
    );
    assert.equal(res.status, 200);
    assert.equal(res.body.ok, true);
    assert.equal(res.body.order.status, "confirmed");
  } finally {
    server.close();
  }
});

// admin authN 仍先於 store：缺 token → 401（不洩漏資料 / 不走 DB）。
test("production 缺 admin token → 仍 401（authN 先於 store）", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await withDbProduction(`${baseUrl}/api/admin/marketplace/orders`, {});
    assert.equal(res.status, 401);
    assert.deepEqual(res.body, { ok: false, error: "missing_admin_token" });
  } finally {
    server.close();
  }
});

// /health 不受 marketplace DB 平移影響。
test("smoke：production 下 /health 仍 200", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await withDbProduction(`${baseUrl}/health`, {});
    assert.equal(res.status, 200);
  } finally {
    server.close();
  }
});
