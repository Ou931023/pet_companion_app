# CR-0066 Production E2E Smoke Test & Flutter API URL Alignment

## 背景

Render 正式部署現況（CR-0064 修 CORS、CR-0065 停用 marketplace 後）：

- Backend（Web Service）：`https://ai-companion-app-7mb8.onrender.com`
- Caregiver Web（Static Site）：`https://ai-companion-caregiver-web.onrender.com`

caregiver_web 已對齊到 `-7mb8` 後端（`caregiver_web/index.html`）。
本 CR 只做「對齊確認 + 補正式 E2E smoke checklist」，**不新增任何功能、不改後端、不改 Realtime 主流程**。

## 目標（範圍刻意縮小）

1. 確認 Flutter production API base URL 會指向目前 Render 後端 `https://ai-companion-app-7mb8.onrender.com`。
2. 檢查專案不再殘留 `localhost` / `127.0.0.1` / `10.0.2.2` / 舊 Render URL（不含 `-7mb8`）作為**正式**位址。
3. 釘住正式 build 指令（單一真相），補上聚焦的正式 E2E smoke checklist。
4. 實機跑一次：登入、語音/打字、Care Alert、管理者端刷新（**需人工於實機執行**）。

非目標：不收斂 ATS/cleartext（屬 CR-0055 BLOCKER）、不動 `app_config.dart` 行為、不加新測試。

---

## 1. Flutter API base URL 對齊（已驗證）

Flutter 端**不寫死**正式 URL，而是 build 時以 `--dart-define` 注入，並有 production 守門：

- 設定點：`lib/config/app_config.dart`
  - `backendBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: <BACKEND_BASE_URL 別名, 預設 http://127.0.0.1:3001>)`（行 20–26）
  - 所有 endpoint（chat / realtime session / realtime call / STT / 台語 ASR / care-alerts）共用同一個 `backendBaseUrl`（行 90–93 等），無第二個寫死 host。
  - `isApiBaseUrlProductionSafe`（行 119–124）：production 下若 base URL 為空、無 scheme 或 host ∈ {`127.0.0.1`,`localhost`,`10.0.2.2`} → 回 false，啟動層顯示長者友善守門畫面，**不進主流程**。

結論：**程式碼正確，無需修改**。正式版「指向 -7mb8」是靠下方 build 指令注入；localhost 只是 dev 預設且 production 已守門。

### 正式 build 指令（單一真相，請照抄）

```bash
# iOS（實機 release）
flutter build ios --release \
  --dart-define=APP_ENV=production \
  --dart-define=API_BASE_URL=https://ai-companion-app-7mb8.onrender.com \
  --dart-define=SHOW_DEV_PANELS=false \
  --dart-define=SHOW_DEMO_LOGIN=false \
  --dart-define=ALLOW_MOCK_SERVICES=false

# Android（release）
flutter build apk --release \
  --dart-define=APP_ENV=production \
  --dart-define=API_BASE_URL=https://ai-companion-app-7mb8.onrender.com \
  --dart-define=SHOW_DEV_PANELS=false \
  --dart-define=SHOW_DEMO_LOGIN=false \
  --dart-define=ALLOW_MOCK_SERVICES=false
```

> 注意：URL 結尾**不要**加 `/api`（Flutter 端各 endpoint 自帶 `/api/...` 路徑；
> caregiver_web 的 `apiBaseUrl` 才需含 `/api`）。

---

## 2. 殘留位址檢查（已驗證）

`git grep` 結果：

- 舊 Render URL（`ai-companion-app.onrender.com`，不含 `-7mb8`）：**僅出現在 `tasks/CR-0064-*.md` 歷史紀錄**，非執行碼，保留即可。
- `-7mb8`：出現在 `caregiver_web/index.html`（正式設定）與本 CR / CR-0065 任務文件。
- `lib/` 內 `localhost` / `127.0.0.1` / `10.0.2.2`：皆為 dev 預設值與 `legacyBackendHosts` 守門清單，**符合預期**，非正式位址。

結論：**無殘留需清理**。

---

## 3. 正式 E2E Smoke Checklist（聚焦本 CR 的四條主流程）

