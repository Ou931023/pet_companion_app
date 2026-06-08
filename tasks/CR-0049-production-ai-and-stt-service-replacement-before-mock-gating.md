# CR-0049 — Production AI and STT Service Replacement Before Mock Gating

## 1. 任務定位

本任務接續 CR-0048。

CR-0048 已完成：

- MockTaigiAsrStrategy production gating
- Settings ASR dropdown production 隱藏 mock 選項
- Flutter build flavor 文件化
- 確認 demo login / dev panel 已由 CR-0034 隔離

但 CR-0048 也確認兩個正式上架 blocker：

1. `MockAiService` 仍是 live production 依賴。
2. `MockSpeechToTextService` 仍是 live production 依賴。
3. production 預設 `sttMode='mock'`。
4. 直接拔掉會破壞 Realtime / ConversationController / AiToolRouter，所以必須先替換正式 service，再做 gating。

本 CR 目標是先建立正式 AI / STT service path，讓 production 不再依賴 mock service。

---

## 2. 本次目標

完成 production AI / STT service replacement：

1. production 不再注入 `MockAiService`。
2. production 不再注入 `MockSpeechToTextService`。
3. production `sttMode` 預設改為正式模式，例如 `openAiProxy` 或現有正式 STT 模式。
4. `AiToolRouter._chat` 的最終 fallback 不再依賴 mock AI。
5. development / test 仍可使用 mock。
6. 不破壞 Realtime WebRTC 主流程。
7. 不破壞 Care Alert notify auth。
8. 不破壞 Memory / Companion Engine。
9. 測試覆蓋 production 不注入 mock。

---

## 3. 必讀文件

請先閱讀：

- `CLAUDE.md`
- `docs/CHANGE_REVIEW.md`
- `docs/FLUTTER_BUILD_FLAVORS.md`
- `docs/STORE_RELEASE_CHECKLIST.md`
- `lib/app.dart`
- `lib/config/app_config.dart`
- `lib/controllers/conversation_controller.dart`
- `lib/controllers/voice_agent_controller.dart`
- `lib/services/ai_tool_router.dart`
- `lib/services/*ai*`
- `lib/services/*speech*`
- `lib/services/*stt*`
- `test/config/asr_strategy_mock_gating_test.dart`
- CR-0048 相關測試

---

## 4. 先盤點

修改前請盤點並回報：

1. `MockAiService` 的介面與所有 consumer。
2. `MockSpeechToTextService` 的介面與所有 consumer。
3. `AiToolRouter._chat` 如何呼叫 AI service。
4. `ConversationController` 如何呼叫 speech-to-text service。
5. Realtime 對話是否其實不需要本地 STT mock。
6. production `sttMode` 目前來源與預設值。
7. 是否已有正式 OpenAI proxy / Companion Engine service 可取代 mock。
8. 是否已有正式 STT proxy service 可取代 mock。
9. 哪些測試依賴 mock。
10. 哪些正式流程會因替換 service 受影響。

---

## 5. AI Service Replacement

### 5.1 Production AI Service

請建立或啟用正式 AI service。

可接受方案：

- 使用既有 backend Companion Engine / `/api/companion/analyze` /正式 chat endpoint。
- 使用既有 OpenAI proxy service。
- 建立最小正式 backend AI service adapter，但不可直接在 Flutter 放 OpenAI API key。

不可接受：

- production 仍注入 `MockAiService`
- Flutter 端硬編 OpenAI API key
- fake response
- demo-only response
- silent fallback mock
- 空回覆假裝成功

### 5.2 AiToolRouter._chat

`AiToolRouter._chat` 的最終回覆路徑需接正式 service。

要求：

1. 工具型請求維持現有 tool flow。
2. 非工具語句 fallback 不可走 MockAiService。
3. 正式 service 失敗時需回傳可理解錯誤或陪伴式失敗訊息，但不可假裝 AI 成功。
4. 不破壞既有 tool calling 測試。
5. 不破壞 Realtime 本地指令流程。

---

## 6. STT Service Replacement

### 6.1 Production STT Mode

production 預設 `sttMode` 不可為 `mock`。

請改成正式模式，例如：

- `openAiProxy`
- `realtime`
- 專案既有正式 STT mode

實際名稱請依程式碼現況決定，不要憑空新增不相容 enum。

