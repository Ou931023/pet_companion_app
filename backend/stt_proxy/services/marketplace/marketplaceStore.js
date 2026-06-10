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

const defaultPg = require("../../db/postgres");
const {
  isJsonFallbackAllowed,
  FeatureUnavailableInProductionError,
  FEATURE_UNAVAILABLE_IN_PRODUCTION,
} = require("../../config/env");

// 持久化策略（CR-0066+ 商城 JSON→PostgreSQL 平移；比照 careAlertStoreService §5.3）：
//   - **DB-優先**：isPostgresAvailable()（要求 DATABASE_URL + PGVECTOR_ENABLED=true）為 true
//     → 走 PostgreSQL（migration 009 建表、015 放寬 id 為 TEXT 並灌種子）。
//   - **dev/staging（isJsonFallbackAllowed=true）且無 DB** → 走既有 JSON store（行為零變更，
//     保住所有現有測試與無 DB 的 Demo 機）。
//   - **production（ALLOW_JSON_FALLBACK=false）且無 DB** → 防禦性停用：回 / throw
//     feature_unavailable（不把 JSON 當正式資料來源）。實務上 production 一定設好 DB，
//     故此分支僅為 misconfiguration 的安全網。
//   - **DB 例外**：production 不降級 JSON（讀類 throw 一般 Error→500；envelope 類回
//     write_failed）；dev/staging 降級 JSON。
//
// 對外 9+1 函式的簽名 / 回傳形狀 / error 碼一律不可變（key 用 'ok'）。
let activePg = defaultPg;

// 測試專用：注入 / 還原 pg。mock pg 需提供：
//   - query(text, params) → { rows }
//   - isPostgresAvailable() → boolean（決定走 DB 或 JSON）
function setPgForTest(pg) {
  activePg = pg || defaultPg;
}

// 是否走 DB。缺 isPostgresAvailable（或拋例外）一律視為不可用 → JSON 路徑。
async function isDbAvailable(pg) {
  if (!pg || typeof pg.isPostgresAvailable !== "function") return false;
  try {
    return await pg.isPostgresAvailable();
  } catch (_error) {
    return false;
  }
}

// DB 例外只記結構化 log（不含商品 / 訂單 / 對話原文）；僅 op 與 error.message。
function logDbError(op, error) {
  console.error(`[marketplace-store] DB ${op} failed`, {
    error: error?.message || String(error),
  });
}

// production（!isJsonFallbackAllowed）→ JSON 不可作為正式資料來源。
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

// ---- DB 路徑共用工具 ----

// timestamptz 從 pg 取回是 JS Date；對外契約用 ISO8601 字串。
function toIso(value) {
  if (value == null) return null;
  if (value instanceof Date) return value.toISOString();
  return value;
}

// 把 marketplace_products row 映射為對外 product 形狀（與 JSON 路徑逐欄一致）：
// 文字欄位 null→""、price/stock→int、commission_rate NUMERIC→Number、時間 Date→ISO。
function rowToProduct(row) {
  return {
    id: row.id,
    center_id: row.center_id ?? "",
    center_name: row.center_name ?? "",
    name: row.name ?? "",
    description: row.description ?? "",
    category: row.category ?? "",
    price: Math.max(0, Math.round(toFiniteNumber(row.price, 0))),
    stock: Math.max(0, Math.round(toFiniteNumber(row.stock, 0))),
    image_url: row.image_url ?? "",
    status: row.status ?? "active",
    commission_rate: normalizeCommissionRate(row.commission_rate),
    created_at: toIso(row.created_at),
    updated_at: toIso(row.updated_at),
  };
}

// 把 marketplace_orders row 映射為對外 order 形狀（與 JSON 路徑逐欄一致）。
// items 來自 items_json（pg 取回 JSONB 已是 JS 陣列）。
function rowToOrder(row) {
  const items = Array.isArray(row.items_json)
    ? row.items_json
    : Array.isArray(row.items)
      ? row.items
      : [];
  return {
    id: row.id,
    user_id: row.user_id ?? null,
    elder_name: row.elder_name ?? "",
    center_id: row.center_id ?? null,
    center_name: row.center_name ?? "",
    items: items.map((it) => ({
      product_id: it.product_id,
      product_name: it.product_name,
      quantity: it.quantity,
      unit_price: it.unit_price,
      subtotal: it.subtotal,
    })),
    total_amount: Math.round(toFiniteNumber(row.total_amount, 0)),
    commission_rate: normalizeCommissionRate(row.commission_rate),
    commission_amount: Math.round(toFiniteNumber(row.commission_amount, 0)),
    center_revenue: Math.round(toFiniteNumber(row.center_revenue, 0)),
    status: row.status ?? "pending",
    delivery_note: row.delivery_note ?? "",
    created_at: toIso(row.created_at),
    updated_at: toIso(row.updated_at),
  };
}

