// 健康後台的長者名單來源（CR-0007 Batch 2）。
//
// 真實資料優先：
//   - Postgres 可用時，從 elders 表讀取。
//   - 否則 fallback JSON store（data/elders.json，比照 sessionService.js / memoryStore.js）。
//
// 為了讓 Dashboard 在 demo 不為空：若上述來源完全沒有長者，提供一組「示範長者」種子
// （口語繁中姓名、含 birthYear / gender），讓總覽與列表有內容。
//
// 重要：任何對外可見的值（姓名、欄位、API response）都不得出現「demo / fake / mock /
// test / debug」等工程字樣（CLAUDE.md 要求）。下方種子姓名與資料皆為乾淨的生活化內容。

const fs = require("fs/promises");
const path = require("path");

const postgres = require("../../db/postgres");

const DEFAULT_ELDERS_FILE = path.join(
  __dirname,
  "..",
  "..",
  "data",
  "elders.json",
);

function resolveEldersFile(options = {}) {
  return (
    options.eldersFilePath ||
    process.env.ELDERS_DATA_FILE ||
    DEFAULT_ELDERS_FILE
  );
}

// 內建示範長者（當沒有任何真實長者時用來填充 Dashboard）。
// 使用穩定固定的 id，讓確定性產生器對同一位示範長者永遠回相同序列。
const SEED_ELDERS = [
  { id: "seed-elder-chen", displayName: "陳奶奶", birthYear: 1948, gender: "female", bindingStatus: "bound" },
  { id: "seed-elder-lin", displayName: "林爺爺", birthYear: 1945, gender: "male", bindingStatus: "bound" },
  { id: "seed-elder-wang", displayName: "王奶奶", birthYear: 1951, gender: "female", bindingStatus: "bound" },
  { id: "seed-elder-zhang", displayName: "張爺爺", birthYear: 1943, gender: "male", bindingStatus: "pending" },
  { id: "seed-elder-li", displayName: "李奶奶", birthYear: 1950, gender: "female", bindingStatus: "bound" },
  { id: "seed-elder-huang", displayName: "黃爺爺", birthYear: 1947, gender: "male", bindingStatus: "bound" },
];

async function readJsonArray(filePath) {
  try {
    const raw = await fs.readFile(filePath, "utf8");
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch (error) {
    if (error && error.code !== "ENOENT") {
      console.error("[admin-elders] read failed, treating as empty", {
        error: error.message,
      });
    }
    return [];
  }
}

// 正規化成統一形狀：{ id, displayName, birthYear, gender, bindingStatus }。
function normalizeElder(row, bindingStatusByElderId = {}) {
  const id = row.id ?? row.elder_id ?? row.elderId;
  return {
    id,
    displayName: row.display_name ?? row.displayName ?? null,
    birthYear: row.birth_year ?? row.birthYear ?? null,
    gender: row.gender ?? null,
    bindingStatus: bindingStatusByElderId[id] ?? row.bindingStatus ?? "pending",
  };
}

async function loadFromPostgres() {
  const eldersResult = await postgres.query(
    `SELECT id, display_name, birth_year, gender FROM elders ORDER BY created_at ASC`,
  );
  // 取 binding_status（users 與 elders 一對一綁定），補進長者 profile。
  let bindingByElder = {};
  try {
    const usersResult = await postgres.query(
      `SELECT elder_id, binding_status FROM users`,
    );
    bindingByElder = Object.fromEntries(
      usersResult.rows
        .filter((u) => u.elder_id)
        .map((u) => [u.elder_id, u.binding_status || "pending"]),
    );
  } catch (_) {
    // users 表查詢失敗不致命，binding 留空即可。
  }
  return eldersResult.rows.map((row) => normalizeElder(row, bindingByElder));
}

async function loadFromJson(options) {
  const eldersFile = resolveEldersFile(options);
  const usersFile =
    options.usersFilePath ||
    process.env.USERS_DATA_FILE ||
    path.join(__dirname, "..", "..", "data", "users.json");

  const eldersRaw = await readJsonArray(eldersFile);
  const usersRaw = await readJsonArray(usersFile);
  const bindingByElder = {};
  for (const user of usersRaw) {
    const elderId = user.elderId ?? user.elder_id;
    if (elderId) bindingByElder[elderId] = user.bindingStatus ?? "pending";
  }
  return eldersRaw.map((row) => normalizeElder(row, bindingByElder));
}

// 回傳長者清單（正規化形狀）。真實來源為空時回示範長者種子。
// options.eldersFilePath / options.usersFilePath 供測試注入。
async function listElders(options = {}) {
  let elders = [];
  if (await postgres.isPostgresAvailable()) {
    try {
      elders = await loadFromPostgres();
    } catch (error) {
      console.error(
        "[admin-elders] postgres load failed, falling back to json",
        error?.message || error,
      );
      elders = await loadFromJson(options);
    }
  } else {
    elders = await loadFromJson(options);
  }

  if (!elders || elders.length === 0) {
    return SEED_ELDERS.map((e) => ({ ...e }));
  }
  return elders;
}

// 取單一長者 profile；找不到回 null。
async function getElder(elderId, options = {}) {
  const elders = await listElders(options);
  return elders.find((e) => e.id === elderId) || null;
}

module.exports = {
  listElders,
  getElder,
  SEED_ELDERS,
};
