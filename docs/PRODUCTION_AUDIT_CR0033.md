# CR-0033 Production Audit Report

> 稽核日期：2026-06-08  ·  分支：feat/auth-admin-backend  ·  類型：Audit + Docs（無功能改動）
> 本報告反映「現況」。近期 CR-0036/0037/0038、CR-P2A/P2B 已完成的修補（consent gate+API、移除 mockFallback 造假正式登入、realtime 訊息白話化、Care Alert DB-優先+JSON fallback、notification/audit log）已計入，未重複列為未修。

## 1. Executive Summary

- Overall readiness: **尚未 production-ready**。陪伴 / Realtime / 情緒分級 / 醫療安全用語 / 長者友善 UI / consent gate 等核心已具雛形且品質佳，但「照護端授權邊界」與「正式環境隔離」尚未建立，仍有多項上架阻斷。
- Number of P0 findings: **4**
- Number of P1 findings: **7**
- Number of P2 findings: **6**
- Number of P3 findings: **6**
- Biggest production blockers:
  1. 照護端 / 管理端**讀取 API 多數未驗證**（住民情緒 / 生理 / 健康 / 遊戲指標）。
  2. **Care Alert API 無驗證、無住民-照護者授權邊界**（任何人可讀全部 alert、改狀態、觸發 Telegram）。
  3. **後端 auth mock 模式預設開啟**（Firebase Admin 未設定或 `AUTH_ALLOW_MOCK!=='false'` 時直接採信前端帶入的 firebaseUid → 身分冒用）。
  4. **缺正式環境 fail-fast 驗證 / build flavor**：缺 env 時靜默降級為 JSON fallback / mock auth，正式版無法明確隔離 dev 路徑。

## 2. Audit Method

- 靜態關鍵字掃描（rg）：`mock|demo|fake|fallback|hardcoded|TODO|測試|示範|假資料`、`OPENAI_API_KEY|TELEGRAM|CHAT_ID|DATABASE_URL|ADMIN_API_TOKEN|SECRET|PASSWORD`、`SHOW_DEV_PANELS|SHOW_DEMO_LOGIN|AUTH_ALLOW_MOCK|mockFallback|kDebugMode`、`確診|診斷|憂鬱症`、`console.log|.stack`，範圍涵蓋 `lib/`、`test/`、`backend/`、`caregiver_web/`、`docs/`、`ios/`、`android/`。
- 手動精讀關鍵檔：`lib/config/app_config.dart`、`lib/services/auth/session_api_service.dart`、`backend/stt_proxy/server.js`（路由與權限）、`services/auth/sessionService.js`、`services/admin/requireAdmin.js`、`services/careAlertStoreService.js`、`services/telegramNotifyService.js`、`services/marketplace/marketplaceStore.js`、`services/dailyCareTask/dailyCareTaskStore.js`、`caregiver_web/app.js`、`ios/Runner/Info.plist`、`android/app/build.gradle.kts`、`backend/stt_proxy/.env.example`、`.gitignore`、`pubspec.yaml`。
- 未讀取任何 `.env`（僅讀 `.env.example`，且報告中所有值已遮蔽）。
- 執行測試：見 §13。
- DB schema 對照：列出 `db/migrations/001..012` 與 CLAUDE.md §3.3 核心表清單比對。

## 3. Findings by Severity

### P0 — Production Blockers

