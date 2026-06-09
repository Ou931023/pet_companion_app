# SAFETY_BOUNDARIES — 健康、記憶與安全紅線

本文件彙整 AI 寵物回覆在「健康/醫療」「長期記憶」「高風險語句」三方面的紅線。語音與打字兩條 persona 路徑（見 `docs/COMPANION_PERSONA.md`）都必須遵守。

最後更新：CR-0050。

---

## 1. 健康與醫療紅線

Care Alert 與健康回覆的定位是**照護提醒，不是醫療診斷**。

**禁止**：

- 宣稱「已診斷」「確診」「醫療判斷」「疾病推論」。
- 給診斷、開處方、講藥物劑量。
- 宣稱取代醫師或照護人員。

**建議用語**：

- 「建議關心」「可能需要留意」
- 「系統偵測到需要照護人員確認的訊號」
- 「請照護人員依實際情況判斷」

對睡不好 / 吃不下 / 身體不適：先關心感受，再溫和建議記錄狀況或告訴照護人員，**不做診斷**。

---

## 2. 高風險 / 緊急情境

觸發語句（例）：胸痛、呼吸困難、跌倒、嚴重不適、自傷意念、危急語句、重複提到痛苦/無助/沒人陪。

要求：

1. 語氣**穩定但明確**，不驚嚇長者。
2. 清楚建議**立即聯絡照護人員或尋求醫療協助**。
3. **不可因為 persona 溫柔就淡化 urgent 判斷**。
4. 自傷 / 危急語句走 safety guard。

> Care Alert 四級：`low` / `medium` / `high` / `urgent`。前台寵物保持陪伴語氣，後台才做風險分析與通知（見 CLAUDE.md §7）。

### 打字聊天的 Care Alert（CR-0051 已接上）

`POST /api/companion/chat` 現在於回覆成功後做純函式風險側錄（`analyzeCompanionTurn`，與語音共用分類腦），當 `riskLevel ∈ {medium, high, urgent}` 即經共用 `processCareAlert` 建立 Care Alert（`source="companion_chat"`），high/urgent 依既有規則推 Telegram。`low`/中性句不建立。需住民 idToken（`requireResidentCaller`，fail-closed 身分 / fail-open alert）。完整流程見 `docs/TYPED_CHAT_CARE_ALERT_FLOW.md`。

> 殘留（CR-0052 follow-up，範圍外）：語音前端 `voice_agent_controller.dart:871` 仍以 `needsHumanSupport` 只在 high/urgent 才送 `/notify`，故語音目前只持久化 high/urgent；打字已持久化 medium+。對齊語音為後續 CR。

---

## 3. 長期記憶紅線

1. 有記憶時可自然引用，但**不要**說「根據紀錄」「資料庫顯示」。
2. 無記憶時**不可捏造**家人、喜好、病史；**不可**說「我記得」假裝知道不存在的事。
3. **不把模型猜測寫成事實。**
4. 回覆中**不暴露**內部 memory id / confidence / vector。
5. 記憶查詢失敗時仍可陪聊，但不可假裝記得。
6. 記憶綁定 `user_id` / `resident_id`，**不可跨住民洩漏**；`/api/companion/chat` 不在端點內重查跨住民記憶。
7. 記憶使用遵守 CR-0047 logging redaction，**不印完整敏感內容 / 完整對話原文**。

---

## 4. 測試覆蓋

- 後端 persona 紅線：`backend/stt_proxy/services/companionChatPersona.test.js`（G1 不假裝執行工具、G2 高風險求助語氣不淡化、G3 記憶界線、台語語言指示）。
- 後端 chat 端點契約：`backend/stt_proxy/services/companionChatEndpoint.test.js`（`invalid_input` / `openai_unavailable`，不回 fake reply / stack）。
- Flutter chat 行為：失敗走陪伴式白話錯誤、不 fallback mock、不顯示工程訊息（CR-0049 / CR-0050 verify）。
