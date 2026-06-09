# CR-0051 — Typed Companion Chat Risk Analysis and Care Alert Integration

## 1. 任務定位

本任務接續 CR-0050。

CR-0050 已完成：

- `POST /api/companion/chat` 使用獨立陪伴型 persona
- 文字聊天不再借用工具化 Realtime persona
- 無工具罐頭、不假裝執行工具
- 無記憶不捏造，有記憶可自然提及
- 健康問題維持照護提醒，不做醫療診斷
- 語音 Realtime persona byte-identical，未破壞

目前殘留正式版風險：

> 打字聊天中的高風險文字目前只得到安全語氣回覆，不會建立 Care Alert，也不會觸發通知。  
> 這會造成「語音聊天」與「文字聊天」面對同一個高風險訊號時行為不一致。

本 CR 目標是讓打字聊天文字也進入情緒分析、風險判斷與 Care Alert 流程。

---

## 2. 本次目標

完成 typed companion chat 的 emotion / risk / Care Alert integration：

1. 打字聊天文字需進行情緒與風險分析。
2. 高風險文字需建立 Care Alert。
3. high / urgent 需依既有規則觸發通知。
4. low / medium 需依既有規則入庫與推播。
5. Care Alert risk level 必須統一使用正式四級：
   - `low`
   - `medium`
   - `high`
   - `urgent`
6. 不可使用 runtime legacy `attention` 等不一致代碼作為新正式資料。
7. 不破壞 CR-0050 persona。
8. 不破壞 Realtime 語音路徑。
9. 不破壞 `/api/care-alerts/notify` caller auth。
10. 補測試覆蓋 typed chat → risk analysis → Care Alert → notification。

---

## 3. 必讀文件

請先閱讀：

- `CLAUDE.md`
- `docs/CHANGE_REVIEW.md`
- `docs/COMPANION_PERSONA.md`
- `docs/SAFETY_BOUNDARIES.md`
- `docs/AUTHORIZATION_MODEL.md`
- `docs/STORE_RELEASE_CHECKLIST.md`
- `backend/stt_proxy/server.js`
- `backend/stt_proxy/services/companion*`
- `backend/stt_proxy/services/careAlert*`
- `backend/stt_proxy/services/emotion*`
- `backend/stt_proxy/services/risk*`
- `backend/stt_proxy/services/notification*`
- `backend/stt_proxy/services/privacy/redaction.js`
- CR-0045 `/api/care-alerts/notify` auth tests
- CR-0050 companion chat persona tests

---

## 4. 架構前置裁決

本 CR 修改前，請先由 architecture-agent 或架構守門人裁決以下事項，並寫入 CHANGE_REVIEW：

1. `/api/companion/chat` 是否必須加 caller auth。
2. 若加 auth，是否重用 CR-0045 的 `requireResidentCaller` / resident caller context。
3. typed chat 是否允許 caregiver / super_admin 代送。
4. risk level 權威代碼是否只允許：
   - `low`
   - `medium`
   - `high`
   - `urgent`
5. 現有 legacy `attention` 如何 mapping。
6. typed chat 建立 Care Alert 失敗時，chat response 是否：
   - partial success
   - fail closed
   - 或回覆仍成功但記錄錯誤
7. 是否向長者 UI 顯示已建立 Care Alert。
   - 建議不要顯示明顯監控感文案。

未完成裁決前，不要直接大改主流程。

---

## 5. 先盤點

修改前請先盤點並回報：

1. 目前語音路徑如何建立 Care Alert。
2. `/api/care-alerts/notify` 目前如何驗證 caller 與建立 alert。
3. `/api/companion/chat` 是否已有 caller auth。
4. `/api/companion/chat` request body 是否含 elderId / residentId / conversationId。
5. 目前情緒分析 service 是否可重用。
6. 目前風險判斷 service 是否可重用。
7. 目前 Care Alert store / notification service 是否可重用。
8. risk level 目前有哪些 legacy 值：
   - `urgent`
   - `attention`
   - `low`
   - `medium`
   - `high`
   - 其他
