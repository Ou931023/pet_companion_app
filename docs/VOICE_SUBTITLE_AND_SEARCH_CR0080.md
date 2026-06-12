# CR-0080：寵物語音字幕同步 + 上網搜尋可靠性

本文件記錄 CR-0080 兩個 Demo 前高優先修正：
（A）寵物語音字幕與語音不同步、會提前翻頁；
（B）使用者問即時資訊時，寵物常回「不能馬上查」。

兩者都遵守專案鐵則：**不改 Realtime WebRTC 主流程、不做假搜尋、不硬編即時資訊、不顯示工程錯誤訊息。**

---

## 1. 修改摘要

| 區塊 | 檔案 | 改了什麼 |
| --- | --- | --- |
| A 字幕分頁 | `lib/widgets/pet_subtitle_text.dart`（新增） | 寵物字幕分頁器：把長回覆切成「最多兩、三行、長者好讀」的短頁，用**保守估算、略慢於語音**的節奏自動翻頁，絕不提前翻頁。 |
| A 字幕分頁 | `lib/widgets/speech_bubble.dart` | 新增 `enablePaging`；寵物字幕改用 `PetSubtitleText`，等待/使用者泡泡維持原樣。 |
| A 字幕分頁 | `lib/widgets/conversation_bubble_stack.dart` | 只有「寵物字幕」時 `enablePaging: true`。 |
| B 搜尋判斷 | `lib/services/web_search_service.dart` | 擴充 `shouldSearch` 的即時資訊關鍵字（天氣／新聞／補助／政策／價格時刻／災防／申請流程…），並抽成 `realtimeInfoKeywords`。 |
| B 搜尋判斷 | `backend/stt_proxy/services/tavilySearchService.js` | `needsWebSearch` 改用同一份 `REALTIME_INFO_KEYWORDS`，**與前端對齊**。 |
| B 拒絕文案 | `backend/stt_proxy/server.js`（`COMPANION_CHAT_PERSONA`） | 新增「【即時資訊】」段落：問即時資訊時不可冷冰冰回「我不能馬上查」，要溫暖接住並給可行動方向；同時嚴禁編造假的即時數字。 |

> 後端 `/api/web/search`、`/api/realtime/call` 等路由與 response 形狀**未變**（API 契約不動）。

---

## 2. Part A：字幕不同步原因與修法

### 原因

- 字幕泡泡（`SpeechBubble`）原本是「一次顯示完整回覆、`maxLines` 6 行 + `…` 截斷」。
  長回覆會被截掉、長者看不到後段；而真正會「字幕跳頁」的時機是寵物用工具
  （例如搜尋）時的第二段念稿覆蓋第一段——第一段語音還沒念完、字幕就被換掉。
- 專案內**原本沒有**任何「依語音節奏分頁」的機制，需要新建，且不可用純 timer 亂翻。

### 修法（`PetSubtitleText`）

1. **分頁**：依中文／台語標點（。！？，、；：）與換行切成自然短句，貪婪合併成
   每頁約 28 字（最多兩、三行）。無標點的超長句會硬切，避免單頁爆行。
2. **翻頁節奏（保守估算，絕不提前）**：
   `每頁停留 = max(2.8s, 該頁字數 / 每秒 3.2 字)`。
   念稿速度刻意估得比實際語音（約每秒 4 字）**慢**，所以字幕只會「跟在語音後面」，
   不會搶在寵物還沒念完就翻到下一頁。
3. **單頁不翻頁**：短回覆只有一頁、行為與過去相同，也不會留下待處理計時器。
4. **新回覆重來**：`text` 改變（新一輪回覆）時從第一頁重新開始。
5. **長者友善**：多頁時顯示小圓點，讓長者知道「還有後續、現在在第幾頁」。

> 註：本 CR 不修改 `lib/services/realtime_voice_service.dart`（Realtime 主流程）。
> 字幕分頁完全在 UI 層完成，對 Realtime / 一般 TTS 兩條路徑共用的字幕泡泡都生效。

---

## 3. Part B：搜尋常回「不能馬上查」原因與修法

### 原因盤點（實際追過的流程）

1. App 已有真正的搜尋：後端 `/api/web/search` → `tavilySearchService`
   （天氣走 Open-Meteo、其他走 Tavily，再用模型整理成長者好讀的 2–4 句）。
