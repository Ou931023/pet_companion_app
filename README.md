# AI 寵物陪伴系統

以長者陪伴為核心的 Flutter App。長者可與 AI 寵物進行即時語音對話；系統結合長期記憶、生活任務與 Care Alert，讓家屬或照護人員掌握需要關心的事件。本專案仍在開發與驗證中，不是醫療診斷工具。

## 系統組成

- `lib/`、`test/`：Flutter 長者端與測試。主要功能包含寵物互動、Realtime 語音、對話、記憶、提醒／今日任務、Care Alert 與設定。
- `backend/stt_proxy/`、`backend/agent/`：Node.js API、Realtime SDP 轉送、代理工具路由、記憶、Care Alert、通知與資料存取。
- `caregiver_web/`：照護管理網頁，顯示授權範圍內的長者、任務與 Care Alert 資訊。
- `care_mall_website/`：獨立商城頁面；與照護管理網頁不同，不是目前的主要管理入口。
- `store_legal_site/`：隱私權政策、服務條款、支援與資料刪除說明的公開靜態頁面。

架構與 API 契約以 [`PROJECT_ARCHITECTURE.md`](PROJECT_ARCHITECTURE.md) 為準；各模組的修改邊界見 [`docs/TEAM_AGENTS.md`](docs/TEAM_AGENTS.md)。

## 主要流程

正式即時語音採 WebRTC：Flutter 建立 SDP offer，經後端 `POST /api/realtime/call` 轉送至 OpenAI Realtime Calls API，再由 WebRTC/DataChannel 接收語音與事件。正式流程不使用假回覆或 mock 取代。後端保管服務憑證；Flutter 不應包含 API key。

代理工具由後端控制。涉及通知、購買或其他對外行動時，必須遵守既有的權限與確認流程。長期記憶使用 PostgreSQL／pgvector；Care Alert 由陪伴對話中的風險線索產生，前台仍以陪伴語氣互動。台語與中台混合語言是持續驗證項目，不能把語言偏好設定視為台語 ASR 已完成驗收。

## 網頁與後端部署

依目前版本庫的部署設定與交接文件：

| 元件 | 平台／位置 | 備註 |
|---|---|---|
| 照護管理網頁 `caregiver_web/` | Render Static Site，設定名稱 `ai-companion-caregiver-web` | `render.yaml` 定義建置與發布；實際線上版本仍須到 Render 驗證。 |
| 後端 API | Render Web Service，文件記載 `https://ai-companion-api-1gm7.onrender.com` | App 的 `API_BASE_URL` 預設指向此網址；資料庫使用 PostgreSQL。 |
| 法律／支援頁面 `store_legal_site/` | GitHub Pages：`https://ou931023.github.io/pet_companion_app/` | 僅公開靜態說明頁，**不是**照護管理網頁或 API。 |

Render／GitHub Pages 的網址或其 DNS 位址，**不能直接當成 AMD-ITRI 算力申請表要求的團隊固定出口 Public IP**。若該資源以來源 IP 管制，應提供團隊實際連線用、可持續控制的固定對外 IP（例如經確認適用的雲端跳板）；目前版本庫沒有可據以填報的固定出口 IP。

部署與上架檢查見 [`docs/STORE_SUBMISSION_RUNBOOK.md`](docs/STORE_SUBMISSION_RUNBOOK.md)；照護管理網頁的設定見 [`caregiver_web/README.md`](caregiver_web/README.md)。舊展示文件可能保留過時的 Render 網址，正式操作請以目前部署後台與建置設定核對。

## 本機開發

需要 Flutter SDK，以及符合 [`backend/stt_proxy/package.json`](backend/stt_proxy/package.json) 要求的 Node.js 版本。不要將環境變數檔、金鑰或後端執行時資料加入 Git。

```bash
# Flutter 依賴與檢查
flutter pub get
flutter test

# 後端依賴與測試
cd backend/stt_proxy
npm install
npm test
```

後端啟動指令為 `npm start`。正式部署需要的環境變數名稱、資料庫 migration 與驗證步驟，請依 [`docs/BACKEND_DEPLOYMENT_GUIDE.md`](docs/BACKEND_DEPLOYMENT_GUIDE.md) 和 [`docs/PRODUCTION_CONFIG_CHECKLIST.md`](docs/PRODUCTION_CONFIG_CHECKLIST.md) 設定；不要把實際值寫在 README、程式碼或 issue。正式 Flutter 建置使用 `APP_ENV=production` 與 HTTPS `API_BASE_URL`；本機開發須顯式使用 `APP_ENV=development` 並指定可連線的後端。iPhone 實機不能以 `127.0.0.1` 連到開發電腦。

## AMD AI 代理人創新應用組

競賽用的 AMD 雲端資源目前屬申請／整合規劃，**尚未在本專案證明已接線或完成推論測試**。預定讓 AMD 資源承載代理規劃與工具選擇；現有 OpenAI Realtime WebRTC 語音主流程維持不變。AMD AI Developer Program 的雲端額度、AMD Developer Cloud 帳號及 AMD-ITRI Joint Lab 競賽算力是不同申請／啟用流程，不能互相視為已開通。只有取得資源並保存實際模型、呼叫與工具結果紀錄後，才能在參賽資料中寫成已實測成果。

## 安全與現況說明

- 不讀取或提交任何 `.env`、token、私鑰與 `backend/stt_proxy/data/*.json` 執行時資料。
- 不把 Realtime 主流程改成 mock；功能與實機驗收狀態須分開描述。
- 本 README 描述版本庫的架構與部署設定，不保證線上環境已同步部署最新程式或完成所有實機測試。