9. 管理端目前支援哪些 risk level。
10. typed chat 是否已有 conversation/message persistence。
11. notification cooldown 是否可直接重用。
12. Care Alert summary 是否已做 redaction / truncation。

---

## 6. Auth / Caller Context 要求

typed chat 會涉及住民敏感資料與照護警示，因此不能讓未驗證 caller 任意建立 alert。

要求：

1. `/api/companion/chat` 若會建立 Care Alert，必須知道訊息屬於哪位 resident。
2. 不可信任 client 任意傳入 elderId / residentId。
3. 應優先重用 CR-0045 的 resident caller context。
4. 未驗證 caller 不可建立 Care Alert。
5. 跨 resident 不可建立 Care Alert。
6. valid token 但 resident 不符需 403 或依架構裁決處理。
7. invalid token 需 401。
8. production 不得接受 fake token。
9. 不得在 log 印 token。

---

## 7. Risk Level 統一要求

正式 risk level 必須統一：

```txt
low
medium
high
urgent
```

要求：

1. typed chat 新建 Care Alert 不得使用 `attention`。
2. 若現有 runtime 仍有 `attention`，請建立 mapping，但不要污染新資料。
3. legacy mapping 必須有測試。
4. 管理端顯示不可因新 alert level 壞掉。
5. notification 規則維持既有設計：
   - low：預設不推播，只記錄
   - medium：依現有規則
   - high：通知
   - urgent：立即通知

---

## 8. Typed Chat Risk Analysis

### 8.1 應分析的訊號

至少涵蓋：

- 孤單：「家裡好安靜」「沒人理我」
- 睡不好：「晚上都睡不好」
- 食慾差：「不太想吃飯」
- 情緒低落：「覺得很難過」
- 焦慮：「一直很不安」
- 身體不適：「胸口很痛」「喘不過氣」「頭暈站不穩」
- 自傷危機：「不想活了」等危急語句

### 8.2 Care Alert 觸發方向

建議對齊既有 risk service：

- 輕微孤單、無聊：low
- 明顯孤單、低落、睡不好、食慾差：medium
- 嚴重身體不適、狀況加重：high
- 自傷、危急語句、立即危險：urgent

不要另寫一套與語音路徑不一致的規則。

---

## 9. Care Alert 建立與通知

請重用既有 Care Alert 流程，避免建立旁路。

要求：

1. alert payload 應標記來源為 typed chat，例如：
   - `typed_chat`
   - `companion_chat`
   - 或現有相容值
2. alert summary 不得保存過長原文。
3. notification 不得包含完整敏感對話。
4. notification log / cooldown 沿用既有機制。
5. high / urgent 授權 typed chat 應觸發 Telegram。
6. 未授權 typed chat 不可建立 alert。
7. 未授權 typed chat 不可觸發 Telegram。
8. Care Alert 建立失敗不可造成未處理 exception。
9. alert 失敗時 chat response 行為需依架構裁決。

---

## 10. Response Contract

`/api/companion/chat` 原有成功 response 不應被破壞。

若需新增欄位，請採 backward-compatible optional 欄位，例如：

```json
{
  "reply": "...",
  "careAlert": {
    "created": true,
    "riskLevel": "high",
    "id": "..."
  }
}
```

要求：

1. Flutter 既有讀取 reply 不可壞掉。
2. 新欄位 optional。
3. 不回傳 internal risk debug。
4. 不回傳 system prompt。
5. 不回傳 token / secret / raw model payload。
6. 不回傳完整敏感原文。

---

## 11. Flutter 行為需求

請檢查 Flutter `CompanionChatService` / `AiToolRouter._chat`：

1. 若後端回傳 careAlert optional 欄位，Flutter 解析不可壞。
2. 不要顯示 raw risk JSON。
3. 不要顯示「已建立風險警示」等強烈監控感文案，除非產品已有此設計。
4. chat 失敗仍維持 CR-0050 白話錯誤。
5. 不 fallback mock。
6. 不破壞 reminders tool flow。
7. release log 不輸出完整 chat content / alert summary。

---

## 12. 測試需求

### 12.1 Backend Tests

至少新增或更新：

