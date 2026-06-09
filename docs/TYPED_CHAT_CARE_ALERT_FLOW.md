# TYPED_CHAT_CARE_ALERT_FLOW — 打字聊天的情緒/風險分析與 Care Alert

本文件說明 `POST /api/companion/chat`（長者打字聊天）如何進入情緒/風險分析、何時建立 Care Alert、通知規則，以及與語音路徑的一致性與差異。

最後更新：CR-0052（語音 persist gate 已對齊；語音細節見 `docs/VOICE_CARE_ALERT_FLOW.md`）。

---

## 1. 流程概觀

1. 長者打字 → Flutter `CompanionChatService.reply()` 帶 `Authorization: Bearer <住民 idToken>` 呼叫 `POST /api/companion/chat`。
2. 後端 `requireResidentCaller`（CR-0045）驗證 token → 由 token 權威推導 `elderId`（**不信任 client 傳入的 elderId**）。
3. 產生陪伴回覆（CR-0050 persona，`buildCompanionChatInstructions` + `generateCompanionReply`，回覆文字不受風險分析影響）。
4. 回覆成功後，做**純函式風險側錄**：`analyzeCompanionTurn(userText)` 取 `safety.riskLevel` + `careAlertSummary`（**不重查記憶、不查知識、不寫記憶**，避免跨住民 I/O）。
5. `normalizeRiskLevel(...)` 正規化（legacy `normal→low`、`attention→medium`）。
6. **send predicate**：`riskLevel ∈ {medium, high, urgent}` 才建立 Care Alert，經共用 `processCareAlert(body)`（與 `/api/care-alerts/notify` 同一條 persist + cooldown + notification-log + Telegram 管線）。`low` / 中性句**不建立、不持久化**。
7. 回應加上向後相容 optional 欄位 `careAlert`（見 §4）。

---

## 2. Risk Level（正式四級）

`low / medium / high / urgent`，由 `backend/companion/safety_guard.js` `classifySafety()` 直接輸出，與語音路徑**共用同一個分類腦**（不另寫規則）：

| riskLevel | 訊號（例） | 建立 alert（打字） | Telegram |
|---|---|---|---|
| `urgent` | 自傷/自殺、急性醫療、跌倒昏倒、立即危險 | ✅ | ✅ 立即 |
| `high` | 強烈絕望、明顯無助 | ✅ | ✅ |
| `medium` | 明顯孤單、低落、睡不好、食慾差 | ✅ | ❌（只進 store / caregiver_web） |
| `low` | 一般狀態、中性句（catch-all 預設） | ❌ 不建立 | ❌ |

`attention` 是 legacy 代碼，**不作為新資料**：`normalizeRiskLevel` 在寫入前一律 `attention→medium`、`normal→low`，`careAlertStoreService` 寫入時再正規化一次，新 `care_alerts` 列只會是四級之一。

---

## 3. Alert Source 與通知

- 打字聊天建立的 alert `source = "companion_chat"`（語音路徑為 `companion_analysis`）——兩者為**獨立 cooldown 來源**，高風險推播互不抑制。
- persist / notify 門檻沿用既有：`/notify` 收到即持久化；`shouldTelegramNotify`（`TELEGRAM_NOTIFY_LEVELS = {high, urgent}`）只推 high/urgent；cooldown 防洗版；每次寫 `notification_logs`。
- `triggerSummary` 用 `buildCareAlertSummary`（白話、非診斷、已截斷）；`transcriptSnippet` 截前 200 字（§9.2 不存過長原文）；通知不含完整對話原文。

---

## 4. Response 契約（向後相容）

成功回應：

```json
{ "success": true, "reply": "...",
  "careAlert": { "created": true, "riskLevel": "high", "id": "..." } }
```

- 中性句 / low：**省略** `careAlert` 欄位。
- warranted 但持久化失敗：`{ "created": false, "riskLevel": "<level>", "id": null }`。
- `created` 反映**持久化**，非通知（medium alert 會 `created:true` 但 Telegram skipped）。
- **只暴露 `riskLevel`**：不回 internal risk debug / system prompt / token / raw model payload / 完整敏感原文。
- Flutter 既有 `reply` 解析不受影響；`careAlert` 嚴格 optional，長者端**不渲染**任何監控感文案（後台才看 Care Alert）。

---

## 5. Auth（fail-closed 身分 / fail-open alert）

- 身分/授權失敗（無 token / 無效 token / 跨住民 / 未綁定 / inactive）→ **401/403，無回覆、無 alert**（fail-closed）。
- alert 端失敗（persist / Telegram 失敗）→ **回覆仍 200，`careAlert.created=false`**（fail-open；陪伴回覆永不被 alert 端問題阻擋）。
- production 不接受 fake token；log 不印 token / 完整 chat / 完整 summary。
- 後端 hard-auth 與 Flutter 送 token **必須同一 release**（CR-0051 B + C 同批）。

---

## 6. 與語音路徑的差異與一致性

- **一致**：分類腦（`analyzeCompanionTurn`/`safety_guard`）、四級代碼、persist+notify 管線、cooldown 機制完全共用。
- **persist 門檻一致（CR-0052 已對齊）**：語音前端 `voice_agent_controller.dart` 的 persist gate 已由 `needsHumanSupport`（僅 high/urgent）改為 canonical-riskLevel-based `shouldPersistCareAlert`（`{medium, high, urgent}`），與打字聊天 send predicate 一致 → 語音與打字現在都持久化 medium+。Telegram 仍只 high/urgent（後端 `TELEGRAM_NOTIFY_LEVELS` 權威決定，前端不複製）。詳見 `docs/VOICE_CARE_ALERT_FLOW.md`。
- **僅存差異（設計如此）**：alert `source` 不同（語音 `companion_analysis` / 打字 `companion_chat`）→ 獨立 cooldown 來源；`needsHumanSupport` 仍是語音端可讀的「是否需人為關懷」語意旗標（high/urgent），但**不再**作為 persist gate。

---

## 7. 為何不向長者顯示監控感文案

Care Alert 的定位是「陪伴過程中的異常提醒」，前台寵物以陪伴語氣互動、**後台才做風險分析與通知**（CLAUDE.md §7）。在長者端顯示「已建立風險警示／已通知照護人員」會造成被監視感，違反產品定位，故 Flutter 解析 `careAlert` 後不渲染任何新文案。

---

## 8. 資料治理註記

打字聊天接上 Care Alert **未新增資料類別或同意範圍**（`care_alerts` / `notification_logs` / caregiver_web 本就支援 medium/low，Care Alert 已在既有同意範圍內）。惟此變更**提高了寫入 caregiver console 的頻率**（medium 訊號現在也會被記錄）。隱私/資料安全揭露（`docs/GOOGLE_PLAY_DATA_SAFETY.md` 等）描述 Care Alert 蒐集時，應涵蓋打字聊天亦為來源之一。
