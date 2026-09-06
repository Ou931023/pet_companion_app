# 使用手冊 — AI 寵物陪伴系統 / Care Alert Companion App

> 對象：指導師長與專題組員。目的：快速了解這個 App 是什麼、怎麼操作、怎麼跑起來。
> （本文件為「說明＋操作＋執行」導向，非長者友善版；面向使用者的白話提示在 App 內。）

---

## 1. 專案簡介

這是一個以**長者陪伴**為核心的 AI 寵物 App。長者用**語音**和 AI 寵物自然對話，寵物會依對話內容、情緒、長期記憶與生活線索，給出陪伴式回應；同時系統會在背景做 **Care Alert 風險分析**，當長者出現異常（孤單、情緒低落、睡眠/食慾異常、身體不適、疑似危急）時，讓家屬或長照人員及早注意。

核心價值三件事：**即時語音陪伴**、**長期記憶**、**Care Alert 風險提醒**。

---

## 2. 系統架構（一張表看懂）

| 層 | 技術 | 負責 |
|---|---|---|
| 前端（長者端） | Flutter（主要跑 iOS 實機） | 寵物首頁、即時語音對話、字幕、記憶、設定、Care Alert 呈現 |
| 前端（照護端） | caregiver_web（網頁管理端） | 家屬 / 長照人員查看 Care Alert 風險重點 |
| 後端 | Node.js（`backend/stt_proxy`，部署於 Render） | Realtime SDP 交換、AI 指令組裝、工具路由、長期記憶 API、Care Alert 分析與通知、搜尋、台語 ASR |
| AI / 語音 | OpenAI Realtime（WebRTC）＋ GPT 系列模型 | 即時語音聽說、回覆生成、摘要 |
| 資料庫 | PostgreSQL ＋ pgvector | 長期記憶、語意檢索、Care Alert 紀錄、商城 / 任務資料 |
| 第三方 | Firebase Auth、Tavily、Open-Meteo、Telegram | 登入、網路搜尋、天氣、長照通知 |

**即時語音流程（重點）**：Flutter 取麥克風音訊 → 建立 WebRTC offer SDP → POST 後端 `/api/realtime/call` → 後端轉送 OpenAI Realtime → 回 answer SDP → Flutter 建立連線 → 透過 data channel 收即時事件（轉錄、寵物回覆、語音播放）。

---

## 3. 角色與入口

| 角色 | 用什麼 | 看到什麼 |
|---|---|---|
| 長者（使用者） | iPhone 上的 App | 寵物首頁、跟寵物語音/打字聊天、記憶、設定 |
| 家屬 / 長照人員 | caregiver_web 網頁 | Care Alert 清單與風險重點（不是一堆技術資料） |

> 前台寵物永遠以「陪伴語氣」互動；風險分析在後台進行，不讓長者覺得被監視。

---

## 4. App 操作說明（長者端逐步）

### 4.1 登入
- 開啟 App → 登入頁 → 用 **Google** 或 **Email** 登入；iPhone 也可使用 **Apple 登入**（正式版不顯示 Demo 快速登入）。
- 登入成功後進入「寵物首頁」。

### 4.2 跟寵物語音對話（核心）
1. 首頁中央是 AI 寵物，下方是**麥克風按鈕**。
2. **按一下麥克風 → 對著手機說話**（畫面會顯示「正在聽」）。
3. 說完稍等，寵物會**用語音回覆**，同時上方**字幕**會把回覆一段一段顯示（長回覆會自動分頁，跟著語音節奏，不會搶在念完前翻頁）。
4. 採「**一人一句**」輪流制：寵物講完會回到待命，**要再按一次麥克風**才講下一句。
5. 也可以改用**打字**跟寵物聊天（同樣會有寵物回覆）。

### 4.3 問即時資訊（上網搜尋）
- 直接問「今天天氣如何？」「最近有什麼新聞？」「長照補助怎麼申請？」等，寵物會上網查、再用白話念出重點（資料來源由後端整理，前端不持有任何搜尋金鑰）。

### 4.4 長期記憶
- 寵物會自然記住重要的事（稱呼、家人、興趣、生活習慣、常提到的狀態等），之後對話會自然提到。
- 可從「**記憶管理**」入口查看 / 整理寵物記得的內容。

