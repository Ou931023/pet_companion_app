# Caregiver Operations Runbook

> 目的：確認管理者 / 照護人員後台真的能看到 App 行為數據，並說明正式上架後如何提供給照護人員，以及 Telegram Bot 要怎麼配置、驗收與維運。
>
> 紅線：本文件只列變數名稱與操作流程，不放 `.env`、token、私鑰、chat id、完整 email 或完整對話原文。

---

## 1. 現況結論

管理者後台不是只有形式。現有資料鏈路如下：

1. Flutter App 透過 `AppUsageTrackingService` 上報使用事件到 `POST /api/app-usage/events`。
2. 後端以 `requireResidentCaller` 從長者 Firebase ID Token 推導 `elderId`，不信任前端自行傳入住民身分。
3. Production 後端將事件寫入 PostgreSQL `app_usage_events`。
4. `GET /api/caregiver/analytics` 讀取 `app_usage_events`、`care_alerts`、日常任務與照片驗證資料後彙整。
5. `caregiver_web` 的「長者狀態分析」頁以正式 API 顯示真實統計；沒有資料時顯示「資料不足」，不以假資料補畫面。

關鍵檔案：

- `lib/services/app_usage_tracking_service.dart`
- `lib/config/app_config.dart`
- `backend/stt_proxy/server.js`
- `backend/stt_proxy/services/appUsageEventStore.js`
- `backend/stt_proxy/services/admin/caregiverAnalyticsService.js`
- `backend/stt_proxy/db/migrations/017_create_app_usage_events.sql`
- `caregiver_web/app.js`

---

## 2. 後台目前看得到哪些 App 行為數據

後端允許的 `app_usage_events` 事件類型：

- `app_open`
- `app_background`
- `session_start`
- `session_end`
- `voice_interaction_start`
- `voice_interaction_end`
- `voice_navigation`
- `typed_chat_sent`
- `pet_interaction`
- `reminder_created`
- `daily_task_completed`
- `photo_verification_submitted`
- `puzzle_started`
- `puzzle_completed`
- `font_size_changed`
- `settings_changed`
- `pet_style_changed`

`caregiver_web` 會在「長者狀態分析」呈現：

- 使用天數
- 語音互動次數
- 語音導覽次數
- 打字訊息次數
- 寵物互動次數
- 建立提醒次數
- 任務完成次數
- 拼圖完成次數
- 設定調整次數
- 最近使用時間
- 寵物類型、視覺風格、成長階段、心情、飽足度、親密度與最近互動
- Care Alert 統計與任務 / 照片驗證狀況

限制與誠實標註：

- 情緒趨勢與遊戲退化指標目前若沒有真實寫入來源，後台會顯示資料不足。
- 簽到狀態目前以「當日是否有任務證明提交」推估，不是獨立簽到表。
- App 使用統計不會存完整對話逐字稿，metadata 只保留 primitive 並截斷。

---

## 3. 上架後如何提供給照護人員

### 3.1 正式交付原則

- 不可以把 `ADMIN_API_TOKEN` 給一般照護人員。
- 一般照護人員只能以自己的 Firebase 帳號 / ID Token 進入 caregiver 模式。
- 照護人員只看得到 `resident_caregiver_links` 中被授權且狀態為 active 的住民。
- 如果照護人員離職或不再照護某位長者，要停用 caregiver 帳號或停用授權關聯。

### 3.2 管理者開通流程

1. 確認後端 production 已部署，且資料庫 migration 已跑完。
2. 確認 caregiver_web 已部署到正式 HTTPS 網址，並且 `window.APP_CONFIG.apiBaseUrl` 指向正式 API。
3. 管理者以 super admin 身分登入 caregiver_web。
4. 到「照護人員管理」新增照護人員：
   - Email
   - 顯示名稱
   - Firebase UID 可先留空，待綁定後補上
5. 讓照護人員建立或登入自己的 Firebase 帳號。
6. 取得該照護人員的 Firebase UID 後，由管理者回到「照護人員管理」補上 `firebaseUid`。
7. 到「住民授權指派」建立照護人員與長者的授權關聯。
8. 照護人員以 caregiver 身分登入後，只會看到被指派的住民。

### 3.3 Firebase Web 登入設定

caregiver_web 已支援 Firebase Email / Google 登入。正式部署時，請在 `config.js` 或
`index.html` 的 `window.APP_CONFIG` 設定 Firebase Web app config：

```js
window.APP_CONFIG = {
  apiBaseUrl: "https://api.your-domain.com/api",
  firebase: {
    apiKey: "...",
    authDomain: "...",
    projectId: "...",
    appId: "...",
  },
};
```

注意：

- Firebase Web `apiKey` 不是後端私鑰，但仍應只放 Firebase Web config，不可放 service account 或 private key。
- Firebase Console 需把 caregiver_web 正式網域加入 Authorized domains。
- 照護人員登入成功後，前端會自動取得 ID Token，後端依 `users.firebase_uid` 解析為 caregiver。
- 手動登入權杖欄位只作為備援，不建議作為正式交付流程。

部署前檢查：

```bash
node scripts/check_caregiver_web_config.js caregiver_web/config.js
```

這支檢查只讀指定的 `config.js`，不讀 `.env`，用來擋住缺 Firebase Web config、
localhost / ngrok API、未明確設定 feature flag、或誤放後端 secret 的情況。

