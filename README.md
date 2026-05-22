# 愛陪伴 v2 Realtime Voice Pet Companion

結合全語音互動、AI 陪伴寵物、長照生活任務與獨立長照商城網站的第一版展示原型。

> 畢業專題 Demo 架構、Realtime 主流程、長期記憶流程、fallback、Demo 腳本與倫理隱私聲明，詳見 [`docs/demo_architecture.md`](docs/demo_architecture.md)。

## 專題介紹

系統分成三部分：

1. Flutter App（語音互動 + 陪伴寵物 + 任務 + 設定 + 歷史）
2. STT Proxy 後端（由後端持有 OpenAI API Key）
3. 獨立商城網站（與 Flutter App 分離）

第二版主流程為 Realtime Voice：
- Flutter 麥克風串流 -> Backend session broker -> OpenAI Realtime API
- 即時 transcript / 即時回覆文字事件 / 即時語音回覆狀態
- 寵物狀態在 listening / thinking / speaking 間切換

## 專案狀態

已完成第一版整合
- OpenAI Realtime WebRTC 語音對話穩定性優化
- 語音中斷、連線異常與 timeout fallback
- Companion Engine 結構化理解層
- 隱含情緒與陪伴需求分析
- pgvector 長期記憶檢索
- 知識搜尋與可信資料來源整合
- 台語語音模型路由與 fallback 架構
- 語音情緒輔助判斷

持續優化中
- Realtime 多輪對話穩定性壓力測試
- 台語 ASR 模型準確度提升
- 語音音量特徵接入
- 長期記憶品質與去重規則優化
- 搜尋來源篩選與回答品質提升
- 陪伴回覆語氣微調

## Flutter App 啟動方式

1. 安裝 Flutter SDK 並確認 `flutter` 指令可用。
2. 進入專案根目錄（以下用 `<專案根目錄>` 代表實際路徑）：
   - `cd <專案根目錄>`
3. 安裝套件：
   - `flutter pub get`
4. 啟動（桌機 / 模擬器 / 預設裝置）：
   - `flutter run`

### iPhone 實機 Demo 啟動方式

iPhone 實機無法用 `127.0.0.1` 連到開發電腦，啟動時要用 `--dart-define` 指定電腦在區域網路（LAN）的 IP：

1. 查出開發電腦的 LAN IP（macOS）：
   - `ipconfig getifaddr en0`（例如 `192.168.0.17`）
2. 確認 iPhone 與電腦連到同一個 Wi-Fi。
3. 確認後端已啟動且 `.env` 內 `HOST=0.0.0.0`（見下方 Backend 說明）。
4. 取得 iPhone 裝置 ID：
   - `flutter devices`
5. 以實機啟動並指定後端位址：
   - `flutter run -d <iPhone裝置ID> --dart-define=BACKEND_BASE_URL=http://<電腦LAN-IP>:3001`
   - 範例：`flutter run -d 00008110-000XXXXXXXXXXXXX --dart-define=BACKEND_BASE_URL=http://192.168.0.17:3001`

`BACKEND_BASE_URL` 預設為 `http://127.0.0.1:3001`（適合桌機 / 模擬器）；iPhone 實機請務必用 `--dart-define` 覆寫成電腦的 LAN IP。

## Backend 啟動方式（STT Proxy + Realtime Broker）

1. 進入後端目錄：
   - `cd <專案根目錄>/backend/stt_proxy`
2. 安裝套件：
   - `npm install`
3. 建立 `.env`：
   - 複製 `.env.example` 為 `.env`，並填入 `OPENAI_API_KEY`
   - iPhone 實機 Demo：請確認 `.env` 內 `HOST=0.0.0.0`，後端才會綁定所有網路介面，讓同一個 Wi-Fi 下的 iPhone 連得到（純本機開發可用 `127.0.0.1`）
4. 啟動服務：
   - `npm start`
5. 檢查健康狀態：
   - 本機：`GET http://localhost:3001/health`
   - iPhone 實機驗證：用手機瀏覽器開 `http://<電腦LAN-IP>:3001/health`，看得到 JSON 即代表連得到後端

## OpenAI API Key 設定方式

請在 `backend/stt_proxy/.env` 設定：

