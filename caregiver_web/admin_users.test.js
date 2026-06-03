// CR-0029：caregiver_web 使用者管理顯示回歸測試（靜態來源檢查）。
//
// caregiver_web 為原生 JS（依賴 document/window），無 DOM 測試環境；
// 以「來源靜態檢查」確保使用者管理入口、API 呼叫、狀態文字與安全顯示不被誤刪。
//
// 執行：node --test caregiver_web/admin_users.test.js

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const appJs = fs.readFileSync(path.join(__dirname, "app.js"), "utf8");
const indexHtml = fs.readFileSync(path.join(__dirname, "index.html"), "utf8");

test("使用者管理入口與容器存在", () => {
  assert.ok(indexHtml.includes("使用者管理"), "應有『使用者管理』分頁");
  assert.ok(indexHtml.includes('id="tab-users"'), "應有 #tab-users 分頁鈕");
  assert.ok(indexHtml.includes('id="view-users"'), "應有 #view-users 區塊");
  assert.ok(indexHtml.includes('id="users-table-wrap"'), "應有使用者表格容器");
  assert.ok(indexHtml.includes('id="users-status"'), "應有狀態訊息區");
  assert.ok(appJs.includes('showView("users")'), "tab 切換應呼叫 showView('users')");
});

test("呼叫 Admin Users API 並帶 Bearer 權杖", () => {
  assert.ok(appJs.includes('adminUrl("/users")'), "應呼叫 /admin/users");
  assert.ok(appJs.includes("function loadUsers"), "應有 loadUsers");
  assert.ok(appJs.includes("Authorization"), "應帶 Authorization header");
  assert.ok(appJs.includes("Bearer "), "應使用 Bearer token");
  assert.ok(appJs.includes("ADMIN_TOKEN_KEY"), "權杖存 localStorage（不寫死）");
});

test("token 不寫死在前端原始碼", () => {
  // 不可出現硬編碼的 Bearer token 字面值（應為 "Bearer " + token 動態組合）。
  assert.ok(
    !/Bearer\s+[A-Za-z0-9._\-]{12,}/.test(appJs),
    "不可硬編碼 Bearer token"
  );
  // admin-token 輸入框不可有預設 value。
  assert.ok(
    !/id="admin-token"[^>]*value="[^"]+"/.test(indexHtml),
    "admin-token 輸入框不可有預設 token 值"
  );
});

test("登入方式與驗證狀態為中文標籤", () => {
  for (const label of ["Google", "Apple", "Email"]) {
    assert.ok(appJs.includes(label), `登入方式應含 ${label}`);
  }
  assert.ok(appJs.includes("已驗證"), "應有『已驗證』");
  assert.ok(appJs.includes("未驗證"), "應有『未驗證』");
  assert.ok(appJs.includes("尚未登入或無紀錄"), "lastLoginAt 為 null 應有白話說明");
});

test("載入中 / 失敗 / 空狀態文字齊全", () => {
  assert.ok(appJs.includes("使用者資料載入中"), "應有載入中狀態");
  assert.ok(appJs.includes("使用者資料載入失敗"), "應有失敗狀態");
  assert.ok(appJs.includes("目前尚無使用者帳戶資料"), "應有空狀態");
});

test("顯示遮蔽後 Email，且不引用任何敏感欄位", () => {
  assert.ok(appJs.includes("emailMasked"), "應顯示後端遮蔽後的 emailMasked");
  const banned = [
    "password_hash",
    "passwordHash",
    "provider_user_id",
    "providerUserId",
    "access_token",
    "refresh_token",
    "id_token",
    "verification_token",
    "reset_password_token",
    "session_token",
    "otp",
  ];
  for (const key of banned) {
    assert.ok(!appJs.includes(key), `前端不可引用敏感欄位：${key}`);
  }
});

test("非醫療/非假資料提示：資料來自 PostgreSQL、Email 遮蔽", () => {
  assert.ok(indexHtml.includes("PostgreSQL"), "應說明資料來自 PostgreSQL");
  assert.ok(
    indexHtml.includes("遮蔽"),
    "應說明 Email 遮蔽顯示"
  );
});