### 6.2 Production SpeechToText Service

production 不可注入 `MockSpeechToTextService`。

可接受方案：

- 使用正式 OpenAI STT proxy service。
- 使用 Realtime transcript path。
- 使用平台 speech-to-text service if already implemented。
- 若某些功能僅 development 使用本地 STT，production 應隱藏或 disable 該入口，而不是 mock。

不可接受：

- production fallback 到 mock transcript
- production 顯示 Mock STT 字樣
- production 沒 token 時自動假 transcript
- production 無聲失敗但 UI 顯示成功

---

## 7. Provider Wiring

請修改 `lib/app.dart` 或相關 provider wiring：

1. production：注入正式 AI service。
2. production：注入正式 STT service。
3. development/test：可依 flag 注入 mock。
4. 若 production 缺必要 API config，應顯示安全錯誤或 fail-fast。
5. 不得無條件建立 mock service instance。
6. 不得在 production provider tree 內保留 mock fallback。

---

## 8. UI / Settings

請檢查：

1. Settings 中 STT 模式選項。
2. 任何 Mock STT、Demo AI、Fake AI 字樣。
3. production 不應看到 mock 選項。
4. 若某個 STT 功能尚未正式可用，production UI 應隱藏或顯示「尚未啟用」且不產生假資料。

---

## 9. 測試需求

請至少新增或更新 Flutter 測試：

1. production provider tree 不注入 `MockAiService`。
2. production provider tree 不注入 `MockSpeechToTextService`。
3. production `sttMode` 預設不是 `mock`。
4. development/test 可明確注入 mock。
5. `AiToolRouter._chat` production path 使用正式 AI service adapter。
6. 正式 AI service 失敗不 fallback mock。
7. production STT 失敗不 fallback mock。
8. Settings production 不顯示 Mock STT。
9. Realtime / ConversationController 相關既有測試全綠。
10. Care Alert notify auth 相關測試不受影響。

---

## 10. 文件需求

請更新：

- `docs/CHANGE_REVIEW.md`
- `docs/FLUTTER_BUILD_FLAVORS.md`
- `docs/STORE_RELEASE_CHECKLIST.md`
- `docs/ENVIRONMENT_SETUP.md` if needed

文件需說明：

1. production AI service path。
2. production STT service path。
3. development/test mock 如何啟用。
4. production 不再允許 mock fallback。
5. release 前如何驗證 mock 已完全隔離。

---

## 11. 限制

本 CR 不得：

1. 破壞 Realtime WebRTC。
2. 破壞 Care Alert notify auth。
3. 破壞 Memory API。
4. 破壞 Companion Engine。
5. 在 Flutter 端放 OpenAI API key。
6. 用 fake response 取代正式 AI。
7. 用 fake transcript 取代正式 STT。
8. production fallback mock。
9. 硬刪 mock 導致 development/test 失效。
10. 為通過測試放寬 production guard。

---

## 12. 驗收標準

完成後必須符合：

1. production 不注入 `MockAiService`。
2. production 不注入 `MockSpeechToTextService`。
3. production `sttMode` 預設不是 `mock`。
4. production 不顯示 Mock STT / Demo AI 字樣。
5. development/test mock 仍可測。
6. Flutter analyze 通過。
7. Flutter 相關測試通過。
8. Realtime / ConversationController / AiToolRouter 相關測試通過。
9. STORE_RELEASE_CHECKLIST 更新狀態。
10. 無 hardcoded token / fake response / fake transcript。

---

## 13. 完成回報格式

請用以下格式回報：

```md
## CR-0049 完成回報

### 1. 本次目標
-

### 2. 修改檔案
-

### 3. Mock 依賴盤點
-

### 4. AI service replacement
-

### 5. STT service replacement
-

### 6. Provider wiring 改動
-

### 7. Settings / UI 隔離
-

### 8. 測試結果
-

### 9. 正式版風險檢查
- production 是否仍注入 MockAiService：
- production 是否仍注入 MockSpeechToTextService：
- production sttMode 是否仍為 mock：
- production 是否仍 fallback mock：
- 是否有 fake response：
- 是否有 fake transcript：
- 是否破壞 Realtime / Care Alert / Memory：

### 10. 殘留風險
-

### 11. 下一個建議 CR
-
```
