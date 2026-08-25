// CR-0042：caregiver_web 身分模式 / 角色 header / 401-403 / 空狀態 靜態回歸測試。
//
// caregiver_web 為原生 JS（依賴 document/window），無 DOM 測試環境；
// 比照本資料夾其他測試以「來源靜態檢查」確保：
//   - super_admin / caregiver / none 三種身分語意清楚
//   - 統一 header helper 依模式帶正確 token（caregiver token 與 admin token 分開）
//   - 401 顯示登入失效並停止重複請求、403 顯示權限不足
//   - caregiver 無授權住民 → 友善空狀態
//   - caregiver 不顯示 super_admin-only 入口（或顯示權限不足）
//   - 不在 console / log 顯示完整 token
//
// 執行：node --test caregiver_web/auth_mode.test.js

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const appJs = fs.readFileSync(path.join(__dirname, "app.js"), "utf8");
const indexHtml = fs.readFileSync(path.join(__dirname, "index.html"), "utf8");

test("身分狀態清楚區分 super_admin / caregiver / none", () => {
  assert.ok(appJs.includes("authState"), "應有 authState 身分狀態");
  assert.ok(appJs.includes("authMode"), "狀態應含 authMode");
  for (const mode of ['"super_admin"', '"caregiver"', '"none"']) {
    assert.ok(appJs.includes(mode), `應出現身分模式 ${mode}`);
  }
  assert.ok(appJs.includes("function loadAuthState"), "應有 loadAuthState 還原身分");
});

test("caregiver token 與 super_admin token 分開儲存（不同 localStorage key）", () => {
  const adminKey = appJs.match(/var\s+ADMIN_TOKEN_KEY\s*=\s*"([^"]+)"/);
  const caregiverKey = appJs.match(/var\s+CAREGIVER_TOKEN_KEY\s*=\s*"([^"]+)"/);
  assert.ok(adminKey, "應定義 ADMIN_TOKEN_KEY");
  assert.ok(caregiverKey, "應定義 CAREGIVER_TOKEN_KEY");
  assert.notEqual(
    adminKey[1],
    caregiverKey[1],
    "caregiver token 與 admin token 不可使用同一個 key"
  );
  assert.ok(appJs.includes("function getCaregiverToken"), "應有 getCaregiverToken");
});

test("統一 header helper 依 authMode 帶正確 token", () => {
  assert.ok(appJs.includes("function getActiveToken"), "應有 getActiveToken");
  assert.ok(appJs.includes("function authHeaders"), "應有統一 authHeaders");
  assert.ok(appJs.includes("function authJsonHeaders"), "應有 authJsonHeaders");
  // getActiveToken：super_admin → admin token；caregiver → caregiver token。
  const idx = appJs.indexOf("function getActiveToken");
  const body = appJs.slice(idx, idx + 260);
  assert.ok(body.includes("getAdminToken"), "super_admin 模式應帶 admin token");
  assert.ok(body.includes("getCaregiverToken"), "caregiver 模式應帶 caregiver token");
  // authHeaders 用 getActiveToken（而非寫死 admin token）。
  const hIdx = appJs.indexOf("function authHeaders");
  assert.ok(
    appJs.slice(hIdx, hIdx + 160).includes("getActiveToken"),
    "authHeaders 應透過 getActiveToken 產生 header"
  );
});

test("caregiver login 不把 token 寫進 admin token 欄位", () => {
  const idx = appJs.indexOf("function applyLogin");
  assert.ok(idx >= 0, "應有 applyLogin");
  const body = appJs.slice(idx, idx + 400);
  // caregiver 分支必須寫入 CAREGIVER_TOKEN_KEY。
  assert.ok(
    body.includes("CAREGIVER_TOKEN_KEY, token"),
    "caregiver token 應存入 CAREGIVER_TOKEN_KEY"
  );
  // caregiver 分支不可把 token 寫入 ADMIN_TOKEN_KEY：
  // 確認 setItem(ADMIN_TOKEN_KEY 只出現在 super_admin 分支之前。
  const superSet = body.indexOf("ADMIN_TOKEN_KEY, token");
  const caregiverSet = body.indexOf("CAREGIVER_TOKEN_KEY, token");
  assert.ok(superSet >= 0 && caregiverSet >= 0, "兩種模式各自存入對應 key");
  assert.ok(superSet < caregiverSet, "ADMIN 與 CAREGIVER token 分屬不同分支");
});

