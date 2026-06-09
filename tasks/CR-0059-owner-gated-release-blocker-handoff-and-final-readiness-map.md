# CR-0059 — Owner-Gated Release Blocker Handoff and Final Readiness Map

## 1. 任務定位

本任務接續 CR-0058。

目前已完成：

- 授權鏈：CR-0039～CR-0045
- Store readiness 第一輪：CR-0046
- Logging redaction：CR-0047
- Mock 隔離與正式 AI/STT：CR-0048～CR-0049
- Companion persona / typed chat / voice Care Alert：CR-0050～CR-0052
- E2E smoke plan-only：CR-0053
- Transport security plan / blocked：CR-0054～CR-0055
- Marketplace / DailyCareTask production 隱藏與後端 fail-closed：CR-0056～CR-0057
- Store metadata / legal / identity / signing readiness：CR-0058

目前剩餘 blocker 大多不是 Claude 可單獨完成的程式工作，而是 owner-gated：

1. 正式 HTTPS 後端網域與 TLS。
2. 真 Firebase / PostgreSQL / OpenAI / Telegram。
3. 實體 iOS / Android 裝置 smoke。
4. App Store / Google Play 帳號與簽章。
5. 正式 Bundle ID / applicationId。
6. 品牌名、icon、screenshots。
7. Privacy Policy / Terms / Support URL。
8. 上架後台 metadata 與 Data Safety 表單。

本 CR 目標是產出最終交接地圖，把所有剩餘 blocker、owner action、可重啟 CR、不可假完成事項整理成一份明確的 release handoff。

---

## 2. 本次目標

完成 owner-gated release handoff：

1. 彙整所有已完成 CR 狀態。
2. 彙整所有尚未解除的 release blockers。
3. 區分：
   - Claude 可做
   - owner 必須提供
   - 真環境才能驗證
   - post-release 才做
4. 建立最終 release readiness map。
5. 建立 owner action checklist。
6. 建立「環境齊後重啟哪個 CR」對照表。
7. 更新 STORE_RELEASE_CHECKLIST。
8. 不改 runtime code。
9. 不假裝 ready。
10. 不新增新功能 scope。

---

## 3. 必讀文件

請先閱讀：

- `CLAUDE.md`
- `docs/CHANGE_REVIEW.md`
- `docs/STORE_RELEASE_CHECKLIST.md`
- `docs/E2E_SMOKE_TEST_PLAN.md`
- `docs/E2E_SMOKE_TEST_REPORT.md`
- `docs/TRANSPORT_SECURITY.md`
- `docs/APP_STORE_METADATA.md`
- `docs/GOOGLE_PLAY_DATA_SAFETY.md`
- `docs/RELEASE_SIGNING.md`
- `docs/STORE_ASSET_CHECKLIST.md`
- `docs/MARKETPLACE_PRODUCTION_DECISION.md`
- `docs/DAILY_CARE_TASK_PRODUCTION_DECISION.md`
- `docs/AUTHORIZATION_MODEL.md`
- `docs/CAREGIVER_WEB_AUTH.md`
- `docs/CAREGIVER_PROVISIONING.md`
- `docs/LOGGING_AND_REDACTION.md`

---

## 4. 先盤點

請先盤點：

1. 已完成 CR 清單與 commit。
2. P0 / P1 / P2 是否還有 code-level blocker。
3. 哪些 blocker 是 owner-gated。
4. 哪些 blocker 是 environment-gated。
5. 哪些 blocker 是 store-console-gated。
6. 哪些 blocker 是 post-release。
7. 哪些文件仍有 TODO。
8. 哪些設定仍不能上架。
9. 哪些功能被 production hidden。
10. 哪些功能不可在商店文案中宣稱。
11. 哪些 smoke test 未執行。
12. 哪些 build 未執行。
13. 哪些 security hardening 已 patch-ready 但未落地。

---

## 5. Release Handoff 文件

請新增：

- `docs/RELEASE_HANDOFF.md`

內容至少包含：

### 5.1 Completed Production Hardening

以表格列出：

- CR 編號
- 名稱
- 狀態
- commit
- 解決的 blocker
- 是否需真環境再驗證

### 5.2 Remaining Release Blockers

分成：

#### Owner Decision Blockers

- 正式 App 名稱
- Bundle ID / applicationId
- icon / adaptive icon
- screenshots
- privacy policy URL
- terms URL
- support URL / email
- developer account
- content rating
- review notes

#### Infrastructure Blockers

- HTTPS backend
- TLS certificate
- production database
- Firebase production project
- OpenAI production key
- Telegram production bot / chat mapping
- CORS production origin
- caregiver_web production hosting

#### Device Smoke Blockers

- iOS device smoke
- Android device smoke
- Realtime WebRTC smoke
- Care Alert medium/high/urgent smoke
- Telegram smoke
- caregiver_web scope smoke

#### Store Console Blockers

