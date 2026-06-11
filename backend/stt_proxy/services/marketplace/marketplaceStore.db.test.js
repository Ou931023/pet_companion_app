// CR-0066+ B4：marketplaceStore DB 路徑單測（mock pg，不需實連 DB）。
//
// 驗：商品 / 訂單 DB 路徑的 SQL / 欄位映射、createOrder 交易序列（BEGIN→鎖列→
// 條件式扣庫存→INSERT→COMMIT）、各 error 碼會 ROLLBACK、回傳形狀與 JSON 路徑一致、
// production DB 例外不降級 JSON（讀類 throw / envelope 類 write_failed）。

const assert = require("node:assert/strict");
const test = require("node:test");

const store = require("./marketplaceStore");

// mock pg：available 控制 isPostgresAvailable；rowsFor 可為固定 rows 或
// (text,params)=>rows；throwOn(text,params) 回 true 時該次 query 拋例外。
// 不提供 getPool → createOrderDb 走 pg.query 序列（可驗 BEGIN/COMMIT/ROLLBACK）。
function makeMockPg({ available = true, rowsFor = [], throwOn = null } = {}) {
  const calls = [];
  return {
    calls,
    isPostgresAvailable: async () => available,
    query: async (text, params) => {
      calls.push({ text, params });
      if (throwOn && throwOn(text, params)) {
        throw new Error("mock db failure");
      }
      const rows = typeof rowsFor === "function" ? rowsFor(text, params) : rowsFor;
      return { rows: rows || [] };
    },
  };
}

const prodEnv = { APP_ENV: "production" };

function productRow(overrides = {}) {
  return {
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
    commission_rate: "0.100", // NUMERIC 從 pg 取回為字串
    created_at: new Date("2026-06-01T10:00:00.000Z"),
    updated_at: new Date("2026-06-01T10:00:00.000Z"),
    ...overrides,
  };
}

// ---- listProducts（DB 路徑）----

test("listProducts DB：預設只回 active、ORDER BY created_at DESC、row→product 映射", async () => {
  const pg = makeMockPg({ available: true, rowsFor: [productRow()] });
  const list = await store.listProducts({ pg });
  assert.equal(list.length, 1);
  const p = list[0];
  assert.equal(p.id, "seed-bath-chair");
  assert.equal(p.price, 1800);
  assert.equal(p.commission_rate, 0.1); // NUMERIC 字串 → Number
  assert.equal(p.created_at, "2026-06-01T10:00:00.000Z"); // Date → ISO
  assert.equal(p.image_url, "");
  // 回傳形狀（key 集合）需與 JSON 路徑 normalizeProduct 一致。
  assert.deepEqual(
    Object.keys(p).sort(),
    Object.keys(store.normalizeProduct({ name: "x" })).sort(),
  );

  const { text, params } = pg.calls[0];
  assert.match(text, /SELECT \* FROM marketplace_products/);
  assert.match(text, /status = \$1/);
  assert.match(text, /ORDER BY created_at DESC/);
  assert.equal(params[0], "active");
});

test("listProducts DB：status=all 不帶 WHERE；category 過濾", async () => {
  const all = makeMockPg({ available: true, rowsFor: [] });
  await store.listProducts({ pg: all, status: "all" });
  assert.doesNotMatch(all.calls[0].text, /WHERE/);

  const cat = makeMockPg({ available: true, rowsFor: [] });
  await store.listProducts({ pg: cat, category: "復健輔具" });
  assert.match(cat.calls[0].text, /category = \$2/);
  assert.equal(cat.calls[0].params[1], "復健輔具");
});

test("listProducts：production DB 例外 → throw 一般 Error（不降級 JSON、非 FeatureUnavailable）", async () => {
  const pg = makeMockPg({ available: true, throwOn: () => true });
  await assert.rejects(
    () => store.listProducts({ pg, env: prodEnv }),
    (err) => {
      assert.ok(!/feature_unavailable_in_production/.test(err.message || ""));
      return true;
    },
  );
});

// ---- getProductById（DB 路徑）----

test("getProductById DB：找到映射、找不到回 null", async () => {
  const found = makeMockPg({ available: true, rowsFor: [productRow()] });
  const p = await store.getProductById("seed-bath-chair", { pg: found });
  assert.ok(p);
  assert.equal(p.id, "seed-bath-chair");
  assert.match(found.calls[0].text, /WHERE id = \$1/);

  const missing = makeMockPg({ available: true, rowsFor: [] });
  assert.equal(await store.getProductById("nope", { pg: missing }), null);
});

