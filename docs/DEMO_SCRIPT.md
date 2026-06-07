# docs/DEMO_SCRIPT.md — 畢專 Demo 劇本與 5 分鐘展示流程

> 對應 CR-0005 Batch 3（Demo 劇本）+ Batch 4（5 分鐘流程）。
> 目標：讓任何組員照著這份文件，就能完整演示
> 「AI 寵物陪伴長者 → 偵測風險 → Telegram 通知 → 長照管理端處理」。
>
> 相關文件：`PROJECT_ARCHITECTURE.md`（架構真相）、`docs/CHANGE_REVIEW.md`（CR 紀錄）。

---

## 0. 一頁總覽（30 秒看懂這場 Demo）

| 我們想讓評審看到 | 怎麼呈現 |
| --- | --- |
| AI 寵物像真的在陪長者 | 長者用語音跟寵物聊天，寵物即時、溫暖回應 |
| 系統會默默留意長者狀況 | 後台把對話判斷成風險等級，長者端只看到「有人關心你」 |
| 出事會通知家人 | 高風險時 Telegram 即時推播給長照群組 |
| 家人 / 照護端能接手處理 | caregiver_web 看到提醒卡片，標記已查看 / 已處理 |

**三段式風險示範**：日常聊天（不通知）→ 持續觀察（只進管理端）→ 需通知（推 Telegram）。

---

## 1. Demo 前準備

### 1.1 需要啟動的服務

| 服務 | 啟動指令 | 確認 |
| --- | --- | --- |
| **Backend API（:3001）** | `cd backend/stt_proxy && npm start` | 終端機出現 `STT Proxy listening on http://0.0.0.0:3001` |
| **Caregiver Web（:8080）** | `cd caregiver_web && python3 -m http.server 8080` | 瀏覽器開 `http://127.0.0.1:8080/` 看到「長者關懷管理中心」 |
| **Flutter App（長者端）** | `flutter run`（iPhone 實機優先） | 首頁出現寵物與「想聊天就點我」語音按鈕 |

> caregiver_web 預設連 `http://127.0.0.1:3001/api`；
> 若用手機或另一台電腦看管理端，點頁面最下方「⚙ 連線設定」改成 `http://<Mac區網IP>:3001/api`。

### 1.2 環境變數檢查（只確認「有沒有設」，不要貼出實際值）

Backend `.env` 需要下列變數（值由負責人保管，**Demo 過程不要打開 .env**）：

- `OPENAI_API_KEY` — Realtime 對話與分析
- `TELEGRAM_BOT_TOKEN` — Telegram bot
- `TELEGRAM_CARE_CHAT_ID` — 要推播的照護群組 / 對話 id
- （選用）`PORT`、`HOST`、`REALTIME_MODEL`、`MEMORY_TOP_K`

快速自我檢查（不外洩值）：

```bash
node -e "require('dotenv').config({path:'backend/stt_proxy/.env'}); \
  console.log('OPENAI', !!process.env.OPENAI_API_KEY, \
  'TG_TOKEN', !!process.env.TELEGRAM_BOT_TOKEN, \
  'TG_CHAT', !!process.env.TELEGRAM_CARE_CHAT_ID)"
# 期望輸出三個 true
```

### 1.3 Telegram 準備

1. 確認 bot 已加入要展示的群組 / 已和長照人員建立對話。
2. 確認 `TELEGRAM_CARE_CHAT_ID` 是「要收到通知的那個聊天」。
3. **開演前先送一則測試訊息**確認鏈路通（會真的送出，請用測試字樣）：

```bash
curl -X POST http://127.0.0.1:3001/api/care-alerts/notify \
  -H "Content-Type: application/json" \
  -d '{"riskLevel":"high","category":"other","triggerSummary":"[開演前測試] 通知鏈路確認","transcriptSnippet":"測試","source":"preflight","createdAt":"2026-05-31T09:00:00+08:00"}'
# 期望：回 {"success":true}，且 Telegram 群組收到訊息
```

> 注意：同一「來源＋風險等級」有 **冷卻期（預設約 10 分鐘）**，冷卻內重送會回 `skipped_cooldown`、不再推播。
> 若想正式演示前不被冷卻擋住，preflight 用的 `source` 請和正式 Demo 不同（例如 `preflight` vs `demo`）。