1. typed chat 孤單語句 → 建立 low 或 medium alert，依既有規則。
2. typed chat 睡不好 → 建立 medium alert。
3. typed chat 食慾差 → 建立 medium alert。
4. typed chat 胸口痛 → 建立 high 或 urgent alert。
5. typed chat 自傷危機 → 建立 urgent alert。
6. high / urgent typed chat → Telegram spy 有通知。
7. low typed chat → 不推播或依既有規則。
8. 無 token typed chat 不可建立 alert。
9. invalid token typed chat 不可建立 alert。
10. 跨 resident typed chat 不可建立 alert。
11. risk level 不出現 `attention`。
12. Care Alert source 標記 typed chat。
13. chat response 保持 backward-compatible。
14. alert 建立失敗時 chat response 行為符合裁決。
15. redaction：log 不含完整 typed chat / alert summary。
16. legacy risk mapping 有測試。
17. CR-0050 persona tests 仍通過。
18. CR-0045 notify auth tests 仍通過。

### 12.2 Flutter Tests

至少新增或更新：

1. chat response 含 careAlert optional 欄位不破壞解析。
2. chat response 無 careAlert 欄位仍正常。
3. chat error 不 fallback mock。
4. 不顯示 raw risk JSON。
5. reminder tool flow 仍穿透。
6. release log 不輸出完整 chat content if applicable.

---

## 13. 文件需求

請更新：

- `docs/CHANGE_REVIEW.md`
- `docs/COMPANION_PERSONA.md`
- `docs/SAFETY_BOUNDARIES.md`
- `docs/STORE_RELEASE_CHECKLIST.md`

如需要，新增：

- `docs/TYPED_CHAT_CARE_ALERT_FLOW.md`

文件需說明：

1. typed chat 如何進入情緒與風險分析。
2. risk level 正式四級。
3. typed chat alert source。
4. notification 規則。
5. 為何不向長者顯示過度監控感文案。
6. 與語音路徑的差異與一致性。
7. legacy `attention` 的處理方式。

---

## 14. 限制

本 CR 不得：

1. 破壞 CR-0050 persona。
2. 破壞 Realtime WebRTC。
3. 破壞 `/api/care-alerts/notify` caller auth。
4. 破壞 Memory API 契約。
5. 破壞 reminders / tool calling。
6. 使用 fake risk。
7. fallback 到 mock。
8. 使用 legacy `attention` 作為新 alert level。
9. 在通知中傳完整原文。
10. 在 UI 顯示讓長者有被監視感的文案。
11. 為通過測試而關閉通知。
12. 把健康提醒寫成醫療診斷。
13. 在 Flutter 放 OpenAI key。
14. 信任 client 傳入 residentId。

---

## 15. 驗收標準

完成後必須符合：

1. typed chat 會進行情緒 / 風險分析。
2. 高風險 typed chat 會建立 Care Alert。
3. high / urgent typed chat 會依規則通知。
4. 未授權 typed chat 不建 alert、不通知。
5. risk level 使用 `low / medium / high / urgent`。
6. 新資料不使用 `attention`。
7. response backward-compatible。
8. Flutter 不 fallback mock。
9. Realtime / tool calling 不受破壞。
10. Backend tests 全綠。
11. Flutter analyze / 相關測試通過。
12. CHANGE_REVIEW 已更新。

---

## 16. 完成回報格式

請用以下格式回報：

```md
## CR-0051 完成回報

### 1. 本次目標
-

### 2. 修改檔案
-

### 3. 架構裁決
-

### 4. 既有語音 / notify / chat flow 盤點
-

### 5. Typed chat risk integration
-

### 6. Care Alert 建立與通知
-

### 7. Risk level 統一
-

### 8. Flutter 行為
-

### 9. 測試結果
-

### 10. 正式版風險檢查
- 未驗證 typed chat 是否仍可建 alert：
- 跨 resident 是否被擋：
- high/urgent 是否通知：
- 是否仍出現 attention：
- 是否破壞 persona：
- 是否破壞 Realtime / tool flow：
- 是否有監控感 UI 文案：

### 11. 殘留風險
-

### 12. 下一個建議 CR
-
```
