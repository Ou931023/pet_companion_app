# CR-0079 — Elderly Friendly Error Message Polish

> 日期：2026-06-12
> 來源：CR-0076 UX Audit（`docs/UX_AUDIT_CR0076.md` §10）認定的 Demo 前唯一程式碼 P0。
> 性質：只改「錯誤訊息顯示層」，不改任何功能流程、不改 API 契約、不碰 Realtime 連線主流程。

---

## 1. 修改摘要

把 3 處會將工程錯誤訊息直接顯示給長者的地方，改成白話、可行動的提示：

1. Agent Router（工具呼叫）失敗時不再外洩 `error.toString()`、HTTP 狀態碼與 `agent route` 字眼；工程細節改進 `debugPrint` log。
2. Realtime data channel 收到 API `error` 事件時，原始（多為英文）訊息只進 log，UI 一律顯示白話提示並引導改用打字聊天。
3. 設定頁「進階診斷」的「最近錯誤」不再顯示 Dart enum 名稱（如 `sdpExchangeFailed`），改用既有的中文白話 `message` extension。

`lib/services/realtime_voice_service.dart` 為 🔒 鎖定檔：本次修改已先經 architecture-agent 審查核准（結論：核准 / 風險 low，紀錄見 `docs/CHANGE_REVIEW.md` CR-0079 條目），並由 realtime-voice-agent 依核准 diff 執行。

## 2. 原始問題

| 位置 | 原行為 | 長者會看到 |
|---|---|---|
| `lib/services/agent_router_service.dart:57` | `errorMessage: 'agent route failed: ${statusCode}'` | `agent route failed: 500` |
| `lib/services/agent_router_service.dart:64` | `errorMessage: 'agent route timeout'` | `agent route timeout` |
| `lib/services/agent_router_service.dart:66` | `errorMessage: error.toString()` | 例如 `ClientException: Connection refused` |
| `lib/services/realtime_voice_service.dart:794` | fallback 文案 `'Realtime API 發生錯誤'` | 工程詞「Realtime API」 |
| `lib/services/realtime_voice_service.dart:798` | `_emit(error, message)` 直接外送 API 原文 | 英文 API 錯誤訊息（經 `voice_agent_controller._handleRealtimeFailure` 在 `lastFailureType == none` 時直接成為按鈕錯誤文字） |
| `lib/screens/settings_screen.dart:890` | `'${lastFailure.name}：…'` | enum 原名如 `sdpExchangeFailed` |

## 3. 修改檔案

- `lib/services/agent_router_service.dart`
- `lib/services/realtime_voice_service.dart`（🔒，經 architecture-agent 核准、realtime-voice-agent 執行）
- `lib/screens/settings_screen.dart`
- `test/services/agent_router_service_test.dart`（更新 1 個斷言、新增 2 個測試）
- `test/realtime_voice_service_test.dart`（新增 1 個測試）

## 4. 白話文案對照表

| 情境 | 原訊息 | 現在的白話訊息 |
|---|---|---|
| Agent Router HTTP ≥ 400（服務忙碌 / API 錯誤） | `agent route failed: 500` | 寵物現在回應比較慢，請稍等一下再試一次。 |
| Agent Router 逾時 | `agent route timeout` | 等待時間比較久，請稍後再試一次。 |
| Agent Router 網路 / 其他例外 | `ClientException: …` 等原始字串 | 目前連線不太穩，請確認網路後再試一次。 |
| Realtime API error 事件（含英文原文與無 message fallback） | 英文 API 原文 / `Realtime API 發生錯誤` | 語音連線暫時不穩，請稍後再試一次，也可以先用打字和寵物聊天。 |
| 設定頁診斷「最近錯誤」 | `sdpExchangeFailed：…`（enum 原名） | 既有 `RealtimeFailureTypeLabel.message` 中文文案（如「連線不太穩，正在幫你重新連接。」） |

所有原始工程細節（HTTP 狀態碼、exception、API 原文）仍完整進 `debugPrint` / `_log`，觀測性不變。

## 5. 未改動範圍（明確不做，附原因）

- **Realtime 連線主流程**：`_isStopping` guard、`_isSpeaking` 重置、SDP/ICE/DataChannel、`_recordFailure` 狀態機完全未動。
- **同檔另外兩處 `_emit(RealtimeEventType.error, …)`**（`realtime_voice_service.dart` 約 350 / 1124 行）：350 行前一行已 `_recordFailure`，controller 端會改用 `failureType.message` 白話文案，使用者看不到英文；1124 行本來就 emit 白話訊息。
- **`lib/controllers/agent_tool_controller.dart:92`** 的 `error.toString()`：不在本 CR 允許檔案清單；且 `AgentRouterService.route()` 已自行 catch 所有例外並回傳白話訊息，此 catch 路徑實務上難以觸發。建議併入後續錯誤訊息掃尾。
- **`lib/models/agent_route_result.dart:31`**（`json['error']?.toString()`）：backend 回傳的 error 字串透傳，屬 API 契約層，不在本 CR 範圍；backend `/agent/route` 失敗時 Flutter 端已走 HTTP ≥ 400 白話路徑，實際外漏面有限。
- **`caregiver_web/app.js:2929`**：管理端（照護人員）且已有白話 fallback，CR-0076 列為 P2，另行處理。
- **既有 analyze error**：`test/config/mock_service_provider_gating_test.dart:160` 的 `invalid_override` 為 CR-0072 加 `history` 參數後的既有問題，與本 CR 無關、未處理。

## 6. 測試結果

- `flutter test test/services/agent_router_service_test.dart` → **4/4 通過**（更新逾時斷言；新增 HTTP 500 與網路例外兩案例，斷言不含狀態碼 / `agent route` / exception 字串）
- `flutter test test/realtime_voice_service_test.dart` → **18/18 通過**（新增：餵英文 error 事件，斷言 emit 的 payload 等於白話訊息且不含原文）
- `flutter test test/voice_agent_controller_realtime_lifecycle_test.dart test/realtime_timeout_test.dart` → **30/30 通過**（下游狀態機不受影響）
- `flutter analyze` → 僅剩上述 1 個與本 CR 無關的既有 error，本次修改檔案 0 issue

## 7. 驗收標準快答

1. **修掉哪 3 處？** agent_router_service（3 條錯誤路徑）、realtime_voice_service error 事件分支、settings 診斷 enum 顯示。
2. **長者現在看到什麼？** 見 §4 對照表，全部白話、含下一步。
3. **Realtime 失敗會引導打字嗎？** 會：「…也可以先用打字和寵物聊天。」
4. **settings enum 轉中文了嗎？** 是，改用既有 `.message` extension。
5. **Realtime 主流程有動嗎？** 沒有，僅 emit 字串內容；經 architecture-agent 驗證核准。
6. **flutter analyze 過了嗎？** 本次修改檔案 0 issue；僅剩 1 個既有、無關的測試檔 error（見 §5）。
