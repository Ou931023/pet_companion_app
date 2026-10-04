# AI Pet Companion | AI 寵物陪伴系統

An AI pet companion app for older adults. It combines real-time voice conversation, personal memory, everyday tasks, and Care Alerts so caregivers can notice when someone may need attention. It is **not a medical diagnosis or emergency response service**.

這是一套以長者陪伴為核心的 AI 寵物系統，結合即時語音、長期記憶、生活任務與 Care Alert，協助家屬或照護人員留意需要關心的狀況。它**不是醫療診斷或緊急救援服務**。

[繁體中文](#繁體中文) · [English](#english)

## 繁體中文

### 專案內容

| 目錄 | 用途 |
|---|---|
| `lib/`、`test/` | Flutter 長者端與測試：寵物互動、語音對話、記憶、任務、Care Alert、設定。 |
| `backend/stt_proxy/`、`backend/agent/` | Node.js API、Realtime 連線轉送、代理工具、記憶、通知與資料存取。 |
| `caregiver_web/` | 照護管理網頁，供授權人員查看任務與風險重點。 |
| `care_mall_website/` | 獨立商城頁面；不等於照護管理網頁。 |
| `store_legal_site/` | 隱私權政策、服務條款、支援與帳號資料刪除說明。 |

正式語音主流程為 Flutter → 後端 `POST /api/realtime/call` → OpenAI Realtime Calls API 的 WebRTC SDP 交換；正式服務憑證只放在後端。長期記憶使用 PostgreSQL／pgvector。代理工具與對外行動由後端管理，需遵守授權及確認流程。詳細契約見 [`PROJECT_ARCHITECTURE.md`](PROJECT_ARCHITECTURE.md)。

### 取得與執行

需要 Flutter SDK、Dart SDK，以及 Node.js `>=20.18.1 <25`。iOS 開發另需 macOS 與 Xcode。執行前，先依 [`docs/ENVIRONMENT_SETUP.md`](docs/ENVIRONMENT_SETUP.md) 設定本機後端需要的環境變數；**不要把實際金鑰提交到 Git**。

```bash
git clone https://github.com/Ou931023/pet_companion_app.git
cd pet_companion_app

# Terminal 1: backend
cd backend/stt_proxy
npm install
npm start

# Terminal 2: Flutter app (from the repository root)
flutter pub get
flutter run --dart-define=APP_ENV=development \
  --dart-define=API_BASE_URL=http://127.0.0.1:3001
```

桌機或同機模擬器可用上面的本機位址；iPhone 實機必須把 `API_BASE_URL` 換成開發電腦在同一網路中的可連線位址，不能用手機自己的 `127.0.0.1`。後端健康檢查：`GET http://127.0.0.1:3001/health`。Firebase 登入與資料庫相關功能需完成各自的設定，並非只執行上述指令就會全部可用。

照護管理網頁的本機啟動及設定方式見 [`caregiver_web/README.md`](caregiver_web/README.md)。如要檢查程式，可在專案根目錄執行 `flutter test`，並在 `backend/stt_proxy/` 執行 `npm test`；本 README 的更新不代表這些測試或實機流程已完成驗收。

### 部署與貢獻

版本庫的設定將照護管理網頁部署為 Render Static Site、後端部署於 Render、公開法律／支援頁部署於 GitHub Pages。這些是**部署配置**；線上版本、環境變數與資料庫 migration 仍須由部署者核對。請參閱 [`docs/BACKEND_DEPLOYMENT_GUIDE.md`](docs/BACKEND_DEPLOYMENT_GUIDE.md) 與 [`docs/STORE_SUBMISSION_RUNBOOK.md`](docs/STORE_SUBMISSION_RUNBOOK.md)。Render 或 GitHub Pages 的網站網址不等於固定出口 Public IP。

修改前請先閱讀 [`AGENTS.md`](AGENTS.md)、[`PROJECT_ARCHITECTURE.md`](PROJECT_ARCHITECTURE.md) 與 [`docs/TEAM_AGENTS.md`](docs/TEAM_AGENTS.md)。勿提交 `.env`、金鑰、token、私人資料或 `backend/stt_proxy/data/*.json` 執行時資料；勿以 mock 取代正式 Realtime 流程。功能實作、部署與實機驗收是不同狀態，請據實記錄。

## English

### Repository layout

| Directory | Purpose |
|---|---|
| `lib/`, `test/` | Flutter app for older adults and its tests: pet interaction, voice, memory, tasks, Care Alerts, and settings. |
| `backend/stt_proxy/`, `backend/agent/` | Node.js API, Realtime connection broker, agent tools, memory, notifications, and persistence. |
| `caregiver_web/` | Caregiver dashboard for authorized users. |
| `care_mall_website/` | Separate storefront, not the caregiver dashboard. |
| `store_legal_site/` | Public privacy, terms, support, and account-deletion pages. |

The production voice path uses WebRTC SDP exchange: Flutter → backend `POST /api/realtime/call` → OpenAI Realtime Calls API. Service credentials remain on the backend. Long-term memory uses PostgreSQL/pgvector. Backend-controlled tools enforce authorization and confirmation before external actions. See [`PROJECT_ARCHITECTURE.md`](PROJECT_ARCHITECTURE.md) for the architecture and API contracts.

### Get started

Install Flutter/Dart and Node.js `>=20.18.1 <25`. iOS development also requires macOS and Xcode. Configure the backend's required environment variable **names** using [`docs/ENVIRONMENT_SETUP.md`](docs/ENVIRONMENT_SETUP.md); never commit actual credentials.

```bash
git clone https://github.com/Ou931023/pet_companion_app.git
cd pet_companion_app

# Terminal 1: backend
cd backend/stt_proxy
npm install
npm start

# Terminal 2: Flutter app (from the repository root)
flutter pub get
flutter run --dart-define=APP_ENV=development \
  --dart-define=API_BASE_URL=http://127.0.0.1:3001
```

For a physical iPhone, replace `API_BASE_URL` with an address of your development computer that the phone can reach; `127.0.0.1` on the phone points back to the phone. Check the backend at `GET http://127.0.0.1:3001/health`. Firebase sign-in and database-backed features require their own configuration. For the caregiver dashboard, follow [`caregiver_web/README.md`](caregiver_web/README.md).

Run `flutter test` from the repository root and `npm test` from `backend/stt_proxy/` to check the respective codebases. The presence of a feature in this repository does not imply that its production deployment or physical-device validation is complete.

### Deployment and contributions

The repository configures the caregiver dashboard as a Render Static Site, the backend on Render, and public legal/support pages on GitHub Pages. Verify the live revision, environment, and database migrations before relying on a deployment. See the [`backend deployment guide`](docs/BACKEND_DEPLOYMENT_GUIDE.md) and [`release runbook`](docs/STORE_SUBMISSION_RUNBOOK.md). A website URL is not a fixed outbound public IP.

Before contributing, read [`AGENTS.md`](AGENTS.md), [`PROJECT_ARCHITECTURE.md`](PROJECT_ARCHITECTURE.md), and [`docs/TEAM_AGENTS.md`](docs/TEAM_AGENTS.md). Do not commit `.env` files, keys, tokens, private data, or runtime files under `backend/stt_proxy/data/`. Do not replace the production Realtime flow with a mock. Distinguish implementation, deployment, and device verification in change reports.
