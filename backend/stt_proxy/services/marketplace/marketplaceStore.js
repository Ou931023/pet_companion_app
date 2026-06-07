// 長照商品商城（Marketplace）持久化 store。
//
// CR-0032：把原本只連外部維康網站的商城，升級成平台自有的長照商品商城。
// 沿用專案既有 data/*.json 檔案模式（同 careAlertStoreService），分兩個檔：
//   - data/marketplace_products.json  商品
//   - data/marketplace_orders.json    訂單
//
// 注意：
// - 兩個 *.json 皆屬 runtime data，不進版控。
// - 讀寫失敗只記 log、回傳 {ok:false}，絕不丟例外讓 server crash。
// - 訂單金額（單價、小計、總額、抽成、長照中心實收）一律由後端依「當下商品資料」
//   重新計算，不信任前端帶入的價格，避免被竄改。
// - 測試請以 options.*FilePath 或對應 env 指向 temp 檔，避免污染正式 data。
//
// 正式方向為 PostgreSQL（schema 見 db/migrations/009_create_marketplace.sql），
// MVP 先用 JSON store，介面保持單純，日後可平移到 DB。

const path = require("path");
const fs = require("fs/promises");
const { randomUUID } = require("crypto");

const {
  isJsonFallbackAllowed,
  FeatureUnavailableInProductionError,
  FEATURE_UNAVAILABLE_IN_PRODUCTION,
} = require("../../config/env");

// CR-0034 B2 / CR-0042 blocker：商城為 **JSON-only** store，正式版尚未平移到 PostgreSQL。
// 因此 production（ALLOW_JSON_FALLBACK=false）一律阻擋，避免把 JSON 當成正式資料來源。
// dev/staging 不受影響（isJsonFallbackAllowed=true），行為零變更。
// envelope 形回傳的函式回 { ok:false, error }；回傳值（陣列 / 物件）的函式改 throw
// 具名錯誤，由各 route 既有 try/catch 轉成既有錯誤回應（不改回應形狀、不外洩 stack）。
function jsonFeatureBlocked(options = {}) {
  return !isJsonFallbackAllowed(options.env || process.env);
}

const DEFAULT_PRODUCTS_FILE = path.join(
  __dirname,
  "..",
  "..",
  "data",
  "marketplace_products.json",
);
const DEFAULT_ORDERS_FILE = path.join(
  __dirname,
  "..",
  "..",
  "data",
  "marketplace_orders.json",
);

// 商品分類固定選項（CR-0032 §三）。未知分類一律收斂為「其他」。
const PRODUCT_CATEGORIES = [
  "照護用品",
  "復健輔具",
  "營養補充",
  "清潔衛生",
  "日常生活",
  "其他",
];

const PRODUCT_STATUSES = ["active", "inactive"];

// 訂單狀態（CR-0032 §六）。
const ORDER_STATUSES = ["pending", "confirmed", "shipping", "completed", "cancelled"];
const ORDER_STATUS_LABELS = {
  pending: "待處理",
  confirmed: "已確認",
  shipping: "配送中",
  completed: "已完成",
  cancelled: "已取消",
};

// Demo 種子商品（CR-0032 §十一）。固定 id 方便 Demo 重現與測試。
//
// 圖片用 loremflickr 依關鍵字取圖、加 ?lock=<n> 讓每個品項固定同一張（不會每次換）。
// 圖會與品項主題相關（不保證每張都精準）；長者端 [MarketplaceProductImage] 有 fallback，
// 萬一取圖失敗也只會顯示乾淨的圖示底，不會破圖。正式照片可在 caregiver_web 商品管理改 URL。
const SEED_IMG = (keywords, lock) =>
  `https://loremflickr.com/600/600/${keywords}?lock=${lock}`;

