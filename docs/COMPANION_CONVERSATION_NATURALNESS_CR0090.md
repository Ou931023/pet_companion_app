# CR-0090 — Companion Conversation Naturalness Polish

改善 AI 寵物對話自然度：少罐頭、不重複、安慰更自然、不每次硬轉提醒 / 任務、台語更自然好懂；安全邊界一律保留。改動集中在**後端 persona / instruction 字串**，未碰 Realtime 主流程與鎖定檔。

---

## 1. 問題盤點

| 現象 | 根因 |
|---|---|
| 對話太像罐頭、重複同一句安慰 | persona 缺「抗重複 / 換句話說」明確指示；語音端尤甚（無近期回覆歷史可參考） |
| 每次硬轉提醒 / 喝水 / 吃藥 / 任務 | 語音 persona 的工具「意義對照表」要求一律肯定地把話帶向某個動作，且「絕對禁止說我沒辦法」，造成過度推功能 |
| 安慰過度醫療化 / 一直叫人喝水 | 缺「先陪伴、不急著給解法、不過度醫療化」的明確指引 |
| 台語每句硬翻成純台語、難懂 | 台語指示原本要求「整段純台語、不可使用標準中文」，犧牲了長者理解 |

---

## 2. 語音 / 打字 persona 修改位置（後端）

| 區塊 | 檔案 / 位置 | 改了什麼 |
|---|---|---|
| 語音 persona | `backend/stt_proxy/server.js` `REALTIME_INSTRUCTIONS` | 新增「【陪伴優先 / 自然度】」段（抗重複、不硬轉功能、先陪伴、不過度醫療化、不每句問句收尾）；在工具「意義對照表」前加閘門：**只在長者「明確要你做某件事」時才套用**，閒聊 / 訴說心情不套用、不硬轉功能。工具能力與安全提醒**原樣保留**。 |
| 打字 persona | `server.js` `COMPANION_CHAT_PERSONA` | 新增「【自然陪伴】」段（同一段對話不重複開頭 / 安慰、不每次「聽起來…」開頭、不每次問句結尾、閒聊不硬轉任務、低落先陪伴後求助、一次一個溫和回應）。 |
| 台語 | `server.js` `outputLanguageInstruction`（語音 + 打字共用） | 由「整段純台語、不可使用標準中文」改為「自然口語、以台語為主、**長者聽得懂優先**、可國台語混用、不用生僻字、不要每句硬翻成純台語」。 |
| 測試匯出 | `server.js` `module.exports.buildRealtimeInstructions` | 純函式測試 seam（非新路由 / 非 response 形狀）。 |

> 未改：`companionChatService.js`（不含 persona）、`next_strategy_planner.js`、記憶 / 情緒注入框架、工具路由功能。Flutter 端未改。

---

## 3. 新回覆風格規則（重點）

- **抗重複**：同一段對話不連續用相同開頭 / 同一句安慰；不每次「聽起來…」開頭；不每次問句結尾。
- **陪伴優先**：普通聊天就自然接話，不硬把話題帶去提醒 / 喝水 / 吃藥 / 運動 / 任務。
- **安慰合宜**：先簡短接住情緒、陪一下，不急著給解法、不過度醫療化；真的需要時才輕輕提醒找家人 / 照護人員。
- **明確需求仍用工具**：語音端工具「意義對照表」保留，閘門只在長者明確要求動作時套用（例：「提醒我吃藥」「幫我簽到」仍正常觸發工具）。
- **不一口氣丟一堆建議**：一次一個具體、溫和的回應。

---

## 4. 台語模式處理

- 以台語為主、但**長者聽得懂優先**；句子短、用日常台語詞，不用艱深 / 文謅謅的台語字。
- 不好用台語講、或可能讓長者聽不懂的詞，可自然國台語混用，不硬翻成生僻台語。
- 繁體漢字書寫（不用羅馬拼音 / 台羅）；開頭不用生硬國語化招呼；沒聽清楚用台語自然確認。

---

## 5. 情境案例（期望行為）

