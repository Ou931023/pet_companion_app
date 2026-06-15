# CR-0086 — Caregiver Analytics Dashboard（長者狀態分析）

長照管理端（caregiver_web）新增「長者狀態分析」頁，讓照護者不只看即時警示，也能用近期趨勢掌握長者心理 / 生理 / 任務 / 互動狀況。後端新增一條 caregiver-capable 分析 API，沿用既有授權模型。

---

## 1. 功能目的

- 在後台用「卡片 + 統計 + 趨勢」快速看出單一長者「今天是否正常 / 近期是否變差」。
- 沿用既有授權邊界：caregiver 只能看被授權住民、super_admin 可看全部。
- **誠實原則**：有真實紀錄的項目用真實資料；尚無真實資料的項目顯示「資料不足」，不以假資料偽裝正式資料。

與既有「健康分析」頁的差異：健康分析是單一長者的完整深掘（生理 / 心理 / 情緒歷史 / 遊戲 / 警示）；本頁是「近期狀態彙整」，把 Care Alert 統計、任務完成、情緒、互動時間整理成一眼可讀的近期總覽，並提供 7 / 14 / 30 天區間。

---

## 2. 頁面內容

導覽列新增分頁「長者狀態分析」（位於「照護提醒」之後）。頁面包含：

1. **長者選擇器**：下拉選單，只列出登入者有權限的長者（caregiver = 授權住民、super_admin = 全部）；只有一位授權長者時自動選取。另有統計區間選擇（7 / 14 / 30 天）與重新整理。
2. **今日總覽**：今日警示數、區間警示數、任務完成率、最近情緒、最近風險等級、最近互動時間。
3. **Care Alert 統計**：low / medium / high / urgent 各次數、總警示數、高風險比例 `(high+urgent)/total`、最近一次警示時間；無警示顯示「近期沒有警示紀錄」。
4. **任務與簽到狀況**：吃藥 / 喝水 / 運動完成率長條、整體完成率、未完成任務數、簽到狀態與最近簽到時間。
5. **情緒趨勢**：近期情緒列表 + 資料真實性標籤；無真實資料顯示「資料不足」。
6. **遊戲認知退化指標**：近期趨勢；無足夠紀錄顯示「目前尚無足夠遊戲紀錄」。
7. **寵物照護狀態**：目前後台無資料來源，顯示空狀態說明（後續可擴充）。

載入中 / 空資料 / 401（登入失效）/ 403（無權限）/ 一般錯誤皆有白話提示，不顯示 raw exception、stack trace 或 HTTP 工程字串。

---

## 3. API 路徑與權限規則

### `GET /api/caregiver/analytics`

- **中介層**：`resolveAdminAuthContext`（caregiver-or-super_admin；Bearer = 共享 `ADMIN_API_TOKEN` → super_admin，或 Firebase idToken → caregiver）。
- **Query**：`elderId`（必填）、`rangeDays`（選填，預設 7，夾在 1..90，非法值回 7）。
- **權限**：
  - super_admin → 可查任一 `elderId`。
  - caregiver → 經 `authz.assertCanAccessResident(authContext, elderId)`；跨住民 → 403（fail-closed）。
- **回應**：
  - `401 { ok:false, error:"missing_admin_token" }`（未帶 token）/ `401 invalid_session`（無效 token）。
  - `403 { ok:false, error:"forbidden" }`（caregiver 跨住民）。
  - `400 { ok:false, error:"elder_id_required" }`（缺 elderId）。
  - `200 { ok:true, elderId, rangeDays, generatedAt, summary, emotionTrend, emotionDataSource, careAlertStats, taskStats, gameMetrics, petStatus }`。
  - `500 { ok:false, error:"caregiver_analytics_failed" }`。

授權與既有 `/api/care-alerts`、`/api/admin/elders`、`/api/admin/daily-care-tasks` 完全相同的模型（`resolveAdminAuthContext` + `authorizationService`），無新增授權機制。

### 長者選擇器資料來源

