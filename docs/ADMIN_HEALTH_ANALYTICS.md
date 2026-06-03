# 管理者端健康分析儀表板（CR-0030）

> 本文件說明 caregiver_web「健康分析」儀表板的內容、**資料來源真實性**與非醫療定位，
> 供開發、Demo 與評審問答使用。核心原則：**誠實標註**——不以假資料偽裝，真實資料不足時
> 明確顯示「資料不足」。

---

## 1. 功能目的

讓管理者端不只看 Care Alert 警示，還能整合呈現每位長者的：

1. 生理健康分析（睡眠、互動、提醒 / 用藥 / 喝水 / 運動完成度）
2. 心理健康分析（情緒穩定度、風險訊號、建議照護行動）
3. 情緒分析歷史（情緒時間軸）
4. 遊戲認知退化指標（認知分數趨勢）
5. 長者個人健康摘要（profile + 上述彙整）
6. 非醫療診斷提示

並能向評審清楚說明每一項的資料**來自哪裡、是否真實**。

---

## 2. 正式資料流

```text
長者對話 / 情緒分析 / Care Alert / 任務紀錄 / 遊戲紀錄
        ↓
後端分析彙整 API（/api/admin/overview、/elders、/elders/:id 與子路由）
        ↓
（健康分析子路由目前未加 requireAdmin；使用者帳戶 API 才強制權限，見 CR-0029）
        ↓
彙整生理、心理、情緒、遊戲退化指標，並標註資料真實性 dataSource
        ↓
caregiver_web 健康分析儀表板顯示（含非醫療提示與資料不足空狀態）
```

---

## 3. 資料來源真實性（誠實原則，最重要）

每個健康指標回應都帶 `dataSource` 標註，前端據此顯示標籤或「資料不足」：

| dataSource | 含義 | 前端顯示 |
| --- | --- | --- |
| `measured` | 真實量測 / 真實紀錄（保留欄位，未來接真實資料用） | 「真實紀錄」標籤 |
| `reference` | **示範種子長者**的可重現參考指標（非真實量測，僅供畫面展示） | 「示範參考資料」標籤 |
| `insufficient` | 真實長者目前尚無此類真實資料 | 「資料不足」空狀態（不捏造） |

### 目前各類資料的真實狀態（誠實揭露）

| 項目 | 真實長者 | 示範種子長者 | 說明 |
| --- | --- | --- | --- |
| 長者名單 / Profile | ✅ 真實 | 示範種子 | 來自 PostgreSQL `elders`（無則 JSON，皆空時用示範種子） |
| **Care Alert** | ✅ **真實** | （依實際） | 來自 `careAlertStoreService`，是每位長者最真實的訊號 |
| 生理 / 生活指標 | ⛔ 資料不足 | 參考（reference） | 無感測器 / 無真實寫入流程 → 真實長者顯示資料不足 |
| 情緒分析歷史 | ⛔ 資料不足 | 參考（reference） | 情緒「每輪」即時分析有做，但尚未持久化成每人歷史序列 |
| 遊戲認知退化 | ⛔ 資料不足 | 參考（reference） | 小遊戲分數尚未回傳後端持久化 |

> 「示範種子長者」只在系統完全沒有真實長者時出現（讓 Demo 畫面不空）。
> 對真實長者，凡無真實資料一律顯示「資料不足」，**不以假資料填充**。

### 仍存在的 fallback（誠實記錄，未宣稱全 PostgreSQL 化）

- `elders` 來源：PostgreSQL 優先，否則 `data/elders.json`，皆空才用示範種子。
- 生理 / 情緒 / 遊戲的「參考資料」由確定性產生器（`healthMetrics.js`，以 elderId 為種子、
  可重現）供給，**僅供示範種子長者**，不代表真實長者狀態。
- 真實資料的寫入位置已備妥（`emotion_history` / `elder_health_metrics` /
  `game_cognitive_metrics` 三張表，見 `007_create_health_metrics.sql`），但目前尚無寫入流程；
  接上後 `dataSource` 即可升級為 `measured`。

---

## 4. API（沿用 CR-0007 既有契約 + CR-0030 新增標註）

