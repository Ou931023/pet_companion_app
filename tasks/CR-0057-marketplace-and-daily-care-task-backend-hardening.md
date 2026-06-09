# CR-0057 — Marketplace and DailyCareTask Backend Hardening After Production Hide

## 1. 任務定位

本任務接續 CR-0056。

CR-0056 已完成：

- Marketplace production 策略裁決：A2，本版 production 隱藏 / 停用，保留 dev/test。
- DailyCareTask production 策略裁決：B2，本版 production 隱藏 / 停用，保留 dev/test。
- Flutter production 完全隱藏商城與今日任務入口。
- caregiver_web production 預設隱藏 marketplace / daily-care-task 分頁。
- production 不顯示 demo 商品、假訂單、假任務。
- Data Safety 不申報 marketplace 金流。
- 後端未改，既有 fail-closed 保留。

CR-0056 殘留兩個小型後端風險：

1. marketplace / daily-care GET 類路由仍需要補存取限制或更清楚的 production fail-closed。
2. `POST /api/marketplace/orders` production 目前可能以 throw / 500 形式失敗，應改為乾淨 `not_enabled` response。

本 CR 目標是補齊後端防禦縱深，讓 production 即使被直接打 API，也不會出現不乾淨錯誤、不會讀 JSON、不會洩漏資料。

---

## 2. 本次目標

完成 Marketplace / DailyCareTask 後端加固：

1. production marketplace API fail-closed。
2. production dailyCareTask API fail-closed。
3. `POST /api/marketplace/orders` production 回乾淨 `not_enabled`，不回 500。
4. GET 類 API 在 production 不讀 JSON、不回 demo data。
5. 需要 auth / scope 的路由補上適當限制。
6. development / test 保留既有能力。
7. 不破壞 CR-0056 UI 隱藏策略。
8. 不破壞 Realtime / Care Alert / Memory / Auth。
9. 補測試覆蓋 production direct API call。

---

## 3. 必讀文件

請先閱讀：

- `CLAUDE.md`
- `docs/CHANGE_REVIEW.md`
- `docs/MARKETPLACE_PRODUCTION_DECISION.md`
- `docs/DAILY_CARE_TASK_PRODUCTION_DECISION.md`
- `docs/STORE_RELEASE_CHECKLIST.md`
- `backend/stt_proxy/server.js`
- backend marketplace routes / services
- backend dailyCareTask routes / services
- `backend/stt_proxy/config/env.js`
- CR-0056 相關測試與文件

---

## 4. 先盤點

修改前請先盤點並回報：

1. marketplace routes：
   - GET products
   - GET orders
   - POST orders
   - 其他 marketplace API
2. marketplace service production guard。
3. marketplace JSON fallback 是否仍可能被 production 觸發。
4. dailyCareTask routes：
   - GET tasks
   - POST submission
   - review / status routes if any
5. dailyCareTask service production guard。
6. dailyCareTask JSON fallback 是否仍可能被 production 觸發。
7. 哪些路由目前不需 auth。
8. 哪些路由需要 resident / caregiver / super_admin scope。
9. 現有測試如何設定 APP_ENV。
10. CR-0056 UI 隱藏後是否仍有 client 呼叫這些 API。

---

## 5. Marketplace 後端需求

### 5.1 Production Fail-Closed

production 中 marketplace 內建交易功能應停用。

要求：

1. `GET /api/marketplace/products` 不回 demo seed。
2. `GET /api/marketplace/orders` 不回 demo / JSON data。
3. `POST /api/marketplace/orders` 回乾淨 `not_enabled`。
4. 不應 throw 成 500。
5. response 不含 stack trace。
6. response 不含 JSON file path。
7. 不讀 production JSON fallback。
8. 保留外部連結商城策略，不宣稱內建交易可用。

建議 response：

```json
{
  "error": "not_enabled",
  "message": "Marketplace is not enabled in production."
}
```

實際 status code 可由架構裁決，建議 403 或 501，但需一致並有測試。

### 5.2 Development / Test

development / test 可保留既有 seed / JSON 行為，但必須受 env guard 控制，不得影響 production。

---

## 6. DailyCareTask 後端需求

### 6.1 Production Fail-Closed

production 中 DailyCareTask 正式任務審核功能應停用。

要求：

