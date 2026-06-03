// CR-0029：管理者端使用者帳戶清單服務。
//
// 資料來源「只」來自 PostgreSQL（不使用 JSON fallback、不 hardcode demo users）。
// 只 SELECT 安全欄位，並在回傳前遮蔽 Email；絕不回傳 password_hash / provider_user_id /
// 任何 token / verification code。回傳格式見 docs/ADMIN_USER_MANAGEMENT.md。

const postgres = require("../../db/postgres");

// 只查安全欄位（白名單）。即使資料表存在敏感欄位，也不會被選出。
const SELECT_SAFE_USERS_SQL = `
  SELECT
    id,
    display_name,
    email,
    auth_provider,
    email_verified,
    created_at,
    last_login_at
  FROM users
  ORDER BY created_at DESC
  LIMIT 100
`;

// Email 遮蔽：wang@gmail.com → wa***@gmail.com。
// 規則：保留 local part 前兩碼（不足兩碼則保留全部），其餘以 *** 取代，domain 原樣。
function maskEmail(email) {
  const raw = (email == null ? "" : email).toString().trim();
  if (!raw || !raw.includes("@")) return "";
  const atIndex = raw.indexOf("@");
  const name = raw.slice(0, atIndex);
  const domain = raw.slice(atIndex + 1);
  if (!domain) return "";
  const visible = name.slice(0, 2);
  return `${visible}***@${domain}`;
}

// 顯示名稱：優先用真實 display_name；email 帳號常無名字，退而用 email 的 @ 前綴當預設名
// （例如 wang@gmail.com → wang），避免後台姓名欄一排空白。皆無則回 null（前端顯示「—」）。
function deriveDisplayName(row = {}) {
  const name = (row.display_name == null ? "" : String(row.display_name)).trim();
  if (name) return name;
  const email = (row.email == null ? "" : String(row.email)).trim();
  const atIndex = email.indexOf("@");
  if (atIndex > 0) {
    const local = email.slice(0, atIndex).trim();
    if (local) return local;
  }
  return null;
}

// 將 DB row 轉成「只含安全欄位」的對外格式（第二層保護：即便 SQL 誤選敏感欄位也不外漏）。
function toSafeUser(row = {}) {
  return {
    id: row.id,
    displayName: deriveDisplayName(row),
    emailMasked: maskEmail(row.email),
    authProvider: row.auth_provider ?? null,
    emailVerified: Boolean(row.email_verified),
    createdAt: row.created_at ?? null,
    lastLoginAt: row.last_login_at ?? null,
  };
}

// 查詢使用者清單。queryFn 可注入（測試用），預設走 postgres.query（PG-only）。
// PG 未設定 / 查詢失敗時會 throw，由呼叫端回傳安全錯誤（不做 JSON fallback）。
async function listSafeUsers({ queryFn } = {}) {
  const run = queryFn || postgres.query;
  const result = await run(SELECT_SAFE_USERS_SQL);
  const rows = (result && result.rows) || [];
  return rows.map(toSafeUser);
}

module.exports = {
  listSafeUsers,
  maskEmail,
  deriveDisplayName,
  toSafeUser,
  SELECT_SAFE_USERS_SQL,
};
