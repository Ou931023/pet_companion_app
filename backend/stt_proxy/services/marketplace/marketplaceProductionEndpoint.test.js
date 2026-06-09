// CR-0057 Marketplace production 停用路徑端點測試（defense-in-depth + wire 契約一致）。
//
// 裁決規格（architecture-agent）：
//   - production（isJsonFallbackAllowed=false）下，marketplace 所有會出現
//     feature_unavailable_in_production 的路由 → 統一回 501。
//   - 形狀：{ ok:false, error:"not_enabled", message:<白話、無工程字眼/path/stack> }。
//   - dev/test 既有行為（200/400/404）位元不變（見 marketplaceEndpoint.test.js）。
//
// production 切換沿用既有端點測試慣例（careAlertNotifyAuthEndpoint.test.js #11）：
//   require server 時 NODE_ENV=test（啟動 fail-fast no-op、不 process.exit），
//   再於單一請求前後暫時把 NODE_ENV/APP_ENV 切到 production，finally 還原。
//   store 在「呼叫當下」讀 process.env，故路由真的會走 production 停用分支。

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

const ADMIN_HEADERS = {
  "Content-Type": "application/json",
  Authorization: "Bearer test-admin-token",
};

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

// 統一斷言：501 + marketplace 形狀（ok:false / not_enabled / 友善 message），
// 且不外洩 stack / file path / demo / JSON 字樣。
function assertMarketplaceDisabled(res) {
  assert.equal(res.status, 501);
  assert.ok(res.body && typeof res.body === "object");
  assert.equal(res.body.ok, false);
  assert.equal(res.body.error, "not_enabled");
  assert.equal(typeof res.body.message, "string");
  assert.ok(res.body.message.length > 0);
  // 內部碼不外洩到 wire。
  assert.ok(!res.raw.includes("feature_unavailable_in_production"));
  // 不含工程字眼 / 路徑 / stack / demo / JSON。
  for (const banned of ["Error", "stack", ".json", "/Users", "/var", "demo", "Demo", "JSON"]) {
    assert.ok(!res.raw.includes(banned), `response 不應含 "${banned}"：${res.raw}`);
  }
}

test("production GET /api/marketplace/products → 501 not_enabled，不讀 JSON / 不回 demo", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetchInProduction(`${baseUrl}/api/marketplace/products`, {});
    assertMarketplaceDisabled(res);
  } finally {
    server.close();
  }
});

test("production GET /api/marketplace/products/:id → 501 not_enabled", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetchInProduction(`${baseUrl}/api/marketplace/products/any-id`, {});
    assertMarketplaceDisabled(res);
  } finally {
    server.close();
  }
});

test("production POST /api/marketplace/orders → 501 not_enabled（非 500）", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetchInProduction(`${baseUrl}/api/marketplace/orders`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        userId: "u-elder",
        items: [{ productId: "p1", quantity: 1 }],
      }),
    });
    assertMarketplaceDisabled(res);
  } finally {
    server.close();
  }
});

test("production POST /api/admin/marketplace/products（admin 通過後）→ 501 not_enabled", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetchInProduction(`${baseUrl}/api/admin/marketplace/products`, {
      method: "POST",
      headers: ADMIN_HEADERS,
      body: JSON.stringify({ name: "防滑沐浴椅", price: 1800, stock: 5 }),
    });
    assertMarketplaceDisabled(res);
  } finally {
    server.close();
  }
});

test("production PUT /api/admin/marketplace/products/:id → 501 not_enabled", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetchInProduction(`${baseUrl}/api/admin/marketplace/products/p1`, {
      method: "PUT",
      headers: ADMIN_HEADERS,
      body: JSON.stringify({ name: "x", price: 1 }),
    });
    assertMarketplaceDisabled(res);
  } finally {
    server.close();
  }
});

test("production PATCH /api/admin/marketplace/products/:id/status → 501 not_enabled", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetchInProduction(
      `${baseUrl}/api/admin/marketplace/products/p1/status`,
      {
        method: "PATCH",
        headers: ADMIN_HEADERS,
        body: JSON.stringify({ status: "inactive" }),
      },
    );
    assertMarketplaceDisabled(res);
  } finally {
    server.close();
  }
});

test("production GET /api/admin/marketplace/orders → 501 not_enabled", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetchInProduction(`${baseUrl}/api/admin/marketplace/orders`, {
      headers: ADMIN_HEADERS,
    });
    assertMarketplaceDisabled(res);
  } finally {
    server.close();
  }
});

test("production GET /api/admin/marketplace/orders/:id → 501 not_enabled", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetchInProduction(`${baseUrl}/api/admin/marketplace/orders/o1`, {
      headers: ADMIN_HEADERS,
    });
    assertMarketplaceDisabled(res);
  } finally {
    server.close();
  }
});

test("production PATCH /api/admin/marketplace/orders/:id/status → 501 not_enabled", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetchInProduction(
      `${baseUrl}/api/admin/marketplace/orders/o1/status`,
      {
        method: "PATCH",
        headers: ADMIN_HEADERS,
        body: JSON.stringify({ status: "confirmed" }),
      },
    );
    assertMarketplaceDisabled(res);
  } finally {
    server.close();
  }
});

// admin authN 仍先於 store 停用訊號：缺 token → 401（不洩漏 501/資料）。
test("production 缺 admin token → 仍 401（authN 先於 feature 停用）", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetchInProduction(`${baseUrl}/api/admin/marketplace/orders`, {});
    assert.equal(res.status, 401);
    assert.deepEqual(res.body, { ok: false, error: "missing_admin_token" });
  } finally {
    server.close();
  }
});

// reminders 在 stt_proxy 無專屬後端 HTTP 路由（屬 client 端本地功能），
// 故以 /health 作 smoke：證明本 CR 的 501 變更僅限 marketplace/daily-care，
// 不影響其他 production-stable 路由。
test("reminders smoke：production 下 /health 仍 200（501 變更未外溢）", async () => {
  const server = await startServer();
  try {
    const baseUrl = `http://127.0.0.1:${server.address().port}`;
    const res = await fetchInProduction(`${baseUrl}/health`, {});
    assert.equal(res.status, 200);
  } finally {
    server.close();
  }
});
