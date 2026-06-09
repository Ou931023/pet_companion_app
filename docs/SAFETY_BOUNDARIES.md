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

### 已知殘留（CR-0050 範圍外）

`POST /api/companion/chat` 目前**只**讓 persona 用安全語氣回覆高風險文字，**不會建立 Care Alert 紀錄**（沒有寫入 `care_alerts`、不觸發通知）。語音 / Care Alert pipeline 不受影響。將打字高風險文字接上風險分級 + Care Alert 建立，列為後續 CR（需先由 architecture-agent 確認權威 risk level 代碼）。

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
