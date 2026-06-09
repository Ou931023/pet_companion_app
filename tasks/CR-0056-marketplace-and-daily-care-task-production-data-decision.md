# CR-0056 — Marketplace and DailyCareTask Production Data Decision

## 1. 任務定位

本任務接續 CR-0055。

CR-0055 已確認：

- HTTPS / ATS / Android cleartext 落地卡 owner 基礎建設
- 真環境 E2E smoke 也卡 owner 基礎建設
- 因此下一步應轉向不依賴真裝置、真網域、真憑證的 production blocker

目前稽核殘留項之一：

> marketplace / dailyCareTask 仍存在 JSON-only 或 production guard 擋住的狀態。  
> 正式版不可讓 production 功能依賴 JSON fallback；若尚未 PG 化，則必須正式隱藏或停用，不可半成品出現在 production UI。

本 CR 目標是釐清 Marketplace 與 DailyCareTask 在 production 的正式策略：  
A. PG 化並正式啟用；或  
B. production 正式隱藏 / 停用，文件化為 post-release。

---

## 2. 本次目標

完成 marketplace / dailyCareTask production decision：

1. 盤點 marketplace 目前資料來源與 UI 入口。
2. 盤點 dailyCareTask 目前資料來源與 UI 入口。
3. 確認 production 是否仍被 guard 擋住。
4. 確認是否還有 JSON fallback。
5. 由 architecture-agent 裁決：
   - PG 化正式啟用
   - 或 production 隱藏 / 停用
6. 若選 PG 化：建立正式 migration / service / tests。
7. 若選隱藏：production UI 不顯示半成品入口，API fail-closed。
8. 不破壞 Care Alert、Realtime、Memory、Auth。
9. 更新 store checklist 與 CHANGE_REVIEW。

---

## 3. 必讀文件

請先閱讀：

- `CLAUDE.md`
- `docs/PRODUCTION_AUDIT_CR0033.md`
- `docs/CHANGE_REVIEW.md`
- `docs/STORE_RELEASE_CHECKLIST.md`
- `docs/ENVIRONMENT_SETUP.md`
- `docs/E2E_SMOKE_TEST_REPORT.md`
- backend marketplace service / route
- backend dailyCareTask service / route
- Flutter marketplace UI / service
- Flutter daily task UI / service
- caregiver_web marketplace / daily task UI if any
- `.env.example`

---

## 4. 先盤點

修改前請先盤點並回報：

1. marketplace 目前 API routes。
2. marketplace 目前 store service。
3. marketplace 是否使用 JSON file。
4. marketplace production guard 行為。
5. marketplace Flutter / web UI 入口。
6. dailyCareTask 目前 API routes。
7. dailyCareTask 目前 store service。
8. dailyCareTask 是否使用 JSON file。
9. dailyCareTask production guard 行為。
10. dailyCareTask Flutter / web UI 入口。
11. 是否已有 PostgreSQL table 可用。
12. 是否有 migration。
13. 哪些測試依賴 JSON。
14. production 若啟用會有哪些風險。
15. production 若隱藏會影響哪些 demo / 論文功能描述。

---

## 5. 架構裁決

請由 architecture-agent 或架構守門人先裁決：

### Marketplace

選一：

- A1：本版正式 PG 化並啟用。
- A2：本版 production 隱藏 / 停用，保留 development。
- A3：僅保留外部連結商城，不啟用內建商城交易。

### DailyCareTask

選一：

- B1：本版正式 PG 化並啟用。
- B2：本版 production 隱藏 / 停用，保留 development。
- B3：只保留提醒，不啟用照護任務審核。

裁決需寫入 `docs/CHANGE_REVIEW.md`。

---

## 6. 路線 A：PG 化正式啟用

若選擇 PG 化，請完成：

### 6.1 Migration

建立或補齊 tables，例如依實際需求：

Marketplace:

- marketplace_products
- marketplace_orders
- marketplace_order_items
- marketplace_sellers / care_center_products if needed

DailyCareTask:

- daily_care_tasks
- daily_care_task_submissions
- daily_care_task_reviews

要求：

1. migration 冪等。
2. 不破壞現有資料。
3. production 不再使用 JSON fallback。
4. development 可 seed 測試資料，但不能作為 production 主資料。

### 6.2 Backend Service

要求：

1. production 使用 PostgreSQL。
2. 缺 DATABASE_URL fail-fast。
3. JSON fallback 僅 dev/test 可用，且受 env guard 控制。
4. API response 保持 backward-compatible 或文件化變更。
5. 錯誤不回 stack / secret。
6. 權限需合理：
   - resident 只能看自己的任務
   - caregiver 只能看授權住民
   - super_admin 管理全域

