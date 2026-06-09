# RELEASE_HANDOFF — AI 寵物陪伴系統 正式上架交接地圖

> 目的：把專案目前的 production 整備狀態、**所有剩餘 release blocker**、owner action、可重啟 CR、不可假完成事項，整理成一份可交接給組員 / 指導老師 / 後續開發者的單一地圖。
> 建立：CR-0059（docs-only，未改 runtime）。日期：2026-06-10。分支：`feat/auth-admin-backend`。
> 對照：`docs/STORE_RELEASE_CHECKLIST.md`（逐項清單）、`docs/CHANGE_REVIEW.md`（治理紀錄）、各專題 decision/plan 文件。

> ⚠️ 本檔**不**代表「已可上架」。剩餘 blocker 多為 **owner-gated**（需帳號 / 憑證 / 網域 / 素材 / 實機）。Claude（agent）可做的程式與文件硬化已大致完成；其餘需 owner 提供資源後才能落地或驗證。

---

## 1. 一句話現況

核心功能（語音陪伴 / 打字陪伴 / 長期記憶 / 情緒風險分析 / Care Alert 四級 / Telegram 通知 / 授權鏈 / caregiver_web / 隱私同意 / production 安全閘門）的**程式面已 production-hardened 並有測試覆蓋**（backend 495、flutter 541 綠）。**尚未上架**，因剩餘 blocker 為 owner-gated：HTTPS 後端、真憑證、實機 smoke、商店帳號 / 簽章、icon / 法律 URL。（**App identity 已於 CR-0061 拍板定值**：Bundle ID/applicationId `tw.edu.ncyu.im.aicompanion`、品牌 `AI Companion`/`AI陪伴`。）

---

## 2. 已完成 Production Hardening（CR-0039 → CR-0058）

| CR | 名稱 | 狀態 | commit | 解決的 blocker | 需真環境再驗證 |
|---|---|---|---|---|---|
| CR-0033 | Production-readiness 稽核報告 | ✅ docs | fe59ba4 | 盤點 P0/P1/P2 | — |
| CR-0034 | 環境治理：env 模組 / fail-fast / production guards / JSON policy | ✅ | 5ac0338…ef40233 | mock auth / JSON fallback production guard | 部分（fail-fast 真環境啟動） |
| CR-0038 | Realtime 失敗白話訊息（去工程術語） | ✅ | 5affb2f | UI 工程字眼 | 裝置 smoke |
| CR-0039 | care-alert / admin 路由 requireAdmin | ✅ | 6cc1d77 | 未授權讀取 | — |
| CR-0040 | resident-caregiver 授權 scope | ✅ | f70bdd7 | 跨住民資料 | — |
| CR-0041 | caregiver identity over HTTP + scoped admin session | ✅ | 39a8ae5 | 管理端身分 | — |
| CR-0042 | caregiver_web role-based auth UI + 401/403/empty | ✅ | 42b3e29 | 管理端 UX | — |
| CR-0043 | caregiver/resident-link provisioning（super_admin-only） | ✅ | 9a0ede5 | 帳號開通 | — |
| CR-0044 | caregiver_web provisioning UI | ✅ | 4c576cb | 開通 UI | — |
| CR-0045 | /notify caller auth + server-authoritative elderId + Flutter Bearer idToken | ✅ | 6ef2094 / 179de27 | 偽造 elderId | 真 Firebase smoke |
| CR-0046 | Store readiness 第一輪 docs + 移除 "demo" 描述 | ✅ | 62b15ee | metadata 草稿 | — |
| CR-0047 | Production logging redaction / PII 去識別化 | ✅ | deab409 | log 洩漏 | 真環境 log 抽查 |
| CR-0048 | MockTaigiAsrStrategy build-flavor 隔離 | ✅ | 1235854 | production mock | — |
| CR-0049 | production STT/AI 正式化、零 mock 實例、/api/companion/chat | ✅ | c4fe416 / 3d20c7b / bfa2317 / d178370 | mock fallback | 真 OpenAI smoke |
| CR-0050 | typed-chat 獨立陪伴 persona | ✅ | cd6160f | persona 工具化 | — |
| CR-0051 | typed chat 風險分析 + Care Alert 整合 | ✅ | 774b14f | 打字高風險不建 alert | 真環境 smoke |
| CR-0052 | 語音 Care Alert persist gate 對齊 medium+ | ✅ | 3e4c22b | 語音/打字記錄不一致 | 真環境 smoke |
| CR-0053 | E2E smoke plan + Plan-only report | ✅ docs | d2a8736 | smoke 計畫 | **是（Execute 待 infra）** |
| CR-0054 | CORS allow-all 修補 + transport patch-ready | ✅ / 🔁 | 0ad1f1f | production CORS allow-all | transport 待落地 |
| CR-0055 | transport patch 落地嘗試 = BLOCKED | 🔁 docs | 0fe13dc | （未解，前置不足） | **是（待 HTTPS+裝置）** |
| CR-0056 | Marketplace / DailyCareTask production 隱藏（A2/B2） | ✅ | 53d3cab | 半成品入口 | — |
| CR-0057 | 上述後端停用路徑收斂 501 not_enabled | ✅ | 95a5462 | production 500/誤映 | — |
| CR-0058 | store metadata / legal / identity / icon / signing readiness | ✅ docs | 7cefda6 | metadata/identity 整備 | owner 素材 |