// ---- 商品 ----

// 首次啟動或檔案不存在 / 為空時，寫入 Demo 種子商品，方便展示。
// 已有商品時不覆蓋。回傳實際寫入的商品清單（或既有清單）。
async function seedDefaultProductsDb(pg) {
  // migration 015 已灌種子；DB 路徑回現有商品清單（no-op 種子，不重複寫）。
  const result = await pg.query(
    `SELECT * FROM marketplace_products ORDER BY created_at DESC`,
  );
  return (result.rows || []).map(rowToProduct);
}

async function seedDefaultProductsJson(options) {
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

async function seedDefaultProducts(options = {}) {
  const pg = options.pg || activePg;
  if (await isDbAvailable(pg)) {
    try {
      return await seedDefaultProductsDb(pg);
    } catch (error) {
      logDbError("seedDefaultProducts", error);
      // best-effort：DB 例外時不在 production 降級寫 JSON。
    }
  }
  // production 無 DB：JSON-only 停用 → 不寫種子（startup best-effort，靜默 no-op）。
  if (jsonFeatureBlocked(options)) return [];
  return seedDefaultProductsJson(options);
}

async function listProductsDb(pg, options) {
  const where = [];
  const params = [];
  // status：'all' 回全部；預設（未帶）只回 active（長者端安全）；其餘照值過濾。
  const status = (options.status || "").toString().trim().toLowerCase();
  if (status === "all") {
    // 不過濾
  } else if (status) {
    params.push(status);
    where.push(`status = $${params.length}`);
  } else {
    params.push("active");
    where.push(`status = $${params.length}`);
  }
  if (options.category) {
    params.push(normalizeCategory(options.category));
    where.push(`category = $${params.length}`);
  }
  let sql = `SELECT * FROM marketplace_products`;
  if (where.length > 0) sql += ` WHERE ${where.join(" AND ")}`;
  sql += ` ORDER BY created_at DESC`;
  const result = await pg.query(sql, params);
  return (result.rows || []).map(rowToProduct);
}

async function listProductsJson(options) {
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

async function listProducts(options = {}) {
  const pg = options.pg || activePg;
  const fallbackAllowed = isJsonFallbackAllowed(options.env || process.env);
  if (await isDbAvailable(pg)) {
    try {
      return await listProductsDb(pg, options);
    } catch (error) {
      logDbError("listProducts", error);
      // 讀類：production 不降級 JSON → throw 一般 Error（route → 500）；dev 降級 JSON。
      if (!fallbackAllowed) throw error;
    }
  } else if (!fallbackAllowed) {
    // production 無 DB：JSON 不可作為正式資料來源（防禦性停用）。
    throw new FeatureUnavailableInProductionError();
  }
  return listProductsJson(options);
}

async function getProductByIdDb(pg, id) {
  const result = await pg.query(
    `SELECT * FROM marketplace_products WHERE id = $1`,
    [id],
  );
  const row = (result.rows || [])[0];
  return row ? rowToProduct(row) : null;
}

async function getProductByIdJson(id, options) {
  const filePath = resolveProductsFile(options);
  const rows = await readAll(filePath, "products");
  return rows.find((p) => p.id === id) || null;
}

async function getProductById(id, options = {}) {
  const pg = options.pg || activePg;
  const fallbackAllowed = isJsonFallbackAllowed(options.env || process.env);
  if (await isDbAvailable(pg)) {
    try {
      return await getProductByIdDb(pg, id);
    } catch (error) {
      logDbError("getProductById", error);
      if (!fallbackAllowed) throw error;
    }
  } else if (!fallbackAllowed) {
    throw new FeatureUnavailableInProductionError();
  }
  return getProductByIdJson(id, options);
}

async function createProductDb(pg, payload) {
  const product = normalizeProduct(payload);
  await pg.query(
    `INSERT INTO marketplace_products (
       id, center_id, center_name, name, description, category, price, stock,
       image_url, status, commission_rate, created_at, updated_at
     ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12::timestamptz,$13::timestamptz)`,
    [
      product.id, // $1
      product.center_id, // $2
      product.center_name, // $3
      product.name, // $4
      product.description, // $5
      product.category, // $6
      product.price, // $7
      product.stock, // $8
      product.image_url, // $9
      product.status, // $10
      product.commission_rate, // $11
      product.created_at, // $12
      product.updated_at, // $13
    ],
  );
  return { ok: true, product };
}

async function createProductJson(payload, options) {
  const filePath = resolveProductsFile(options);
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

async function createProduct(payload = {}, options = {}) {
  if (!payload || !String(payload.name || "").trim()) {
    return { ok: false, error: "invalid_payload" };
  }
  const pg = options.pg || activePg;
  const fallbackAllowed = isJsonFallbackAllowed(options.env || process.env);
  if (await isDbAvailable(pg)) {
    try {
      return await createProductDb(pg, payload);
    } catch (error) {
      logDbError("createProduct", error);
      if (!fallbackAllowed) return { ok: false, error: "write_failed" };
    }
  } else if (!fallbackAllowed) {
    return { ok: false, error: FEATURE_UNAVAILABLE_IN_PRODUCTION };
  }
  return createProductJson(payload, options);
}

async function updateProductDb(pg, id, payload) {
  const existRes = await pg.query(
    `SELECT * FROM marketplace_products WHERE id = $1`,
    [id],
  );
  const existRow = (existRes.rows || [])[0];
  if (!existRow) return { ok: false, error: "not_found" };
  const updated = normalizeProduct(payload, rowToProduct(existRow));
  const result = await pg.query(
    `UPDATE marketplace_products SET
       center_id=$2, center_name=$3, name=$4, description=$5, category=$6,
       price=$7, stock=$8, image_url=$9, status=$10, commission_rate=$11,
       updated_at=$12::timestamptz
     WHERE id=$1 RETURNING *`,
    [
      id, // $1
      updated.center_id, // $2
      updated.center_name, // $3
      updated.name, // $4
      updated.description, // $5
      updated.category, // $6
      updated.price, // $7
      updated.stock, // $8
      updated.image_url, // $9
      updated.status, // $10
      updated.commission_rate, // $11
      updated.updated_at, // $12
    ],
  );
  const row = (result.rows || [])[0];
  return { ok: true, product: row ? rowToProduct(row) : updated };
}

async function updateProductJson(id, payload, options) {
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

async function updateProduct(id, payload = {}, options = {}) {
  const pg = options.pg || activePg;
  const fallbackAllowed = isJsonFallbackAllowed(options.env || process.env);
  if (await isDbAvailable(pg)) {
    try {
      return await updateProductDb(pg, id, payload);
    } catch (error) {
      logDbError("updateProduct", error);
      if (!fallbackAllowed) return { ok: false, error: "write_failed" };
    }
  } else if (!fallbackAllowed) {
    return { ok: false, error: FEATURE_UNAVAILABLE_IN_PRODUCTION };
  }
  return updateProductJson(id, payload, options);
}

async function setProductStatusDb(pg, id, status) {
  const result = await pg.query(
    `UPDATE marketplace_products SET status=$2, updated_at=NOW()
     WHERE id=$1 RETURNING *`,
    [id, status],
  );
  const row = (result.rows || [])[0];
  if (!row) return { ok: false, error: "not_found" };
  return { ok: true, product: rowToProduct(row) };
}

async function setProductStatusJson(id, status, options) {
  const filePath = resolveProductsFile(options);
  try {
    const rows = await readAll(filePath, "products");
    const index = rows.findIndex((p) => p.id === id);
    if (index === -1) return { ok: false, error: "not_found" };
    const updated = {
      ...rows[index],
      status,
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

async function setProductStatus(id, status, options = {}) {
  const normalized = (status || "").toString().trim().toLowerCase();
  if (!PRODUCT_STATUSES.includes(normalized)) {
    return { ok: false, error: "invalid_status" };
  }
  const pg = options.pg || activePg;
  const fallbackAllowed = isJsonFallbackAllowed(options.env || process.env);
  if (await isDbAvailable(pg)) {
    try {
      return await setProductStatusDb(pg, id, normalized);
    } catch (error) {
      logDbError("setProductStatus", error);
      if (!fallbackAllowed) return { ok: false, error: "write_failed" };
    }
  } else if (!fallbackAllowed) {
    return { ok: false, error: FEATURE_UNAVAILABLE_IN_PRODUCTION };
  }
  return setProductStatusJson(id, normalized, options);
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
// 把 rawItems 合併為 Map<productId, qty>。回 { ok:false, error } 或 { quantities }。
function buildQuantities(payload) {
  const rawItems = Array.isArray(payload.items) ? payload.items : [];
  if (rawItems.length === 0) {
    return { error: "empty_cart" };
  }
  const quantities = new Map();
  for (const raw of rawItems) {
    const productId = raw && (raw.productId ?? raw.product_id);
    const qty = Math.round(toFiniteNumber(raw && raw.quantity, 0));
    if (!productId || qty <= 0) {
      return { error: "invalid_item" };
    }
    quantities.set(productId, (quantities.get(productId) || 0) + qty);
  }
  return { quantities };
}

// DB 路徑：單一 transaction（BEGIN → 鎖列驗證 → 條件式扣庫存 → INSERT 訂單 → COMMIT）。
// 任一驗證失敗或例外都 ROLLBACK；所有 error 碼與 JSON 路徑一致。
// 真 pool（有 getPool）會以單一 client 跑交易；mock pg（僅 query）則以 query 序列驗證。
async function createOrderDb(pg, payload) {
  const built = buildQuantities(payload);
  if (built.error) return { ok: false, error: built.error };
  const quantities = built.quantities;

  const pool = typeof pg.getPool === "function" ? pg.getPool() : null;
  const client = pool ? await pool.connect() : null;
  const run = client ? (t, p) => client.query(t, p) : (t, p) => pg.query(t, p);
  let began = false;
  try {
    await run("BEGIN");
    began = true;

    const ids = [...quantities.keys()];
    const sel = await run(
      `SELECT * FROM marketplace_products WHERE id = ANY($1) FOR UPDATE`,
      [ids],
    );
    const byId = new Map((sel.rows || []).map((r) => [r.id, r]));

    const items = [];
    let centerId = null;
    let centerName = "";
    let commissionRate = null;
    let totalAmount = 0;

    for (const [productId, qty] of quantities.entries()) {
      const product = byId.get(productId);
      if (!product) {
        await run("ROLLBACK");
        return { ok: false, error: "product_not_found" };
      }
      if (product.status !== "active") {
        await run("ROLLBACK");
        return { ok: false, error: "product_unavailable" };
      }
      if (centerId == null) {
        centerId = product.center_id;
        centerName = product.center_name;
        commissionRate = normalizeCommissionRate(product.commission_rate);
      } else if (product.center_id !== centerId) {
        // MVP 不支援跨長照中心拆單。
        await run("ROLLBACK");
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

    // 扣庫存：條件式 UPDATE（stock>=qty），affected rows 為 0 → 庫存不足 → ROLLBACK。
    for (const [productId, qty] of quantities.entries()) {
      const upd = await run(
        `UPDATE marketplace_products SET stock = stock - $2, updated_at = NOW()
         WHERE id = $1 AND stock >= $2 RETURNING id`,
        [productId, qty],
      );
      if (!upd.rows || upd.rows.length === 0) {
        await run("ROLLBACK");
        return { ok: false, error: "insufficient_stock", productId };
      }
    }

    const commissionAmount = Math.round(totalAmount * (commissionRate || 0));
    const centerRevenue = totalAmount - commissionAmount;
    const id = randomUUID();
    const insRes = await run(
      `INSERT INTO marketplace_orders (
         id, user_id, elder_name, center_id, center_name, items_json,
         total_amount, commission_rate, commission_amount, center_revenue,
         status, delivery_note, created_at, updated_at
       ) VALUES ($1,$2,$3,$4,$5,$6::jsonb,$7,$8,$9,$10,$11,$12, NOW(), NOW())
       RETURNING *`,
      [
        id, // $1
        payload.userId ?? payload.user_id ?? null, // $2
        (payload.elderName ?? payload.elder_name ?? "").toString().trim(), // $3
        centerId, // $4
        centerName, // $5
        JSON.stringify(items), // $6
        totalAmount, // $7
        commissionRate || 0, // $8
        commissionAmount, // $9
        centerRevenue, // $10
        "pending", // $11
        (payload.deliveryNote ?? payload.delivery_note ?? "").toString().trim(), // $12
      ],
    );

    await run("COMMIT");
    const row = (insRes.rows || [])[0];
    return { ok: true, order: row ? rowToOrder(row) : null };
  } catch (error) {
    if (began) {
      try {
        await run("ROLLBACK");
      } catch (_rollbackError) {
        // ROLLBACK 失敗只忽略（連線可能已壞），原始錯誤往上拋。
      }
    }
    throw error;
  } finally {
    if (client && typeof client.release === "function") client.release();
  }
}

async function createOrderJson(payload, options) {
  const productsFile = resolveProductsFile(options);
  const ordersFile = resolveOrdersFile(options);

  const built = buildQuantities(payload);
  if (built.error) return { ok: false, error: built.error };
  const quantities = built.quantities;

  try {
    const products = await readAll(productsFile, "products");
    const byId = new Map(products.map((p) => [p.id, p]));

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

async function createOrder(payload = {}, options = {}) {
  const pg = options.pg || activePg;
  const fallbackAllowed = isJsonFallbackAllowed(options.env || process.env);
  if (await isDbAvailable(pg)) {
    try {
      return await createOrderDb(pg, payload);
    } catch (error) {
      logDbError("createOrder", error);
      if (!fallbackAllowed) return { ok: false, error: "write_failed" };
    }
  } else if (!fallbackAllowed) {
    return { ok: false, error: FEATURE_UNAVAILABLE_IN_PRODUCTION };
  }
  return createOrderJson(payload, options);
}

async function listOrdersDb(pg, options) {
  const where = [];
  const params = [];
  if (options.status && options.status !== "all") {
    params.push(options.status);
    where.push(`status = $${params.length}`);
  }
  if (options.userId != null) {
    params.push(options.userId);
    where.push(`user_id = $${params.length}`);
  }
  let sql = `SELECT * FROM marketplace_orders`;
  if (where.length > 0) sql += ` WHERE ${where.join(" AND ")}`;
  sql += ` ORDER BY created_at DESC`;
  const result = await pg.query(sql, params);
  return (result.rows || []).map(rowToOrder);
}

async function listOrdersJson(options) {
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

async function listOrders(options = {}) {
  const pg = options.pg || activePg;
  const fallbackAllowed = isJsonFallbackAllowed(options.env || process.env);
  if (await isDbAvailable(pg)) {
    try {
      return await listOrdersDb(pg, options);
    } catch (error) {
      logDbError("listOrders", error);
      if (!fallbackAllowed) throw error;
    }
  } else if (!fallbackAllowed) {
    throw new FeatureUnavailableInProductionError();
  }
  return listOrdersJson(options);
}

async function getOrderByIdDb(pg, id) {
  const result = await pg.query(
    `SELECT * FROM marketplace_orders WHERE id = $1`,
    [id],
  );
  const row = (result.rows || [])[0];
  return row ? rowToOrder(row) : null;
}

async function getOrderByIdJson(id, options) {
  const filePath = resolveOrdersFile(options);
  const rows = await readAll(filePath, "orders");
  return rows.find((o) => o.id === id) || null;
}

async function getOrderById(id, options = {}) {
  const pg = options.pg || activePg;
  const fallbackAllowed = isJsonFallbackAllowed(options.env || process.env);
  if (await isDbAvailable(pg)) {
    try {
      return await getOrderByIdDb(pg, id);
    } catch (error) {
      logDbError("getOrderById", error);
      if (!fallbackAllowed) throw error;
    }
  } else if (!fallbackAllowed) {
    throw new FeatureUnavailableInProductionError();
  }
  return getOrderByIdJson(id, options);
}

async function updateOrderStatusDb(pg, id, status, fields) {
  const sets = [`status = $2`, `updated_at = NOW()`];
  const params = [id, status];
  // 配送備註可一併更新（管理端填寫）。
  if (fields.deliveryNote != null || fields.delivery_note != null) {
    params.push(
      (fields.deliveryNote ?? fields.delivery_note ?? "").toString().trim(),
    );
    sets.push(`delivery_note = $${params.length}`);
  }
  const result = await pg.query(
    `UPDATE marketplace_orders SET ${sets.join(", ")} WHERE id = $1 RETURNING *`,
    params,
  );
  const row = (result.rows || [])[0];
  if (!row) return { ok: false, error: "not_found" };
  return { ok: true, order: rowToOrder(row) };
}

async function updateOrderStatusJson(id, status, fields, options) {
  const filePath = resolveOrdersFile(options);
  try {
    const rows = await readAll(filePath, "orders");
    const index = rows.findIndex((o) => o.id === id);
    if (index === -1) return { ok: false, error: "not_found" };
    const updated = {
      ...rows[index],
      status,
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

async function updateOrderStatus(id, status, fields = {}, options = {}) {
  const normalized = (status || "").toString().trim().toLowerCase();
  if (!ORDER_STATUSES.includes(normalized)) {
    return { ok: false, error: "invalid_status" };
  }
  const pg = options.pg || activePg;
  const fallbackAllowed = isJsonFallbackAllowed(options.env || process.env);
  if (await isDbAvailable(pg)) {
    try {
      return await updateOrderStatusDb(pg, id, normalized, fields);
    } catch (error) {
      logDbError("updateOrderStatus", error);
      if (!fallbackAllowed) return { ok: false, error: "write_failed" };
    }
  } else if (!fallbackAllowed) {
    return { ok: false, error: FEATURE_UNAVAILABLE_IN_PRODUCTION };
  }
  return updateOrderStatusJson(id, normalized, fields, options);
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
  // 測試 / 工具用：注入 mock pg。
  setPgForTest,
};
