# E2E_SMOKE_TEST_REPORT — Production-like Smoke 執行紀錄

> 每次執行一個 Run 區塊（最新在上）。執行方式見 `docs/E2E_SMOKE_TEST_PLAN.md`。
> 紅線：報告不得出現 token / Telegram chat id / 完整對話 / 完整 email / `DATABASE_URL` 值；佐證用遮蔽值或去敏截圖。

---

## Run #1 — CR-0055 套用 transport patch 嘗試（NOT EXECUTED / BLOCKED）

| 欄位 | 內容 |
|---|---|
| 日期 | 2026-06-09 |
| 模式 | **Blocked（§12.2）— 未套用 patch、未執行裝置 smoke** |
| 執行者 | 工程代理（背景，無實體裝置 / 無正式 HTTPS 後端） |
| backend URL 是否 HTTPS | ✗ 未提供正式 HTTPS 後端（AppConfig 預設仍 `http://127.0.0.1:3001`，正式網域未確認） |
| iOS 裝置與版本 | 無 |
| Android 裝置與版本 | 無 |
| commit | 見本次 CR-0055 commit |

### 為何未套用 patch（§2 前置未齊 → §12.2 Blocked）

CR-0055 的核心交付是「套用 iOS/Android transport patch **並**跑 T1–T9 實機 smoke」。任務 §2 列 8 項前置，末行明訂「若未齊，請不要套用 patch，改成更新 blocker 報告」；§11.1 禁止「沒 HTTPS 後端就硬關 HTTP 並假裝成功」。本執行環境缺以下前置，故**未動 `Info.plist` / `AndroidManifest.xml`**：

| §2 前置 | 狀態 |
|---|---|
| 1. 正式 HTTPS backend URL | ✗ 未提供 |
| 2. 有效 TLS 憑證 | ✗ 未提供 |
| 3. production env 連 PostgreSQL/Firebase/OpenAI/Telegram | ✗ 無連線 |
| 4. iOS 實體裝置 | ✗ 無 |
| 5. Android 實體裝置 | ✗ 無 |
| 6. Flutter production API base URL 指向 HTTPS | ✗ 未設定（dev 預設 localhost） |
| 7. caregiver_web production origin / CORS allowlist | ✗ 無 prod `config.js`（僅 example） |
| 8. 可 rollback 的 git 狀態 | ✓ 乾淨（但因 1–7 不套用） |

> 關鍵：T3（Realtime 語音）/ T5 / T6（語音 Care Alert）本質上需**真機麥克風 + WebRTC**，背景代理無法執行；即使有 HTTPS 後端也無法達成 §12.1 的裝置 smoke 通過。故只能 §12.2。

### 當前 transport 狀態（未收斂，與 CR-0054 相同）

- iOS `ios/Runner/Info.plist`：`NSAllowsArbitraryLoads=true`（未動）。
- Android `android/app/src/main/AndroidManifest.xml`：`usesCleartextTraffic="true"`（未動）。
- `res/xml/network_security_config.xml`：未建立（patch 未套用）。
- ✅ 後端 CORS 修正（CR-0054 Batch 1）保留，未受影響。

### T1–T9 結果

全部 **NOT EXECUTED（BLOCKED）**——無實體裝置 + 無正式 HTTPS 後端，無法啟動任一項。就緒 patch 與 smoke 步驟見 `docs/TRANSPORT_SECURITY.md §3/§5`。

### Rollback

未啟用（未套用任何 patch，無需 rollback）。

### Release Blockers（本輪維持）

1. iOS ATS 全域明文 + Android cleartext 仍開（patch 就緒於 `TRANSPORT_SECURITY.md`，未套用）。
2. 正式 HTTPS 後端網域未提供 / 未確認就緒（§2#1–2）。
3. 無實體 iOS/Android 裝置可跑 T1–T9（§2#4–5）。
4. caregiver_web 正式 origin / CORS allowlist 未設（§2#7）。