> 測試基線（agent 親跑）：backend `npm test` **495/495** + `npm run check` exit 0；`flutter analyze` clean + `flutter test` **541/541**；caregiver_web `node --test` **90/90**。

---

## 3. 剩餘 Release Blockers（分類）

### 3.1 Owner Decision Blockers（需 owner 拍板，多不可逆）

| 項目 | 現況 | 不可逆 | 相關 CR |
|---|---|---|---|
| 正式 App 名稱（中英品牌） | ✅ `AI Companion` / 中文 `AI陪伴`（CR-0061 定值，已接線 plist/label） | 否（已一致） | CR-0061 |
| iOS Bundle ID | ✅ `tw.edu.ncyu.im.aicompanion`（CR-0061 定值，已寫入 pbxproj） | **是（上架後）** | CR-0061 |
| Android applicationId | ✅ `tw.edu.ncyu.im.aicompanion`（CR-0061 定值，已寫入 build.gradle.kts） | **是（上架後）** | CR-0061 |
| 開發者 / 發行者名稱 | ✅ 國立嘉義大學資訊管理學系專題第四組（CR-0061 定值） | — | CR-0061 |
| Privacy Policy URL | `legal_config.dart` `TODO_*`（有 isPlaceholder 防護） | — | CR-0058 |
| Terms URL / Support URL / Email | 同上 `TODO_*` | — | CR-0058 |
| 內容分級問卷 | ⛔ 未填 | — | CR-0058 |
| 第三方登入 / Sign in with Apple 決策 | Apple 登入為「即將推出」佔位 | — | CR-0058 |
| Review notes / 審查測試帳號策略 | 草稿（不可用 super_admin token） | — | CR-0058 |

### 3.2 Infrastructure Blockers（需 owner 部署 / 提供）

- 正式 HTTPS 後端網域 + 有效 TLS 憑證。
- 正式 PostgreSQL（pgvector）+ 跑 migration 001–014。
- Firebase 正式專案：✅ iOS/Android App 已以正式 Bundle ID `tw.edu.ncyu.im.aicompanion` 註冊，設定檔已落地（`GoogleService-Info.plist` BUNDLE_ID 對齊；`google-services.json` 含對應 client，**兩檔 gitignored 不進 git**，CR-0062）。🟡 待真機 Firebase Auth smoke 驗證。（提醒：Firebase 專案內仍留舊 `com.Andrew.*` Android app，功能無害，建議 owner 之後於 console 移除以清理。）
- OpenAI production key（Realtime/STT/chat/embedding）。
- Telegram production bot token + 授權 care chat 對應（**非**測試 chat）。
- `CORS_ALLOWED_ORIGINS` 設為 caregiver_web 正式 origin（CR-0054 後 middleware 已正確讀此值）。
- caregiver_web production hosting（HTTPS 同源 `/api` 或正式 API URL + `config.js`）。

### 3.3 Device Smoke Blockers（需實機 + 上述 infra）

- iOS / Android 實體裝置 smoke（Realtime 麥克風 + WebRTC 需真機）。
- Realtime 語音 / typed chat / Care Alert medium·high·urgent / Telegram high·urgent / caregiver_web scoped dashboard smoke。
- 對應 `docs/E2E_SMOKE_TEST_PLAN.md`（B/W/F/T 項）與 `docs/TRANSPORT_SECURITY.md §5`（T1–T9）。