// ---- createProduct（DB 路徑）----

test("createProduct DB：INSERT 欄位映射、回 {ok:true, product}", async () => {
  const pg = makeMockPg({ available: true, rowsFor: [] });
  const r = await store.createProduct(
    { name: "助行器", center_id: "c1", category: "亂填", price: 2500.6, stock: 6, commission_rate: 0.1 },
    { pg },
  );
  assert.equal(r.ok, true);
  assert.ok(r.product.id);
  assert.equal(r.product.category, "其他"); // 未知分類收斂
  assert.equal(r.product.price, 2501);
  const { text, params } = pg.calls[0];
  assert.match(text, /INSERT INTO marketplace_products/);
  assert.equal(params[0], r.product.id);
  assert.equal(params[3], "助行器"); // name
  assert.equal(params[6], 2501); // price
});

test("createProduct：缺 name → invalid_payload，不打 DB", async () => {
  const pg = makeMockPg({ available: true });
  const r = await store.createProduct({}, { pg });
  assert.deepEqual(r, { ok: false, error: "invalid_payload" });
  assert.equal(pg.calls.length, 0);
});

test("createProduct：production DB 例外 → write_failed（不降級 JSON）", async () => {
  const pg = makeMockPg({ available: true, throwOn: () => true });
  const r = await store.createProduct({ name: "床" }, { pg, env: prodEnv });
  assert.deepEqual(r, { ok: false, error: "write_failed" });
});

// ---- updateProduct（DB 路徑）----

test("updateProduct DB：先 SELECT 再 UPDATE RETURNING；查無 → not_found", async () => {
  const pg = makeMockPg({
    available: true,
    rowsFor: (text) =>
      /SELECT/.test(text)
        ? [productRow()]
        : [productRow({ name: "新名", updated_at: new Date("2026-06-02T00:00:00.000Z") })],
  });
  const r = await store.updateProduct("seed-bath-chair", { name: "新名" }, { pg });
  assert.equal(r.ok, true);
  assert.equal(r.product.name, "新名");
  assert.match(pg.calls[0].text, /SELECT \* FROM marketplace_products WHERE id = \$1/);
  assert.match(pg.calls[1].text, /UPDATE marketplace_products SET/);

  const missing = makeMockPg({ available: true, rowsFor: [] });
  const nf = await store.updateProduct("nope", { name: "x" }, { pg: missing });
  assert.deepEqual(nf, { ok: false, error: "not_found" });
});

// ---- setProductStatus（DB 路徑）----

test("setProductStatus DB：UPDATE status RETURNING；invalid_status 不打 DB", async () => {
  const pg = makeMockPg({
    available: true,
    rowsFor: [productRow({ status: "inactive" })],
  });
  const r = await store.setProductStatus("seed-bath-chair", "inactive", { pg });
  assert.equal(r.ok, true);
  assert.equal(r.product.status, "inactive");
  assert.match(pg.calls[0].text, /UPDATE marketplace_products SET status=\$2/);

  const bad = makeMockPg({ available: true });
  const r2 = await store.setProductStatus("x", "flying", { pg: bad });
  assert.deepEqual(r2, { ok: false, error: "invalid_status" });
  assert.equal(bad.calls.length, 0);

  const missing = makeMockPg({ available: true, rowsFor: [] });
  const nf = await store.setProductStatus("nope", "active", { pg: missing });
  assert.deepEqual(nf, { ok: false, error: "not_found" });
});

// ---- createOrder（DB 交易路徑）----

// rowsFor 模擬交易：SELECT FOR UPDATE 回商品列；UPDATE 扣庫存回 [{id}]；INSERT 回訂單列。
function orderTxRows(products, { insufficient = false } = {}) {
  return (text, params) => {
    if (/SELECT \* FROM marketplace_products WHERE id = ANY/.test(text)) {
      return products;
    }
    if (/UPDATE marketplace_products SET stock/.test(text)) {
      return insufficient ? [] : [{ id: params[0] }];
    }
    if (/INSERT INTO marketplace_orders/.test(text)) {
      return [
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
          created_at: new Date("2026-06-03T00:00:00.000Z"),
          updated_at: new Date("2026-06-03T00:00:00.000Z"),
        },
      ];
    }
    return [];
  };
}

