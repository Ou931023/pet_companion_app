<!--# CR-0028 — 正式版情緒辨識與 Care Alert 分析紀錄

## 任務背景

本專案是長者 AI 寵物陪伴系統，核心不只是讓長者和 AI 寵物聊天，而是希望在自然對話過程中，透過語意分析理解長者目前的情緒狀態，並在長者出現孤單、低落、焦慮、睡眠困擾、身體不適或其他需要關懷的訊號時，讓 AI 寵物調整陪伴方式，必要時建立 Care Alert，提醒長照人員或管理者進一步關心。

本次 CR-0028 要將目前系統中的「情緒辨識」整理成正式展示可說明、可驗證、可記錄、可被管理者端查看的完整功能。

評審老師若詢問：

- 你們有沒有做情緒辨識？
- 情緒辨識怎麼做？
- 是用文字還是語音？
- 情緒辨識結果用在哪裡？
- 什麼情況會通知長照人員？
- 這是不是醫療診斷？
- 你們怎麼避免誤判？

系統與文件都必須能清楚回答。

---

## 核心原則

1. 情緒辨識以「文字語意分析」為主。
2. 語音輸入需先經過語音轉文字，再進入情緒分析流程。
3. 若現有系統已有語音特徵欄位，例如語速、停頓、音量、對話長度，可作為輔助資料，但不可誇大成醫療級語音情緒辨識。
4. 情緒辨識結果不是醫療診斷，只作為 AI 陪伴與長照提醒輔助。
5. low / medium 主要用於 AI 寵物陪伴語氣調整與情緒紀錄。
6. high / urgent 才建立高風險 Care Alert 或觸發 Telegram 通知流程。
7. 不要破壞現有 Realtime、Care Alert、Telegram、長期記憶、登入註冊流程。
8. 不要加入 fake data、hardcoded demo result、demo-only fallback 來偽裝功能。
9. 不要為了展示而讓每句話都觸發警示，避免 Care Alert 過度敏感。
10. 所有對外文字都要避免「診斷」、「確診」、「疾病判定」等醫療診斷語氣。

---

## 一、請先盤點現有架構

修改前請先檢查目前專案中與情緒分析、陪伴策略、Care Alert 相關的檔案與資料流。

請至少盤點以下範圍：

### 1.1 Flutter 長者端

可能相關檔案包含但不限於：

- `lib/controllers/voice_agent_controller.dart`
- `lib/controllers/conversation_controller.dart`
- `lib/controllers/pet_controller.dart`
- `lib/services/realtime_voice_service.dart`
- `lib/services/companion_engine_service.dart`
- `lib/services/memory_service.dart`
- `lib/models/conversation_turn.dart`
- `lib/models/pet_state.dart`
- `lib/screens/home_screen.dart`
- `lib/screens/care_alert_screen.dart`

請確認：

- 長者語音或文字輸入在哪裡產生。
- 語音轉文字結果在哪裡進入對話流程。
- Companion Analyze API 在哪裡被呼叫。
- 情緒結果目前是否會影響寵物狀態、表情、動作或回覆策略。
- Care Alert 目前在哪裡被建立。
- 是否已有 `_maybeCreateCareAlert()` 或類似邏輯。

### 1.2 Node.js 後端

可能相關檔案包含但不限於：

- `backend/stt_proxy/server.js`
- `backend/stt_proxy/services/companion_prompt_builder.js`
- `backend/stt_proxy/services/care_alert_store_service.js`
- `backend/stt_proxy/services/emotion_fusion_service.js`
- `backend/stt_proxy/services/*emotion*`
- `backend/stt_proxy/services/*companion*`
- `backend/stt_proxy/routes/*`
- `backend/stt_proxy/tests/*`

請確認：

- `/api/companion/analyze` 是否存在。
- 分析結果是否包含 emotion、mood、riskLevel、careAlertSummary。
- high / urgent 是否會建立 Care Alert。
- Telegram 是否只在 high / urgent 或指定條件下通知。
- Care Alert summary 是否已經是非醫療語氣。
- 是否已有 risk level：`low | medium | high | urgent`。

### 1.3 管理者端 / caregiver_web

可能相關檔案包含但不限於：

- `caregiver_web/index.html`
- `caregiver_web/app.js`
- `caregiver_web/styles.css`
- `caregiver_web/*`
- `docs/*`

請確認：

- Care Alert 列表是否顯示風險等級。
- Alert 詳情是否顯示情緒摘要。
- 是否已有情緒分析歷史或趨勢區塊。
- 是否需要補上「情緒 / 風險摘要」欄位。
- 是否需要新增「非醫療診斷」提示。

### 1.4 文件

請檢查：

- `README.md`
- `docs/DEMO_FLOW.md`
- `docs/CHANGE_REVIEW.md`
- `docs/PROJECT_ARCHITECTURE.md`
- 是否已有 `docs/EMOTION_RECOGNITION.md`

請確認目前文件是否能回答：

- 情緒辨識怎麼做。
- 使用文字還是語音。
- 和 Care Alert 的關係。
- 是否為醫療診斷。
- 評審問答怎麼回答。

---

## 二、正式資料流

請整理並確保系統情緒辨識資料流如下：

```text
長者語音 / 文字輸入
        ↓
若為語音：OpenAI Realtime / ASR 轉成文字
若為文字：直接取得輸入文字
        ↓
後端 Companion Analyze
        ↓
文字語意情緒分析
        ↓
產生情緒狀態、風險等級、照護摘要
        ↓
AI 寵物根據結果調整回覆策略
        ↓
low / medium：陪伴回應與情緒紀錄
high / urgent：建立 Care Alert
        ↓
管理者端查看情緒摘要、風險等級與照護建議
        ↓
必要時 Telegram 通知照護人員>