### 3.4 Store Console Blockers（需商店帳號 + 後台操作）

- App Store Connect / Google Play Console App record + metadata 填寫。
- Google Play Data Safety 表單 / iOS App Privacy nutrition labels 後台填寫。
- Release signing：Android 正式 keystore（取代現行 debug key）+ Play App Signing；iOS 憑證 / provisioning（見 `docs/RELEASE_SIGNING.md`）。
- App review 測試帳號（審查專用 Firebase 帳號 + 預指派住民，**不可** hardcode、不可用 super_admin）。

### 3.5 Post-release Scope（明確排除於本次 release blocker）

- Marketplace PG 化 + 金流 / IAP 合規（CR-0042 候選；見 `docs/MARKETPLACE_PRODUCTION_DECISION.md`）。
- DailyCareTask PG 化 + AI Vision proof 儲存 + authz（見 `docs/DAILY_CARE_TASK_PRODUCTION_DECISION.md`）。
- caregiver_web 完整 Firebase popup 一鍵登入（目前貼 idToken）。
- email auto-claim（FU-CR-0043a）、email DB unique index（FU-CR-0043b）、reactivate-link endpoint（FU-CR-0044a）、dedicated requireSuperAdmin middleware。
- marketplace/daily-care 無 auth GET defense-in-depth 加固、orders 細節（CR-0057 已記，非阻擋）。
- Android namespace `com.example.*` → 正式（內部、非送審阻擋）。
- full analytics / 健康後台 demo 資料替換為真實序列。

---

## 4. Final Readiness Matrix（20 areas）

| # | Area | Current status | Owner needed | Claude can do next | Release blocker? | Evidence |
|---|---|---|---|---|---|---|
| 1 | Auth / authorization | ✅ 程式完成（CR-0039–45） | 真 Firebase 驗證 | — | 否（待 smoke 確認） | AUTHORIZATION_MODEL.md |
| 2 | Care Alert | ✅ 四級 + persist + 通知（CR-0051/52） | — | — | 否 | VOICE/TYPED_CHAT_CARE_ALERT_FLOW.md |
| 3 | Realtime voice | ✅ 程式完成 | 實機 smoke | — | 否（待 smoke） | E2E_SMOKE_TEST_PLAN §F |
| 4 | Typed chat | ✅ persona + 風險（CR-0050/51） | — | — | 否 | COMPANION_PERSONA.md |
| 5 | Memory | ✅ pgvector + 授權範圍 | 真 PG 驗證 | — | 否（待 smoke） | CLAUDE.md §6 |
| 6 | Logging / privacy | ✅ redaction（CR-0047） | 真環境 log 抽查 | — | 否 | LOGGING_AND_REDACTION.md |
| 7 | Marketplace | ✅ production 隱藏 + 501（CR-0056/57） | （post-release 才開放） | — | 否 | MARKETPLACE_PRODUCTION_DECISION.md |
| 8 | DailyCareTask | ✅ production 隱藏 + 501 | （post-release） | — | 否 | DAILY_CARE_TASK_PRODUCTION_DECISION.md |
| 9 | Transport security | 🔁 patch-ready 未落地 | HTTPS 後端 + 裝置 | 套用 patch（CR-0055 重啟） | **是** | TRANSPORT_SECURITY.md |
| 10 | Firebase | 🟡 App 已註冊正式 Bundle ID + 設定檔落地（CR-0062） | 真機 Auth smoke 驗證 | — | **是（待真機驗證）** | ENVIRONMENT_SETUP §3 |
| 11 | PostgreSQL | ⛔ 待 owner 正式 DB | DB + migration 跑 | — | **是** | ENVIRONMENT_SETUP §3 |
| 12 | Telegram | ⛔ 待 owner 正式 bot/chat | token + chat 對應 | — | **是**（high/urgent 通知核心） | CLAUDE.md §8 |
| 13 | iOS app identity | ✅ Bundle ID `tw.edu.ncyu.im.aicompanion` + 顯示名 `AI Companion`（CR-0061） | — | — | 否 | APP_STORE_METADATA §7 |
| 14 | Android app identity | ✅ applicationId `tw.edu.ncyu.im.aicompanion` + label `AI Companion`（CR-0061，namespace 依 owner 維持） | — | — | 否 | APP_STORE_METADATA §7 |
| 15 | Legal URLs | ⛔ TODO_*（有防護） | 真 URL + email | 填入後接線（CR-0058 completion） | **是** | legal_config.dart |
| 16 | Store metadata | 🟡 草稿完整、待真值 | 真 URL / 名稱 / 素材 | 填入後定稿 | **是** | APP_STORE_METADATA.md |
| 17 | Release signing | ⛔ release 仍用 debug key | keystore + 帳號 | signingConfig 接線（owner 提供 key 後） | **是** | RELEASE_SIGNING.md |
| 18 | Screenshots | ⛔ 無 | 去識別化素材 | — | **是** | STORE_ASSET_CHECKLIST.md |
| 19 | Data Safety | 🟡 草稿、財務=否一致 | 後台填寫 | 草稿維護 | **是**（後台） | GOOGLE_PLAY_DATA_SAFETY.md |
| 20 | E2E smoke | 🔁 Plan-only 未執行 | infra + 裝置 | 執行 + 寫 Run（CR-0053 重啟） | **是** | E2E_SMOKE_TEST_REPORT.md |