### 6.3 Tests

至少測：

1. production 不讀 JSON。
2. PG service CRUD。
3. unauthorized 401。
4. unauthorized resident/caregiver scope 403。
5. authorized success。
6. missing DB fail-fast 或明確錯誤。
7. JSON fallback 僅 dev/test。

---

## 7. 路線 B：Production 隱藏 / 停用

若選擇本版不正式啟用，請完成：

1. production UI 隱藏入口。
2. production API fail-closed 或回明確 not_enabled。
3. development/test 保留功能。
4. 不顯示「商城可下單」等誤導文案。
5. store metadata 不宣稱未正式啟用的交易功能。
6. 論文 / 文件描述需改成「規劃」或「外部連結商城」。
7. 測試 production 不顯示入口。
8. 測試 production API 不會讀 JSON。
9. 更新 STORE_RELEASE_CHECKLIST。

---

## 8. UI / UX 要求

production 不得出現：

- demo 商品
- 假訂單
- 假付款
- 假審核
- mock task submission
- JSON seed data
- 工程錯誤
- 未完成但看似可交易的按鈕

若功能暫不開放，請用友善文案：

> 此功能正在準備中，正式開放後會再提供使用。

但不要讓上架審查以為已提供交易功能。

---

## 9. 測試需求

依裁決至少新增或更新：

### 如果 PG 化

1. backend PG service tests。
2. migration static tests。
3. production no JSON fallback tests。
4. auth/scope tests。
5. Flutter/caregiver_web UI tests if changed。

### 如果隱藏 / 停用

1. production UI hidden tests。
2. production API not_enabled tests。
3. no JSON read in production tests。
4. development still available tests if needed。
5. store checklist docs updated tests not required but must update docs。

---

## 10. 文件需求

請更新：

- `docs/CHANGE_REVIEW.md`
- `docs/STORE_RELEASE_CHECKLIST.md`
- `docs/APP_STORE_METADATA.md`
- `docs/GOOGLE_PLAY_DATA_SAFETY.md`
- `docs/E2E_SMOKE_TEST_REPORT.md` if status changes
- project architecture docs if feature status changes

如需要，新增：

- `docs/MARKETPLACE_PRODUCTION_DECISION.md`
- `docs/DAILY_CARE_TASK_PRODUCTION_DECISION.md`

文件需說明：

1. marketplace production 狀態。
2. dailyCareTask production 狀態。
3. 是否使用 PG。
4. 是否隱藏。
5. 是否仍需 owner 後續決策。
6. 上架描述不可宣稱未啟用功能。

---

## 11. 限制

本 CR 不得：

1. 讓 production 依賴 JSON fallback。
2. 用假資料充當正式資料。
3. 假裝商城交易已完成。
4. 假裝照護任務正式審核已完成。
5. 破壞 Realtime。
6. 破壞 Care Alert。
7. 破壞 Auth / scope。
8. 為了通過測試放寬 authorization。
9. 在 production UI 顯示 demo 商品或 mock task。
10. 提交 secret / .env。

---

## 12. 驗收標準

完成後必須符合：

1. marketplace production 狀態明確。
2. dailyCareTask production 狀態明確。
3. production 不依賴 JSON fallback。
4. production 不顯示半成品入口。
5. 若 PG 化，migration / service / tests 完整。
6. 若隱藏，UI / API / metadata 一致。
7. backend tests 通過。
8. Flutter / caregiver_web 若改動，相關測試通過。
9. STORE_RELEASE_CHECKLIST 更新。
10. CHANGE_REVIEW 更新。

---

## 13. 完成回報格式

請用以下格式回報：

```md
## CR-0056 完成回報

### 1. 本次目標
-

### 2. 架構裁決
- Marketplace：
- DailyCareTask：

### 3. 修改檔案
-

### 4. Marketplace 處理結果
-

### 5. DailyCareTask 處理結果
-

### 6. JSON fallback 狀態
-

### 7. Production UI / API 狀態
-

### 8. 測試結果
-

### 9. 文件更新
-

### 10. 正式版風險檢查
- marketplace production 是否仍讀 JSON：
- dailyCareTask production 是否仍讀 JSON：
- production 是否有 demo 商品：
- production 是否有 fake task：
- store metadata 是否誤宣稱：
- 是否破壞 auth/scope：
- 是否破壞 Care Alert / Realtime：

### 11. 殘留風險
-

### 12. 下一個建議 CR
-
```