| 情境 | 長者 | 期望 |
|---|---|---|
| 普通聊天 | 今天天氣不錯。 | 自然接話，不硬轉照護 / 任務。 |
| 疲倦 | 我今天好累。 | 先短句安慰陪伴，不診斷、不馬上叫喝水。 |
| 睡不好 | 我昨晚睡不好。 | 關心 + 簡短，必要時提醒白天慢慢來。 |
| 孤單 | 我覺得沒有人陪我。 | 接住孤單感、陪一下，不過度警報化。 |
| 不想吃飯 | 我不太想吃飯。 | 溫和關心，可提醒少量吃一點；持續不適再找照護者。 |
| 明確提醒 | 等一下提醒我吃藥。 | 仍使用提醒工具，回覆簡短自然。 |
| 高風險 | 我不想活了。 | 依既有安全邊界與 Care Alert 流程，不得只用一般安慰帶過。 |
| 台語·累 | 我今仔日足累。 | 「今仔日較累喔，先慢慢來，有我佇遮陪你。」（自然，可混用） |

---

## 6. 安全邊界（一律保留，未弱化）

- 語音 persona 高風險提醒句（胸痛 / 呼吸困難 / 跌倒 / 嚴重不適 / 自傷意念 → 聯絡家人或就醫）**原樣保留**。
- 打字 persona「【健康與安全】」段（不診斷 / 不開處方 / 不講劑量；高風險明確引導立即求助；溫柔語氣不淡化緊急）**原樣保留**。
- 後端風險分級 `safety_guard.js`、Care Alert 摘要、`next_strategy_planner.js` 安全分支**完全未改**。
- 既有 `companionChatPersona.test.js` / `companionChatCareAlert.test.js` 安全斷言全數通過（安全閂未動）。

---

## 7. 測試結果

- 更新 / 新增 `backend/stt_proxy/services/companionChatPersona.test.js`：
  - 台語改測新自然台語 guardrails（「以台語為主」「長者聽得懂優先」「不要每句都硬翻成純台語」）。
  - 新增「打字自然陪伴」guardrail（抗重複 / 不硬轉任務 / 先陪伴後求助）。
  - 新增「語音 persona」guardrail（陪伴優先 + 抗重複 + 工具表只在明確需求時套用 + 高風險安全保留 + 無工程字眼外漏）。
- 既有 persona / 安全 / 即時資訊 / 記憶斷言維持不變、全綠。
- 結果：`backend/stt_proxy` `npm test` **595 passed / 0 failed**、`npm run check` exit 0。未改 Flutter，故未跑 flutter test。

---

## 8. 已知限制

- **🔒 mid-session persona 漂移**：`lib/services/realtime_voice_service.dart`（鎖定檔）內有一份**縮版語音 persona 副本**（`_instructionsWithCompanionContext`，僅用於 companionContext 變更時的 `session.update`）與其自帶的台語指引、工具念稿包裝。本 CR **未動該檔**（理論上不需），故這份 mid-session 副本不會反映本次 persona / 台語措辭。建議由 **realtime-voice-agent** 後續同步（已記於 `docs/CHANGE_REVIEW.md` CR-0090 後續事項）。一般情況下 session 起始 instructions 來自後端 `/api/realtime/call`（已套用本 CR），影響有限。
- **Flutter 端 fallback**：`lib/services/companion_reply_strategy_service.dart` 的本機安慰句庫（多句「我陪你」）為離線 fallback，本 CR 未改（主對話走 LLM persona）；列為後續可選優化。
- **工具念稿措辭**：`ai_tool_router.dart` / `native_tool_executor_service.dart` 既有確認句多為白話（如「好，我會…提醒你」），本 CR 未改；少數較像系統通知者列為後續可選。
- **模型輸出非完全 deterministic**：測試以「persona 是否含必要 guardrail 字串」驗證，而非硬比對生成內容。
- 未改 Realtime 主流程 / 字幕同步（CR-0089）/ 寵物素材（CR-0088）/ 推播（CR-0087）/ Care Alert / Telegram / 後台 / 後端 DB。
