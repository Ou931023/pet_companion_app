// CR-0032 Marketplace store 單元測試。
// 以 temp 檔隔離，不污染正式 data。

const assert = require("node:assert/strict");
const test = require("node:test");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const store = require("./marketplaceStore");

function tempFiles() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "marketplace_unit_"));
  return {
    productsFilePath: path.join(dir, "products.json"),
    ordersFilePath: path.join(dir, "orders.json"),
  };
}

test("createProduct 正規化欄位並可被 list 查到（預設只回 active）", async () => {
  const opt = tempFiles();
  const r = await store.createProduct(
    {
      name: "防滑沐浴椅",
      center_id: "c1",
      center_name: "安心長照中心",
      category: "亂填分類",
      price: 1800.7,
      stock: 12.9,
      commission_rate: 0.1,
      status: "active",
    },
    opt,
  );
  assert.equal(r.ok, true);
  assert.ok(r.product.id, "應自動產生 id");
  assert.equal(r.product.category, "其他", "未知分類收斂為其他");
  assert.equal(r.product.price, 1801, "price 取整數");
  assert.equal(r.product.stock, 13, "stock 取整數");

  const list = await store.listProducts(opt);
  assert.equal(list.length, 1);
  assert.equal(list[0].id, r.product.id);
});

test("listProducts 預設隱藏 inactive，status=all 才全回", async () => {
  const opt = tempFiles();
  const a = await store.createProduct({ name: "上架品", status: "active" }, opt);
  const b = await store.createProduct({ name: "下架品", status: "inactive" }, opt);
  assert.equal(a.ok, true);
  assert.equal(b.ok, true);

  const visible = await store.listProducts(opt);
  assert.equal(visible.length, 1);
  assert.equal(visible[0].name, "上架品");

  const all = await store.listProducts({ ...opt, status: "all" });
  assert.equal(all.length, 2);
});

test("setProductStatus 下架後長者端就看不到", async () => {
  const opt = tempFiles();
  const p = await store.createProduct({ name: "助行器", status: "active" }, opt);
  const off = await store.setProductStatus(p.product.id, "inactive", opt);
  assert.equal(off.ok, true);
  assert.equal(off.product.status, "inactive");

  const visible = await store.listProducts(opt);
  assert.equal(visible.length, 0);
});

test("createOrder 依當下商品重算金額、抽成與長照中心實收，並扣庫存", async () => {
  const opt = tempFiles();
  const p1 = await store.createProduct(
    {
      name: "防滑沐浴椅",
      center_id: "c1",
      center_name: "安心長照中心",
      price: 1800,
      stock: 12,
      commission_rate: 0.1,
    },
    opt,
  );
  const p2 = await store.createProduct(
    {
      name: "助行器",
      center_id: "c1",
      center_name: "安心長照中心",
      price: 2500,
      stock: 6,
      commission_rate: 0.1,
    },
    opt,
  );

  const order = await store.createOrder(
    {
      userId: "u1",
      elderName: "陳奶奶",
      items: [
        { productId: p1.product.id, quantity: 1 },
        { productId: p2.product.id, quantity: 2 },
      ],
    },
    opt,
  );
  assert.equal(order.ok, true);
  // 1800*1 + 2500*2 = 6800
  assert.equal(order.order.total_amount, 6800);
  assert.equal(order.order.commission_amount, 680, "6800 * 0.1");
  assert.equal(order.order.center_revenue, 6120, "6800 - 680");
  assert.equal(order.order.status, "pending");
  assert.equal(order.order.items.length, 2);

  // 庫存應被扣掉。
  const afterP2 = await store.getProductById(p2.product.id, opt);
  assert.equal(afterP2.stock, 4, "6 - 2");
});

test("createOrder 庫存不足回 insufficient_stock，不扣庫存", async () => {
  const opt = tempFiles();
  const p = await store.createProduct(
    { name: "助行器", center_id: "c1", price: 2500, stock: 1, commission_rate: 0.1 },
    opt,
  );
  const order = await store.createOrder(
    { userId: "u1", items: [{ productId: p.product.id, quantity: 3 }] },
    opt,
  );
  assert.equal(order.ok, false);
  assert.equal(order.error, "insufficient_stock");
  const after = await store.getProductById(p.product.id, opt);
  assert.equal(after.stock, 1, "失敗不應扣庫存");
});