| ID | Area | File / Path | Finding | Why It Blocks Production | Recommended Fix |
|---|---|---|---|---|---|
| P0-1 | Backend / Authz | `backend/stt_proxy/server.js` 行 923, 978, 988, 998, 1011, 1024, 1037 | `/api/admin/overview`、`/api/admin/elders`、`/api/admin/elders/:id`、`/api/admin/elders/:id/physio\|emotion\|game-metrics`、`/api/admin/daily-care-tasks` **未掛 `requireAdmin`**，任何能連到後端者皆可取得住民情緒 / 生理 / 健康 / 遊戲指標。 | 未授權存取住民敏感資料，違反 CLAUDE.md §9.11/§9.12；§5 明列「unauthenticated admin API」為 P0。 | 全部 admin 讀取 API 套用 admin 驗證；正式版改 admin 登入 + RBAC + 住民授權範圍過濾。 |
| P0-2 | Backend / Care Alert | `backend/stt_proxy/server.js` 行 374, 470, 486, 499 | `/api/care-alerts`、`/api/care-alerts/:id`、`/api/care-alerts/:id/status`、`/api/care-alerts/notify` **皆無驗證、無住民-照護者授權邊界**；`caregiver_web/app.js` 行 237/267/390 也未帶任何 auth header。 | 任意端可讀全部住民 Care Alert（含敏感摘要）、變更處理狀態、觸發 Telegram 推播 → 跨住民資料外洩、§5「Care Alert sent to wrong caregiver / cross-user leakage」P0。 | 加入照護者驗證；alert 查詢依授權 resident_caregiver_links 過濾；notify 對象由授權關聯推導。 |
| P0-3 | Backend / Auth | `backend/stt_proxy/services/auth/sessionService.js` 行 56-59 | `mockAllowed()` 預設 true；Firebase Admin 未 configured（或 `AUTH_ALLOW_MOCK!=='false'`）時走 mock 模式，**不驗 idToken、直接採信前端帶入 firebaseUid**。 | 正式環境若漏設 Firebase 或漏關 mock，等同任意帳號冒用（§2.1「mock user」「hardcoded」類）。無 production 強制驗證。 | 正式 build 強制 `firebaseAdmin.isConfigured()` 且 `AUTH_ALLOW_MOCK=false`；缺則啟動即 fail-fast。 |
| P0-4 | Backend / Env | `backend/stt_proxy/server.js`（無 startup 驗證）；多個 store | 啟動無 required-env 驗證 / 無 NODE_ENV=production gate；缺 `OPENAI_API_KEY` / `DATABASE_URL` / `ADMIN_API_TOKEN` / Firebase 時**靜默降級**（JSON fallback、mock auth、Realtime 執行期才失敗）。 | §5「production uses JSON fallback as main database」「app cannot build / silent degrade」P0；正式版未能以 flag/flavor 明確隔離 dev 路徑（違反 CLAUDE.md §2.2）。 | 新增 production 啟動驗證：缺關鍵 env 即退出；production 關閉 JSON fallback / mock auth。 |

### P1 — High Risk

| ID | Area | File / Path | Finding | Risk | Recommended Fix |
|---|---|---|---|---|---|
| P1-1 | Backend / CORS | `server.js` 行 136-148 | `ALLOWED_ORIGINS` 空（預設）時 **allow-all origin**。 | 正式環境瀏覽器端 CSRF / 跨站讀取風險。 | production 強制設定白名單，空值時拒絕瀏覽器來源。 |
| P1-2 | Backend / Authz | `services/admin/requireAdmin.js` | 單一共享 `ADMIN_API_TOKEN`，**無逐人 admin 登入 / 無 RBAC / 已驗證的 admin 端點也無住民授權範圍**。 | 任一持 token 者可見全部住民；無細粒度授權與稽核身分。 | 改 admin 帳號登入 + JWT + role/resident scoping。 |
| P1-3 | Notification | `services/telegramNotifyService.js` 行 82-95 | 全部 Care Alert 推送到單一 `TELEGRAM_CARE_CHAT_ID`，**非由授權 resident-caregiver 關聯推導**。 | 違反 CLAUDE.md §8.2「通知對象須來自授權關聯」；可能通知到非該住民的照護者。 | 通知對象依授權關聯查出對應 chat；保留 cooldown / log。 |
| P1-4 | Persistence | `careAlertStoreService.js`、`auth/sessionService.js`、`memory/memoryStore.js`、`consentStoreService.js`、`search/documentStore.js`（DB-優先+JSON fallback）；`marketplace/marketplaceStore.js`、`dailyCareTask/dailyCareTaskStore.js`（**JSON-only，無 DB 路徑**） | 多個 store 仍以 JSON 為正式降級或唯一來源。 | 違反 CLAUDE.md §3.3「正式版不可依賴 JSON file 作為主要資料庫」；JSON-only store 在正式版等同無持久化保證。 | 規劃逐表 PG 化；production 關閉 fallback；marketplace / dailyCareTask 補 DB。 |
| P1-5 | iOS / Network | `ios/Runner/Info.plist`（`NSAllowsArbitraryLoads=true`）；`lib/config/app_config.dart`（預設 `http://127.0.0.1:3001`） | ATS 全關 + 預設後端為 http localhost。 | App Store ATS 審查阻力；正式版需 https 與最小化例外。 | 後端走 https；移除全域 ATS 例外或加正當理由；production base url 走正式網域。 |
| P1-6 | Caregiver Web / Auth | `caregiver_web/app.js` 行 11, 645-652, 724 | Admin token 由使用者手動輸入並存 `localStorage`，**無真正 admin 登入 session**。 | XSS 可竊取 token；不符正式管理端權限控管（§3.4）。 | 改為正式 admin 登入流程 + 後端 session/JWT。 |
| P1-7 | Flutter / UI 用語 | `lib/controllers/conversation_controller.dart` 行 438, 442, 771-773 | STT 失敗時自動切換並向長者顯示「已為你切換到 **Mock STT**…」等工程字眼。 | 正式使用者不應看到 "Mock STT"（§2.1 禁字、CLAUDE.md §11.6）。 | 改白話文案（例：「語音剛剛不太順，我先換個方式繼續聽你說」），mock 切換邏輯 dev-only 隔離。 |

