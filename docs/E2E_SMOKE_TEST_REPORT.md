# E2E_SMOKE_TEST_REPORT — Production-like Smoke 執行紀錄

> 每次執行一個 Run 區塊（最新在上）。執行方式見 `docs/E2E_SMOKE_TEST_PLAN.md`。
> 紅線：報告不得出現 token / Telegram chat id / 完整對話 / 完整 email / `DATABASE_URL` 值；佐證用遮蔽值或去敏截圖。

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