### 1.4 測試資料是否清空

- Care Alert 存在 `backend/stt_proxy/data/care_alerts.json`（**runtime 資料、不進 git**）。
- 想要乾淨的管理端畫面：**先備份再清空**

```bash
cp backend/stt_proxy/data/care_alerts.json backend/stt_proxy/data/care_alerts.backup.json
echo "[]" > backend/stt_proxy/data/care_alerts.json   # 由負責人手動執行；清空前務必先備份
```

> 也可保留 2–3 筆「已處理」舊資料，讓管理端看起來像真的在運作中。依現場決定。

### 1.5 開演前 60 秒檢查清單

- [ ] backend :3001 有在跑（`curl -s http://127.0.0.1:3001/api/care-alerts | head`）
- [ ] caregiver_web :8080 開得起來、且能載到資料（不是「連不上後端」）
- [ ] Flutter App 已連上、語音按鈕顯示「想聊天就點我」
- [ ] iPhone 麥克風權限已允許、音量開好、網路穩
- [ ] Telegram 群組畫面已投影 / 已準備好給評審看
- [ ] preflight 測試訊息已收到（鏈路 OK）
- [ ] 投影畫面排好：長者手機 +（管理端網頁 / Telegram）

---

## 2. Demo 角色分工

| 角色 | 由誰扮 | 負責 |
| --- | --- | --- |
| **長者** | 組員 A | 對著 App 自然說出劇本台詞（口語、慢一點、清楚） |
| **AI 寵物** | App 本身 | 即時語音回應、表情/狀態變化（不需人扮，但講者要引導觀眾看） |
| **長照人員 / 家人** | 組員 B | 操作 caregiver_web：看到提醒 → 標記已查看 → 已處理；展示 Telegram 通知 |
| **Demo 操作者** | 組員 C | 顧服務、切畫面、必要時用備援（API / 預備資料）救場 |
| **報告講者** | 組員 D | 串場解說，把「現在發生什麼、為什麼重要」講給評審聽 |

> 小組人少時：A 兼長者+講者，B 顧管理端+Telegram，C 顧後端與救場。

---

## 3. 劇本 A：日常陪伴（不觸發通知）

**情境**：證明它平常就是個溫暖的陪伴夥伴，不是監控器。

**長者說**（對著 App 語音）：
> 「咕咕雞，我今天有點無聊，想找你聊聊天。」

**預期結果**：
- AI 寵物以**陪伴語氣**自然回應（先接情緒、再陪聊），不講道理、不像客服。
- 風險判定 `low` → **不建立 Care Alert、不推 Telegram**。
- 管理端 / Telegram **沒有任何新訊息**。

**講者解說重點**：
> 「平常的對話，系統只是好好陪他聊天，不會打擾家人，也不會讓長者覺得被監視。」

---

## 4. 劇本 B：持續觀察（medium，只進管理端、不推 Telegram）

**情境**：長者透露輕微的身心訊號，還沒到要通知，但值得「持續觀察」。

**長者說**：
> 「我最近都睡不好，也覺得有點孤單。」

**預期結果**：
- AI 寵物先安撫、放慢語氣陪伴（前台仍是溫暖陪伴，不會把「風險」講給長者聽）。
- 後台判定 `medium`。
- 進入 **caregiver_web**，顯示為一張卡片（風險層級：持續觀察）。
- **Telegram 不推播**（只有 high / urgent 才推）。

> ⚠️ **重要（誠實演示說明）**：目前長者端 App 只有在 **high / urgent** 時才會自動把提醒送進管理端；
> `medium` 不會經由 App 自動建立。因此**劇本 B 的管理端卡片，請用下方「預備資料」方式灌入**（這走的是真實後端 API 與真實持久化，不是假畫面）。
> 講者話術可說：「系統把它列為持續觀察，先記錄下來給家人參考，但還不需要驚動任何人。」

**灌入 medium 提醒（真實 API，持久化但不推 Telegram）**：

