# CR-0050 — Companion Chat Persona Refinement for Production

## 1. 任務定位

本任務接續 CR-0049。

CR-0049 已完成：

- production STT 正式化
- production 不再注入 MockAiService
- production 不再注入 MockSpeechToTextService
- 後端新增 `POST /api/companion/chat`
- Flutter `AiToolRouter._chat` 改走正式後端 chat endpoint
- mock AI / STT 送審 blocker 已閉合

目前殘留體驗風險：

> 新正式 chat endpoint 可用，但打字閒聊 persona 偏工具化，容易不像 AI 寵物陪伴。  
> 正式版應符合論文定位：不是只回答問題，而是先接住長者情緒、延續記憶、用溫暖簡短語氣陪伴。

本 CR 目標是調整 `/api/companion/chat` 與 Flutter chat fallback 的陪伴式 persona，使正式文字聊天與語音聊天保持一致，不再像工具型助理。

---

## 2. 本次目標

完成 production companion chat persona refinement：

1. `/api/companion/chat` 使用正式陪伴型 system prompt。
2. 回覆語氣符合 AI 寵物陪伴定位。
3. 優先接住情緒，再回應內容。
4. 回覆簡短、自然、長者友善。
5. 可使用長期記憶，但不可假裝記得不存在的事。
6. 健康問題維持照護提醒，不做醫療診斷。
7. 高風險語句仍能接 Care Alert / safety guard。
8. 不破壞 Realtime WebRTC 主流程。
9. 不破壞 tool calling / reminders / Care Alert / Memory。
10. 補測試覆蓋 persona、health safety、memory boundary。

---

## 3. 必讀文件

請先閱讀：

- `CLAUDE.md`
- `docs/CHANGE_REVIEW.md`
- `docs/FLUTTER_BUILD_FLAVORS.md`
- `docs/STORE_RELEASE_CHECKLIST.md`
- `backend/stt_proxy/server.js`
- `backend/stt_proxy/services/companion/*`
- `backend/stt_proxy/services/companion_prompt_builder*`
- `backend/stt_proxy/services/safety*`
- `backend/stt_proxy/services/memory*`
- `lib/services/companion_chat_service.dart`
- `lib/services/ai_tool_router.dart`
- CR-0049 新增的 companion chat endpoint tests

---

## 4. 先盤點

修改前請盤點並回報：

1. `/api/companion/chat` 目前 prompt 內容。
2. 是否重用 Realtime 陪伴 persona。
3. 是否有 companion prompt builder 可共用。
4. 是否有 memory context 可取用。
5. 是否有 safety guard 可共用。
6. `AiToolRouter._chat` 如何處理後端 chat 回覆。
7. chat endpoint 失敗時 Flutter 如何顯示。
8. 目前測試是否只驗證可用，未驗證語氣。
9. 健康／高風險語句目前如何處理。
10. 台語／國台語混合語氣是否已納入。

---

## 5. 後端 persona 需求

### 5.1 核心語氣

正式 chat persona 應遵守：

1. 先回應情緒，再回應事情。
2. 像溫暖的 AI 寵物，不像客服或工具助理。
3. 回覆不宜太長。
4. 避免過度條列。
5. 避免工程術語。
6. 避免「我是 AI 模型」等生硬說法。
7. 不使用恐嚇式健康提醒。
8. 不假裝真人、醫師或照護人員。
9. 不承諾自己做不到的事。
10. 長者聽得懂、讀得懂。

### 5.2 典型輸入回應方向

請至少覆蓋：

- 「今天家裡好安靜」
  - 先接孤單，再輕輕陪聊。
- 「我晚上都睡不好」
  - 先關心，再建議告訴照護人員或記錄狀況。
- 「我不太想吃飯」
  - 關心食慾，避免診斷，建議留意與告知照護人員。
- 「小宇今天沒來」
  - 若記憶知道小宇是孫子，可自然接續；若不知道，不可亂猜。
- 「幫我提醒吃藥」
  - 若屬 tool flow，仍應走提醒工具，不被 chat persona 攔截。
- 「胸口很痛」
  - 需明確建議立即通知照護人員或求助，並可觸發高風險流程。
- 台語／國台語混合語句
  - 可用貼近但不誇張的語氣回應。

---

## 6. Memory Boundary

要求：

