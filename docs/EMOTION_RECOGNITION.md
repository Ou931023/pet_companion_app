# 情緒辨識與 Care Alert 分析（CR-0028）

> 本文件說明本專案「情緒辨識」與「Care Alert 風險分析」的正式做法，供開發、Demo 與
> 評審問答使用。所有對外文字皆避免醫療診斷語氣：本系統的情緒辨識**僅作為 AI 陪伴與
> 長照關懷的輔助參考，並非醫療診斷**。

---

## 0. 一句話總結

> 長者說話 → 轉成文字 → 後端用**文字語意分析**判斷情緒，並以**語音特徵**（語速、停頓、
> 音量）輔助修正 → 產生情緒、風險等級與照護摘要 → AI 寵物據此調整陪伴語氣；當風險達
> **high / urgent** 時建立 Care Alert，必要時透過 Telegram 通知照護人員。

---

## 1. 評審問答（Quick Q&A）

| 問題 | 回答 |
| --- | --- |
| 有沒有做情緒辨識？ | 有。在每一輪對話後即時分析長者情緒。 |
| 情緒辨識怎麼做？ | 以**文字語意分析**為主（加權關鍵詞/語句訊號），再用**語音特徵融合**修正信心度。 |
| 是用文字還是語音？ | **以文字為主**。語音會先經 OpenAI Realtime / ASR 轉成文字再分析；語音特徵（語速、停頓、音量）只作輔助，不誇大成醫療級語音情緒辨識。 |
| 情緒辨識結果用在哪裡？ | (1) AI 寵物的回覆語氣與表情/動作；(2) 風險分級；(3) 長照管理端的情緒摘要與趨勢。 |
| 什麼情況會通知長照人員？ | 風險達 **high / urgent** 時建立 Care Alert 並可透過 Telegram 通知；low / medium 只做陪伴與紀錄，不通知。 |
| 這是不是醫療診斷？ | **不是**。只作陪伴與關懷輔助。所有摘要與管理端文案都避免「診斷 / 確診 / 疾病判定」字眼。 |
| 怎麼避免誤判 / 過度敏感？ | (1) 風險由重到輕逐層判定，門檻明確；(2) 只有 `needsHumanSupport`（high/urgent）才建立 Care Alert；(3) 同 source + 風險等級有 cooldown 防洗版；(4) 簡→繁正規化避免漏接；(5) 信心度上限 0.95，不宣稱 100% 確定。 |

---

## 2. 正式資料流

```text
長者語音 / 文字輸入
        ↓
若為語音：OpenAI Realtime / ASR 轉成文字
若為文字：直接取得輸入文字
        ↓
後端 Companion Analyze（POST /api/companion/analyze）
        ↓
文字語意情緒分析（emotion_classifier）
   + 語音特徵融合（voice_feature_service → emotion_fusion_service）
   + 風險分級（safety_guard）
   + 照護摘要（companion_prompt_builder.buildCareAlertSummary）
        ↓
產生：情緒 emotion / 信心度 confidence / 風險 riskLevel / careAlertSummary
        ↓
AI 寵物根據結果調整回覆策略、表情、動作
        ↓
low / medium：陪伴回應與情緒紀錄（不通知）
high / urgent：建立 Care Alert
        ↓
管理者端（caregiver_web）查看情緒摘要、風險等級與照護建議
        ↓
high / urgent 必要時 Telegram 通知照護人員（含 cooldown 防洗版）
```

---

## 3. 情緒辨識細節

### 3.1 文字語意分析 — `backend/companion/emotion_classifier.js`

- 方法：**加權關鍵詞 / 語句訊號比對**（regex + 權重），取最高權重的情緒。
- 情緒類別（7 類）：`happy`、`neutral`、`sad`、`lonely`、`anxious`、`tired`、`nostalgic`。
- 輸出：`{ emotion, confidence (0–0.95), reason }`。
- 信心度刻意上限 0.95，表示系統**不宣稱百分之百確定**。

### 3.2 語音特徵（輔助）— `backend/companion/voice_feature_service.js`

由前端傳入的 `audioFeatures` 估算下列特徵，僅作輔助，不單獨做情緒診斷：

- `volumeMean` / `volumeVariance`：音量平均與變異
- `pauseDensity`：停頓密度（silence / speech）
- `estimatedSpeechRate`：語速（字數/秒）
- `speechDuration` / `silenceDuration`
- `confidence`：特徵可信度