```bash
curl -X POST http://127.0.0.1:3001/api/care-alerts/notify \
  -H "Content-Type: application/json" \
  -d '{"riskLevel":"medium","category":"sleep","triggerSummary":"長者提到最近睡不好、有點孤單，建議持續觀察近況。","transcriptSnippet":"我最近都睡不好，也覺得有點孤單","source":"demo","createdAt":"2026-05-31T10:00:00+08:00"}'
# 期望：回 {"success":true,"telegram":"skipped_low_risk"} → 管理端會出現卡片、Telegram 不響
```

**管理端操作**：重新整理 → 指出「需通知 / 緊急」統計沒變、列表多了一張「持續觀察」卡片。

---

## 5. 劇本 C：需通知（high，推 Telegram + 進管理端）

**情境**：長者出現明顯、反覆的負面訊號，需要家人 / 長照人員介入。

**長者說**：
> 「我覺得沒有人關心我，最近常常覺得很累，也不太想吃東西。」

**預期結果**：
- AI 寵物**仍以陪伴語氣**回應、先穩住情緒（前台不會說「你有風險」）。
- 後台判定 `high`（`needsHumanSupport = true`）。
- 長者端 App **自動建立 Care Alert 並呼叫通知**：
  - **Telegram 即時推播**到照護群組（含風險等級、白話摘要、對話片段）。
  - 同步進入 **caregiver_web**（統計「需通知」+1）。
- 長者端的「今日關心紀錄」只會看到溫暖的「有人關心你」，**看不到風險字眼**。

**管理端操作（壓軸）**：
1. 切到 Telegram 群組畫面：指出剛剛跳出的通知。
2. 切到 caregiver_web：點開那張「需通知」卡片 → 看到摘要與對話片段。
3. 按「標記為已查看」→ 再按「標記為已處理」→ 卡片狀態更新、統計「已處理」+1。

**講者收尾**：
> 「從長者一句話，到家人手機收到通知、再到照護端完成處理，整條關懷鏈路是即時而完整的。」

### 5.1 （選用）urgent 變體 — 危急情況

**長者說**：「我剛剛在浴室滑倒了，爬不太起來。」
**預期**：判定 `urgent` → Telegram 推播（摘要含「立即確認安全」語氣）→ 管理端標記為「緊急」。
與劇本 C 流程相同，差別在等級更高、措辭更急。

---

## 6. 5 分鐘展示流程（Batch 4：照表操課 timeline）

| 時間 | 誰 | 動作 | 投影/畫面 | 講者口白（重點） |
| --- | --- | --- | --- | --- |
| 0:00–0:30 | 講者 | 開場：題目與痛點 | 標題頁 | 「獨居長者的孤單與突發狀況，常常沒人即時知道。」 |
| 0:30–1:30 | 長者 | **劇本 A 日常陪伴** | 長者手機 | 「先看它平常怎麼陪伴——溫暖、即時、像朋友。」 |
| 1:30–2:30 | 長者 | **劇本 B 持續觀察** | 長者手機 →（操作者灌 medium）→ 管理端 | 「出現睡不好、孤單，系統先記錄為『持續觀察』，還不驚動家人。」 |
| 2:30–4:00 | 長者 + 長照人員 | **劇本 C 需通知** | 長者手機 → Telegram → 管理端 | 「狀況升高 → 家人手機即時收到 → 照護端接手處理。」 |
| 4:00–4:40 | 長照人員 | 管理端標記已查看 / 已處理 | caregiver_web | 「家人能一鍵接手、留下處理紀錄。」 |
| 4:40–5:00 | 講者 | 收尾：價值 + 技術亮點一句話 | 架構圖 / 標題頁 | 「Realtime 語音 + 長期記憶 + 風險分級通知，一條龍的長者關懷。」 |

> **節奏提醒**：劇本 A 不要拖；重點戲在 C（通知那一刻）。把 Telegram 跳通知的瞬間留給評審看。

---

## 7. 沒資料 / 出狀況怎麼辦（救場手冊）

> 原則：**寧可用預備資料補救，也不要當場卡住或出現工程錯誤訊息**。所有補救都走真實 API / 真實畫面，不是假功能。

### 7.1 Realtime 語音連不上 / 太吵聽不清楚
- 退路 1：改用 App 的**文字輸入框**打出劇本台詞（一樣會跑分析與回應）。
- 退路 2：講者口頭描述，操作者直接用 **API 灌入對應提醒**（見下方），把戲接到管理端 / Telegram。
- 白話 fallback：畫面只會顯示「連線不太穩，我們正在幫你重新連接」，不會出現英文錯誤。

