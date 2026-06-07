// caregiver_web 部署設定範本（API base URL）。
//
// 用途：讓「同一份靜態網頁」可在不同環境指向不同的後端 API，
//       不需要改 app.js，也不會把 localhost 硬編成正式預設。
//
// 使用方式（二擇一）：
//   A. 直接編輯 index.html 內的 window.APP_CONFIG（最簡單）。
//   B. 複製本檔為 config.js，填入正式位址，並在 index.html 的
//      <script src="./app.js..."></script> 之前加入：
//        <script src="./config.js"></script>
//      部署時只覆蓋 config.js 即可切換環境（config.js 不應進版控）。
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

window.APP_CONFIG = {
  // 正式部署：改成後端正式 API 位址，例如 "https://api.your-domain.com/api"。
  // 留 null：使用同源相對路徑 "/api"。
  apiBaseUrl: null,
};