### P2 — Medium Risk

| ID | Area | File / Path | Finding | Risk | Recommended Fix |
|---|---|---|---|---|---|
| P2-1 | DB Schema | `backend/stt_proxy/db/migrations/001..012` | 對照 CLAUDE.md §3.3，**缺**：residents、caregivers、resident_caregiver_links、conversations、messages、emotion_events、care_alert_status_events、reminders、checkins、pet_profiles、pet_skins、game_sessions、notification_tokens、data_deletion_requests。現有覆蓋：pgvector、memory、search、companion_memories、users/elders、health_metrics、marketplace、consent_records、care_alerts、notification/audit logs。 | 核心關聯（授權邊界、對話、情緒事件、刪除請求）缺 schema，授權與資料治理無法落地。 | 依 §3.3 補 migration，先補 resident_caregiver_links 以支撐 P0-1/P0-2。 |
| P2-2 | Persistence / Demo data | `backend/stt_proxy/data/demoSearchTestCases.json`、`mockCrawledDocuments.json`、`crawled_documents.json`（git 追蹤中） | 搜尋種子 / demo / mock 資料已 commit 進版控。 | demo/mock 命名與資料混入正式 build（§2.2 須隔離）。 | 移到 dev-only seed / fixtures，正式 build 不載入。 |
| P2-3 | Android / Build | `android/app/build.gradle.kts` 行 30、`AndroidManifest.xml` 行 11 | `applicationId="com.Andrew.petCompanionApp"`（含個人名、大小寫混用）；`android:label="pet_companion_app"`。 | 非正式化品牌 ID / 顯示名；adaptive icon、release signing 未驗證。 | 正式化 applicationId / label / icon / signing config。 |
| P2-4 | Backend / Logging | `backend/stt_proxy/services/memoryExtractor.js` 行 171, 248-249 | `console.error` 輸出完整 error stack 與「sanitized input」。 | 正式 log 可能含敏感對話片段 / PII（§9.14）。 | production 降級日誌、去識別化、避免輸出輸入內容。 |
| P2-5 | Flutter / Mock 隔離 | `lib/app.dart` 行 66-68,167-204,261-292 | `MockAiService`/`MockSpeechToTextService`/`MockShopService`/`MockTaigiAsrStrategy` 永遠注入 provider tree（非 build flavor 隔離）。 | mock service 仍存在於正式 build（§2.2 要求隔離）。 | 以 build flavor / compile flag 隔離 mock，正式 build 不注入。 |
| P2-6 | Auth / Fallback | `lib/services/auth/session_api_service.dart` 行 84-122、`lib/models/auth_session.dart` 行 85 | `AuthSession.mockFallback()` 仍存在（CR-0037 後僅 `provider=='mock'` Demo 路徑使用，正式帳號已改丟例外）。 | 行為已收斂，但仍是需在正式版隔離的 demo 路徑。 | 以 flavor 隔離 Demo 登入路徑，正式 build 不可達 mockFallback。 |

### P3 — Low Risk