test("受保護 API 有「無 token / session 失效」守門（不狂打）", () => {
  assert.ok(appJs.includes("function ensureCanFetch"), "應有 ensureCanFetch 守門");
  assert.ok(appJs.includes("function hasActiveToken"), "應有 hasActiveToken");
  assert.ok(appJs.includes("sessionInvalid"), "401 後應有 sessionInvalid 旗標");
  // loadAlerts 應透過 authHeaders + 守門。
  const idx = appJs.indexOf("function loadAlerts");
  const body = appJs.slice(idx, idx + 900);
  assert.ok(body.includes("ensureCanFetch"), "loadAlerts 應先守門");
  assert.ok(body.includes("authHeaders()"), "loadAlerts 應用統一 authHeaders");
});

test("401 顯示登入失效並停止重複請求", () => {
  assert.ok(
    appJs.includes("登入已失效，請重新登入"),
    "401 應顯示『登入已失效，請重新登入』"
  );
  const idx = appJs.indexOf("function handleSessionExpired");
  assert.ok(idx >= 0, "應有 handleSessionExpired");
  const body = appJs.slice(idx, idx + 240);
  assert.ok(body.includes("sessionInvalid = true"), "401 應設 sessionInvalid=true 停止後續請求");
});

test("403 顯示權限不足（不清 token）", () => {
  assert.ok(
    appJs.includes("目前帳號沒有權限查看此資料"),
    "403 應顯示『目前帳號沒有權限查看此資料』"
  );
  // 403 分支不應呼叫 logout / removeItem(token)。
  assert.ok(appJs.includes('throw new Error("forbidden")'), "應辨識 403 forbidden");
  const forbiddenHandling = appJs
    .split("\n")
    .filter((l) => l.includes("forbidden"))
    .join("\n");
  assert.ok(
    !/forbidden[\s\S]{0,80}removeItem/.test(forbiddenHandling),
    "403 不應清除 token"
  );
});

test("caregiver 無授權住民顯示友善空狀態", () => {
  assert.ok(
    appJs.includes("目前尚未被指派可查看的住民。請聯絡管理者確認權限設定。"),
    "caregiver 空狀態文案應齊全"
  );
  // 不以假資料 / 全部資料填補：空狀態走 isCaregiverMode 判斷。
  assert.ok(appJs.includes("EMPTY_CAREGIVER_MSG"), "應有空狀態常數");
  assert.ok(appJs.includes("isCaregiverMode"), "應依 caregiver 模式顯示空狀態");
});

test("caregiver 不顯示 super_admin-only 入口 / 嘗試讀取顯權限不足", () => {
  assert.ok(appJs.includes("function applyAuthModeUi"), "應有 applyAuthModeUi");
  const idx = appJs.indexOf("function applyAuthModeUi");
  const body = appJs.slice(idx, idx + 400);
  // caregiver 模式隱藏使用者 / 商品 / 訂單分頁。
  assert.ok(body.includes("tabUsers"), "應切換使用者管理分頁可見性");
  assert.ok(body.includes("tabProducts"), "應切換商品管理分頁可見性");
  assert.ok(body.includes("tabOrders"), "應切換訂單管理分頁可見性");
  assert.ok(body.includes("caregiver"), "依 caregiver 模式隱藏 super_admin-only 入口");
  // loadUsers / loadOrders 在 caregiver 模式顯示權限不足、不打 API。
  const usersIdx = appJs.indexOf("function loadUsers");
  assert.ok(
    appJs.slice(usersIdx, usersIdx + 260).includes("isCaregiverMode()"),
    "loadUsers 應對 caregiver 顯示權限不足"
  );
  const ordersIdx = appJs.indexOf("function loadOrders");
  assert.ok(
    appJs.slice(ordersIdx, ordersIdx + 260).includes("isCaregiverMode()"),
    "loadOrders 應對 caregiver 顯示權限不足"
  );
});

test("super_admin-only overview 在 caregiver 模式不打 API（避免 403 洗版）", () => {
  const idx = appJs.indexOf("function loadHealthOverview");
  assert.ok(idx >= 0, "應有 loadHealthOverview");
  const body = appJs.slice(idx, idx + 320);
  assert.ok(body.includes("isCaregiverMode()"), "caregiver 模式應跳過 overview fetch");
});