2. 不論**語音或打字**，搜尋都先經前端 `AiToolRouter.route()` →
   `WebSearchService.shouldSearch()` 這道 intent 閘門；命中才會打 `/api/web/search`，
   語音路徑再由 `speakToolOutcome()` 把結果念出來。
3. **真正的破口是 intent 偵測太窄**：像「最近有什麼長照補助」「敬老津貼怎麼申請」
   沒命中關鍵字 → 不進搜尋 → 落到一般陪伴聊天 → 模型只能靠 prompt 回應，
   產生「我不能馬上查」這類拒絕句。
4. 次要破口：打字聊天的 `COMPANION_CHAT_PERSONA` 沒教模型「遇到查不到的即時資訊該怎麼
   溫暖回應」，容易冷冰冰拒絕。

### 修法

1. **擴充 intent 並前後端對齊**：`shouldSearch`（前端）與 `needsWebSearch`（後端）
   共用同一份關鍵字清單，涵蓋天氣／新聞／補助／津貼／政策法規／價格時刻／災防／申請流程。
   兩端對齊可避免「前端要查、後端說不用查」而回出生硬訊息。
   - 刻意不放單獨的「今天／現在／最近」，避免把「我今天有點累」這類心情話誤判成搜尋。
2. **persona 不再硬拒絕**：打字聊天遇到漏接的即時資訊問題時，先接住心意、再給白話可行動
   方向（例如：用語音說「幫我查○○」就能上網查、看氣象、問家人），**但嚴禁編造**任何
   天氣／金額／新聞／補助細節假裝查到了。
3. **失敗時白話、不假裝**：搜尋工具失敗沿用既有白話 fallback（「現在好像連不上網路，
   我晚點再幫你查。」／「搜尋暫時失敗了，我晚點再幫你查。」），不顯示 API error /
   stack trace / tool raw error，也不假裝查到了。

### 安全原則（維持不變）

- 搜尋一律由後端處理；Flutter 端只呼叫安全 endpoint，**不持有任何搜尋 / OpenAI API key**。
- 不硬編即時資訊；查不到就誠實說還沒查到。

---

## 4. 驗收與測試

### 後端（`node --test`，純函式、不打外部 API）

- `services/tavilySearchService.test.js`：`needsWebSearch` 新增天氣/補助/政策/價格/颱風等
  正向案例，並確認「我今天有點累／我現在心情不太好／最近都睡不好」仍判為非搜尋。
- `services/companionChatPersona.test.js`：驗證 persona 含「【即時資訊】」段落、不可回
  「我不能馬上查」、需引導「幫我查○○」、且不可編造假資訊。
- 結果：14 項通過。

### 前端（`flutter test`）

- `test/services/web_search_intent_test.dart`（新增）：`shouldSearch` 正向（含補助/政策/
  價格/天氣變體）、負向（一般陪伴聊天）、空字串。
- `test/widgets/pet_subtitle_text_test.dart`（新增）：分頁正確、不漏字、超長無標點硬切、
  單頁不留計時器。
- `test/conversation_ui_state_test.dart`（更新）：長回覆改為「分頁且不 overflow、不會把整段
  塞進單一 Text」，並排空翻頁計時器。
- 結果：上述相關測試全數通過（20/20）。

> 既有 `test/config/mock_service_provider_gating_test.dart` 在 **改動前的 baseline 就無法編譯**
> （`_ThrowingChatService.reply` 與 `CompanionChatService.reply` 簽章不一致），與本 CR 無關，
> 未在本 CR 範圍內修改。

### 手動驗收建議（語音 / 打字皆可）

1. 問「今天嘉義天氣如何？」→ 應進搜尋並念出天氣，不再回「不能查」。
2. 問「最近有什麼長照補助？」→ 應進搜尋。
3. 問「現在有什麼重要新聞？」→ 應進搜尋。
4. 模擬搜尋失敗（例如後端離線）→ 應出現白話 fallback，不出現工程錯誤。
5. 確認不會硬編即時資料（查不到就誠實說晚點再查）。
6. 確認「我今天有點累」這類陪伴聊天不會被誤判成搜尋。
7. 字幕：請寵物講一段較長的話 → 字幕一頁一頁顯示、語音念完該頁前不會提前翻頁。

---

## 5. 沒有改動的部分（刻意）

- Realtime WebRTC 主流程（`lib/services/realtime_voice_service.dart`）。
- Auth、Care Alert 風險分析、Marketplace、Daily Care Tasks。
- 任何 `/api` 路由與 response 形狀（API 契約）。
