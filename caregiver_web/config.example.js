// caregiver_web 部署設定範本（API base URL）。
//
// 用途：讓「同一份靜態網頁」可在不同環境指向不同的後端 API，
//       不需要改 app.js，也不會把 localhost 硬編成正式預設。
//
// 使用方式（二擇一）：
//   A. 直接編輯 index.html 內的 window.APP_CONFIG（最簡單）。
//   B. 複製本檔為 config.js，填入正式位址。index.html 已載入 ./config.js；
//      部署時只覆蓋 config.js 即可切換環境（config.js 不應進版控）。
//   C. Render / Static Site 部署時執行：
//      node caregiver_web/build_config_from_env.js
//      由 CAREGIVER_WEB_* 環境變數產生 config.js。
//
// 解析順序（app.js getApiBase）：
//   1. 使用者在頁面「連線設定」手動輸入（localStorage，dev / 區網用）。
//   2. window.APP_CONFIG.apiBaseUrl（本檔 / index.html 注入）。
//   3. 同源相對路徑 "/api"（caregiver_web 與後端同網域 / 反向代理時適用）。
//
// 注意：
//   - 正式環境請填真正的後端網域，例如 "https://api.your-domain.com/api"。
//   - 留 null 代表使用同源相對路徑 "/api"。
//   - 請勿把 localhost / 127.0.0.1 當成正式預設；本機開發位址只在 dev 設定。
//
// 身分 / 登入（CR-0103，見 docs/CAREGIVER_WEB_AUTH.md）：
//   - 本檔「不放任何 token」。super_admin（ADMIN_API_TOKEN）仍在頁面頂部「管理者」
//     模式手動輸入，且不可提供給一般照護人員。
//   - 照護人員正式登入請設定 firebase web config。頁面會用 Firebase Email / Google
//     登入取得 ID Token，再以 caregiver 模式呼叫後端，後端自動套住民範圍。
//   - Firebase web config 的 apiKey 是前端識別設定，不是後端 service account 私鑰；
//     請勿把 Firebase Admin private key / service account JSON 放在這裡。

window.APP_CONFIG = {
  // 正式部署：改成後端正式 API 位址，例如 "https://api.your-domain.com/api"。
  // 留 null：使用同源相對路徑 "/api"。
  apiBaseUrl: null,

  // Firebase Web Auth 設定。正式部署時請填 Firebase Console 的 Web app config。
  // 未設定或留 null 時，頁面會停用 Firebase 登入按鈕，保留手動權杖 fallback 給管理者協助測試。
  firebase: {
    apiKey: null,
    authDomain: null,
    projectId: null,
    appId: null,
  },

  // 功能旗標（CR-0056）：控制管理端分頁是否顯示。
  //
  // 與長者端一致，marketplace（商品 / 訂單管理）與 dailyCareTasks（今日任務）
  // 能力保留但「正式版預設隱藏入口」，避免照護人員看到尚未正式啟用的分頁。
  // 後端 admin API 行為不受此影響（僅前端隱藏分頁；防禦縱深，非權限控管）。
  //
  // 預設關（false）= 隱藏分頁；開發 / 內部驗證需要時，於部署的 config.js
  // 將對應旗標改成 true 即可顯示。未提供時一律視為關閉。
  featureFlags: {
    marketplace: false,
    dailyCareTasks: false,
  },
};