test("不在 console / log 顯示完整 token", () => {
  assert.ok(!/console\.\w+\([^)]*[tT]oken/.test(appJs), "不可 console 印出 token");
  // 不應有硬編碼的 Bearer token 字面值。
  assert.ok(
    !/Bearer\s+[A-Za-z0-9._\-]{12,}/.test(appJs),
    "不可硬編碼 Bearer token"
  );
});

test("index.html 提供身分 / 登入 UI 與兩種模式入口", () => {
  assert.ok(indexHtml.includes('id="auth-bar"'), "應有身分登入列");
  assert.ok(indexHtml.includes('id="auth-mode-caregiver"'), "應有照護人員模式選項");
  assert.ok(indexHtml.includes('id="auth-mode-super"'), "應有管理者模式選項");
  assert.ok(indexHtml.includes('id="auth-token-input"'), "應有登入權杖輸入框");
  assert.ok(indexHtml.includes('id="firebase-login-panel"'), "應有 Firebase 登入區");
  assert.ok(indexHtml.includes('id="firebase-email"'), "應有照護人員 Email 欄位");
  assert.ok(indexHtml.includes('id="firebase-secret"'), "應有照護人員密碼欄位");
  assert.ok(indexHtml.includes('id="firebase-email-login"'), "應有 Email 登入按鈕");
  assert.ok(indexHtml.includes('id="firebase-google-login"'), "應有 Google 登入按鈕");
  assert.ok(indexHtml.includes('id="auth-login"'), "應有登入按鈕");
  assert.ok(indexHtml.includes('id="auth-logout"'), "應有登出按鈕");
  assert.ok(indexHtml.includes("照護人員"), "UI 應標示照護人員身分");
  assert.ok(indexHtml.includes("管理者"), "UI 應標示管理者身分");
  // 登入權杖輸入框不可有預設值（不 hardcode token）。
  assert.ok(
    !/id="auth-token-input"[^>]*value="[^"]+"/.test(indexHtml),
    "登入權杖輸入框不可有預設 token"
  );
});

test("super_admin token 風險與 caregiver 取得方式有清楚說明", () => {
  assert.ok(
    appJs.includes("請勿提供給一般照護人員"),
    "應說明 super_admin token 不可給一般照護人員"
  );
  assert.ok(
    appJs.includes("Email 或 Google 登入") && appJs.includes("ID Token"),
    "應說明 caregiver 以 Firebase 登入取得 ID Token"
  );
});

test("CR-0103：caregiver_web 內建 Firebase Email / Google login 且未設定時保留備援", () => {
  assert.ok(appJs.includes("FIREBASE_APP_MODULE_URL"), "應以 Firebase Web SDK 初始化");
  assert.ok(appJs.includes("firebase-auth.js"), "應載入 Firebase Auth 模組");
  assert.ok(appJs.includes("function hasFirebaseWebConfig"), "應檢查 Firebase Web config");
  assert.ok(appJs.includes("signInWithEmailAndPassword"), "應支援 Email 登入");
  assert.ok(appJs.includes("GoogleAuthProvider"), "應支援 Google 登入");
  assert.ok(appJs.includes("getIdToken"), "登入成功後應取得 ID Token");
  assert.ok(appJs.includes("applyFirebaseCaregiverLogin"), "應套用 caregiver scoped login");
  assert.ok(appJs.includes("signOutFirebaseCaregiver"), "登出應同步 Firebase signOut");
  assert.ok(
    appJs.includes("尚未設定 Firebase Web 登入，請暫用登入權杖備援。"),
    "未設定 Firebase 時應友善保留備援"
  );
});

test("既有 super_admin dashboard 載入函式未被破壞", () => {
  for (const fn of [
    "function loadAlerts",
    "function loadHealthOverview",
    "function loadElderList",
    "function loadDailyTasks",
    "function loadUsers",
    "function loadOrders",
  ]) {
    assert.ok(appJs.includes(fn), `仍應保留 ${fn}`);
  }
  // 向後相容：舊版只有 super_admin 共享 token、無 authMode → 仍視為 super_admin。
  const idx = appJs.indexOf("function loadAuthState");
  const body = appJs.slice(idx, idx + 400);
  assert.ok(
    body.includes("getAdminToken()") && body.includes('"super_admin"'),
    "有 admin token 但無 authMode 時應回退 super_admin（不破壞既有體驗）"
  );
});