> 圖例：✅ 完成 / 🟡 interim 待真值 / 🔁 patch-ready 或 plan 待執行 / ⛔ 待 owner。

---

## 5. Restart Map（環境齊後重啟哪個 CR）

| 觸發條件（owner 備齊） | 重啟 / 新 CR | 動作 |
|---|---|---|
| 正式 HTTPS 後端 + TLS + 真 Firebase/PG/OpenAI/Telegram | **CR-0053 Execute** | 跑真環境 E2E smoke，寫 `E2E_SMOKE_TEST_REPORT` Run #2 |
| HTTPS 後端就緒 + 實體 iOS/Android 裝置 | **CR-0055 Execute** | 套用 `TRANSPORT_SECURITY §3` patch（iOS ATS / Android cleartext）+ 跑 T1–T9，可 rollback |
| owner 提供 Bundle ID / 品牌 / icon / 法律 URL / keystore | **CR-0058 Owner completion** | 接線 legal_config URL、改 Bundle ID/applicationId、補 adaptive icon、signingConfig 換正式 key、定稿 metadata |
| 上述大致完成後 | **CR-0059 refresh** | 更新本 handoff 與 matrix |
| 全部 blocker 解除、送審前 | **CR-0060 Release Candidate Final Regression** | 全量回歸（backend/flutter/caregiver_web）+ release build + 最終 smoke + checklist 全綠確認 |

---

## 6. Owner Action Checklist

- [ ] **提供正式 Privacy Policy URL**
  - Why：App Store / Google Play 上架必填；App 內 `legal_config.dart` 也需要。
  - Put in：`legal_config.dart` + `APP_STORE_METADATA` + `STORE_RELEASE_CHECKLIST`
  - Related CR：CR-0058 / CR-0059 restart
  - Blocking：release blocker
- [ ] **提供 Terms of Service URL / Support URL / 客服 Email**
  - Why：上架必填 + 同意流程入口。
  - Put in：`legal_config.dart`（取代 4× `TODO_*`）+ metadata
  - Related：CR-0058 — Blocking：release blocker
- [x] **拍板正式 Bundle ID / applicationId（建議機構反向網域）** — ✅ CR-0061：`tw.edu.ncyu.im.aicompanion`（嘉義大學反向網域）
  - Why：上架後**不可逆**；綁 Apple 憑證 / Firebase App / Sign in with Apple。
  - Done in：`ios/Runner.xcodeproj/project.pbxproj`（app + RunnerTests）+ `android/app/build.gradle.kts`（applicationId）。**待 owner**：Firebase 設定檔須以此 ID 建 App。
  - Related：CR-0061
- [x] **拍板最終品牌名（中英）** — ✅ CR-0061：`AI Companion` / `AI陪伴`；發行者「國立嘉義大學資訊管理學系專題第四組」
  - Done in：iOS CFBundleDisplayName + Android `android:label` + metadata §1/§2/§3/§7
  - Related：CR-0061