| ID | Area | File / Path | Finding | Risk | Recommended Fix |
|---|---|---|---|---|---|
| P3-1 | Metadata | `pubspec.yaml` 行 2 | `description: Ai companion pet demo for elderly care interactions.`（含 "demo"）。 | 商店 metadata 出現 demo 字樣。 | 改為正式描述（移除 "demo"）。 |
| P3-2 | iOS / Metadata | `ios/Runner/Info.plist` | `CFBundleName=pet_companion_app`、`CFBundleDisplayName=Pet Companion App` 未定案品牌名。 | 顯示名未正式化。 | 確定正式 App 名稱與在地化。 |
| P3-3 | Flutter / Logging | `lib/`（debugPrint 散布，voice_agent_controller 27 處等） | 大量 `debugPrint`。 | release log 噪音（非阻斷）。 | 統一 log 包裝，release 抑制。 |
| P3-4 | Flutter / Flags | `lib/config/app_config.dart` 行 13-29 | `SHOW_DEMO_LOGIN` / `SHOW_DEV_PANELS` 皆預設 false（良好），`loginAsDemoUser()` 能力保留。 | 預設安全；僅需確保正式 build 不開。 | 文件化並於 release 固定 false。 |
| P3-5 | Docs | `docs/DEMO_SCRIPT.md`、`docs/demo_architecture.md`、`docs/PGVECTOR_DEMO_SETUP.md`、`DEMO_TAIGI.md` | 多份文件仍以 demo 框架敘述。 | 與「正式產品」定位不一致。 | 後續補正式部署 / 隱私 / 上架文件。 |
| P3-6 | Realtime / Log | `lib/services/realtime_voice_service.dart` 內部 `_log` 含 RTCPeerConnection 等技術字 | 僅內部 debug log（不顯示給長者）。 | 非使用者可見，低風險。 | 維持現狀，release 抑制即可。 |

## 4. Findings by System Area

### 4.1 Flutter Elder App
- Realtime 為真實 WebRTC（`RTCPeerConnection`/`createOffer`/`setRemoteDescription`，無 fake transcript）。✅
- Consent gate（`ConsentGate`）於主流程前攔截，需同意才進 App。✅
- Dev panel（Realtime Diagnostics / Companion Debug）以 `AppConfig.showDevPanels` 隔離，預設隱藏。✅
- Demo 快速登入以 `SHOW_DEMO_LOGIN` 隔離，預設隱藏。✅
- 問題：mock services 永遠注入（P2-5）、STT 失敗向長者顯示 "Mock STT"（P1-7）、debugPrint 散布（P3-3）、預設後端 http localhost（P1-5）。

### 4.2 Backend
- 路由權限不一致：marketplace/users 端點有 `requireAdmin`，但 overview/elders/care-alerts 等敏感讀取無驗證（P0-1, P0-2）。
- Auth mock 預設開（P0-3）、無 startup env 驗證（P0-4）、CORS 預設 allow-all（P1-1）。
- 無 stack trace 回前端（錯誤一律回 `{success:false,error:<code>}`）✅；但 memoryExtractor console 仍印 stack/input（P2-4）。

### 4.3 PostgreSQL / pgvector / Persistence
- 既有 migration 001-012 覆蓋 memory/pgvector/users/elders/care_alerts/consent/notification/audit/marketplace/health_metrics。
- §3.3 多核心表缺（P2-1）；marketplace、dailyCareTask 為 JSON-only（P1-4）；其餘 store DB-優先 + JSON fallback（P1-4）。
- `GET /api/admin/users` 規定只走 PG、不做 JSON fallback（fail-closed）✅。

### 4.4 Caregiver Web
- 全部資料來自後端 API（無前端假資料）✅；含非醫療診斷免責提示（有測試守護）✅。
- Admin token 存 localStorage、無正式登入（P1-6）；care-alerts 與 elders 分析未帶 auth（受 P0-1/P0-2 牽連）。

### 4.5 Notification / Telegram
- Token / chatId 皆由 env 讀取、不寫死、不回前端、不寫 log ✅；缺設定回 `telegram_not_configured` ✅；有 cooldown 與 notification log ✅。
- 單一共享 chat、非授權關聯推導（P1-3）。