test("createOrder DB：交易序列 BEGIN→SELECT FOR UPDATE→UPDATE 扣庫存→INSERT→COMMIT，重算金額", async () => {
  const products = [
    productRow({ id: "p1", price: 1800, stock: 12, commission_rate: "0.100", center_id: "c1" }),
    productRow({ id: "p2", name: "助行器", price: 2500, stock: 6, commission_rate: "0.100", center_id: "c1" }),
  ];
  const pg = makeMockPg({ available: true, rowsFor: orderTxRows(products) });
  const r = await store.createOrder(
    {
      userId: "u1",
      elderName: "陳奶奶",
      items: [
        { productId: "p1", quantity: 1 },
        { productId: "p2", quantity: 2 },
      ],
    },
    { pg },
  );
  assert.equal(r.ok, true);
  assert.equal(r.order.total_amount, 6800); // 1800 + 2500*2
  assert.equal(r.order.commission_amount, 680); // 6800 * 0.1
  assert.equal(r.order.center_revenue, 6120);
  assert.equal(r.order.status, "pending");
  assert.equal(r.order.items.length, 2);
  assert.equal(r.order.commission_rate, 0.1);
  assert.equal(r.order.created_at, "2026-06-03T00:00:00.000Z");

  const seq = pg.calls.map((c) => c.text.trim().split(/\s+/).slice(0, 2).join(" "));
  assert.equal(seq[0], "BEGIN");
  assert.match(pg.calls[1].text, /SELECT \* FROM marketplace_products WHERE id = ANY\(\$1\) FOR UPDATE/);
  assert.match(pg.calls[2].text, /UPDATE marketplace_products SET stock = stock - \$2/);
  assert.match(pg.calls[3].text, /UPDATE marketplace_products SET stock/);
  assert.match(pg.calls[4].text, /INSERT INTO marketplace_orders/);
  assert.equal(pg.calls[5].text.trim(), "COMMIT");
});

test("createOrder DB：庫存不足（UPDATE affected rows=0）→ ROLLBACK + insufficient_stock", async () => {
  const products = [productRow({ id: "p1", stock: 1, center_id: "c1" })];
  const pg = makeMockPg({
    available: true,
    rowsFor: orderTxRows(products, { insufficient: true }),
  });
  const r = await store.createOrder(
    { userId: "u1", items: [{ productId: "p1", quantity: 3 }] },
    { pg },
  );
  assert.equal(r.ok, false);
  assert.equal(r.error, "insufficient_stock");
  // 應有 ROLLBACK，且無 COMMIT / INSERT。
  const texts = pg.calls.map((c) => c.text.trim());
  assert.ok(texts.includes("ROLLBACK"));
  assert.ok(!texts.includes("COMMIT"));
  assert.ok(!pg.calls.some((c) => /INSERT INTO marketplace_orders/.test(c.text)));
});

test("createOrder DB：跨長照中心 → ROLLBACK + multiple_centers", async () => {
  const products = [
    productRow({ id: "p1", center_id: "c1" }),
    productRow({ id: "p2", center_id: "c2" }),
  ];
  const pg = makeMockPg({ available: true, rowsFor: orderTxRows(products) });
  const r = await store.createOrder(
    { userId: "u1", items: [{ productId: "p1", quantity: 1 }, { productId: "p2", quantity: 1 }] },
    { pg },
  );
  assert.equal(r.ok, false);
  assert.equal(r.error, "multiple_centers");
  assert.ok(pg.calls.map((c) => c.text.trim()).includes("ROLLBACK"));
});

test("createOrder DB：商品不存在 → ROLLBACK + product_not_found", async () => {
  const pg = makeMockPg({ available: true, rowsFor: orderTxRows([]) });
  const r = await store.createOrder(
    { userId: "u1", items: [{ productId: "ghost", quantity: 1 }] },
    { pg },
  );
  assert.equal(r.ok, false);
  assert.equal(r.error, "product_not_found");
});

test("createOrder DB：下架商品 → ROLLBACK + product_unavailable", async () => {
  const products = [productRow({ id: "p1", status: "inactive" })];
  const pg = makeMockPg({ available: true, rowsFor: orderTxRows(products) });
  const r = await store.createOrder(
    { userId: "u1", items: [{ productId: "p1", quantity: 1 }] },
    { pg },
  );
  assert.equal(r.ok, false);
  assert.equal(r.error, "product_unavailable");
});

