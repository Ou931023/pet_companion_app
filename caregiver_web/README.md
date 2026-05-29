# caregiver_web — 長照照護管理後台 (MVP)

純靜態網頁（HTML / CSS / vanilla JS，無建置工具），讓長照人員或家屬查看 AI 陪伴寵物偵測到、後端已保存的 Care Alert。

## 啟動方式

1. 先啟動後端（提供 Care Alert API）：
   ```bash
   cd backend/stt_proxy
   npm run dev
   ```
   後端會在 `http://0.0.0.0:3001` 監聽，API 前綴為 `/api`。

2. 用任意靜態伺服器服務本資料夾（建議 port 5501，避開商城用的 5500）：
   ```bash
   cd caregiver_web
   python3 -m http.server 5501
   ```
   然後瀏覽器開 `http://127.0.0.1:5501`。

## API base URL 設定

- 預設為 `http://127.0.0.1:3001/api`。
- 頁面上方可輸入並「儲存位址」，會存進瀏覽器 `localStorage`（key：`caregiver_api_base`）。
- 手機或其他電腦連線時，改成 `http://<Mac區網IP>:3001/api`（例如 `http://172.20.10.3:3001/api`）。

## 功能

- 讀取 `GET /api/care-alerts`，支援 `riskLevel` / `status` / `limit` 篩選。
- 點擊單筆讀取 `GET /api/care-alerts/:id` 顯示詳情。
- 統計概覽：目前筆數、緊急數、待處理數。
- 載入中 / 無資料 / 連線錯誤皆有白話提示，無任何假資料。

## 目前限制（MVP）

- 無登入系統。
- 無角色權限。
- 無「標記已處理」（不呼叫 PATCH，狀態為唯讀）。
- 只讀取 Care Alert，不修改後端資料。