### 3.3 文字 + 語音融合 — `backend/companion/emotion_fusion_service.js`

以文字情緒為基底，用語音特徵修正信心度，例如：

- `lonely` + 高停頓密度 → 提高信心度
- `anxious` + 快語速 / 音量不穩 → 提高信心度
- 緩語速 + 高停頓但文字訊號不強 → 傾向推測 `sad` / `tired`

輸出：`{ textEmotion, finalEmotion, confidence, reason }`。`finalEmotion` 即對外採用的情緒。

---

## 4. 風險分級 — `backend/companion/safety_guard.js`

權威四級（單一真相來源，見 `PROJECT_ARCHITECTURE.md`）：

| riskLevel | 中文標籤 | 判定方向 | needsHumanSupport | 是否建立 Care Alert | 是否 Telegram |
| --- | --- | --- | --- | --- | --- |
| `urgent` | 緊急 | 自傷/自殺、急性醫療（胸痛/喘不過氣）、跌倒昏倒 | ✅ | ✅ | ✅（經 cooldown） |
| `high` | 需通知 | 強烈絕望、明顯無助、不想吃東西、什麼都不想做 | ✅ | ✅ | ✅（經 cooldown） |
| `medium` | 持續觀察 | 睡眠/食慾/孤單/低落等需留意訊號 | ❌ | ❌ | ❌ |
| `low` | 一般 | 一般平穩狀態 | ❌ | ❌ | ❌ |

實作要點：

- **由重到輕逐層 early-return**，確保高風險優先、urgent 門檻不被稀釋。
- **簡→繁正規化**（`normalizeForSafety`）：OpenAI Realtime 轉錄常輸出簡體字（睡不着 / 难过 / 没人陪…），先正規化再用繁體 regex 比對，避免高風險語句整句漏接。
- 向下相容：舊值 `normal → low`、`attention → medium`（見 `companion_engine.normalizeRiskLevel`）。

---

## 5. Care Alert 照護摘要（非診斷語氣）

`backend/companion/companion_prompt_builder.js` 的 `buildCareAlertSummary()` 產生**單一白話字串**
`careAlertSummary`，供 Telegram 與 caregiver_web 直接顯示。原則：

- 白話、非診斷；**不得**出現「憂鬱症 / 確診 / 病人 / 診斷」等醫療判定字眼。
- 不過度嚴重化：low 不誇大警示。
- urgent 一定建議「儘快確認安全」，不退化為普通關心。

範例（high）：

```text
系統偵測長者提到強烈的無助或難過，建議照護人員今天主動關心近況，並留意長者是否需要陪伴或進一步協助。
```

---

## 6. `/api/companion/analyze` 回傳結構（重點欄位）

```jsonc
{
  "turnId": "turn-...",
  "emotion": "lonely",          // 7 類之一（融合後）
  "emotionConfidence": 0.78,    // 0–0.95
  "companionNeed": "companionship",
  "replyStrategy": "soft_companion",
  "petExpression": "concerned",  // 寵物表情
  "petAction": "move_closer",    // 寵物動作
  "safety": {
    "riskLevel": "high",         // low | medium | high | urgent
    "needsHumanSupport": true
  },
  "careAlertSummary": "系統偵測長者提到…，建議照護人員…",  // 白話、非診斷
  "fusion": {
    "textEmotion": "sad",
    "finalEmotion": "lonely",
    "confidence": 0.78,
    "reason": "…"
  },
  "voiceFeatures": { "pauseDensity": 0.42, "estimatedSpeechRate": 2.1, "...": null }
}
```

---

## 7. 前端如何使用結果

### 7.1 AI 寵物（長者端）

- `lib/services/companion_engine_service.dart`：呼叫 `/api/companion/analyze`，回傳 `CompanionAnalysisResult`。
- `lib/controllers/voice_agent_controller.dart`：
  - 依 `emotion` / `petExpression` / `petAction` 調整寵物表情與動作。
  - `_maybeCreateCareAlert()`：**僅當 `safety.needsHumanSupport` 為真（即 high/urgent）**才建立
    一筆 `CareAlert`（`triggerSummary` 優先採用後端 `careAlertSummary`），並 fire-and-forget
    呼叫 `POST /api/care-alerts/notify`。失敗不影響 Realtime 對話。