const SEED_PRODUCTS = [
  // ---- 安心長照中心（抽成 0.10）----
  {
    id: "seed-bath-chair",
    center_id: "center-anxin",
    center_name: "安心長照中心",
    name: "防滑沐浴椅",
    description: "洗澡時穩穩坐著，椅腳防滑，幫長輩洗得安心又安全。",
    category: "照護用品",
    price: 1800,
    stock: 12,
    image_url: SEED_IMG("shower,chair", 11),
    status: "active",
    commission_rate: 0.1,
  },
  {
    id: "seed-care-bed",
    center_id: "center-anxin",
    center_name: "安心長照中心",
    name: "居家電動照護床",
    description: "可調高低和角度，起身、翻身都省力，照顧者腰背也輕鬆。",
    category: "照護用品",
    price: 18800,
    stock: 4,
    image_url: SEED_IMG("hospital,bed", 12),
    status: "active",
    commission_rate: 0.1,
  },
  {
    id: "seed-walker",
    center_id: "center-anxin",
    center_name: "安心長照中心",
    name: "助行器",
    description: "輕巧好推、握把好抓，外出散步多一份支撐和安全感。",
    category: "復健輔具",
    price: 2500,
    stock: 6,
    image_url: SEED_IMG("walker,mobility", 13),
    status: "active",
    commission_rate: 0.1,
  },
  {
    id: "seed-wheelchair",
    center_id: "center-anxin",
    center_name: "安心長照中心",
    name: "輕量摺疊輪椅",
    description: "車身輕、好收折，進出車子或外出看診都方便。",
    category: "復健輔具",
    price: 4200,
    stock: 5,
    image_url: SEED_IMG("wheelchair", 14),
    status: "active",
    commission_rate: 0.1,
  },
  {
    id: "seed-cane",
    center_id: "center-anxin",
    center_name: "安心長照中心",
    name: "四腳止滑拐杖",
    description: "四個腳穩穩站，站立走路更安心，握把好握不咬手。",
    category: "復健輔具",
    price: 680,
    stock: 20,
    image_url: SEED_IMG("walking,cane", 15),
    status: "active",
    commission_rate: 0.1,
  },
  {
    id: "seed-anti-slip-slippers",
    center_id: "center-anxin",
    center_name: "安心長照中心",
    name: "防滑居家拖鞋",
    description: "鞋底止滑、包覆好穿脫，在家走動更安全，減少跌倒。",
    category: "日常生活",
    price: 450,
    stock: 25,
    image_url: SEED_IMG("slippers", 16),
    status: "active",
    commission_rate: 0.1,
  },
  {
    id: "seed-bp-monitor",
    center_id: "center-anxin",
    center_name: "安心長照中心",
    name: "電子血壓計",
    description: "一鍵量測、大字幕好讀，在家就能天天記錄血壓變化。",
    category: "其他",
    price: 1280,
    stock: 15,
    image_url: SEED_IMG("blood,pressure,monitor", 17),
    status: "active",
    commission_rate: 0.1,
  },
  // ---- 康福長照中心（抽成 0.12）----
  {
    id: "seed-protein-drink",
    center_id: "center-kangfu",
    center_name: "康福長照中心",
    name: "高蛋白營養飲",
    description: "胃口不好也能補充營養，順口好喝，幫長輩維持體力。",
    category: "營養補充",
    price: 899,
    stock: 20,
    image_url: SEED_IMG("nutrition,drink", 21),
    status: "active",
    commission_rate: 0.12,
  },
  {
    id: "seed-milk-powder",
    center_id: "center-kangfu",
    center_name: "康福長照中心",
    name: "銀髮營養奶粉",
    description: "好沖泡好吸收，補充每天需要的營養，照顧腸胃也照顧體力。",
    category: "營養補充",
    price: 1150,
    stock: 18,
    image_url: SEED_IMG("milk,powder", 22),
    status: "active",
    commission_rate: 0.12,
  },
  {
    id: "seed-vitamins",
    center_id: "center-kangfu",
    center_name: "康福長照中心",
    name: "綜合維他命保健",
    description: "一天一顆，補足日常容易缺的維他命，幫長輩維持精神。",
    category: "營養補充",
    price: 650,
    stock: 30,
    image_url: SEED_IMG("vitamins,supplement", 23),
    status: "active",
    commission_rate: 0.12,
  },
  {
    id: "seed-adult-diaper",
    center_id: "center-kangfu",
    center_name: "康福長照中心",
    name: "成人紙尿褲",
    description: "透氣不悶、吸收力好，日常照護更輕鬆，長輩也舒服。",
    category: "清潔衛生",
    price: 650,
    stock: 30,
    image_url: SEED_IMG("diaper", 24),
    status: "active",
    commission_rate: 0.12,
  },
  {
    id: "seed-wet-wipes",
    center_id: "center-kangfu",
    center_name: "康福長照中心",
    name: "濕式衛生紙巾",
    description: "溫和不刺激，擦拭清潔很方便，外出或臥床照護都好用。",
    category: "清潔衛生",
    price: 120,
    stock: 50,
    image_url: SEED_IMG("wet,wipes", 25),
    status: "active",
    commission_rate: 0.12,
  },
  {
    id: "seed-care-pad",
    center_id: "center-kangfu",
    center_name: "康福長照中心",
    name: "看護墊",
    description: "吸收力強、表面乾爽，鋪床或座椅都能用，換洗更省事。",
    category: "清潔衛生",
    price: 380,
    stock: 40,
    image_url: SEED_IMG("medical,pad", 26),
    status: "active",
    commission_rate: 0.12,
  },
  {
    id: "seed-food-container",
    center_id: "center-kangfu",
    center_name: "康福長照中心",
    name: "保溫餐盒",
    description: "保溫保鮮，讓長輩好好吃上一頓熱飯，外出送餐也方便。",
    category: "日常生活",
    price: 560,
    stock: 22,
    image_url: SEED_IMG("lunchbox,food", 27),
    status: "active",
    commission_rate: 0.12,
  },
  {
    id: "seed-thermometer",
    center_id: "center-kangfu",
    center_name: "康福長照中心",
    name: "電子體溫計",
    description: "幾秒就量好、嗶聲提醒，量體溫不費力，數字看得清楚。",
    category: "其他",
    price: 480,
    stock: 28,
    image_url: SEED_IMG("thermometer", 28),
    status: "active",
    commission_rate: 0.12,
  },
];

