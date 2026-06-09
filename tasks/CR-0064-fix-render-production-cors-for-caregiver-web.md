# CR-0064 Fix Render Production CORS for caregiver_web

## 背景

目前後端已部署在 Render：

* Backend URL: `https://ai-companion-app.onrender.com`
* Caregiver Web URL: `https://ai-companion-caregiver-web.onrender.com`
* Backend root directory: `backend/stt_proxy`
* Caregiver web root directory: `caregiver_web`

目前 Supabase migration `001`～`014` 已完成，`/health` 正常：

```json
{
  "status": "ok",
  "hasOpenAiKey": true,
  "realtimeModel": "gpt-realtime"
}
```

但 caregiver_web 登入管理者後會卡在：

```text
正在以管理者身分載入資料...
```

Browser Console 顯示 CORS 錯誤：

```text
Origin https://ai-companion-caregiver-web.onrender.com is not allowed by Access-Control-Allow-Origin.
Fetch API cannot load https://ai-companion-app.onrender.com/api/care-alerts?limit=20 due to access control checks.
```

在 Render backend Shell 測試：

```bash
curl -i -X OPTIONS "https://ai-companion-app.onrender.com/api/care-alerts?limit=20" \
  -H "Origin: https://ai-compas-control-allow-origin: http://localhost:5173
```

但 Render backend env 已確認包含：

```text
CORS_ALLOWED_ORIGINS=https://ai-companion-caregiver-web.onrender.com
ALLOWED_ORIGINS=https://ai-companion-caregiver-web.onrender.com
```

代表目前後端程式仍有舊 CORS fallback / 舊 middleware / 測試或開發用 origin 覆蓋正式 origin。

## 目標

一次性修正 `backend/stt_proxy/server.js` 的-web.onrender.com
```

並且不得再回傳：

```text
http://localhost:5173
```

## 必做事項

### 1. 全專案搜尋 localhost CORS 來源

請搜尋並檢查以下字串：

```bash
grep -R "localhost:5173\|127.0.0.1:5173\|Access-Control-Allow-Origin\|cors(" backend/stt_proxy -n
```

找出是哪裡導致 production OPTIONS request 仍回傳：

```text
access-control-allow-origin: http://localhost:5173
```

### 2. 修正 CORS middleware

請修改 `backend/stt_proxy/server.js`，要求：

1. CORS 白名單優先讀：

   * `process.env.CORS_ALLOWED_ORIGINS`
   * fallback 才讀 `plight 必須正確回傳 204。
5. 必須允許 credentials。
6. 必須允許 methods：

   * `GET`
   * `HEAD`
   * `PUT`
   * `PATCH`
   * `POST`
   * `DELETE`
   * `OPTIONS`
7. 必須允許 headers：

   * `Content-Type`
   * `Authorization`
   * `X-Admin-Token`
   * `X-Requested-With`
8. no-origin request 要允許，避免 server-to-server、health check、native app request 被擋。
9. 如果 origin 不在白名單，要 fail closed，不可以 allow-all。

### 3. 避免重複 middleware

請確認 `server.js` 中不要有多個 CORS middleware 互相覆蓋。

尤其檢查並移除或合併：

```js
app.use(cors(...))
apse URL 檢查

確認 `caregiver_web/index.html` 中正式 API base URL 為：

```js
window.APP_CONFIG = window.APP_CONFIG || { apiBaseUrl: "https://ai-companion-app.onrender.com/api" };
```

不要讓正式部署再使用同源 `/api`，因為 caregiver_web 是 Render Static Site，backend 是另一個 Render Web Service。

### 5. 新增或修正測試

請新增或修正 backend test，驗證：

1. 當 env 為：

```js
CORS_ALLOWED_ORIGINS=https://ai-companion-caregiver-web.onrender.com
```

request origin 為：

```text
https:ntrol-Allow-Origin: https://ai-companion-caregiver-web.onrender.com
```

2. 不可回傳：

```text
Access-Control-Allow-Origin: http://localhost:5173
```

3. 未授權 origin 應被拒絕或不回 CORS allow header。

### 6. 執行測試

請執行：

```bash
cd backend/stt_proxy
npm test
```

如果專案有指定 check 指令，也請執行：

```bash
npm run check
```

若 `npm run check` 不存在，請明確回報不存在，不要假裝通過。

### 7. 提交 commit

若測試通過，請 commit：

```bash
git add backend/stt_proxy caregiver_web/index.html
git commit -m "Fix production CORS for caregiver web on Render"
```

不要加入任何 secret 檔案：

* `.env`
* Firebase service account json
* `google-services.json`
* `GoogleService-Info.plist`
* keystore
* `key.properties`

## 驗收標準

部署到 Render 後，backend Shell 執行：

```bash
curl -i -X OPTIONS "https://ai-companion-app.onrender.com/api/care-alerts?limi/ai-companion-caregiver-web.onrender.com
access-control-allow-credentials: true
```

不得再看到：

```text
access-control-allow-origin: http://localhost:5173
```

接著打開：

```text
https://ai-companion-caregiver-web.onrender.com
```

清除前端快取：

```js
localStorage.clear();
sessionStorage.clear();
location.reload();
```

使用 `ADMIN_API_TOKEN` 登入後，不應再卡在：

```text
正在以管理者身分載入資料...
```

若正式資料庫目前沒有資料，可以顯示空資料或 0 筆，這是可接受結果。