test("createOrder 跨長照中心回 multiple_centers（MVP 不拆單）", async () => {
  const opt = tempFiles();
  const a = await store.createProduct(
    { name: "A", center_id: "c1", price: 100, stock: 10, commission_rate: 0.1 },
    opt,
  );
  const b = await store.createProduct(
    { name: "B", center_id: "c2", price: 100, stock: 10, commission_rate: 0.1 },
    opt,
  );
  const order = await store.createOrder(
    {
      userId: "u1",
      items: [
        { productId: a.product.id, quantity: 1 },
        { productId: b.product.id, quantity: 1 },
      ],
    },
    opt,
  );
  assert.equal(order.ok, false);
  assert.equal(order.error, "multiple_centers");
});

test("createOrder 空購物車回 empty_cart", async () => {
  const opt = tempFiles();
  const order = await store.createOrder({ userId: "u1", items: [] }, opt);
  assert.equal(order.ok, false);
  assert.equal(order.error, "empty_cart");
});

test("updateOrderStatus 改狀態並可填配送備註；非法狀態被擋", async () => {
  const opt = tempFiles();
  const p = await store.createProduct(
    { name: "A", center_id: "c1", price: 100, stock: 10, commission_rate: 0.1 },
    opt,
  );
  const order = await store.createOrder(
    { userId: "u1", items: [{ productId: p.product.id, quantity: 1 }] },
    opt,
  );

  const bad = await store.updateOrderStatus(order.order.id, "flying", {}, opt);
  assert.equal(bad.ok, false);
  assert.equal(bad.error, "invalid_status");

  const ok = await store.updateOrderStatus(
    order.order.id,
    "shipping",
    { deliveryNote: "明天下午送達" },
    opt,
  );
  assert.equal(ok.ok, true);
  assert.equal(ok.order.status, "shipping");
  assert.equal(ok.order.delivery_note, "明天下午送達");
});

test("seedDefaultProducts 寫入種子商品，且不覆蓋既有資料", async () => {
  const opt = tempFiles();
  const seeded = await store.seedDefaultProducts(opt);
  assert.equal(seeded.length, store.SEED_PRODUCTS.length);
  assert.ok(seeded.length >= 12, "Demo 品項應夠豐富（至少 12 樣）");
  assert.ok(seeded.every((p) => p.created_at && p.updated_at));

  // 再次呼叫不應重複寫入。
  const again = await store.seedDefaultProducts(opt);
  assert.equal(again.length, seeded.length);
});

// ---- CR-0034 B2 / CR-0042 blocker：production JSON-only guard ----
// 用 options.env 注入 production 語義（NODE_ENV=test 仍恆為 dev，故不影響其他測試）。
const PROD = { env: { APP_ENV: "production" } };

test("marketplace：production 下 mutation 回 feature_unavailable_in_production（不寫檔）", async () => {
  const opt = tempFiles();
  const create = await store.createProduct({ name: "床" }, { ...opt, ...PROD });
  assert.deepEqual(create, { ok: false, error: "feature_unavailable_in_production" });
  const order = await store.createOrder(
    { items: [{ productId: "x", quantity: 1 }] },
    { ...opt, ...PROD },
  );
  assert.deepEqual(order, { ok: false, error: "feature_unavailable_in_production" });
  const upd = await store.updateProduct("id", { name: "x" }, { ...opt, ...PROD });
  assert.equal(upd.error, "feature_unavailable_in_production");
  const sts = await store.setProductStatus("id", "inactive", { ...opt, ...PROD });
  assert.equal(sts.error, "feature_unavailable_in_production");
  const ord = await store.updateOrderStatus("id", "shipping", {}, { ...opt, ...PROD });
  assert.equal(ord.error, "feature_unavailable_in_production");
  // 確認沒有任何檔案被寫出。
  assert.equal(fs.existsSync(opt.productsFilePath), false);
  assert.equal(fs.existsSync(opt.ordersFilePath), false);
});

test("marketplace：production 下 read 拋 FeatureUnavailableInProductionError", async () => {
  const opt = tempFiles();
  await assert.rejects(
    () => store.listProducts({ ...opt, ...PROD }),
    /feature_unavailable_in_production/,
  );
  await assert.rejects(
    () => store.getProductById("x", { ...opt, ...PROD }),
    /feature_unavailable_in_production/,
  );
  await assert.rejects(
    () => store.listOrders({ ...opt, ...PROD }),
    /feature_unavailable_in_production/,
  );
});

test("marketplace：production seedDefaultProducts no-op（不寫種子）", async () => {
  const opt = tempFiles();
  const seeded = await store.seedDefaultProducts({ ...opt, ...PROD });
  assert.deepEqual(seeded, []);
  assert.equal(fs.existsSync(opt.productsFilePath), false);
});