### Owner Action Items（解除本 CR blocker）

- [ ] 部署正式 / staging 後端至 HTTPS 網域 + 有效 TLS 憑證。
- [ ] 設後端 `CORS_ALLOWED_ORIGINS` 含 caregiver_web 正式 origin；備 caregiver_web `config.js`。
- [ ] 備妥真 iOS + Android 實體裝置。
- [ ] production env 連 PostgreSQL/Firebase/OpenAI/Telegram。

### 下一次執行步驟（前置齊備後）

1. 套用 `TRANSPORT_SECURITY.md §3.1`（Android）+ §3.2（iOS），建議一平台一 commit（便於 §8 rollback）。
2. 以正式 HTTPS 網域 `flutter build ios/apk --release --dart-define=API_BASE_URL=https://...`。
3. 真機跑 T1–T9；任一 T1–T7 transport 相關失敗 → 依 §8 rollback、記錄去敏失敗摘要。
4. 結果寫入本檔「Run #2」並更新 `STORE_RELEASE_CHECKLIST` 對應 BLOCKER 行。

> 本輪未套用任何 patch、未連任何真服務、未產生需清理資料、未假裝通過。

---

## Run #0 — 計畫建立（NOT EXECUTED / Plan-only）

| 欄位 | 內容 |
|---|---|
| 日期 | 2026-06-09 |
| 模式 | **Plan-only（未執行真環境 smoke）** |
| 執行者 | 工程代理（背景，無真憑證 / 無實體裝置） |
| backend commit | 見本次 CR-0053 commit（`git log` 對照） |
| app commit | 同上 |
| 環境 | 無（未連任何真 Firebase / PostgreSQL / OpenAI / Telegram） |
| 裝置 | 無真 iOS / Android 裝置 |

### 為何未執行（誠實說明）

本輪由背景工程代理建立計畫，該執行環境**不具備**下列任一項，且受專案紅線約束（不可讀 `.env`、不可貼 secret、不可假裝通過）：

- 真 Firebase 專案憑證與測試帳號（resident / caregiver / super_admin）。
- 真 PostgreSQL（含 pgvector）連線。
- 真 OpenAI API key。
- 真 Telegram Bot token + 測試 chat id。
- 真 iOS / Android 實體裝置（Realtime 麥克風 / WebRTC 需實機）。
- 正式 HTTPS 後端網域。

故所有 §2–§5 項目狀態為 **PENDING（待真環境執行）**，無任何「通過」可宣稱。

### 逐項狀態（全 PENDING）

| 區塊 | 項目 | 狀態 |
|---|---|---|
| Backend | B1–B13 | PENDING（需真 DB / OpenAI / Firebase / Telegram） |
| caregiver_web | W1–W12 | PENDING（需真 Firebase 帳號 + 後端 + 網域） |
| Flutter App | F1–F15 | PENDING（需 production build + 真裝置 + 真後端） |
| ATS / Cleartext | A1–A5 | PENDING **且 A1 已知為 BLOCKER**（見下） |

### 已可由靜態盤點確認（非 smoke、但對執行有用的事實）

> 以下是 CR-0053 靜態程式碼盤點結果，**不等於 smoke 通過**，只是降低執行時的未知。