### 4.6 Realtime Voice
- 真實 WebRTC、API key 由後端代理（前端不持金鑰）✅；錯誤訊息白話化（CR-0038）✅；狀態機完整（idle/listening/thinking/speaking/error/reconnecting）✅。
- 無 P0/P1 真實性問題。Realtime 核心健康。

### 4.7 Memory
- 記憶綁定 user/elder，consent gate 前置，低品質過濾與 retriever 測試存在 ✅。
- 持久化仍含 JSON fallback（P1-4）；無跨住民洩漏的測試已部分覆蓋（`care_data_isolation_test`、`local_storage_isolation_test`、`pet_stats_isolation_test`）✅。

### 4.8 Emotion / Care Alert
- 四級 low/medium/high/urgent；摘要非診斷語氣，且有 `companion_prompt_builder.test.js`、`next_strategy_planner.test.js`、`care_alert_display.test.js`、`admin_health_analytics.test.js` 等測試守護診斷字眼 ✅（醫療安全用語**通過**）。
- 阻斷在授權邊界與持久化（P0-2、P1-4），非分級邏輯本身。

### 4.9 Privacy / Consent / Data Deletion
- Consent gate + consent API + `consent_records` migration ✅；帳號刪除入口（`/api/auth/delete` + 前端 `deleteAccount`）✅；audit log service + migration ✅；legal/consent content 存在（`lib/config/legal_content.dart`）✅。
- 缺：data_deletion_requests 表（P2-1）；third-party AI 資料流向揭露需確認文案完整度。

### 4.10 Store Readiness
- iOS：權限文案齊全且長者友善 ✅；但 ATS 全關（P1-5）、品牌名未定案（P3-2）。
- Android：applicationId / label 未正式化（P2-3）。
- 缺商店 metadata / 隱私政策 URL / data safety 文件（§11）。

### 4.11 Documentation
- 架構文件齊全（`PROJECT_ARCHITECTURE.md`、`CHANGE_REVIEW.md`、`TEAM_AGENTS.md`、`EMOTION_RECOGNITION.md`、`ADMIN_*`）✅。
- 仍多 demo 框架文件（P3-5）；缺正式部署 / 上架 / 隱私治理對外文件。

## 5. Demo / Mock / Fake Data Inventory

| File / Path | Type | Current Behavior | Production Risk | Follow-up CR |
|---|---|---|---|---|
| `lib/services/mock_ai_service.dart` 等 4 個 mock service | Mock service | 永遠注入 provider tree | 未隔離 dev 路徑 | CR-0040 |
| `lib/controllers/conversation_controller.dart` 行 416-442,771 | STT mock fallback | 失敗自動切 Mock STT 並顯示字樣給長者 | 工程字眼 + 假成功觀感 | CR-0039 |
| `lib/models/auth_session.dart` `mockFallback()` | Demo session | 僅 provider=='mock' Demo 路徑使用 | 需 flavor 隔離 | CR-0040 |
| `backend/stt_proxy/data/demoSearchTestCases.json` | Demo seed | 搜尋測試案例（git 追蹤） | demo 資料入正式 build | CR-0035 |
| `backend/stt_proxy/data/mockCrawledDocuments.json` | Mock seed | 搜尋來源 mock（git 追蹤） | mock 資料入正式 build | CR-0035 |
| `backend/stt_proxy/services/search/mockSearchProvider.js` | Mock provider | 搜尋降級 provider | 需確認正式不啟用 | CR-0035 |
| `lib/config/app_config.dart` `SHOW_DEMO_LOGIN` | Dev flag | 預設 false（隱藏 Demo 登入） | 低（已隔離） | — |

## 6. JSON Fallback Inventory