test("createOrder DB：空購物車 / 不合法品項在交易前擋下，不打 DB", async () => {
  const pg = makeMockPg({ available: true });
  const empty = await store.createOrder({ items: [] }, { pg });
  assert.deepEqual(empty, { ok: false, error: "empty_cart" });
  const invalid = await store.createOrder({ items: [{ productId: "p1", quantity: 0 }] }, { pg });
  assert.deepEqual(invalid, { ok: false, error: "invalid_item" });
  assert.equal(pg.calls.length, 0);
});

test("createOrder：DB 例外 → ROLLBACK；production 回 write_failed（不降級 JSON）", async () => {
  const pg = makeMockPg({
    available: true,
    throwOn: (text) => /INSERT INTO marketplace_orders/.test(text),
    rowsFor: orderTxRows([productRow({ id: "p1", center_id: "c1" })]),
  });
  const r = await store.createOrder(
    { userId: "u1", items: [{ productId: "p1", quantity: 1 }], env: prodEnv },
    { pg, env: prodEnv },
  );
  assert.deepEqual(r, { ok: false, error: "write_failed" });
  assert.ok(pg.calls.map((c) => c.text.trim()).includes("ROLLBACK"));
});

// ---- listOrders / getOrderById / updateOrderStatus（DB 路徑）----

test("listOrders DB：status / userId 過濾、ORDER BY created_at DESC、row→order 映射", async () => {
  const orderRow = {
    id: "o1",
    user_id: "u1",
    elder_name: "陳奶奶",
    center_id: "c1",
    center_name: "安心長照中心",
    items_json: [{ product_id: "p1", product_name: "椅", quantity: 1, unit_price: 1800, subtotal: 1800 }],
    total_amount: 1800,
    commission_rate: "0.100",
    commission_amount: 180,
    center_revenue: 1620,
    status: "pending",
    delivery_note: "",
    created_at: new Date("2026-06-03T00:00:00.000Z"),
    updated_at: new Date("2026-06-03T00:00:00.000Z"),
  };
  const pg = makeMockPg({ available: true, rowsFor: [orderRow] });
  const list = await store.listOrders({ pg, status: "pending", userId: "u1" });
  assert.equal(list.length, 1);
  assert.equal(list[0].commission_rate, 0.1);
  assert.equal(list[0].items.length, 1);
  assert.equal(list[0].created_at, "2026-06-03T00:00:00.000Z");
  const { text, params } = pg.calls[0];
  assert.match(text, /status = \$1/);
  assert.match(text, /user_id = \$2/);
  assert.match(text, /ORDER BY created_at DESC/);
  assert.equal(params[0], "pending");
  assert.equal(params[1], "u1");
});

test("getOrderById DB：找到映射、找不到回 null", async () => {
  const found = makeMockPg({
    available: true,
    rowsFor: [
      {
        id: "o1",
        items_json: [],
        commission_rate: "0.100",
        status: "pending",
        created_at: new Date("2026-06-03T00:00:00.000Z"),
        updated_at: new Date("2026-06-03T00:00:00.000Z"),
      },
    ],
  });
  const o = await store.getOrderById("o1", { pg: found });
  assert.equal(o.id, "o1");
  assert.match(found.calls[0].text, /SELECT \* FROM marketplace_orders WHERE id = \$1/);

  const missing = makeMockPg({ available: true, rowsFor: [] });
  assert.equal(await store.getOrderById("nope", { pg: missing }), null);
});

test("updateOrderStatus DB：UPDATE status + 配送備註 RETURNING；invalid_status 不打 DB", async () => {
  const updatedRow = {
    id: "o1",
    items_json: [],
    commission_rate: "0.100",
    status: "shipping",
    delivery_note: "明天下午送達",
    created_at: new Date("2026-06-03T00:00:00.000Z"),
    updated_at: new Date("2026-06-04T00:00:00.000Z"),
  };
  const pg = makeMockPg({ available: true, rowsFor: [updatedRow] });
  const r = await store.updateOrderStatus(
    "o1",
    "shipping",
    { deliveryNote: "明天下午送達" },
    { pg },
  );
  assert.equal(r.ok, true);
  assert.equal(r.order.status, "shipping");
  assert.equal(r.order.delivery_note, "明天下午送達");
  assert.match(pg.calls[0].text, /UPDATE marketplace_orders SET status = \$2/);
  assert.match(pg.calls[0].text, /delivery_note = \$3/);

  const bad = makeMockPg({ available: true });
  const r2 = await store.updateOrderStatus("o1", "flying", {}, { pg: bad });
  assert.deepEqual(r2, { ok: false, error: "invalid_status" });
  assert.equal(bad.calls.length, 0);

  const missing = makeMockPg({ available: true, rowsFor: [] });
  const nf = await store.updateOrderStatus("nope", "confirmed", {}, { pg: missing });
  assert.deepEqual(nf, { ok: false, error: "not_found" });
});

