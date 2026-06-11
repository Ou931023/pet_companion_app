# E2E_SMOKE_TEST_REPORT — Production-like Smoke 執行紀錄

> 每次執行一個 Run 區塊（最新在上）。執行方式見 `docs/E2E_SMOKE_TEST_PLAN.md`。
> 紅線：報告不得出現 token / Telegram chat id / 完整對話 / 完整 email / `DATABASE_URL` 值；佐證用遮蔽值或去敏截圖。

---

## Run #2 — CR-0069 Production E2E Smoke #2（含 Marketplace + Daily Care Tasks 已 production-enabled；部分 Execute，其餘 PENDING 待實機）

| 欄位 | 內容 |
|---|---|
| 日期 | 2026-06-11（API 層自動 smoke）／（填寫實機執行日期） |
| 模式 | **部分 Execute**：API 層 smoke（health / marketplace / daily-care / 管理端 auth gate / caregiver_web 旗標）已由代理實打正式端點驗證；S1–S9、M-dev、D-dev 實機與登入相關待人工執行 |
| 後端 URL | ✅ 已確認在線 `https://ai-companion-app-7mb8.onrender.com`（CR-0064/0065 現役 Render Web Service；本輪 `GET /health` 200） |
| caregiver_web | ✅ 已確認在線 `https://ai-companion-caregiver-web.onrender.com`（`/` 200，`featureFlags { marketplace:true, dailyCareTasks:true }`，`app.js?v=20260611-cr0068`） |
| Flutter build 指令 | `flutter run --release --dart-define=APP_ENV=production --dart-define=API_BASE_URL=https://ai-companion-app-7mb8.onrender.com`（URL 不含 `/api`） |
| app commit | `17da872`（本報告整理時 HEAD；實機請填當下 `git rev-parse --short HEAD`） |
| iOS 裝置 / 版本 | （填寫） |
| Android 裝置 / 版本 | （填寫） |

### A. 已由代理自動驗證（實打正式端點，唯讀 / 去敏佐證；2026-06-11）

| # | 檢項 | 結果 | 佐證（去敏） |
|---|---|---|---|
| A1 | 後端在線 + 無洩 key | ✅ PASS | `GET /health` → 200 `{status:"ok", hasOpenAiKey:true, realtimeModel:"gpt-realtime"}`（只回布林，不回 key） |
| A2 | Marketplace 商品 API（production-enabled） | ✅ PASS | `GET /api/marketplace/products` → 200 `{ok:true}`，15 筆種子商品 |
| A3 | Daily Care Tasks API（production-enabled, CR-0068） | ✅ PASS | `GET /api/daily-care-tasks?elderId=…` → 200 `{success:true, tasks:[]}`（不再 501 not_enabled；migration 016 已套用） |
| A4 | 管理端破壞性端點需授權 | ✅ PASS | `DELETE /api/admin/marketplace/orders/:id`（無 token）→ 401（auth gate 生效） |
| A5 | caregiver_web 上線 + 旗標開啟 | ✅ PASS | `/` 200；`featureFlags { marketplace:true, dailyCareTasks:true }`；`app.js?v=20260611-cr0068`（新版） |
| A6 | Marketplace 下單扣庫存（DB transaction） | ✅ PASS（CR-0067 驗收已實打） | 下單 200、庫存原子扣減、分潤正確（見 CR-0067 紀錄；本輪未重打以免留資料） |
| A7 | Daily Care 建立/列表/改狀態往返（DB） | ✅ PASS（CR-0068 驗收已實打） | create→list→PATCH completed 往返 200、狀態持久；測試資料已清除（見 CR-0068 紀錄） |

> Flutter 靜態：正式 URL 由 dart-define 注入，`isApiBaseUrlProductionSafe` 守門擋 localhost；無殘留舊 Render URL。`flutter test test/config/app_config_test.dart` 既往 9 passed。

### B. 待實機 / 登入相關逐項（填 pass/fail + 去敏佐證）

核心四主流程（對應 `tasks/CR-0066-*.md §3`）：

| # | 流程 | 結果 | 備註（去敏） |
|---|---|---|---|
| S1 | App 啟動指向正式後端 / 無 debug·demo·dev panel | ⏳ PENDING | |
| S2 | 長者登入（Google / Email） | ⏳ PENDING | |
| S3 | 語音對話狀態流轉正常（含台語） | ⏳ PENDING | |
| S4 | 打字對話自然回覆 | ⏳ PENDING | |
| S5 | 語音 → Care Alert（medium 不推 / high 推 Telegram） | ⏳ PENDING | |
| S6 | 打字 → Care Alert | ⏳ PENDING | |
| S7 | 管理者端刷新（alert 狀態更新、scoped 授權） | ⏳ PENDING | |
| S8 | 後端不可用時白話錯誤、不 fallback mock | ⏳ PENDING | |
| S9 | log 去敏 | ⏳ PENDING | |

Marketplace 實機 / 管理端（API 已綠 A2/A6，以下驗 UI 與管理流程）：

| # | 流程 | 結果 | 備註（去敏） |
|---|---|---|---|
| M1 | 長者端「照護商城」入口可見、商品列表顯示 15 筆（含分類色卡 placeholder） | ⏳ PENDING | 需 `--dart-define=ALLOW_MARKETPLACE_IN_PROD=true` build |
| M2 | 商品詳情 / 加入購物車 / 同中心單一規則 | ⏳ PENDING | |
| M3 | 建立訂單成功、訂單頁顯示金額與分潤 | ⏳ PENDING | |
| M4 | caregiver_web（super_admin + Admin Token）商品管理 / 訂單管理可看訂單、可改狀態、可刪除（CR-0067） | ⏳ PENDING | |

Daily Care Tasks 實機 / 管理端（API 已綠 A3/A7，以下驗 UI 與拍照 + AI Vision）：

| # | 流程 | 結果 | 備註（去敏） |
|---|---|---|---|
| D1 | 長者端「今日任務」不再「伺服器忙線中」、列表正常顯示 | ⏳ PENDING | |
| D2 | 拍照完成上傳（multipart）→ 任務狀態更新 | ⏳ PENDING | 需真機相機 + 觸發 AI Vision（OpenAI） |
| D3 | AI Vision 結果分支：passed→完成 / uncertain·failed→送查看（文案不宣稱劑量正確） | ⏳ PENDING | |
| D4 | 完成證明照片可於管理端查看 | ⏳ PENDING | 註：圖片存 runtime 檔，Render ephemeral 不跨 redeploy（已知限制） |
| D5 | caregiver_web 今日任務分頁顯示任務 + 最新 submission + 統計卡 | ⏳ PENDING | 強制刷新載入 `?v=20260611-cr0068` |

> 為何 A 以外未代跑：S3/S5/S6 / D2 需真機麥克風·相機 + WebRTC + AI Vision；S2/M*/S7/D5 需真登入帳號（resident / super_admin + Admin Token）。背景代理無實體裝置與真帳號，依 PLAN §0 / §7 紅線不假裝通過，保留 PENDING。

### 驗收標準（本輪通過定義）

- A1–A7 全 PASS（已達成）→ production 後端 / API 契約 / 旗標 / DB 平移在「服務層」就緒。
- 上架前最小通過集：S1–S9 全 PASS + M1–M4 全 PASS + D1–D5 全 PASS（實機 + 真帳號），任一 fail 記去敏摘要並開後續 CR。

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