```env
OPENAI_API_KEY=your_openai_api_key_here
HOST=0.0.0.0
PORT=3001
REALTIME_MODEL=gpt-realtime
REALTIME_VOICE=alloy
```

注意：
- 不要把 API Key 寫在 Flutter App。
- `.env` 已在 `.gitignore`，不會被提交。

## 商城網站啟動方式

商城為獨立網站，路徑在 `care_mall_website/`，非 Flutter 內嵌頁。

可用任一靜態伺服器啟動（例如 VSCode Live Server），預設示範網址：
- `http://localhost:5500`

Android 模擬器若要連本機網站：
- 請改用 `http://10.0.2.2:5500`

## Realtime 連線方式（正式主流程）

正式 Realtime 語音主流程是 WebRTC SDP 交換：

- Flutter（`RealtimeVoiceService`，WebRTC）
  → 後端 `POST /api/realtime/call`
  → OpenAI GA Realtime API `POST /v1/realtime/calls`

流程說明：
- Flutter 端建立 WebRTC 連線並產生 SDP offer。
- 將 offer 以 `Content-Type: application/sdp` POST 到後端 `POST /api/realtime/call`。
- 後端持有 `OPENAI_API_KEY`，代為呼叫 OpenAI GA 端點 `POST /v1/realtime/calls`，取回 answer SDP 後回傳給 App。
- App 不會拿到正式 API Key。

後端位址：
- 由 `BACKEND_BASE_URL` 決定，預設 `http://127.0.0.1:3001`，實際呼叫端點為 `<BACKEND_BASE_URL>/api/realtime/call`。
- iPhone 實機請用 `--dart-define=BACKEND_BASE_URL=http://<電腦LAN-IP>:3001` 覆寫（見上方「iPhone 實機 Demo 啟動方式」）。

> 註：`POST /api/realtime/session`（session secret 模式）為舊版 legacy 端點，目前主流程**不使用**，僅保留作相容用途，請勿作為主流程依據。

## 備援模式（Fallback）

若 Realtime 連線失敗，App 會提示：
- `目前連線不穩，我先用一般語音模式陪你說話。`

並可切回一般語音模式（第一版流程）。

## 舊版 STT 端點（保留，App 不再提供切換 UI）

第一版檔案上傳式 STT 端點 `POST /api/stt/transcribe` 仍保留在後端作為相容用途，但目前 App 的「設定」頁**已不再提供** STT 模式切換或 STT Proxy URL 輸入欄位。

- 後端位址統一由 `BACKEND_BASE_URL` 決定（見「Realtime 連線方式（正式主流程）」），不需在 App 內手動輸入。
- 此端點非目前主流程；主流程請見「Realtime 連線方式（正式主流程）」。

## Assets 放置方式

請放置到以下路徑（已在 `pubspec.yaml` 宣告）：

- `assets/pets/talk/dog_talk_01.png` ~ `dog_talk_06.png`
- `assets/pets/listening/dog_listening.png`
- `assets/pets/rest/dog_rest_01.png` ~ `dog_rest_03.png`
- `assets/pets/states/dog_normal.png`
- `assets/pets/states/dog_caring.png`
- `assets/pets/states/dog_happy.png`
- `assets/pets/states/dog_excited.png`
- `assets/pets/states/dog_thirsty.png`
- `assets/pets/states/dog_sleepy.png`
- `assets/pets/states/dog_hungry.png`
- `assets/pets/states/dog_sad.png`

若 `dog_normal.png` 或 `dog_sad.png` 缺失，程式會 fallback 到 `dog_rest_01.png`，避免 crash。

## Demo 操作流程（v2）

1. 首次開啟進入 Onboarding，輸入寵物名字，按「開始陪伴」。
2. 進首頁後寵物先 rest 約 1 秒，再主動問候（TTS + talking 動畫）。
3. 點「啟動即時語音陪伴」。
4. 直接對手機說話（不需錄音檔上傳）。
5. App 會即時收到 transcript 與 AI 回覆文字事件，並更新寵物狀態。
6. 使用者說「孤單、難過、擔心、開心」等關鍵字時，寵物 mood/expression/action 會改變。
7. 若 Realtime 斷線，顯示 fallback 提示，仍可改用一般語音模式 demo。