| File / Path | Data Type | Used In | Production Risk | Recommended Production Replacement |
|---|---|---|---|---|
| `services/careAlertStoreService.js` + `data/care_alerts.json` | Care Alert | /care-alerts*、/notify | DB 故障時降級 JSON（可運作但非權威） | PG care_alerts 為唯一來源，production 關 fallback |
| `services/auth/sessionService.js` + `data/users.json`,`elders.json` | 帳號 / 長者 | /api/auth/session | DB 未開時走 JSON | PG users/elders 為唯一來源 |
| `services/memory/memoryStore.js` + `data/companion_memories.json` | 長期記憶 | 記憶讀寫 | JSON fallback | PG + pgvector 唯一來源 |
| `services/consentStoreService.js` | Consent | /api/consent | JSON fallback | PG consent_records 唯一來源 |
| `services/search/documentStore.js` | 搜尋文件 | search | JSON | PG / 正式索引 |
| `services/marketplace/marketplaceStore.js` + `data/marketplace_*.json` | 商城 | /api/marketplace* | **JSON-only（無 DB）** | 補 PG marketplace（migration 009 已建表，service 未接） |
| `services/dailyCareTask/dailyCareTaskStore.js` + `data/daily_care_task*.json` | 日常照護任務 | /api/daily-care-tasks* | **JSON-only（無 DB）** | 補 PG 表與 service |

## 7. Debug / Dev UI Inventory

| File / Path | UI / Flag | Visible in Production? | Risk | Fix |
|---|---|---|---|---|
| `lib/screens/settings_screen.dart` 行 324-376 | Realtime Diagnostics / Companion Debug Panel | 否（`SHOW_DEV_PANELS` 預設 false） | 低 | 維持 flag 隔離 |
| `lib/widgets/companion_debug_panel.dart` | Debug rows（detectedEmotion 等） | 否（僅 dev panel 內） | 低 | 維持隔離 |
| `lib/screens/login_screen.dart` Demo 登入鈕 | `SHOW_DEMO_LOGIN` | 否（預設 false） | 低 | 維持隔離 |
| `caregiver_web/index.html` Admin token 輸入框 | 手動 token 欄位 | 是（管理端） | 中（無正式登入，P1-6） | 改正式 admin 登入 |
| `lib/` debugPrint | console log | 否（非 UI） | 低 | release 抑制 |

## 8. Hardcoded Sensitive / Identity Data Inventory

| File / Path | Data | Risk | Fix |
|---|---|---|---|
| （全專案掃描） | **未發現**寫死的 OpenAI / Telegram / DB / admin secret；全部走 `process.env` | — | 維持 |
| `backend/stt_proxy/.env` | 實際 env 檔存在於本機 | 已 `.gitignore` 且 **未被 git 追蹤**（已驗證 `git ls-files` 無此檔） | 維持不進版控；未讀取內容 |
| `ios/Runner/Info.plist` `CFBundleURLSchemes` | Google OAuth client ID（`com.googleusercontent.apps.****`） | 公開型 client ID，非 secret | 低風險，維持 |
| `backend/stt_proxy/.env.example` `ADMIN_API_TOKEN`/`TELEGRAM_*` | 僅變數名（範例檔） | 範例值已遮蔽，無真實值 | 維持 |
| git 追蹤之 runtime data | `crawled_documents.json` 等 3 檔 | 種子 / demo 資料（非 secret） | 移 dev-only（P2-2） |

> 本報告未貼任何真實 secret，全部遮蔽。未讀取 `.env`。

## 9. Production Environment Gaps

- Missing env validation：後端啟動無 required-env 檢查（缺 OPENAI_API_KEY/DATABASE_URL/ADMIN_API_TOKEN/Firebase 時靜默降級）。需 production fail-fast。
- Missing build flavor：Flutter / backend 皆無 dev/prod flavor 或 NODE_ENV gate 來隔離 mock / JSON fallback / Demo 登入。
- Missing production flags：無「production 關閉 JSON fallback」「強制真實 auth（AUTH_ALLOW_MOCK=false）」「強制 CORS 白名單」的集中開關。
- Missing deployment docs：缺正式部署 / https / DB 佈署 / 環境分離說明（現有多為 demo 文件）。

## 10. Privacy and Data Governance Gaps

- Consent：✅ 已具 consent gate + API + 記錄表（首次同意才進 App）。
- Memory control：✅ 記憶可查看 / 刪除 / 封存，綁定 user/elder；持久化仍含 JSON fallback（P1-4）。
- Account deletion：✅ `/api/auth/delete` + 前端入口。
- Data deletion：⚠ 缺 `data_deletion_requests` 表（P2-1），刪除請求未持久化追蹤。
- Audit log：✅ auditLogService + migration 012。
- Third-party AI disclosure：⚠ 需確認 consent / legal 文案是否完整揭露 OpenAI 等資料流向（CLAUDE.md §9.7）。

