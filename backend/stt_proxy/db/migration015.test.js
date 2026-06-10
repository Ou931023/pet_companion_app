const assert = require("node:assert/strict");
const { test } = require("node:test");
const fs = require("node:fs");
const path = require("node:path");

// CR-0066+ B1：migration 015 靜態審查（本機無 Postgres → 不對真 DB 跑，比照 migration014.test.js）。
// migrate.js 會 glob migrations/*.sql 重跑，故每個 statement 必須冪等可重跑。
// 015 刻意使用 ALTER COLUMN（型別放寬）+ 種子 INSERT ON CONFLICT DO NOTHING。

const SQL_PATH = path.join(__dirname, "migrations", "015_marketplace_pg_seed.sql");

function readSql() {
  return fs.readFileSync(SQL_PATH, "utf8");
}

function statements(sql) {
  const stripped = sql
    .split("\n")
    .map((line) => line.replace(/--.*$/, ""))
    .join("\n");
  return stripped
    .split(";")
    .map((s) => s.trim())
    .filter(Boolean);
}

const SEED_IDS = [
  "seed-bath-chair",
  "seed-care-bed",
  "seed-walker",
  "seed-wheelchair",
  "seed-cane",
  "seed-anti-slip-slippers",
  "seed-bp-monitor",
  "seed-protein-drink",
  "seed-milk-powder",
  "seed-vitamins",
  "seed-adult-diaper",
  "seed-wet-wipes",
  "seed-care-pad",
  "seed-food-container",
  "seed-thermometer",
];

test("migration 015 檔案存在", () => {
  assert.ok(fs.existsSync(SQL_PATH));
});

test("id 型別放寬：products / orders 皆 DROP DEFAULT + TYPE TEXT", () => {
  const sql = readSql();
  assert.match(
    sql,
    /ALTER TABLE marketplace_products ALTER COLUMN id DROP DEFAULT/i,
  );
  assert.match(
    sql,
    /ALTER TABLE marketplace_products ALTER COLUMN id TYPE TEXT/i,
  );
  assert.match(
    sql,
    /ALTER TABLE marketplace_orders ALTER COLUMN id DROP DEFAULT/i,
  );
  assert.match(
    sql,
    /ALTER TABLE marketplace_orders ALTER COLUMN id TYPE TEXT/i,
  );
});

test("種子 INSERT 一律 ON CONFLICT (id) DO NOTHING（冪等可重跑）", () => {
  for (const stmt of statements(readSql())) {
    if (/^INSERT\s+INTO/i.test(stmt)) {
      assert.match(
        stmt,
        /ON CONFLICT \(id\) DO NOTHING/i,
        `非冪等 INSERT: ${stmt.slice(0, 60)}`,
      );
    }
  }
});

test("無破壞性操作（不得 DROP COLUMN / DROP TABLE / TRUNCATE）", () => {
  // 以「去註解」後的 SQL 檢查，避免說明性註解文字誤觸。
  const code = statements(readSql()).join(";\n");
  assert.ok(!/DROP\s+COLUMN/i.test(code), "不應 DROP COLUMN");
  assert.ok(!/DROP\s+TABLE/i.test(code), "不應 DROP TABLE");
  assert.ok(!/TRUNCATE/i.test(code), "不應 TRUNCATE");
});

test("ALTER COLUMN 僅限 id 型別放寬（不動其他欄位、不改既有資料欄）", () => {
  for (const stmt of statements(readSql())) {
    if (/ALTER\s+COLUMN/i.test(stmt)) {
      assert.match(
        stmt,
        /ALTER COLUMN id (DROP DEFAULT|TYPE TEXT)/i,
        `只應動 id 欄: ${stmt.slice(0, 80)}`,
      );
    }
  }
});

test("種子 15 筆商品 id 齊全", () => {
  const sql = readSql();
  for (const id of SEED_IDS) {
    assert.ok(sql.includes(`'${id}'`), `缺少種子 id: ${id}`);
  }
  // 確認剛好 15 筆 VALUES（以 seed- 前綴計數）。
  const matches = sql.match(/'seed-[a-z-]+'/g) || [];
  const unique = new Set(matches);
  assert.equal(unique.size, 15, "應有 15 筆唯一種子 id");
});

test("種子 image_url 一律空字串、status active", () => {
  const sql = readSql();
  // 每筆 VALUES 都帶 'active'；不應出現外部圖片網址。
  assert.ok(!/https?:\/\//i.test(sql), "種子不應含外部圖片 URL");
  assert.match(sql, /'active'/);
});