### 7.2 管理端沒有任何提醒卡片
- 用真實 API 灌 1–2 筆（medium + high），caregiver_web 重新整理即可：

```bash
# medium（不推 Telegram，只進管理端）
curl -X POST http://127.0.0.1:3001/api/care-alerts/notify -H "Content-Type: application/json" \
 -d '{"riskLevel":"medium","category":"loneliness","triggerSummary":"長者提到孤單、睡不好，建議持續觀察。","transcriptSnippet":"我最近都睡不好，也覺得有點孤單","source":"demo","createdAt":"2026-05-31T10:00:00+08:00"}'

# high（會推 Telegram + 進管理端）
curl -X POST http://127.0.0.1:3001/api/care-alerts/notify -H "Content-Type: application/json" \
 -d '{"riskLevel":"high","category":"depressed","triggerSummary":"長者反覆提到沒人關心、心情低落、食慾下降，建議家人主動聯繫。","transcriptSnippet":"我覺得沒有人關心我，也不太想吃東西","source":"demo","createdAt":"2026-05-31T10:05:00+08:00"}'
```

- 查看目前資料：`curl -s "http://127.0.0.1:3001/api/care-alerts?limit=5"`

### 7.3 Telegram 沒有跳通知
- 先確認：回應是 `{"success":true}` 還是別的？
  - `skipped_cooldown` → 冷卻期內，**換一個 `source` 值**再送一次。
  - `skipped_low_risk` → 你送的是 low/medium，本來就不推；要推請用 `high`/`urgent`。
  - `telegram_not_configured` → `TELEGRAM_BOT_TOKEN` 或 `TELEGRAM_CARE_CHAT_ID` 沒設好（找負責人，不要當場開 .env）。
- 最後退路：用**事先截好的 Telegram 通知截圖**佐證，講者說明這是剛剛同一條訊息。

### 7.4 後端沒起來 / port 被占用
- 確認 :3001 是否被占用：`lsof -nP -iTCP:3001 -sTCP:LISTEN`
- 重新 `npm start`；caregiver_web 會顯示白話「暫時連不上後端，請確認服務是否已啟動」，重啟後重新整理即可。

### 7.5 通用救場話術（給講者）
> 「現場網路 / 收音偶爾不穩，我先用我們準備好的同一段資料，讓大家看到完整流程。」
（一邊說，操作者一邊用 API 把資料接上，畫面照常推進。）

---

## 8. 收尾與評審可能提問

- **「會不會侵犯長者隱私 / 讓他覺得被監視？」**
  前台長者端只看到「有人關心你」，看不到風險等級或分析摘要；風險資訊只在後台給家人 / 照護人員。
- **「風險怎麼分級？」** low / medium / high / urgent；只有 high / urgent 會主動通知家人（見 `PROJECT_ARCHITECTURE.md` §5）。
- **「會不會一直洗版通知？」** 有冷卻機制（同來源同等級短時間內只推一次）。
- **「是真的串接還是假的？」** Realtime 語音、OpenAI 分析、Telegram、持久化都是真的；Demo 的備援資料也走真實 API。

---

## 附錄：API 速查（Demo 救場用）

| 用途 | 方法 | 路徑 |
| --- | --- | --- |
| 對話分析（情緒/風險/記憶） | POST | `/api/companion/analyze` |
| 建立提醒 + 通知判斷 | POST | `/api/care-alerts/notify` |
| 查提醒列表（可篩選） | GET | `/api/care-alerts?limit=&riskLevel=&status=` |
| 查單筆提醒 | GET | `/api/care-alerts/:id` |
| 更新狀態（new/acknowledged/resolved） | PATCH | `/api/care-alerts/:id/status` |

通知 payload 主要欄位：`riskLevel`(low/medium/high/urgent)、`category`、`triggerSummary`、`transcriptSnippet`、`source`、`createdAt`。

> 提醒：以上 curl 範例的 `source` 用 `demo` / `preflight` 等明顯字樣，方便 Demo 後辨識與清理；正式環境資料的 `source` 由 App 帶入。