1. 有記憶時可自然引用。
2. 無記憶時不可假裝知道家人、喜好、病史。
3. 不把模型猜測寫成事實。
4. 不在回覆中暴露內部 memory id / confidence / vector。
5. 若記憶查詢失敗，仍可陪伴式回應，但不可說「我記得」。
6. 記憶使用需遵守 CR-0047 logging redaction，不印完整敏感內容。

---

## 7. Health and Safety Boundary

要求：

1. Care Alert 是照護提醒，不是醫療診斷。
2. 健康問題不可給診斷、處方、劑量。
3. 高風險身體不適應建議立即通知照護人員或就醫。
4. 自傷或危急語句需走 safety guard。
5. 回覆語氣要穩定，不驚嚇長者。
6. 不因 persona 溫柔而降低 urgent 判斷。

---

## 8. Flutter 行為需求

請檢查 `CompanionChatService` 與 `AiToolRouter._chat`：

1. 正式 chat 成功時顯示後端回覆。
2. 正式 chat 失敗時顯示陪伴式白話錯誤。
3. 不 fallback mock。
4. 不顯示 HTTP / JSON / stack 等工程錯誤。
5. 不破壞提醒 tool flow。
6. 不破壞 Realtime local command flow。
7. 不破壞 shouldSpeak 行為。
8. 不在 release log 顯示完整文字內容。

---

## 9. 測試需求

### 9.1 Backend Tests

至少新增或更新：

1. 孤單語句回覆不是工具化答覆。
2. 睡不好語句包含關心與照護提醒語氣，不做診斷。
3. 食慾差語句不做醫療診斷。
4. 胸口痛語句走高風險/求助方向。
5. 無記憶時不假裝知道家人。
6. 有記憶時可自然引用。
7. 提醒意圖不被 chat endpoint 吃掉，仍可由 tool flow 處理。
8. 回覆不包含 system prompt / internal fields。
9. 回覆不包含 medical diagnosis。
10. 台語／國台語混合語句可得到自然回應。

### 9.2 Flutter Tests

至少新增或更新：

1. `AiToolRouter._chat` 成功顯示正式 chat response。
2. chat endpoint 失敗不 fallback mock。
3. 失敗訊息為白話。
4. reminder tool flow 仍穿透。
5. release log 不輸出完整 chat content if applicable.

---

## 10. 文件需求

請更新：

- `docs/CHANGE_REVIEW.md`
- `docs/STORE_RELEASE_CHECKLIST.md`

如需要，新增或更新：

- `docs/COMPANION_PERSONA.md`
- `docs/SAFETY_BOUNDARIES.md`

文件需說明：

1. 陪伴式 persona 原則。
2. 健康與醫療紅線。
3. 記憶使用紅線。
4. 台語／國台語混合語氣原則。
5. chat endpoint 與 Realtime persona 如何保持一致。

---

## 11. 限制

本 CR 不得：

1. 破壞 Realtime WebRTC。
2. 破壞 Care Alert notify auth。
3. 破壞 Memory API 契約。
4. 破壞 reminders / tool calling。
5. 使用 fake response。
6. fallback 到 MockAiService。
7. 在 Flutter 放 OpenAI API key。
8. 把健康提醒寫成醫療診斷。
9. 假裝記得不存在的記憶。
10. 大量重寫無關 UI。

---

## 12. 驗收標準

完成後必須符合：

1. `/api/companion/chat` 回覆符合陪伴式 persona。
2. 文字 chat 不再偏工具化。
3. 健康問題不做醫療診斷。
4. 高風險問題仍引導求助 / Care Alert。
5. 記憶引用不越界。
6. Flutter 不 fallback mock。
7. Realtime / tool calling 不受破壞。
8. Backend tests 全綠。
9. Flutter analyze / 相關測試通過。
10. CHANGE_REVIEW 已更新。

---

## 13. 完成回報格式

請用以下格式回報：

```md
## CR-0050 完成回報

### 1. 本次目標
-

### 2. 修改檔案
-

### 3. Persona 盤點結果
-

### 4. 後端 chat persona 改動
-

### 5. Memory / safety boundary
-

### 6. Flutter chat 行為
-

### 7. 測試結果
-

### 8. 正式版風險檢查
- 是否仍工具化：
- 是否仍 fallback mock：
- 是否可能醫療診斷：
- 是否假裝記憶：
- 是否破壞 tool flow：
- 是否破壞 Realtime：

### 9. 殘留風險
-

### 10. 下一個建議 CR
-
```