1. GET tasks 不回 demo / JSON task。
2. POST submission 不接受 fake task submission。
3. review/status routes 不接受 production mock flow。
4. response 乾淨 `not_enabled` 或空陣列，需由架構裁決。
5. 不讀 production JSON fallback。
6. 不回 stack trace。
7. 不破壞 reminders 功能，reminders 不是 DailyCareTask。

### 6.2 Development / Test

development / test 可保留既有能力，但需有測試證明 production 不會走 JSON。

---

## 7. Auth / Scope 要求

請依路由語意補最小限制：

1. super_admin-only 管理路由需 requireAdmin。
2. caregiver 相關資料需走 caregiver scope。
3. resident 自己的任務資料需走 resident caller auth。
4. 若 production 功能停用，應先 fail-closed，再避免執行資料查詢。
5. 不得為了簡化而讓 unauthenticated caller 取得資料。

若本版完全停用該 API，仍需確保 direct call 不洩漏資料。

---

## 8. 測試需求

至少新增或更新 backend tests：

### Marketplace

1. production `GET /api/marketplace/products` 不回 demo seed。
2. production `GET /api/marketplace/orders` 不讀 JSON。
3. production `POST /api/marketplace/orders` 回 `not_enabled`，不是 500。
4. development/test 既有 marketplace 行為仍可用。
5. production response 不含 stack / file path。

### DailyCareTask

1. production GET daily-care-tasks 不回 demo task。
2. production POST submission 不接受 mock flow。
3. production 不讀 JSON fallback。
4. development/test 既有 dailyCareTask 行為仍可用。
5. reminders 不受影響。

### Auth / Scope

視路由實作至少測：

1. unauthenticated caller 不可取得敏感資料。
2. caregiver 不可跨 resident。
3. super_admin 行為符合裁決。
4. production fail-closed 發生在資料讀取前。

---

## 9. 文件需求

請更新：

- `docs/CHANGE_REVIEW.md`
- `docs/MARKETPLACE_PRODUCTION_DECISION.md`
- `docs/DAILY_CARE_TASK_PRODUCTION_DECISION.md`
- `docs/STORE_RELEASE_CHECKLIST.md`
- `docs/GOOGLE_PLAY_DATA_SAFETY.md` if behavior affects disclosure
- `docs/ENVIRONMENT_SETUP.md` if env behavior changes

文件需說明：

1. production direct API call 的行為。
2. marketplace orders 為何回 not_enabled。
3. DailyCareTask 與 reminders 的差異。
4. development/test 如何保留。
5. post-release PG 化的前置工作。

---

## 10. 限制

本 CR 不得：

1. 重新啟用 production marketplace UI。
2. 重新啟用 production DailyCareTask UI。
3. 讓 production 讀 JSON fallback。
4. 回 demo 商品 / 假訂單 / 假任務。
5. 假裝 PG 化已完成。
6. 破壞 reminders。
7. 破壞 Care Alert。
8. 破壞 Realtime。
9. 破壞 Auth / scope。
10. 為了通過測試放寬 authorization。
11. 回 stack trace / file path / sensitive data。

---

## 11. 驗收標準

完成後必須符合：

1. production marketplace direct API call 不讀 JSON。
2. production marketplace orders 回乾淨 not_enabled，不是 500。
3. production dailyCareTask direct API call 不讀 JSON。
4. production 不回 demo data。
5. development/test 既有能力保留。
6. reminders 不受影響。
7. backend tests 全綠。
8. CHANGE_REVIEW 已更新。
9. Store checklist 已更新。
10. 無 sensitive log / stack exposure。

---

## 12. 完成回報格式

請用以下格式回報：

```md
## CR-0057 完成回報

### 1. 本次目標
-

### 2. 修改檔案
-

### 3. Marketplace 後端加固
-

### 4. DailyCareTask 後端加固
-

### 5. Auth / scope 結果
-

### 6. JSON fallback 狀態
-

### 7. 測試結果
-

### 8. 文件更新
-

### 9. 正式版風險檢查
- marketplace production 是否仍讀 JSON：
- marketplace orders 是否仍 500：
- dailyCareTask production 是否仍讀 JSON：
- production 是否回 demo data：
- reminders 是否受影響：
- auth/scope 是否放寬：
- 是否破壞 Realtime / Care Alert：

### 10. 殘留風險
-

### 11. 下一個建議 CR
-
```
