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

API base URL 為可配置，解析順序（擇先非空者）：

1. 使用者在頁面「連線設定」輸入並「儲存位址」（存進瀏覽器 `localStorage`，key：`caregiver_api_base`）。適合本機 / 區網臨時覆寫。
2. 部署注入的 `window.APP_CONFIG.apiBaseUrl`（見下）。
3. 預設同源相對路徑 `/api`（caregiver_web 與後端同網域或經反向代理時直接適用）。**不再硬編 localhost 作為正式預設。**

### 正式部署指定後端位址

二擇一：

- 直接編輯 `index.html` 內的 `window.APP_CONFIG`，例如：
  `window.APP_CONFIG = { apiBaseUrl: "https://api.your-domain.com/api" };`
- 或複製 `config.example.js` 為 `config.js` 填入位址，並在 `index.html` 的
  `app.js` script 之前加入 `<script src="./config.js"></script>`，部署時只覆蓋 `config.js`。

### 本機 / 區網開發

後端另開 port（例如 3001）時，可在頁面「連線設定」輸入 `http://127.0.0.1:3001/api`；
手機或其他電腦連線改成 `http://<Mac區網IP>:3001/api`（例如 `http://172.20.10.3:3001/api`）。
此覆寫只存在本機瀏覽器，不影響正式部署預設。

## 功能

- 讀取 `GET /api/care-alerts`，支援 `riskLevel` / `status` / `limit` 篩選。
- 點擊單筆讀取 `GET /api/care-alerts/:id` 顯示詳情。
- 統計概覽：目前筆數、緊急數、待處理數。
- **標記處理狀態**：在詳情中可將提醒標記為「已查看」或「已處理」，
  會呼叫 `PATCH /api/care-alerts/:id/status`（body：`{"status":"acknowledged"|"resolved"}`），
  成功後即時更新詳情、重新載入列表與統計。狀態為 `resolved` 時不再顯示操作按鈕。
- 載入中 / 無資料 / 連線錯誤 / 狀態更新失敗皆有白話提示，無任何假資料。

## 身分與登入（CR-0042）

頁面頂部「身分與登入」列可選擇身分並貼上對應權杖，詳細機制見
`docs/CAREGIVER_WEB_AUTH.md`。

- **照護人員（caregiver）**：貼上自己的 Firebase ID Token / 機構提供的 caregiver
  session 權杖。登入後只會看到被指派的住民（後端依 `resident_caregiver_links` 過濾），
  且不會看到使用者 / 商品 / 訂單等管理者專用分頁。
- **管理者（super_admin）**：貼上 `ADMIN_API_TOKEN`，可檢視全部住民與所有分頁。
  此為最高權限，**正式環境請勿提供給一般照護人員**。

行為：

- 不同身分使用不同 localStorage key 儲存權杖（caregiver 權杖不會寫進 admin token 欄位）；
  token 不會印到 console。
- `401`：顯示「登入已失效，請重新登入」並停止重複請求。
- `403`：顯示「目前帳號沒有權限查看此資料」（不清除 token）。
- caregiver 無授權住民：顯示「目前尚未被指派可查看的住民。請聯絡管理者確認權限設定。」

> 註：完整 Firebase 一鍵登入（免手動貼 token）為後續 CR；本版先提供清楚標示的
> token 輸入入口。

## 照護人員管理 / 住民授權指派（CR-0044，super_admin-only）

兩個分頁僅在「管理者（super_admin）」身分顯示；caregiver 身分完全看不到入口，
也不會發送這些管理 API。所有 provisioning 請求一律帶 super_admin token
（`adminAuthHeaders()` / `adminJsonHeaders()`），對應後端 CR-0043 的 8 條
`/api/admin/caregivers`、`/api/admin/resident-caregiver-links` 端點。

### 如何進入

以管理者身分登入（在頂部選「管理者」並貼上 `ADMIN_API_TOKEN`），上方分頁列即出現
「照護人員管理」與「住民授權指派」。

### 照護人員管理

- **列表**：顯示名稱、Email（遮蔽）、Firebase 綁定狀態（已綁定 / 待綁定）、狀態
  （啟用中 / 已停用）、建立 / 更新時間。
- **新增照護人員**：填顯示名稱（必填）、Email（必填、需全系統唯一）、Firebase UID（選填）。
  不設定密碼——照護人員一律以自己的 Firebase 帳號登入。Email 重複會顯示白話錯誤。
- **綁定 Firebase UID**：照護人員以 Firebase 登入後取得自己的 UID，由機構轉交後，在該筆
  「編輯」中填入 Firebase UID 完成綁定（即路線 B）。留空 = 待綁定。
- **停用 / 啟用**：停用前提示「停用後，該照護人員將無法查看被指派住民資料。」停用即時生效
  （該帳號讀受保護資料會被後端擋下）。

### 住民授權指派

- **列表**：住民、照護人員、角色（主要照護 / 備援照護 / 唯讀）、狀態（生效中 / 已停用）、
  建立 / 更新時間。
- **新增授權**：住民下拉來自既有住民清單（`/api/admin/elders`）、照護人員下拉來自
  `/api/admin/caregivers`（皆為後端真資料，不用假資料）；角色採後端真值
  **primary / secondary / viewer**。重複的有效授權會顯示白話錯誤。
  任一來源為空時清楚提示需先建立資料。
- **改角色**：只改授權角色（對應後端 `PATCH`，僅支援 role）。
- **停用授權**：提示「停用後，該照護人員將不能再查看此住民的資料。」停用後該照護人員
  立即看不到此住民的提醒與分析。
- **重新啟用**：後端無「重新啟用既有關聯」端點，UI 以相同住民 + 照護人員 + 角色另建一筆
  有效授權達成（呼叫既有建立端點，不改後端）。

### 正式環境提醒

`ADMIN_API_TOKEN` 是最高權限共享密鑰，**正式環境不可發給一般照護人員**。一般照護人員
只應以自己的 Firebase 帳號登入（caregiver 身分），其可見範圍由授權指派決定。

## 狀態說明

- `new`：新提醒（尚未查看）
- `acknowledged`：已查看 / 已知悉
- `resolved`：已處理 / 已關懷

## Logging 原則（CR-0047）

- 前端程式碼**不使用 `console.*`**：不得 `console.log` token、`Authorization` / `Bearer`
  標頭或任何機敏 payload（住民個資、完整對話原文等）到瀏覽器 console。
- 401 / 403 等錯誤只顯示白話提示（如「目前帳號沒有權限查看此資料」），
  不把 raw token 或後端錯誤細節印出。
- 由 `logging_safety.test.js` 以靜態來源檢查守護此原則（`node --test caregiver_web/logging_safety.test.js`）。

## 目前限制（MVP）

- 尚未內嵌 Firebase popup 登入；caregiver 需手動貼上自己的 ID Token / session 權杖（後續 CR 補）。
- 只能依「new → acknowledged → resolved」標記狀態，無法復原為較早狀態（後端允許，但前端 UI 以單向流程為主）。
- super_admin 管理頁（caregiver 帳號管理 + 住民授權指派）已於 **CR-0044** 完成
  （見上方「照護人員管理 / 住民授權指派」；對應後端 provisioning 端點 = **CR-0043**，
  見 `docs/CAREGIVER_PROVISIONING.md`）。
- 授權「重新啟用」以另建一筆有效關聯達成（後端無 re-activate 端點）；舊的已停用關聯會保留作稽核軌跡。