// 種子商品不放外部圖片 URL：外部圖床（loremflickr 當機、placehold.co 不支援繁中→畫成問號）
// 都不可靠。改由長者端 App 自己畫「分類色卡 + 中文品名」placeholder（中文一定正常、不破圖）。
// 之後要放真實照片，於 caregiver_web 商品管理把 image_url 填成真實照片網址即可。
for (const seedProduct of SEED_PRODUCTS) {
  seedProduct.image_url = "";
}

function resolveProductsFile(options = {}) {
  return (
    options.productsFilePath ||
    process.env.MARKETPLACE_PRODUCTS_DATA_FILE ||
    DEFAULT_PRODUCTS_FILE
  );
}

function resolveOrdersFile(options = {}) {
  return (
    options.ordersFilePath ||
    process.env.MARKETPLACE_ORDERS_DATA_FILE ||
    DEFAULT_ORDERS_FILE
  );
}

async function readAll(filePath, tag) {
  try {
    const raw = await fs.readFile(filePath, "utf8");
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch (error) {
    if (error && error.code !== "ENOENT") {
      console.error(`[marketplace-store] ${tag} read failed, treating as empty`, {
        error: error.message,
      });
    }
    return [];
  }
}

async function writeAll(filePath, rows) {
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  await fs.writeFile(filePath, JSON.stringify(rows, null, 2), "utf8");
}

// ---- 正規化輔助 ----

function normalizeCategory(value) {
  const raw = (value == null ? "" : String(value)).trim();
  return PRODUCT_CATEGORIES.includes(raw) ? raw : "其他";
}

function normalizeProductStatus(value) {
  const raw = (value == null ? "" : String(value)).trim().toLowerCase();
  return PRODUCT_STATUSES.includes(raw) ? raw : "active";
}

function toFiniteNumber(value, fallback = 0) {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
}

// 抽成比例收斂到 0..1（允許 0；超界 clamp）。
function normalizeCommissionRate(value) {
  const n = toFiniteNumber(value, 0.1);
  if (n < 0) return 0;
  if (n > 1) return 1;
  return n;
}

function normalizeProduct(payload = {}, existing = null) {
  const now = new Date().toISOString();
  return {
    id: (existing && existing.id) || payload.id || randomUUID(),
    center_id: payload.center_id ?? (existing ? existing.center_id : "") ?? "",
    center_name:
      payload.center_name ?? (existing ? existing.center_name : "") ?? "",
    name: (payload.name ?? (existing ? existing.name : "") ?? "").toString().trim(),
    description:
      payload.description ?? (existing ? existing.description : "") ?? "",
    category: normalizeCategory(
      payload.category ?? (existing ? existing.category : ""),
    ),
    price: Math.max(
      0,
      Math.round(
        toFiniteNumber(payload.price, existing ? existing.price : 0),
      ),
    ),
    stock: Math.max(
      0,
      Math.round(
        toFiniteNumber(payload.stock, existing ? existing.stock : 0),
      ),
    ),
    image_url: payload.image_url ?? (existing ? existing.image_url : "") ?? "",
    status: normalizeProductStatus(
      payload.status ?? (existing ? existing.status : "active"),
    ),
    commission_rate: normalizeCommissionRate(
      payload.commission_rate ??
        (existing ? existing.commission_rate : 0.1),
    ),
    created_at: (existing && existing.created_at) || now,
    updated_at: now,
  };
}

// ---- 商品 ----

// 首次啟動或檔案不存在 / 為空時，寫入 Demo 種子商品，方便展示。
// 已有商品時不覆蓋。回傳實際寫入的商品清單（或既有清單）。
async function seedDefaultProducts(options = {}) {
  // production：JSON-only 商城停用 → 不寫種子（startup best-effort，靜默 no-op）。
  if (jsonFeatureBlocked(options)) return [];
  const filePath = resolveProductsFile(options);
  try {
    const existing = await readAll(filePath, "products");
    if (existing.length > 0) return existing;
    const now = new Date().toISOString();
    const seeded = SEED_PRODUCTS.map((p) => ({
      ...p,
      created_at: now,
      updated_at: now,
    }));
    await writeAll(filePath, seeded);
    return seeded;
  } catch (error) {
    console.error("[marketplace-store] seedDefaultProducts failed", {
      error: error?.message || error,
    });
    return [];
  }
}

async function listProducts(options = {}) {
  if (jsonFeatureBlocked(options)) throw new FeatureUnavailableInProductionError();
  const filePath = resolveProductsFile(options);
  let rows = await readAll(filePath, "products");

  // status：'all' 回全部；預設（未帶）只回 active（長者端安全）；其餘照值過濾。
  const status = (options.status || "").toString().trim().toLowerCase();
  if (status === "all") {
    // 不過濾
  } else if (status) {
    rows = rows.filter((p) => p.status === status);
  } else {
    rows = rows.filter((p) => p.status === "active");
  }

  if (options.category) {
    const wanted = normalizeCategory(options.category);
    rows = rows.filter((p) => normalizeCategory(p.category) === wanted);
  }

  // 新到舊（最後更新在前）。
  rows = [...rows].sort((a, b) =>
    String(b.created_at).localeCompare(String(a.created_at)),
  );
  return rows;
}

async function getProductById(id, options = {}) {
  if (jsonFeatureBlocked(options)) throw new FeatureUnavailableInProductionError();
  const filePath = resolveProductsFile(options);
  const rows = await readAll(filePath, "products");
  return rows.find((p) => p.id === id) || null;
}

async function createProduct(payload = {}, options = {}) {
  if (jsonFeatureBlocked(options)) {
    return { ok: false, error: FEATURE_UNAVAILABLE_IN_PRODUCTION };
  }
  const filePath = resolveProductsFile(options);
  if (!payload || !String(payload.name || "").trim()) {
    return { ok: false, error: "invalid_payload" };
  }
  try {
    const product = normalizeProduct(payload);
    const rows = await readAll(filePath, "products");
    rows.push(product);
    await writeAll(filePath, rows);
    return { ok: true, product };
  } catch (error) {
    console.error("[marketplace-store] createProduct failed", {
      error: error?.message || error,
    });
    return { ok: false, error: "write_failed" };
  }
}

async function updateProduct(id, payload = {}, options = {}) {
  if (jsonFeatureBlocked(options)) {
    return { ok: false, error: FEATURE_UNAVAILABLE_IN_PRODUCTION };
  }
  const filePath = resolveProductsFile(options);
  try {
    const rows = await readAll(filePath, "products");
    const index = rows.findIndex((p) => p.id === id);
    if (index === -1) return { ok: false, error: "not_found" };
    const updated = normalizeProduct(payload, rows[index]);
    rows[index] = updated;
    await writeAll(filePath, rows);
    return { ok: true, product: updated };
  } catch (error) {
    console.error("[marketplace-store] updateProduct failed", {
      error: error?.message || error,
    });
    return { ok: false, error: "write_failed" };
  }
}

async function setProductStatus(id, status, options = {}) {
  if (jsonFeatureBlocked(options)) {
    return { ok: false, error: FEATURE_UNAVAILABLE_IN_PRODUCTION };
  }
  const normalized = (status || "").toString().trim().toLowerCase();
  if (!PRODUCT_STATUSES.includes(normalized)) {
    return { ok: false, error: "invalid_status" };
  }
  const filePath = resolveProductsFile(options);
  try {
    const rows = await readAll(filePath, "products");
    const index = rows.findIndex((p) => p.id === id);
    if (index === -1) return { ok: false, error: "not_found" };
    const updated = {
      ...rows[index],
      status: normalized,
      updated_at: new Date().toISOString(),
    };
    rows[index] = updated;
    await writeAll(filePath, rows);
    return { ok: true, product: updated };
  } catch (error) {
    console.error("[marketplace-store] setProductStatus failed", {
      error: error?.message || error,
    });
    return { ok: false, error: "write_failed" };
  }
}

// ---- 訂單 ----

// 建立訂單。
// payload: { userId, elderName, deliveryNote, items: [{ productId, quantity }] }
// 後端流程：
//   1. 逐項以「當下商品資料」查價、查庫存、查長照中心（不信任前端價格）。
//   2. MVP 限制：一張訂單只能同一長照中心（避免拆單）。
//   3. 計算 total / commission / center_revenue。
//   4. 扣庫存並寫回商品檔（同一次寫入）。
// 任何驗證失敗都回 {ok:false, error}，不丟例外。
async function createOrder(payload = {}, options = {}) {
  if (jsonFeatureBlocked(options)) {
    return { ok: false, error: FEATURE_UNAVAILABLE_IN_PRODUCTION };
  }
  const productsFile = resolveProductsFile(options);
  const ordersFile = resolveOrdersFile(options);

  const rawItems = Array.isArray(payload.items) ? payload.items : [];
  if (rawItems.length === 0) {
    return { ok: false, error: "empty_cart" };
  }

  try {
    const products = await readAll(productsFile, "products");
    const byId = new Map(products.map((p) => [p.id, p]));

    // 數量先依 productId 合併（同商品多列也能正確扣庫存）。
    const quantities = new Map();
    for (const raw of rawItems) {
      const productId = raw && (raw.productId ?? raw.product_id);
      const qty = Math.round(toFiniteNumber(raw && raw.quantity, 0));
      if (!productId || qty <= 0) {
        return { ok: false, error: "invalid_item" };
      }
      quantities.set(productId, (quantities.get(productId) || 0) + qty);
    }

    const items = [];
    let centerId = null;
    let centerName = "";
    let commissionRate = null;
    let totalAmount = 0;

    for (const [productId, qty] of quantities.entries()) {
      const product = byId.get(productId);
      if (!product) return { ok: false, error: "product_not_found" };
      if (product.status !== "active") {
        return { ok: false, error: "product_unavailable" };
      }
      if (toFiniteNumber(product.stock, 0) < qty) {
        return { ok: false, error: "insufficient_stock", productId };
      }
      if (centerId == null) {
        centerId = product.center_id;
        centerName = product.center_name;
        commissionRate = normalizeCommissionRate(product.commission_rate);
      } else if (product.center_id !== centerId) {
        // MVP 不支援跨長照中心拆單。
        return { ok: false, error: "multiple_centers" };
      }
      const unitPrice = Math.max(0, Math.round(toFiniteNumber(product.price, 0)));
      const subtotal = unitPrice * qty;
      totalAmount += subtotal;
      items.push({
        product_id: product.id,
        product_name: product.name,
        quantity: qty,
        unit_price: unitPrice,
        subtotal,
      });
    }

    const commissionAmount = Math.round(totalAmount * (commissionRate || 0));
    const centerRevenue = totalAmount - commissionAmount;
    const now = new Date().toISOString();

    const order = {
      id: randomUUID(),
      user_id: payload.userId ?? payload.user_id ?? null,
      elder_name: (payload.elderName ?? payload.elder_name ?? "").toString().trim(),
      center_id: centerId,
      center_name: centerName,
      items,
      total_amount: totalAmount,
      commission_rate: commissionRate || 0,
      commission_amount: commissionAmount,
      center_revenue: centerRevenue,
      status: "pending",
      delivery_note: (payload.deliveryNote ?? payload.delivery_note ?? "")
        .toString()
        .trim(),
      created_at: now,
      updated_at: now,
    };

    // 扣庫存並寫回商品檔。
    for (const [productId, qty] of quantities.entries()) {
      const product = byId.get(productId);
      product.stock = Math.max(0, Math.round(toFiniteNumber(product.stock, 0)) - qty);
      product.updated_at = now;
    }
    await writeAll(productsFile, products);

    const orders = await readAll(ordersFile, "orders");
    orders.push(order);
    await writeAll(ordersFile, orders);

    return { ok: true, order };
  } catch (error) {
    console.error("[marketplace-store] createOrder failed", {
      error: error?.message || error,
    });
    return { ok: false, error: "write_failed" };
  }
}

async function listOrders(options = {}) {
  if (jsonFeatureBlocked(options)) throw new FeatureUnavailableInProductionError();
  const filePath = resolveOrdersFile(options);
  let rows = await readAll(filePath, "orders");
  if (options.status && options.status !== "all") {
    rows = rows.filter((o) => o.status === options.status);
  }
  if (options.userId != null) {
    rows = rows.filter((o) => o.user_id === options.userId);
  }
  rows = [...rows].sort((a, b) =>
    String(b.created_at).localeCompare(String(a.created_at)),
  );
  return rows;
}

async function getOrderById(id, options = {}) {
  if (jsonFeatureBlocked(options)) throw new FeatureUnavailableInProductionError();
  const filePath = resolveOrdersFile(options);
  const rows = await readAll(filePath, "orders");
  return rows.find((o) => o.id === id) || null;
}

async function updateOrderStatus(id, status, fields = {}, options = {}) {
  if (jsonFeatureBlocked(options)) {
    return { ok: false, error: FEATURE_UNAVAILABLE_IN_PRODUCTION };
  }
  const normalized = (status || "").toString().trim().toLowerCase();
  if (!ORDER_STATUSES.includes(normalized)) {
    return { ok: false, error: "invalid_status" };
  }
  const filePath = resolveOrdersFile(options);
  try {
    const rows = await readAll(filePath, "orders");
    const index = rows.findIndex((o) => o.id === id);
    if (index === -1) return { ok: false, error: "not_found" };
    const updated = {
      ...rows[index],
      status: normalized,
      updated_at: new Date().toISOString(),
    };
    // 配送備註可一併更新（管理端填寫）。
    if (fields.deliveryNote != null || fields.delivery_note != null) {
      updated.delivery_note = (fields.deliveryNote ?? fields.delivery_note ?? "")
        .toString()
        .trim();
    }
    rows[index] = updated;
    await writeAll(filePath, rows);
    return { ok: true, order: updated };
  } catch (error) {
    console.error("[marketplace-store] updateOrderStatus failed", {
      error: error?.message || error,
    });
    return { ok: false, error: "write_failed" };
  }
}

module.exports = {
  PRODUCT_CATEGORIES,
  PRODUCT_STATUSES,
  ORDER_STATUSES,
  ORDER_STATUS_LABELS,
  SEED_PRODUCTS,
  seedDefaultProducts,
  listProducts,
  getProductById,
  createProduct,
  updateProduct,
  setProductStatus,
  createOrder,
  listOrders,
  getOrderById,
  updateOrderStatus,
  normalizeProduct,
  normalizeCommissionRate,
};