完整 checklist 見 `docs/E2E_SMOKE_TEST_PLAN.md`（B/W/F 全項）。本 CR 聚焦使用者點名的四條流程，
對應既有 T-case 編號；逐項結果請記入 `docs/E2E_SMOKE_TEST_REPORT.md` 的 Run 區塊。

前置：後端已部署且 `GET https://ai-companion-app-7mb8.onrender.com/health` 回 `{status:"ok", hasOpenAiKey:true, realtimeModel}`；
以上方指令 build 的 production app 安裝到實機；備妥測試用 resident / caregiver / super_admin 帳號（勿用正式使用者）。

| # | 流程 | 對應 PLAN | 操作 | 通過判準 |
|---|---|---|---|---|
| S1 | App 啟動指向正式後端 | F1 | 以正式指令 build 後開 App | 不卡「服務暫時無法使用」守門；無 debug banner / demo 登入 / dev panel |
| S2 | 長者登入 | F6 | Firebase 登入 | 取得 idToken、進入寵物首頁 |
| S3 | 語音對話 | F7 | 開麥克風講一句中性話 | 連線成功、狀態 idle→listening→thinking→speaking 正常；UI 無 SDP/ICE/token 工程字；不卡住 |
| S4 | 打字對話 | F10 | 用打字輸入一句中性話 | 200、寵物自然回覆（非罐頭/客服語氣） |
| S5 | 語音 → Care Alert | F8/F9 | 說「最近都睡不好、有點孤單」（medium）；另測高風險句 | medium：`care_alerts` 落一筆、Telegram **不推**；high/urgent：落一筆 + Telegram 測試 chat 收到。長者端**全程陪伴語氣、無監控感** |
| S6 | 打字 → Care Alert | F10/F11 | 打字 medium / high 風險句 | 同 S5 對應分級行為（`source=companion_chat`） |
| S7 | 管理者端刷新 | W1/W5/W6/W10 | caregiver_web 以 super_admin / caregiver 登入後刷新 | 看得到 Care Alert 列表（含 S5/S6 新增）；caregiver 只看授權住民；可更新 alert 狀態；不卡「正在以管理者身分載入資料…」、無 marketplace 501 |
| S8 | 失敗白話 | F12 | 暫時讓後端不可用再操作 | 顯示白話錯誤、**不 fallback mock**、不假裝成功 |
| S9 | log 去敏 | F15 | 觀察裝置 / 後端 log | 無 token / 完整 transcript / email / `DATABASE_URL` 值 |

> 安全紅線（同 PLAN §7 上方）：smoke 一律用測試帳號；報告不得出現 token / Telegram chat id / 完整對話 / 完整 email / DB 連線字串；缺環境就走 Plan-only、據實列 blocker，不假裝通過。

---

## 4. 實機執行結果

> ⚠️ 本 CR 由背景工程代理建立。**S1–S9 需在實體 iOS/Android 裝置 + 真麥克風 / WebRTC + 已部署正式後端上人工執行**，
> 代理環境無裝置，無法代跑 → 此區為 **PENDING（待人工執行）**。執行後請把逐項 pass/fail 填入
> `docs/E2E_SMOKE_TEST_REPORT.md` 的「Run #2 — CR-0066」區塊（含日期 / commit / 裝置型號 / OS 版本）。

| 項目 | 狀態 |
|---|---|
| Flutter URL 對齊（程式碼 + build 指令確認） | ✅ 已驗證（§1） |
| 殘留 localhost / 舊 Render URL 檢查 | ✅ 已驗證（§2） |
| Smoke checklist 補齊 | ✅ 已建立（§3 + REPORT Run #2 骨架） |
| S1–S9 實機 smoke | ⏳ PENDING（需人工於實機執行） |

---

## 驗收標準

1. 用 §1 指令 build 的 production app，啟動後實際連到 `https://ai-companion-app-7mb8.onrender.com`（可由 `/health` 行為與功能反推），不停在守門畫面。
2. §3 的 S1–S9 在實機逐項通過（或缺項據實列 blocker），結果記入 `docs/E2E_SMOKE_TEST_REPORT.md` Run #2。
3. 全程不出現工程錯誤字、不假裝成功、不污染正式資料。
