# CR-0086 — Caregiver Analytics Dashboard

## 目標

新增／完善長照管理端的「長者狀態分析」頁面，讓照護者不只看得到即時警示，也能用趨勢資料掌握長者近期心理、生理、任務與互動狀況。

本 CR 的重點是補強展示與正式產品化所需的後台分析能力：

1. 照護者可以在後台看到長者的整體狀態總覽。
2. 可以查看情緒趨勢與 Care Alert 統計。
3. 可以查看任務完成率與簽到狀況。
4. 可以查看遊戲退化指標或互動表現趨勢。
5. 分析頁必須沿用既有授權模型，不得讓照護者看到未授權住民資料。
6. 不得破壞既有警示管理、使用者管理、照護人員管理、住民授權功能。

---

## 背景

目前 caregiver_web 已具備：

- Care Alert 警示列表
- 照護者／管理者登入狀態
- 使用者管理
- 照護人員管理
- 住民授權指派
- 基本授權邊界

但目前後台比較偏「事件列表」，缺少「長期觀察」能力。正式展示時，老師可能會問：

> 長照人員除了收到警示，怎麼看長者是否長期變差？

因此需要新增一個分析頁，讓照護者可以從趨勢圖、統計卡片與任務完成狀況，看出長者近期狀態。

---

## 範圍

### 本 CR 要做

- 新增 caregiver_web 分析頁。
- 新增或擴充後端 API，提供分析資料。
- 分析資料必須依照登入者權限篩選。
- 分析頁支援空資料狀態。
- 分析頁支援載入中與錯誤狀態。
- 補文件與測試。
- 更新 `docs/CHANGE_REVIEW.md`。

### 本 CR 不做

- 不重新設計整個 caregiver_web。
- 不改登入系統主流程。
- 不改 Care Alert 通知規則。
- 不改 Telegram 推播。
- 不改長者端 App UI。
- 不新增大型資料科學模型。
- 不做真實醫療診斷結論。
- 不讀 `.env`。
- 不使用 mock 覆蓋正式資料流程。

---

## 頁面名稱

後台新增頁面建議名稱：

```text
長者狀態分析
```

或：

```text
健康分析
```

導覽列建議順序：

```text
警示管理
長者狀態分析
使用者管理
照護人員管理
住民授權
```

若目前 caregiver_web 導覽名稱不同，請依既有命名風格整合。

---

## UI 內容建議

### 1. 長者選擇器

分析頁頂部需有長者選擇器。

功能：

- super_admin：可選所有長者。
- caregiver：只能選自己被授權的長者。
- 若只有一位授權長者，可自動選取。
- 無授權長者時，顯示空狀態。

顯示內容建議：

```text
長者姓名 / elder_id / 最近更新時間
```

若沒有姓名，使用 elder_id 或既有匿名顯示規則。

---

### 2. 今日總覽卡片

至少顯示以下統計卡：

```text
今日警示數
7 日警示數
今日任務完成率
最近一次情緒
最近一次風險等級
最近互動時間
```

可依現有資料調整，但畫面上至少要讓照護者快速看到「今天是否正常」。

---

### 3. 情緒趨勢

顯示最近 7 天或 14 天情緒趨勢。

建議資料：

```text
date
mood / emotion label
score / confidence
```

畫面可以先用簡單折線、長條或清單呈現。

若目前沒有圖表套件，不要引入過重套件；可以用簡單卡片或 HTML/CSS 條狀視覺完成。

可顯示：

```text
開心 / 平穩 / 低落 / 焦慮 / 疲倦
```

實際 emotion label 以後端資料為準。

---

### 4. Care Alert 統計

顯示最近 7 天或 14 天警示統計。

內容：

```text
low 次數
medium 次數
high 次數
urgent 次數
總警示數
最近一次警示時間
```

可額外顯示：

```text
高風險比例 = (high + urgent) / total
```

如果沒有警示，顯示：

```text
近期沒有警示紀錄
```

不要顯示工程錯誤或空白畫面。

---

### 5. 任務與簽到狀況

顯示日常照護任務完成狀況。

建議內容：

```text
吃藥完成率
喝水完成率
運動完成率
簽到狀態
最近一次簽到時間
未完成任務數
```

如果目前資料表只有部分任務資料，請先根據現有 daily care task / reminder / check-in 資料實作可取得的部分，並在文件中註明目前資料來源。

---

### 6. 遊戲退化指標

顯示拼圖遊戲或認知互動表現。

建議內容：

```text
最近一次遊戲時間
最近完成時間
錯誤次數
近 7 次平均完成時間
是否比前期變慢
```

若目前尚無完整遊戲歷史資料，請採漸進式設計：

- 後端 API 欄位可保留 `gameMetrics`。
- 前端顯示「目前尚無足夠遊戲紀錄」。
- 不要偽造資料。
- 若已有本地或後端遊戲紀錄，則接入真實資料。

---

### 7. 寵物照護狀態

顯示長者目前寵物狀態，用於連結長者互動狀況。

建議內容：

```text
心情
飽足度
親密度
最近互動時間
目前寵物種類
```

若資料只存在前端本地，後台無法取得，請不要硬做假資料；可先顯示從後端取得得到的項目，並在文件列為後續可擴充。

---

## 後端 API 建議

請依現有後端架構新增或擴充 API。

建議路由：

```text
GET /api/caregiver/analytics
```

或依現有命名慣例：

```text
GET /api/admin/resident-analytics
```

實際路徑請以現有 `server.js` 與權限 middleware 命名風格為準。

### Query 參數

```text
elderId
rangeDays
```

範例：