### 7.2 長照管理端（caregiver_web）

- 照護提醒列表 / 詳情：顯示風險等級標籤與照護摘要（`triggerSummary`）。
- 健康分析 → 情緒分析歷史：顯示最近情緒時間軸與摘要。
- **非醫療診斷提示**：列表頁與情緒分析區塊各有一段 `.care-disclaimer`，明確說明
  「情緒辨識與風險分級僅供照護參考，並非醫療診斷」。

---

## 8. 如何避免「Demo 時每句話都跳警示」

1. 只有 `needsHumanSupport`（high/urgent）才建立 Care Alert；一般低落 / 孤單為 medium，只記錄不通知。
2. Telegram 端有 cooldown（同 source + riskLevel 冷卻期內最多推一次），見
   `backend/stt_proxy/services/careAlertCooldown.js`。
3. 前端以 `turnId` 去重，同一輪不重複建立（`_lastAlertedTurnId`）。

---

## 9. 如何驗證（Demo / 自測）

### 9.1 後端 API（不需 .env 即可跑分析邏輯，但完整端點需後端啟動）

```bash
# 啟動後端後（需設定環境變數，見下方）
curl -s -X POST http://localhost:8080/api/companion/analyze \
  -H 'Content-Type: application/json' \
  -d '{"userId":"demo","turnId":"t1","transcript":"我最近睡不好，也沒什麼胃口"}' | jq
# 預期：emotion=tired/sad、safety.riskLevel=medium、careAlertSummary 提到睡眠/食慾，不通知。

curl -s -X POST http://localhost:8080/api/companion/analyze \
  -H 'Content-Type: application/json' \
  -d '{"userId":"demo","turnId":"t2","transcript":"活著好累，什麼都不想做"}' | jq
# 預期：safety.riskLevel=high、needsHumanSupport=true、careAlertSummary 建議主動關心。
```

### 9.2 單元測試

```bash
# 後端情緒 / 風險 / Care Alert 相關
cd backend/stt_proxy && npm test          # 含 companion_engine、safety_guard、careAlert* 等
node --test ../companion/safety_guard.test.js
node --test ../companion/companion_engine.test.js

# 管理端顯示（含非醫療提示）
node --test caregiver_web/care_alert_display.test.js
node --test caregiver_web/admin_dashboard.test.js
```

> 環境變數：完整啟動後端 / Realtime 需要 `OPENAI_API_KEY` 等變數（請勿提交 `.env`）。
> 純情緒/風險分級的單元測試不需要金鑰。

---

## 10. 限制與責任邊界

- 情緒辨識以**文字語意**為主，語音特徵僅輔助，**不是**醫療級語音情緒辨識。
- 結果為機率性判斷（信心度上限 0.95），可能誤判；**不可作為醫療診斷或處置依據**。
- Care Alert 的定位是「陪伴過程中的異常提醒」，不是監控；前台寵物仍以陪伴語氣互動，
  風險分析在後台進行。
- 緊急狀況請以實際聯絡長者、撥打緊急電話為準。

---

## 相關檔案

| 用途 | 檔案 |
| --- | --- |
| 文字情緒辨識 | `backend/companion/emotion_classifier.js` |
| 語音特徵 | `backend/companion/voice_feature_service.js` |
| 情緒融合 | `backend/companion/emotion_fusion_service.js` |
| 風險分級 | `backend/companion/safety_guard.js` |
| 照護摘要 | `backend/companion/companion_prompt_builder.js` |
| 分析主引擎 | `backend/companion/companion_engine.js` |
| Analyze 端點 | `backend/stt_proxy/server.js`（`/api/companion/analyze`） |
| Care Alert 持久化 | `backend/stt_proxy/services/careAlertStoreService.js` |
| Telegram 通知 | `backend/stt_proxy/services/telegramNotifyService.js` |
| 通知 cooldown | `backend/stt_proxy/services/careAlertCooldown.js` |
| 前端分析呼叫 | `lib/services/companion_engine_service.dart` |
| 前端 Care Alert 建立 | `lib/controllers/voice_agent_controller.dart`（`_maybeCreateCareAlert`） |
| 管理端顯示 | `caregiver_web/index.html`、`caregiver_web/app.js` |