| Endpoint | 說明 |
| --- | --- |
| `GET /api/admin/overview` | 六指標總覽（含情緒異常 / 認知退化長者數） |
| `GET /api/admin/elders` | 長者摘要列表 |
| `GET /api/admin/elders/:elderId` | 個人完整分析（profile + careAlerts + physio + psych + emotionHistory + gameMetrics） |
| `GET /api/admin/elders/:elderId/physio` | 生理序列 + summary + `dataSource` |
| `GET /api/admin/elders/:elderId/emotion` | 情緒序列 + dominantEmotion + abnormal + `dataSource` |
| `GET /api/admin/elders/:elderId/game-metrics` | 遊戲序列 + trend + abnormal + `dataSource` |

CR-0030 新增（加性）：各健康指標回應新增 `dataSource`；個人分析另含 `emotionDataSource`。
真實長者無真實資料時 `series: []` 且 `dataSource: "insufficient"`。

> 敏感資料保護：健康分析 API 不回傳 email / token / password 等；使用者帳戶相關的
> 遮蔽與權限見 `docs/ADMIN_USER_MANAGEMENT.md`（CR-0029）。

---

## 5. 管理者端畫面

- 健康分析頁頂端有**非醫療 + 資料來源說明**橫幅。
- 每個分析區塊：
  - 有資料 → 顯示指標，並標「示範參考資料 / 真實紀錄」。
  - 無真實資料 → 顯示「資料不足，待累積更多真實紀錄後再顯示」。
- UI 與既有 caregiver_web 風格一致（沿用 metric-card / bar-row / badge）。

---

## 6. 非醫療定位

- 健康分析整合對話、情緒辨識與 Care Alert 等紀錄，**僅供照護關懷參考，並非醫療診斷**。
- 「情緒異常 / 認知退化」為輔助觀察標記，非疾病判定，不使用「確診 / 診斷 / 病人」等字眼。

---

## 7. 測試

- 後端 `backend/stt_proxy`（`npm test`）：
  - `adminAnalysisService.test.js`：真實長者 → `dataSource:"insufficient"` 且序列為空；
    示範種子長者 → `dataSource:"reference"` 且序列非空、回應不含工程字樣。
  - `adminEndpoint.test.js`：六條 admin 路由 200 / 未知 elderId 404。
- caregiver_web（`node --test caregiver_web/admin_health_analytics.test.js`）：
  非醫療橫幅、五區塊標題、資料來源標籤 / 資料不足處理、不顯示敏感欄位。

---

## 8. 評審問答

**Q：管理者端除了警示，還能看到什麼分析？**
能看到每位長者的生理、心理、情緒歷史、遊戲認知退化指標與個人健康摘要，並整合該長者的真實 Care Alert。

**Q：這些分析資料從哪裡來？是不是假資料？**
長者名單與 Care Alert 是真實資料。生理 / 情緒歷史 / 遊戲指標目前只有「示範種子長者」會顯示
可重現的參考資料（明確標示「示範參考資料」）；真實長者若無真實紀錄，會顯示「資料不足」，
我們不以假資料填充。

**Q：情緒變化有沒有歷史紀錄？**
情緒辨識在每輪對話即時進行（反映在 Care Alert 與寵物行為）。每位長者的「情緒歷史序列」
持久化尚未接上（資料表已備妥），因此真實長者目前顯示資料不足。

**Q：這是不是醫療診斷？**
不是。所有分析僅供照護關懷參考，非醫療診斷，畫面也有明確提示。

---

## 相關檔案

| 用途 | 檔案 |
| --- | --- |
| 分析聚合 + dataSource 標註 | `backend/stt_proxy/services/admin/adminAnalysisService.js` |
| 指標產生器（示範參考、確定性） | `backend/stt_proxy/services/admin/healthMetrics.js` |
| 長者來源（PG / JSON / 示範種子） | `backend/stt_proxy/services/admin/eldersSource.js` |
| 健康資料表（已備妥、尚未寫入） | `backend/stt_proxy/db/migrations/007_create_health_metrics.sql` |
| 管理端畫面 | `caregiver_web/index.html`、`caregiver_web/app.js` |
| 後端測試 | `services/admin/adminAnalysisService.test.js`、`adminEndpoint.test.js` |
| 前端測試 | `caregiver_web/admin_health_analytics.test.js` |
