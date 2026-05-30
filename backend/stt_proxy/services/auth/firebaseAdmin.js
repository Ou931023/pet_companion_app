// Firebase Admin 包裝（CR-0006 Batch 1）。
//
// 設計原則：
// - 套件缺失（未 npm install firebase-admin）或環境變數未設定時，一律「安靜 fallback」，
//   回 isConfigured()=false，由 sessionService 走 demo mock，不得 throw 讓 server 啟動失敗。
// - 只檢查環境變數「是否存在」來判斷是否 configured，絕不印出值、不讀 .env 檔內容。
//
// 需要的環境變數（見 PROJECT_ARCHITECTURE.md §7 Firebase 區塊）：
// - 服務帳戶（擇一）：
//     GOOGLE_APPLICATION_CREDENTIALS（service account JSON 路徑）
//   或拆欄位：FIREBASE_PROJECT_ID + FIREBASE_CLIENT_EMAIL + FIREBASE_PRIVATE_KEY
// - 驗證 token audience：FIREBASE_PROJECT_ID

let cachedAdmin = null; // firebase-admin module（成功 require 後快取）
let cachedApp = null; // 初始化後的 app（避免重複 initializeApp）
let initAttempted = false;

// 是否設定了 Firebase 憑證：
// - 有 GOOGLE_APPLICATION_CREDENTIALS，或
// - 同時有 FIREBASE_PROJECT_ID + FIREBASE_CLIENT_EMAIL + FIREBASE_PRIVATE_KEY
// 只看變數是否存在/非空，不讀內容、不印值。
function hasCredentialsEnv() {
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) return true;
  return Boolean(
    process.env.FIREBASE_PROJECT_ID &&
      process.env.FIREBASE_CLIENT_EMAIL &&
      process.env.FIREBASE_PRIVATE_KEY,
  );
}

// 嘗試動態載入 firebase-admin。缺套件時回 null（不 throw）。
function loadAdmin() {
  if (cachedAdmin) return cachedAdmin;
  try {
    // eslint-disable-next-line global-require
    cachedAdmin = require("firebase-admin");
    return cachedAdmin;
  } catch (_) {
    // 套件未安裝：安靜 fallback。
    return null;
  }
}

// 取得（或初始化）firebase-admin app。任何失敗都回 null，不 throw。
function getApp() {
  if (cachedApp) return cachedApp;
  if (initAttempted) return cachedApp; // 已試過且失敗，不重試
  initAttempted = true;

  const admin = loadAdmin();
  if (!admin) return null;
  if (!hasCredentialsEnv()) return null;

  try {
    // 已有預設 app 就重用，否則用 applicationDefault 或拆欄位 cert 初始化。
    if (admin.apps && admin.apps.length > 0) {
      cachedApp = admin.app();
      return cachedApp;
    }

    let credential;
    if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
      credential = admin.credential.applicationDefault();
    } else {
      credential = admin.credential.cert({
        projectId: process.env.FIREBASE_PROJECT_ID,
        clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
        // 私鑰常以 \n escape 形式存於 env，還原為實際換行。
        privateKey: String(process.env.FIREBASE_PRIVATE_KEY).replace(/\\n/g, "\n"),
      });
    }

    cachedApp = admin.initializeApp({ credential });
    return cachedApp;
  } catch (error) {
    // 初始化失敗（憑證格式錯等）：安靜 fallback 到 mock，不擋 server 啟動。
    console.error(
      "[firebase-admin] init failed, falling back to mock auth",
      error?.message || error,
    );
    cachedApp = null;
    return null;
  }
}

// 是否可用正式 Firebase 驗證：套件存在、env 已設定、且 app 能初始化。
function isConfigured() {
  if (!hasCredentialsEnv()) return false;
  return getApp() != null;
}

// 驗證 Firebase ID Token。
// - configured 時：用 firebase-admin 驗，回 decoded token；失敗回 null（由 sessionService 轉 401）。
// - 未 configured / 套件缺失：回 null（sessionService 改走 mock）。
async function verifyIdToken(idToken) {
  const app = getApp();
  const admin = cachedAdmin;
  if (!app || !admin) return null;
  if (!idToken || typeof idToken !== "string") return null;
  try {
    return await admin.auth(app).verifyIdToken(idToken);
  } catch (_) {
    // token 無效 / 過期：回 null，不外洩細節。
    return null;
  }
}

// 測試用：重置內部快取（讓單測可切換 env / 注入 stub 後重新判斷）。
function _resetForTest() {
  cachedAdmin = null;
  cachedApp = null;
  initAttempted = false;
}

module.exports = {
  isConfigured,
  verifyIdToken,
  hasCredentialsEnv,
  _resetForTest,
};