- [ ] **部署正式 HTTPS 後端 + TLS + 設 `CORS_ALLOWED_ORIGINS`**
  - Why：transport 收斂 + smoke + caregiver_web 的前置。
  - **How：見 `docs/BACKEND_DEPLOYMENT_GUIDE.md`（CR-0063，Render / Railway 步驟、env 清單、`db:migrate`、`/health`、`HOST=0.0.0.0` / `PGVECTOR_ENABLED=true` / SSL 三大雷區）。**
  - Put in：部署環境 / secret manager（**不進 git**）
  - Related：CR-0063 / CR-0053 / CR-0055 — Blocking：release blocker（infra）
- [~] **備正式 Firebase / PostgreSQL / OpenAI / Telegram 憑證**
  - Firebase：✅ iOS/Android App 已以 `tw.edu.ncyu.im.aicompanion` 註冊，`GoogleService-Info.plist` / `google-services.json` 已落地（gitignored，CR-0062）；待真機 Auth smoke。
  - ⛔ 仍待 owner：PostgreSQL（pgvector）、OpenAI production key、Telegram bot token + 授權 chat。
  - Put in：部署 env（**不進 git**），Firebase 設定檔不進 git
  - Related：CR-0062 / CR-0053 — Blocking：release blocker（infra，部分完成）
- [ ] **產生 Android 正式 keystore + 啟用 Play App Signing；換掉 release 的 debug key**
  - Put in：本機 / CI secret（`key.properties` 不進 git）；`build.gradle.kts` signingConfig 接線
  - Related：CR-0058 / `RELEASE_SIGNING.md` — Blocking：release blocker
- [ ] **Apple Developer 帳號 + iOS 憑證 / provisioning**
  - Related：`RELEASE_SIGNING.md` — Blocking：release blocker
- [ ] **正式 App icon（iOS 1024 + Android adaptive 前景/背景 + Play 512）+ 補 Android adaptive icon**
  - Put in：`ios/.../AppIcon.appiconset`、`android/.../mipmap-*`、`mipmap-anydpi-v26`
  - Related：`STORE_ASSET_CHECKLIST.md` — Blocking：release blocker
- [ ] **5 組去識別化 screenshots + Android feature graphic**
  - Related：`STORE_ASSET_CHECKLIST.md` — Blocking：release blocker
- [ ] **實體 iOS / Android 裝置跑 E2E + transport smoke**
  - Related：CR-0053 / CR-0055 — Blocking：release blocker（驗證）
- [ ] **商店後台 metadata + Data Safety / Privacy labels + 內容分級問卷 + 審查測試帳號**
  - Related：CR-0058 / `GOOGLE_PLAY_DATA_SAFETY.md` — Blocking：release blocker（console）
- [ ] **第三方登入 / Sign in with Apple 決策**
  - Related：CR-0058 — Blocking：release blocker（Apple 規範）

---

## 7. 不可假完成清單（紅線）

1. 不可假裝真環境 smoke 通過（未跑就寫 NOT EXECUTED / BLOCKED）。
2. 不可填假 Privacy Policy / Terms / Support URL。
3. 不可填假 support email。
4. 不可用 debug keystore 當正式簽章送審。
5. 不可保留 production cleartext / iOS arbitrary loads 送審。
6. 不可把 marketplace / daily-care 寫成已正式啟用。
7. 不可使用真使用者個資 / 真對話 / 真電話 / 真 email 截圖。
8. 不可把 Care Alert 寫成醫療診斷 / 確診 / 取代醫師。
9. 不可把 super_admin token 給一般照護人員。
10. 不可上架前 / 正式 build 啟用 mock。
11. 不可擅改不可逆的 Bundle ID / applicationId（未經 owner 拍板）。
12. 不可提交 .env / keystore / Firebase service account / Apple credentials。

---

## 8. 交接結論

- **程式面**：核心功能 + production 安全閘門 + 授權鏈 + 隱私治理已硬化，測試綠（backend 495 / flutter 541 / caregiver_web 90）。
- **agent 可做的**：已大致用盡；剩餘 agent 工作為「owner 提供資源後的接線」（填 URL、換簽章、套 transport patch、跑 smoke）或明確劃為 post-release 的 PG 化。
- **不可上架，因**：剩餘 blocker 全為 owner-gated（infra / 帳號 / 簽章 / 不可逆 identity / 法律 URL / 素材 / 實機驗證）。
- **下一步**：owner 依 §6 checklist 備齊資源 → 依 §5 Restart Map 重啟對應 CR → 最後 CR-0060 release candidate 全量回歸。