```text
GET /api/caregiver/analytics?elderId=xxx&rangeDays=7
```

### 權限要求

- 必須驗證登入者。
- caregiver 只能查自己被授權的 elderId。
- super_admin 可查所有 elderId。
- 未登入回 401。
- 無授權回 403。
- elderId 不存在或無資料時，不應洩漏敏感資訊。

請優先沿用現有 helper，例如：

```text
requireAdmin
requireCaregiverOrAdmin
assertCanAccessResident
filterAlertsByAuthorizedResidents
```

實際名稱以專案現況為準。

---

## API 回傳格式建議

請以現有專案 API response style 為準。若沒有固定格式，可參考：

```json
{
  "ok": true,
  "elderId": "elder_xxx",
  "rangeDays": 7,
  "generatedAt": "2026-06-15T00:00:00.000Z",
  "summary": {
    "todayAlertCount": 0,
    "rangeAlertCount": 2,
    "taskCompletionRate": 0.75,
    "latestEmotion": "neutral",
    "latestRiskLevel": "low",
    "lastInteractionAt": "2026-06-15T09:30:00.000Z"
  },
  "emotionTrend": [
    {
      "date": "2026-06-15",
      "emotion": "neutral",
      "score": 0.72
    }
  ],
  "careAlertStats": {
    "low": 1,
    "medium": 1,
    "high": 0,
    "urgent": 0,
    "total": 2
  },
  "taskStats": {
    "completed": 3,
    "total": 4,
    "completionRate": 0.75,
    "checkInStatus": "completed",
    "lastCheckInAt": "2026-06-15T18:00:00.000Z"
  },
  "gameMetrics": {
    "hasEnoughData": false,
    "message": "目前尚無足夠遊戲紀錄"
  },
  "petStatus": {
    "mood": null,
    "satiety": null,
    "intimacy": null,
    "petType": null
  }
}
```

若目前資料來源不足，欄位可以為 `null` 或空陣列，但前端必須能正常顯示。

---

## 資料來源盤點

實作前請先盤點現有資料來源，可能包含：

```text
care_alerts
emotion history
conversation logs
daily care tasks
check-in records
game history
users / elder_id
resident_caregiver_links
```

如果表名不同，以專案實際資料表為準。

請不要猜資料表；請用現有程式碼與 migration 檔確認。

---

## 前端實作要求

caregiver_web 需新增或更新：

```text
index.html
app.js
styles.css
```

或依目前 caregiver_web 架構調整。

要求：

- 新增分析頁入口。
- 支援長者選擇。
- 支援資料載入中。
- 支援空資料。
- 支援 401 / 403 友善提示。
- 支援 API 錯誤友善提示。
- 不顯示 raw exception、stack trace、HTTP 工程字串給使用者。
- 視覺風格沿用既有後台。

---

## 測試要求

請依現有測試架構補測。

### 後端測試至少涵蓋

1. 未登入查詢 analytics 回 401。
2. caregiver 查未授權 elderId 回 403。
3. caregiver 查授權 elderId 成功。
4. super_admin 查任一 elderId 成功。
5. 無資料時回傳空狀態，不崩潰。
6. Care Alert 統計 low / medium / high / urgent 正確。
7. rangeDays 參數合理處理，例如預設 7 天。
8. 不回傳其他住民資料。

### 前端測試／人工驗收至少涵蓋

1. 分析頁可以開啟。
2. 長者選擇器正常。
3. 載入中狀態正常。
4. 空資料狀態正常。
5. 401 / 403 友善提示正常。
6. 統計卡、情緒趨勢、警示統計、任務狀況區塊可正常顯示。
7. 不影響既有警示管理頁。

---

## 驗收標準

完成後需符合：

- caregiver_web 有「長者狀態分析」頁。
- caregiver 只能看到授權長者的分析資料。
- super_admin 可以查看所有長者。
- 頁面至少包含：
  - 今日總覽
  - 情緒趨勢
  - Care Alert 統計
  - 任務／簽到狀況
  - 遊戲退化指標或空資料提示
  - 寵物照護狀態或空資料提示
- API 不洩漏未授權住民資料。
- 前端無 raw error / stack trace / 工程字。
- `npm test` 或後端既有測試通過。
- `flutter analyze` 不需要執行，除非本 CR 觸及 Flutter。
- `docs/CHANGE_REVIEW.md` 新增 CR-0086 紀錄。
- 若有新增文件，放在 `docs/CAREGIVER_ANALYTICS_DASHBOARD_CR0086.md`。

---

## 建議執行指令

依專案現況選擇執行：

```bash
cd backend/stt_proxy
npm test
npm run test
npm run check
```

若 caregiver_web 沒有自動測試，請至少做人工 smoke test 並於 CHANGE_REVIEW.md 記錄。

---

## 文件要求

請新增：

```text
docs/CAREGIVER_ANALYTICS_DASHBOARD_CR0086.md
```

內容至少包含：

1. 功能目的。
2. 頁面內容。
3. API 路徑與權限規則。
4. 資料來源。
5. 空資料策略。
6. 測試結果。
7. 已知限制。

並更新：

```text
docs/CHANGE_REVIEW.md
```

新增：

```text
## CR-0086 — Caregiver Analytics Dashboard
```

---

## 注意事項

- 不要讀 `.env`。
- 不要改 Telegram 通知規則。
- 不要改 Realtime 語音主流程。
- 不要改長者端 Flutter UI，除非發現必要且需另行說明。
- 不要讓 caregiver 看到未授權住民資料。
- 不要用假資料偽裝正式資料。
- 無資料時請顯示友善空狀態。
- 本 CR 是正式展示補強，不是 demo-only mock page。