### 4.5 寵物狀態與外觀
- 寵物的表情 / 動作會跟著對話情緒變化。
- 可更換寵物外觀（skin）、設定寵物名字。

### 4.6 設定
- 調整**字體大小**、**寵物說話音量 / 開關**、**說話風格**（溫柔 / 慢慢說 / 有精神）、**語言**（中文 / 台語即時語音）。
- 也可重看新手導覽、管理帳號（登出 / 刪除帳號）。

### 4.7 其他功能（依版本旗標可能顯示）
- **提醒**：設定吃藥 / 喝水 / 回診提醒。
- **每日照護任務、照護商城**：正式版預設隱藏，由建置旗標開啟。

### 4.8 Care Alert（後台）
- 長者端不會看到「監控」字樣；風險判斷在後端進行。
- 家屬 / 長照人員在 **caregiver_web** 看到分級後的提醒：`low`（一般關心）/ `medium`（持續觀察）/ `high`（建議通知）/ `urgent`（需立即協助），high/urgent 會透過 Telegram 通知。

---

## 5. 如何執行（給組員 / 要實際跑的人）

### 5.1 需要的工具
- Flutter SDK、Xcode（iOS 實機）、Node.js、（本機跑後端時）PostgreSQL。

### 5.2 後端
- 正式環境：已部署於 Render（`https://ai-companion-app-7mb8.onrender.com`）。
- 本機自跑：
  ```bash
  cd backend/stt_proxy
  HOST=0.0.0.0 PORT=3001 npm start      # HOST=0.0.0.0 手機才連得到
  ```
- 後端需要的**環境變數名稱**（值放在 `backend/stt_proxy/.env`，**不進 git**）：
  `OPENAI_API_KEY`、`TAVILY_API_KEY`、`DATABASE_URL`、`FIREBASE_PROJECT_ID`、`FIREBASE_CLIENT_EMAIL`、`FIREBASE_PRIVATE_KEY`、`TELEGRAM_BOT_TOKEN`、`TELEGRAM_CARE_CHAT_ID` 等。

### 5.3 前端（Flutter）
- 連正式後端（Render）：
  ```bash
  flutter run --release -d <iPhone裝置id> \
    --dart-define=APP_ENV=production \
    --dart-define=API_BASE_URL=https://ai-companion-app-7mb8.onrender.com \
    --dart-define=ALLOW_MARKETPLACE_IN_PROD=true \
    --dart-define=ALLOW_DAILY_CARE_TASKS_IN_PROD=true
  ```
- 連本機後端（同一 Wi-Fi）：`--dart-define=API_BASE_URL=http://<你的電腦區網IP>:3001`。
- 更完整的環境 / 旗標說明見 `docs/ENVIRONMENT_SETUP.md`、`docs/FLUTTER_BUILD_FLAVORS.md`。

### 5.4 測試
- 前端：`flutter test`、`flutter analyze`。
- 後端：`cd backend/stt_proxy && npm test`（node --test）。

---

## 6. 延伸文件（repo 內）

| 想了解 | 看這份 |
|---|---|
| 架構真相來源（模組地圖、API 契約、資料結構） | `PROJECT_ARCHITECTURE.md` |
| 環境設定 / build flavor | `docs/ENVIRONMENT_SETUP.md`、`docs/FLUTTER_BUILD_FLAVORS.md` |
| Demo 怎麼跑 / 怎麼講 | `docs/DEMO_SCRIPT.md`、`docs/demo_architecture.md` |
| 上架前檢查 | `docs/STORE_RELEASE_CHECKLIST.md` |
| 開發紀錄 / 變更審查 | `docs/CHANGE_REVIEW.md` 與各 `docs/*CR0xxx*.md` |

---

## 7. 已知限制 / 注意事項

- **即時語音、搜尋、登入都依賴第三方金鑰**（OpenAI 額度、Tavily、Firebase）；金鑰失效或額度用完時，對應功能會以白話提示失敗，不會假裝成功。
- 即時語音以 **iOS 實機**為主要展示目標；手機需與後端在可連通的網路（本機後端須同一 Wi-Fi）。
- 本機未啟動 PostgreSQL 時，後端會退回 JSON 暫存，長期記憶 / Care Alert / 商城 / 任務等資料不會持久化。
- 金鑰一律只放在後端 `.env`（已被 `.gitignore` 排除），**程式碼與前端不含任何金鑰**，repo 可安全分享。