- App Store Connect metadata
- Google Play Console metadata
- Data Safety form
- Privacy nutrition labels
- release signing
- app review test account

#### Post-release Scope

- Marketplace PG 化 / 金流合規
- DailyCareTask PG 化 / AI Vision proof
- caregiver_web Firebase popup login
- email auto-claim
- DB unique index hardening
- reactivate link endpoint
- full analytics polish

### 5.3 Restart Map

列出環境齊後重啟：

- `CR-0053 Execute`：真環境 E2E smoke
- `CR-0055 Execute`：transport patch + device smoke
- `CR-0058 Owner completion`：identity / icon / legal / signing
- `CR-0059 Final readiness update`：handoff refresh
- `CR-0060 Release Candidate Final Regression`

---

## 6. Final Readiness Matrix

請建立一個 readiness matrix：

欄位：

- Area
- Current status
- Owner needed
- Claude can do next
- Release blocker?
- Evidence document

範例 area：

1. Auth / authorization
2. Care Alert
3. Realtime voice
4. Typed chat
5. Memory
6. Logging / privacy
7. Marketplace
8. DailyCareTask
9. Transport security
10. Firebase
11. PostgreSQL
12. Telegram
13. iOS app identity
14. Android app identity
15. Legal URLs
16. Store metadata
17. Release signing
18. Screenshots
19. Data Safety
20. E2E smoke

---

## 7. Owner Action Checklist

請建立 owner checklist。

每項需包含：

- Action
- Why needed
- Where to put result
- Related CR
- Blocking level

例如：

```md
- [ ] 提供正式 Privacy Policy URL
  - Why: App Store / Google Play 上架必填，App 內 LegalConfig 也需要。
  - Put in: LegalConfig + APP_STORE_METADATA + STORE_RELEASE_CHECKLIST
  - Related CR: CR-0058
  - Blocking: release blocker
```

---

## 8. 不可假完成清單

請明確列出不可假完成事項：

1. 不可假裝真環境 smoke 通過。
2. 不可填假 privacy policy URL。
3. 不可填假 support URL。
4. 不可用 debug keystore 當正式簽章。
5. 不可保留 production cleartext / arbitrary loads 送審。
6. 不可把 marketplace / daily-care 寫成已正式啟用。
7. 不可使用真個資截圖。
8. 不可把 Care Alert 寫成醫療診斷。
9. 不可把 super_admin token 給一般照護人員。
10. 不可上架前啟用 mock。

---

## 9. 文件需求

請新增：

- `docs/RELEASE_HANDOFF.md`

請更新：

- `docs/STORE_RELEASE_CHECKLIST.md`
- `docs/CHANGE_REVIEW.md`
- `docs/E2E_SMOKE_TEST_REPORT.md` if needed
- `docs/APP_STORE_METADATA.md` if needed
- `docs/GOOGLE_PLAY_DATA_SAFETY.md` if needed

---

## 10. 測試與 build

本 CR 原則上 docs-only。

若只改 docs：

- 不需跑單元測試。
- 需明確回報 docs-only，runtime 未改。

若有任何 code/config 改動：

- Flutter / backend / caregiver_web 相關測試需跑。

---

## 11. 限制

本 CR 不得：

1. 修改 runtime code，除非發現明確文件錯誤需要同步 config。
2. 偽造 owner 已完成事項。
3. 偽造 smoke 通過。
4. 填假 URL。
5. 填假 Bundle ID / applicationId。
6. 宣稱 hidden features 已啟用。
7. 宣稱醫療診斷。
8. 提交 secret。
9. 擴大新功能 scope。
10. 把 post-release 功能拉進 release blocker。

---

## 12. 驗收標準

完成後必須符合：

1. `docs/RELEASE_HANDOFF.md` 已建立。
2. 所有 owner-gated blocker 明確。
3. 所有可重啟 CR 明確。
4. 所有 post-release scope 明確。
5. Store checklist 更新。
6. CHANGE_REVIEW 更新。
7. 沒有假完成。
8. 沒有 runtime code change，或若有則測試通過。
9. 下一步 owner action 明確。
10. 專案目前狀態可交接給組員 / 指導老師 / 後續開發者。

---

## 13. 完成回報格式

請用以下格式回報：

```md
## CR-0059 完成回報

### 1. 本次目標
-

### 2. 修改檔案
-

### 3. 已完成 hardening 摘要
-

### 4. Remaining blocker 分類
-

### 5. Owner action checklist
-

### 6. Restart map
-

### 7. Post-release scope
-

### 8. 文件更新
-

### 9. 測試與 build 結果
-

### 10. 正式版風險檢查
- 是否假裝 smoke 通過：
- 是否填假 URL：
- 是否宣稱 hidden feature：
- 是否宣稱醫療診斷：
- 是否提交 secret：
- 是否誤標 release ready：

### 11. 下一個建議 CR
-
```