- ✅ 後端 production fail-fast 已實作（`config/env.js validateProductionEnv` / `assertProductionEnvOrExit`）：缺 `DATABASE_URL` / `OPENAI_API_KEY` / `CORS_ALLOWED_ORIGINS` / Firebase 服務帳戶 / `ADMIN_API_TOKEN` 即 `exit(1)`；顯式 `ALLOW_JSON_FALLBACK=true` / `ALLOW_MOCK_SERVICES=true` / `REQUIRE_AUTH=false` 拒絕啟動；啟動摘要全遮蔽（`describeMaskedConfig`）。→ B1 / B2 / B6 / B7 / B13 有程式基礎。
- ✅ `GET /health` 存在（回 status / hasOpenAiKey / realtimeModel / time）。→ B5。
- ✅ migration 001–014 齊全（含 013 `resident_caregiver_links`、014 `users.status`），有 `db/migration013.test.js` / `migration014.test.js`；`npm run db:migrate` = `node db/migrate.js`。→ B4 有單元基礎，仍需真 DB 跑冪等。
- ✅ Telegram 推播門檻 `TELEGRAM_NOTIFY_LEVELS={high,urgent}`（`telegramNotifyService.js`），medium 不推；語音與打字 persist 皆 medium+（CR-0051/0052）。→ B11 / B12 / F8–F11 邏輯已就位，待真 Telegram 驗證。
- ✅ Flutter `AppConfig` production 強制關閉 mock / demo / dev panel，`isApiBaseUrlProductionSafe` 守門。→ F2–F5 有程式基礎。
- ⛔ **iOS `NSAllowsArbitraryLoads=true`、Android `usesCleartextTraffic="true"` 仍未收斂** → A1 為 release BLOCKER。

### CR-0054 後續更新（傳輸安全）

- ✅ 後端 CORS allow-all 缺口已修（CR-0054 Batch 1）：middleware 改經 `resolveCorsOrigins`，production fail-fast 同源；backend 473/473。→ 計畫 §2 B-CORS 相關項風險下降（仍待真環境 smoke 確認正式 origin 放行/非白名單擋）。
- 🔁 iOS ATS / Android cleartext 收斂 patch 已就緒（CR-0054 Batch 2，`docs/TRANSPORT_SECURITY.md`），**未套用 runtime**；A1–A5 仍 PENDING，落地需 HTTPS 後端 + 裝置 smoke 後另開 CR。

### Release Blockers（本輪確認 / 維持）

1. **未跑真環境端到端 smoke**（本輪 Plan-only）——上架前必須完成一輪 Execute（至少計畫 §7 最小通過集）。Owner：專案負責人 + 具備真憑證者。
2. **ATS / cleartext 未收斂**（iOS 全域 arbitrary loads + Android cleartext）——需正式後端 HTTPS 後收斂並於真機驗證（計畫 §5）。屬 CR-0046 B3。
3. **正式 HTTPS 後端網域未確認就緒**（A1 前置）——未就緒前 ATS 無法收斂、F1 無法用正式網域 build。
4. Google Play Data Safety / App Store Privacy 表單仍待依實際行為填寫送出（見 `docs/GOOGLE_PLAY_DATA_SAFETY.md`，非本 CR）。

### Owner Action Items（執行前置）

- [ ] 備妥真 Firebase 專案 + 3 類測試帳號（resident / caregiver / super_admin），完成 §1。
- [ ] 備妥真 PostgreSQL（pgvector）+ 跑 `npm run db:migrate`。
- [ ] 備妥真 OpenAI key、Telegram Bot token + **測試** chat id。
- [ ] 部署 staging / production 後端到 **HTTPS** 網域，設 `CORS_ALLOWED_ORIGINS`。
- [ ] 準備真 iOS + Android 裝置。
- [ ] 依計畫 §6 準備測試資料前綴與清理腳本（不提交真連線字串）。

### 下一次執行步驟（具體）

1. 補齊上方 Owner Action Items。
2. 後端：`APP_ENV=production node server.js`，先驗 B1（故意缺一個 env 看 fail-fast），再補齊驗 B2–B13。
3. caregiver_web：依 `CAREGIVER_PROVISIONING.md` 建 caregiver + link，跑 W1–W12。
4. Flutter：依 `ENVIRONMENT_SETUP §3.3` 以正式網域 build，真機跑 F1–F15。
5. ATS：正式 HTTPS 就緒後，依計畫 §5 收斂並真機驗證 A1–A5（保留 rollback）。
6. 將每項 pass/fail + 去敏 log 摘要寫入本檔新增的「Run #1」區塊。

> 本輪未污染任何資料、未連任何真服務、未產生任何需清理的測試資料。