## 11. App Store / Google Play Gaps

- iOS：ATS 全關需收斂（P1-5）；品牌名 / icon / launch screen 定案（P3-2）；bundle id 正式化未驗證。
- Android：applicationId / label / adaptive icon / release signing 正式化（P2-3）。
- Store metadata：缺 screenshots / description / keywords / age rating / data safety 答案。
- Privacy policy：缺對外可存取的 privacy policy URL / support URL / contact email。
- Data safety：缺與實際資料蒐集一致的 data safety 申報文件。

## 12. Recommended Fix Order

1. CR-0034 — Production Environment & Config（startup env fail-fast、build flavor、production 關閉 JSON fallback / mock auth / 強制 CORS 白名單）。
2. CR-0035 — 後端授權邊界 Part 1：所有 care-alerts / admin 讀取 API 套用驗證（修 P0-1, P0-2 的「擋門」層）。
3. CR-0036 — resident_caregiver_links schema + 授權範圍過濾（care alert / elder 資料依授權住民）。
4. CR-0037 — 正式 auth 強化：production 強制 Firebase 驗證、AUTH_ALLOW_MOCK=false fail-fast（修 P0-3）。
5. CR-0038 — Caregiver Web 正式管理端登入（取代 localStorage token，修 P1-6）+ RBAC（P1-2）。
6. CR-0039 — Flutter UI 用語清理：移除 "Mock STT" 等工程字眼、STT 降級白話化（修 P1-7）。
7. CR-0040 — Mock / Demo 路徑 build-flavor 隔離（修 P2-5, P2-6, P2-2）。
8. CR-0041 — Telegram 通知對象由授權關聯推導（修 P1-3）。
9. CR-0042 — DB schema 補齊 §3.3 缺表 + marketplace / dailyCareTask PG 化（修 P2-1, P1-4 部分）。
10. CR-0043 — JSON fallback production 收斂（DB 為唯一來源、production disable fallback）。
11. CR-0044 — iOS ATS / https / 正式網域 + 品牌名（修 P1-5, P3-1, P3-2）。
12. CR-0045 — Android applicationId / icon / signing 正式化（修 P2-3）。
13. CR-0046 — Logging 去識別化 + release 抑制（修 P2-4, P3-3）。
14. CR-0047 — 隱私 / data deletion request 持久化 + 第三方 AI 揭露 + 上架 metadata / 文件。

## 13. Tests Run

| Command | Result | Notes |
|---|---|---|
| `flutter analyze` | ✅ No issues found（3.0s） | 0 issue |
| `flutter test` | ✅ All tests passed（476） | 全綠 |
| `cd backend/stt_proxy && npm run check` | ✅ EXIT 0 | 全部 `node --check` 通過 |
| `cd backend/stt_proxy && npm test` | ✅ pass 246 / fail 0 | node --test，不需真 DB / 真金鑰 |
| `cd caregiver_web && node --test *.test.js` | ✅ pass 51 / fail 0 | 純前端 DOM/邏輯測試 |
| `npm run lint`（backend） | ⏭ 未執行 | package.json 無 lint script |
| `flutter build ios/apk --release` | ⏭ 未執行 | 需簽章 / 較長，本稽核 CR 不做 build；列為後續 RC 前驗證 |

## 14. Files Changed in CR-0033

- `docs/PRODUCTION_AUDIT_CR0033.md`（新建，本報告）
- `docs/CHANGE_REVIEW.md`（追加 CR-0033 區段）
- **無任何程式碼 / 設定 / schema 改動**（本 CR 為純稽核 + 文件；所有清理項目以 finding 形式留給後續 CR）。

## 15. Remaining Risks

- 本稽核以靜態閱讀 + 自動化測試為主，**未**做動態滲透測試 / 真實 DB 端對端驗證；P0-1/P0-2 的實際可達性已由路由閱讀確認，但建議 CR-0035 落地時補整合測試。
- `flutter build --release` / iOS、Android 簽章 build 尚未驗證，RC 前必跑。
- 第三方 AI 揭露文案完整度需人工核對 legal/consent 內容。
- 本專案**尚非 production ready**；以上 P0/P1 全數修復並通過 release build 後，方可進入 RC 評估。