沿用既有 `GET /api/admin/elders`（caregiver-capable，後端依授權住民過濾），前端以 `authHeaders()`（含 caregiver token）呼叫，故 caregiver 只會在選單看到授權住民。

---

## 4. 資料來源（依現有資料表，未新增 schema）

| 區塊 | 來源 | 真實性 |
|---|---|---|
| Care Alert 統計 / 今日 + 區間警示 / 最近風險 | `care_alerts`（`careAlertStoreService.listAlerts`，risk 權威四級 low/medium/high/urgent） | **真實** |
| 任務完成率 / 依類型 / 未完成數 | `daily_care_tasks`（`dailyCareTaskStore.listTasksForAdmin`，status `completed` 計完成） | **真實**（視該住民是否有任務資料） |
| 簽到狀態 / 最近簽到 | 由 `daily_care_task_submissions` 最近提交推估（無獨立「簽到」資料表） | 真實提交時間，**簽到語意為 proxy** |
| 情緒趨勢 | `adminAnalysisService.getElderAnalysis().emotionHistory` + `emotionDataSource` | 示範長者=`reference`；真實長者目前無真實寫入流程 → `insufficient` |
| 遊戲退化 | `adminAnalysisService.getElderAnalysis().gameMetrics`（含 `dataSource`） | 同上，真實長者 → `insufficient` |
| 寵物照護狀態 | 後端目前無資料來源（寵物狀態保存在長者端本機） | `available:false` 空狀態 |

聚合邏輯集中在 `backend/stt_proxy/services/admin/caregiverAnalyticsService.js`（純函式可注入資料、可單元測試），route 只做授權與組裝。

---

## 5. 空資料策略

- 每個區塊都有獨立空狀態：警示「近期沒有警示紀錄」、任務「沒有日常任務紀錄」、情緒 / 遊戲「資料不足 / 尚無足夠紀錄」、寵物「後台尚未串接」。
- API 在無資料時回 `200` + 全 0 / `null` / `insufficient`，不丟例外、不洩漏其他住民資料。
- 未知 elderId（super_admin 查不存在住民）回空狀態而非 404，避免洩漏住民是否存在。

---

## 6. 測試結果

- 後端新增：
  - `services/admin/caregiverAnalyticsService.test.js`（單元，注入資料、無 DB）：rangeDays 夾值、Care Alert 分桶 / 高風險比例 / 今日 + 區間計數、任務完成率 / 簽到 proxy、空狀態不捏造、情緒 / 遊戲 dataSource。
  - `services/admin/caregiverAnalyticsEndpoint.test.js`（真 HTTP）：未登入 401、缺 elderId 400、caregiver 授權 200 + 形狀 + Care Alert 統計、caregiver 跨住民 403、super_admin 任一 200、無資料空狀態、rangeDays 非法回 7。
- 前端新增：`caregiver_web/analytics_dashboard.test.js`（靜態原始碼檢查）：分頁 / 區塊 / 橫幅、走 `/api/caregiver/analytics`、caregiver-capable、showView 懶載入、空狀態 / 401 / 403 白話、無敏感欄位。
- 結果：
  - 後端 `npm test` **592 passed / 0 failed**、`npm run check` exit 0。
  - 前端 `node --test caregiver_web/*.test.js` **108 passed / 0 failed**（含既有 101 + 新 7）。

---

## 7. 已知限制

- **簽到為 proxy**：目前無獨立簽到資料表，簽到狀態以「當日是否有任務證明提交」推估。日後若新增 check-in 表可替換。
- **情緒 / 遊戲對真實長者多為「資料不足」**：`emotion_history` / `game_cognitive_metrics` 資料表已存在但目前無真實寫入流程；示範種子長者會顯示 `reference` 標籤資料（非真實量測，已明確標註）。
- **寵物狀態尚未串接**：寵物互動資料目前保存在長者端 App 本機，後端無來源，頁面顯示空狀態。
- `daily_care_tasks.elder_id` 為 TEXT（無 FK），可能為示範字串；統計以實際資料為準。
- 本 CR 未改 Telegram、Realtime 語音主流程、長者端 Flutter UI、既有 API 形狀與 DB schema。