// ---- deleteOrder（DB 交易路徑）----

// 僅 SELECT FOR UPDATE 回訂單列；UPDATE 庫存 / DELETE / BEGIN / COMMIT 回 []。
function deleteTxRows(orderRow) {
  return (text) => {
    if (/SELECT \* FROM marketplace_orders WHERE id = \$1 FOR UPDATE/.test(text)) {
      return orderRow ? [orderRow] : [];
    }
    return [];
  };
}

test("deleteOrder DB：交易序列 BEGIN→SELECT FOR UPDATE→逐項還原庫存→DELETE→COMMIT，回 order", async () => {
  const orderRow = {
    id: "o1",
    user_id: "u1",
    elder_name: "驗收測試",
    center_id: "c1",
    center_name: "康福長照中心",
    items_json: [
      { product_id: "p1", product_name: "濕巾", quantity: 2, unit_price: 120, subtotal: 240 },
      { product_id: "p2", product_name: "拐杖", quantity: 1, unit_price: 680, subtotal: 680 },
    ],
    total_amount: 920,
    commission_rate: "0.120",
    commission_amount: 110,
    center_revenue: 810,
    status: "pending",
    delivery_note: "",
    created_at: new Date("2026-06-03T00:00:00.000Z"),
    updated_at: new Date("2026-06-03T00:00:00.000Z"),
  };
  const pg = makeMockPg({ available: true, rowsFor: deleteTxRows(orderRow) });
  const r = await store.deleteOrder("o1", { pg });
  assert.equal(r.ok, true);
  assert.equal(r.order.id, "o1");
  assert.equal(r.order.items.length, 2);

  const texts = pg.calls.map((c) => c.text.trim());
  assert.equal(texts[0], "BEGIN");
  assert.match(pg.calls[1].text, /SELECT \* FROM marketplace_orders WHERE id = \$1 FOR UPDATE/);
  // 兩項商品各一次還原庫存（stock = stock + $2），參數對應 product_id / quantity。
  assert.match(pg.calls[2].text, /UPDATE marketplace_products SET stock = stock \+ \$2/);
  assert.equal(pg.calls[2].params[0], "p1");
  assert.equal(pg.calls[2].params[1], 2);
  assert.match(pg.calls[3].text, /UPDATE marketplace_products SET stock = stock \+ \$2/);
  assert.equal(pg.calls[3].params[0], "p2");
  assert.equal(pg.calls[3].params[1], 1);
  assert.match(pg.calls[4].text, /DELETE FROM marketplace_orders WHERE id = \$1/);
  assert.equal(texts[texts.length - 1], "COMMIT");
});

test("deleteOrder DB：訂單不存在 → ROLLBACK + not_found，不還原庫存也不刪", async () => {
  const pg = makeMockPg({ available: true, rowsFor: deleteTxRows(null) });
  const r = await store.deleteOrder("nope", { pg });
  assert.deepEqual(r, { ok: false, error: "not_found" });
  const texts = pg.calls.map((c) => c.text.trim());
  assert.ok(texts.includes("ROLLBACK"));
  assert.ok(!texts.includes("COMMIT"));
  assert.ok(!pg.calls.some((c) => /DELETE FROM marketplace_orders/.test(c.text)));
  assert.ok(!pg.calls.some((c) => /UPDATE marketplace_products/.test(c.text)));
});

test("deleteOrder：DB 例外 → ROLLBACK；production 回 write_failed（不降級 JSON）", async () => {
  const orderRow = {
    id: "o1",
    items_json: [{ product_id: "p1", quantity: 1 }],
    commission_rate: "0.100",
    status: "pending",
    created_at: new Date("2026-06-03T00:00:00.000Z"),
    updated_at: new Date("2026-06-03T00:00:00.000Z"),
  };
  const pg = makeMockPg({
    available: true,
    throwOn: (text) => /DELETE FROM marketplace_orders/.test(text),
    rowsFor: deleteTxRows(orderRow),
  });
  const r = await store.deleteOrder("o1", { pg, env: prodEnv });
  assert.deepEqual(r, { ok: false, error: "write_failed" });
  assert.ok(pg.calls.map((c) => c.text.trim()).includes("ROLLBACK"));
});
