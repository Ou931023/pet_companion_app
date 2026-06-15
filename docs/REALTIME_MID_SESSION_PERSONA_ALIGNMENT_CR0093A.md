# CR-0093A — Realtime Mid-session Persona Alignment

把 🔒 `lib/services/realtime_voice_service.dart` 內「mid-session / session.update 縮版語音 persona」同步到 CR-0090 的自然度規則。屬 CR-0090 後續小修，用 **A 編號**避免打亂主線 CR-0093（App Icon Replacement）。

---

## 1. 修改動機

CR-0090 改善了**後端**語音 persona（`backend/stt_proxy/server.js` 的 `REALTIME_INSTRUCTIONS` / `outputLanguageInstruction`），但其回報的後續事項指出：`realtime_voice_service.dart` 內另有一份**縮版 persona 副本**（`_instructionsWithCompanionContext`），只在 Realtime 通話中 **Companion Engine 的 nextStrategy 變更**時，透過 `session.update` 送出，未同步 CR-0090 措辭 → session 中途更新會回到較制式、較易重複、較硬轉任務的舊版。本 CR 專門同步這份縮版。

---

## 2. 鎖定檔審查紀錄

`realtime_voice_service.dart` 為 🔒 鎖定檔，已先送 **architecture-agent 審查**：

- **裁決：✅ APPROVED，風險 LOW。**
- 確認：改動僅為兩個私有字串建構器 `_instructionsWithCompanionContext`（≈1279-1300）與 `_outputLanguageGuidance`（≈1302-1310）的**字串內容**；`session.update` payload 形狀不變（`{type, session:{type, instructions}}`，組裝於 `updateCompanionContext` 531-541）。
- 未觸及：SDP / ICE / STUN / DataChannel / RTCPeerConnection / connect-reconnect / response.create·done·cancel / CR-0089 audio-playback 事件 / `_sendEventPayload` 佇列 / tool-outcome flush / 字幕同步 / 任何狀態機或方法簽章。
- 新增安全句為**加法、強化安全**（此縮版原本沒有急性風險升級句）。
- 綁定條件（全部已遵守）：只改兩方法字串內容、不改名/簽章；保留 `$context` 注入與「請優先遵守 nextStrategy，但不要提到 Companion Engine、分析系統或欄位名稱。」框架語；保留 `_outputLanguageGuidance` 的 `replyLanguage=` regex 與 `mixed-zh-taigi`/`taigi`/default 三個 switch key（僅同步措辭）；payload 保持精簡；安全句溫暖不淪為重複醫療口頭禪；以 `eventSenderForTesting` 補測試、不弱化既有 realtime 測試。

完整核准紀錄見 `docs/CHANGE_REVIEW.md` CR-0093A。

---

## 3. 修改位置

| 方法 | 行（約） | 改動 |
|---|---|---|
| `_instructionsWithCompanionContext(context)` | 1279-1300 | persona 字串新增 CR-0090 規則 + 安全句（見 §4） |
| `_outputLanguageGuidance(context)` | 1302-1310 | `taigi` / `mixed-zh-taigi` 措辭同步為「以台語為主、長者聽得懂優先、可國台語混用、不硬翻生僻字」；regex 與 switch key 不變 |

用途：兩者組出 mid-session `session.update` 的 `instructions`，僅在通話中 nextStrategy 變更時送出；與後端起始 `/api/realtime/call` 的 session instructions 是兩條不同路徑。

---

## 4. 同步的 CR-0090 規則（縮版、精簡）

加入 `_instructionsWithCompanionContext`：
- 回覆簡短自然（通常 1～3 句）。
- 普通聊天就自然接話，不要硬把話題帶去提醒 / 喝水 / 吃藥 / 任務；長者明確要求或情境明確需要時才提醒。
- 先接住情緒再回應；安慰要短。不要每句都用「聽起來…」開頭，也不要每次都用「我會一直陪著你」「你不是一個人」這類同一句罐頭。
- 不要每句都用問句收尾。低落、孤單、疲倦時先陪伴，不急著解決、不過度醫療化。
- **安全（新增）**：胸痛 / 呼吸困難 / 跌倒 / 嚴重不適 / 自傷意念 → 提高安全提醒，溫和但明確建議聯絡家人或尋求醫療協助。

台語（`_outputLanguageGuidance`）：以台語為主、長者聽得懂優先、可自然國台語混用、不硬翻生僻台語字、不用大量羅馬拼音。

保留：工具能力、台語模式、nextStrategy 框架語、不外漏分析欄位名稱。

---

## 5. 測試結果

- 新增 `test/realtime_voice_service_test.dart`「CR-0093A: mid-session session.update persona 同步…」：以 `eventSenderForTesting` 捕捉 `session.update` payload，解析 `session.instructions`，斷言含——不硬轉任務、避免重複罐頭、不每句問句收尾、低落先陪伴不過度醫療化、安全句（胸痛…自傷意念）、台語「以台語為主、長者聽得懂優先」、以及保留 nextStrategy 框架語。
- 不影響既有 realtime / CR-0089 audio started/stopped 事件測試。
- 結果：`flutter analyze` **No issues**；`flutter test` **686 passed / 0 failed**。

---

## 6. 已知限制

- 本縮版刻意精簡（mid-call `session.update` 不宜過長），不等於後端起始 persona 的完整版；兩者規則一致但詳略不同。
- 模型輸出非完全 deterministic；測試以「instructions 是否含必要 guardrail 字串」驗證，非硬比對生成內容。
- 僅同步 persona 文字，未改狀態機 / 連線 / 字幕同步 / 工具路由 / Care Alert / Telegram / 後端 persona。
- 主線下一個 CR 仍為 **CR-0093 — App Icon Replacement**（A 編號不佔用主線序號）。