Render caregiver_web Static Site 正式部署時：

- Build Command：`node caregiver_web/build_config_from_env.js`
- Publish Directory：`caregiver_web`
- `CAREGIVER_WEB_API_BASE_URL=https://ai-companion-api-1gm7.onrender.com/api`
- `CAREGIVER_WEB_FIREBASE_API_KEY`
- `CAREGIVER_WEB_FIREBASE_AUTH_DOMAIN`
- `CAREGIVER_WEB_FIREBASE_PROJECT_ID`
- `CAREGIVER_WEB_FIREBASE_APP_ID`

---

## 4. Telegram Bot 正式配置

### 4.1 現有 Telegram 行為

Telegram 通知由後端唯一決策：

- `low` / `medium`：只進 `care_alerts` 與 caregiver_web，不推 Telegram。
- `high` / `urgent`：寫入 `care_alerts`，並嘗試推 Telegram。
- cooldown 啟用時，相同來源 / 風險等級短時間內不重複洗版。
- 每次通知結果寫入 `notification_logs`，包含 sent / failed / skipped 類型，不存 token、chat id 或完整對話。

關鍵檔案：

- `backend/stt_proxy/services/telegramNotifyService.js`
- `backend/stt_proxy/services/careAlertCooldown.js`
- `backend/stt_proxy/services/notificationLogService.js`
- `backend/stt_proxy/db/migrations/012_create_notification_audit_logs.sql`
- `backend/stt_proxy/server.js`

### 4.2 Render / production 需要的變數名稱

啟用 Telegram 通知時，在部署平台 secret / environment 設定：

- `TELEGRAM_CARE_CHAT_ID`
- `TELEGRAM_BOT_TOKEN`

冷卻可選設定：

- `CARE_ALERT_TELEGRAM_COOLDOWN_ENABLED`
- `CARE_ALERT_TELEGRAM_COOLDOWN_MS`

production fail-fast 規則：

- 若設定了 `TELEGRAM_CARE_CHAT_ID`，就必須設定 `TELEGRAM_BOT_TOKEN`。
- secret 只能放在 Render / 後端部署平台，不可放入 git、文件、截圖或 `.env` 內容。

### 4.3 建議的正式群組模式

目前系統是單一 `TELEGRAM_CARE_CHAT_ID` 模型，因此正式上架初期建議：

1. 建立一個私密 Telegram 群組，例如「AI陪伴 照護通知」。
2. 只加入被授權的家屬 / 照護人員 / 管理者。
3. 把 Bot 加入群組，確認 Bot 有發訊息權限。
4. 後端只推 high / urgent 摘要到此群組。
5. 每次住民或照護者名單變動，都同步檢查 Telegram 群組成員。

重要風險：

- 現有 Telegram 通知不是 per-caregiver chat id，也不是依 `resident_caregiver_links` 找每位照護者的個別 chat。
- 如果未來要服務多個家庭或多個機構，必須新增 per-caregiver / per-resident Telegram 綁定表，避免通知送到不相關照護者。

建議後續 CR：

- `CR-0104 Per-Caregiver Telegram Routing`

目標：

- 為 caregiver 綁定 Telegram chat id 或通知偏好。
- high / urgent 通知依 `resident_caregiver_links` 找授權照護者。
- notification log 記錄每位照護者的通知結果。

---

## 5. 必跑驗收

### 5.1 App usage analytics smoke

1. 用 production build 登入長者帳號。
2. 開啟 App 並停留 1 分鐘。
3. 進行一次語音互動。
4. 送出一次打字聊天。
5. 點一次寵物互動。
6. 建立一次提醒。
7. 完成一次日常任務或照片驗證。
8. 到 caregiver_web「長者狀態分析」確認統計有更新。

驗收結果：

- `app_usage_events` 有資料。
- caregiver_web 顯示真實數字，不是全部資料不足。
- 照護人員模式只能看到被授權住民。

### 5.2 Care Alert + Telegram smoke

1. 用測試長者帳號觸發 medium 關懷句。
2. 確認 caregiver_web 出現 Care Alert。
3. 確認 Telegram 沒有推送 medium。
4. 用測試長者帳號觸發 high / urgent 測試句。
5. 確認 caregiver_web 出現 Care Alert。
6. 確認 Telegram 授權群組收到摘要通知。
7. 確認 `notification_logs` 有 sent / skipped / failed 對應結果。

注意：

- 測試時不要在正式照護群組反覆觸發高風險句，避免造成照護疲勞。
- 若 cooldown 啟用，短時間重複觸發可能會顯示 skipped cooldown，這是預期行為。

---

## 6. 上架前 No-Go 條件

以下任一項未完成，不建議正式公開上架：

- Production 後端沒有 HTTPS 公開網址。
- PostgreSQL migration 未跑完，尤其是 `app_usage_events`、`care_alerts`、`notification_logs`、`resident_caregiver_links`。
- Firebase Admin 無法驗證長者 / 照護人員 ID Token。
- caregiver_web 沒有指向正式 API。
- 照護人員仍被要求拿 `ADMIN_API_TOKEN`。
- Telegram 群組不是私密授權群組。
- 隱私權政策沒有揭露 OpenAI、Telegram、App 使用分析與 Care Alert 資料流向。
- 沒有完成真機 smoke：語音、打字、Care Alert、Telegram、後台 analytics。
