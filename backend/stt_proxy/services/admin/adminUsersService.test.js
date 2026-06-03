// CR-0029：adminUsersService 單元測試。
// 驗證 Email 遮蔽、只回安全欄位、PG-only 查詢（注入 queryFn，不連真 DB）、
// SQL 只選白名單欄位且依 created_at DESC LIMIT 100。

const assert = require("node:assert/strict");
const { test } = require("node:test");

const {
  listSafeUsers,
  maskEmail,
  deriveDisplayName,
  toSafeUser,
  SELECT_SAFE_USERS_SQL,
} = require("./adminUsersService");

// 不可出現在 API 回傳的敏感欄位（即使 DB 有）。
const SENSITIVE_KEYS = [
  "password",
  "password_hash",
  "passwordHash",
  "provider_user_id",
  "providerUserId",
  "apple_user_identifier",
  "access_token",
  "refresh_token",
  "id_token",
  "verification_token",
  "verification_token_hash",
  "reset_password_token",
  "reset_token",
  "otp",
  "email_code",
  "session_token",
  "csrf_token",
  "firebase_uid",
  "firebaseUid",
];

test("maskEmail 遮蔽 local part，保留前兩碼與 domain", () => {
  assert.equal(maskEmail("wang@gmail.com"), "wa***@gmail.com");
  assert.equal(maskEmail("a@x.com"), "a***@x.com");
  assert.equal(maskEmail("ab@x.com"), "ab***@x.com");
  assert.equal(maskEmail("abcdef@example.org"), "ab***@example.org");
});

test("maskEmail 對空值 / 非 email 回空字串（不外漏原值）", () => {
  assert.equal(maskEmail(""), "");
  assert.equal(maskEmail(null), "");
  assert.equal(maskEmail(undefined), "");
  assert.equal(maskEmail("not-an-email"), "");
  assert.equal(maskEmail("name@"), "");
});

test("deriveDisplayName：有名字用名字；email 帳號無名字用 @ 前綴；皆無回 null", () => {
  assert.equal(deriveDisplayName({ display_name: "王小明", email: "wang@gmail.com" }), "王小明");
  // email 帳號常無 display_name → 用 @ 前綴當預設名
  assert.equal(deriveDisplayName({ display_name: null, email: "kikigay1109@gmail.com" }), "kikigay1109");
  assert.equal(deriveDisplayName({ display_name: "  ", email: "abc@x.com" }), "abc");
  // 名字與 email 皆無 → null（前端顯示「—」）
  assert.equal(deriveDisplayName({ display_name: null, email: null }), null);
  assert.equal(deriveDisplayName({ display_name: "", email: "" }), null);
});

test("toSafeUser 只輸出安全欄位、遮蔽 email、丟棄敏感欄位", () => {
  const row = {
    id: "uuid-1",
    display_name: "王小明",
    email: "wang@gmail.com",
    auth_provider: "google",
    email_verified: true,
    created_at: "2026-06-01T10:20:00.000Z",
    last_login_at: "2026-06-02T09:30:00.000Z",
    // 以下敏感欄位即使存在也不可外漏
    password_hash: "HASH",
    provider_user_id: "google-123",
    firebase_uid: "fb-xyz",
    access_token: "AT",
    refresh_token: "RT",
  };
  const safe = toSafeUser(row);
  assert.deepEqual(Object.keys(safe).sort(), [
    "authProvider",
    "createdAt",
    "displayName",
    "emailMasked",
    "emailVerified",
    "id",
    "lastLoginAt",
  ]);
  assert.equal(safe.emailMasked, "wa***@gmail.com");
  const blob = JSON.stringify(safe);
  for (const key of SENSITIVE_KEYS) {
    assert.ok(!blob.includes(key), `safe user 不應含敏感鍵：${key}`);
  }
  assert.ok(!blob.includes("wang@gmail.com"), "不應出現原始 email");
  assert.ok(!blob.includes("HASH"), "不應出現 password_hash 值");
  assert.ok(!blob.includes("google-123"), "不應出現 provider_user_id 值");
});

test("listSafeUsers 使用注入的 queryFn（PG-only，可測試）並映射 rows", async () => {
  let calledSql = "";
  const fakeQuery = async (sql) => {
    calledSql = sql;
    return {
      rows: [
        {
          id: "u1",
          display_name: "李阿嬤",
          email: "lee@yahoo.com.tw",
          auth_provider: "email",
          email_verified: false,
          created_at: "2026-06-02T00:00:00.000Z",
          last_login_at: null,
          password_hash: "SECRET",
        },
      ],
    };
  };
  const users = await listSafeUsers({ queryFn: fakeQuery });
  assert.equal(users.length, 1);
  assert.equal(users[0].emailMasked, "le***@yahoo.com.tw");
  assert.equal(users[0].lastLoginAt, null);
  assert.equal(users[0].emailVerified, false);
  assert.ok(!JSON.stringify(users).includes("SECRET"));
});

test("SQL 只選白名單欄位、ORDER BY created_at DESC、LIMIT 100", () => {
  const sql = SELECT_SAFE_USERS_SQL.toLowerCase();
  assert.ok(/order by\s+created_at\s+desc/.test(sql), "應 ORDER BY created_at DESC");
  assert.ok(/limit\s+100/.test(sql), "應 LIMIT 100");
  // 不可在 SQL 中選敏感欄位。
  for (const banned of [
    "password",
    "provider_user_id",
    "firebase_uid",
    "token",
    "otp",
    "email_code",
  ]) {
    assert.ok(!sql.includes(banned), `SQL 不應 SELECT 敏感欄位：${banned}`);
  }
});
