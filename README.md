# 愛陪伴 v2 Realtime Voice Pet Companion

結合全語音互動、AI 陪伴寵物、長照生活任務與獨立長照商城網站的第一版展示原型。

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
2. 進入專案根目錄：
   - `cd d:\pet_companion_app`
3. 安裝套件：
   - `flutter pub get`
4. 啟動：
   - `flutter run`

## Backend 啟動方式（STT + Realtime Session Broker）

1. 進入後端目錄：
   - `cd d:\pet_companion_app\backend\stt_proxy`
2. 安裝套件：
   - `npm install`
3. 建立 `.env`：
   - 複製 `.env.example` 為 `.env`
4. 啟動服務：
   - `npm start`
5. 檢查健康狀態：
   - `GET http://localhost:3001/health`

## OpenAI API Key 設定方式

請在 `backend/stt_proxy/.env` 設定：

```env
OPENAI_API_KEY=your_openai_api_key_here
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

## Realtime 連線方式

Flutter 只呼叫：
- `POST /api/realtime/session`

Backend 會回傳短效 session secret，Flutter 不會拿到正式 API Key。

預設 URL：
- `http://localhost:3001/api/realtime/session`
- Android 模擬器請改成：`http://10.0.2.2:3001/api/realtime/session`

## 備援模式（Fallback）

若 Realtime 連線失敗，App 會提示：
- `目前連線不穩，我先用一般語音模式陪你說話。`

並可切回一般語音模式（第一版流程）。

## 舊版 STT 切換方式（保留）

在 App 的「設定」頁：

1. 切換 STT 模式：
   - Mock STT
   - OpenAI STT Proxy
2. 設定 STT Proxy URL
   - 實機/桌機可用：`http://localhost:3001/api/stt/transcribe`
   - Android 模擬器請改：`http://10.0.2.2:3001/api/stt/transcribe`

當 OpenAI STT Proxy 連線失敗時，系統會提示並自動退回 Mock STT。

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
