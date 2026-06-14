# CR-0083 Realtime Voice Tool Calling and Tool Subtitle Turn Integrity

## 背景

目前 CR-0080 已完成：

* 寵物長字幕分頁
* 搜尋 intent 關鍵字擴充
* 前後端搜尋判斷對齊
* 避免寵物直接回答「不能馬上查資訊」
* 全套 Flutter test 綠
* 後端測試通過

但後續檢查發現，Realtime 語音互動仍有兩個會直接影響 Demo 體感的核心問題：

## 已確認問題

### 問題 1：Realtime 沒有真正的 tool calling

目前後端送給 OpenAI Realtime 的 `sessionConfig` 沒有掛任何 tools。

語音問搜尋、簽到、商城、任務時，模型本身不會真的呼叫工具，而是靠 Flutter 端 `AiToolRouter` 用關鍵字攔截，再用 `speakToolOutcome()` 把工具結果念回去。

這代表：

```text
使用者語音問題
→ Realtime model 先生成一般回答
→ Flutter 端關鍵字命中才插入工具流程
→ 關鍵字沒命中時，模型仍可能說不能查或亂接話
```

CR-0080 只是把搜尋關鍵字網撐大，沒有根治 Realtime tool calling 結構問題。

### 問題 2：工具回稿可能蓋掉還沒念完的字幕

語音使用工具時，可能發生：

```text
寵物第一段：「好的，我幫你查查看」
語音還沒播完
第二段工具結果 setMessage
字幕被直接換成查詢結果
```

這不是 CR-0080 的長字幕分頁問題，而是「同一個語音回合內，工具前置語與工具結果互相覆蓋」問題。

## 本 CR 目標

本 CR 目標是處理 Realtime 語音工具流程的完整度，尤其是 Demo 體感。

請分成兩階段處理：

### Phase 1：完整盤點與風險確認

先不要直接大改 Realtime 主流程。

請完整盤點：

1. 後端 `/api/realtime/call` 或相關 Realtime session 建立處目前送了哪些 `sessionConfig`
2. 是否有 `tools`
3. 是否有 `tool_choice`
4. 是否有 `instructions`
5. Flutter 端 `AiToolRouter` 如何攔截語音意圖
6. `speakToolOutcome()` 如何更新字幕與語音
7. 工具前置語與工具結果是否共用同一個 message state
8. 哪些工具目前可由語音觸發
9. 哪些工具只存在文字聊天
10. 若接真正 Realtime tools，會不會影響既有文字聊天、Care Alert、Memory、Marketplace、Daily Care Tasks

請輸出文件：

```text
docs/REALTIME_TOOL_CALLING_CR0083.md
```

內容要包含：

* 現況流程圖
* 問題原因
* 可修方案比較
* 最小風險修正建議
* 不建議現在做的部分
* Demo 前必要修正
* Demo 後可做項目

### Phase 2：最小修正

若確認可安全修正，請優先修以下最小問題。

## 必修項 A：避免工具結果蓋掉未完成字幕

### 目標

語音工具流程中，第一段寵物回應與第二段工具結果不能互相覆蓋。

修正後應符合：

```text
寵物說「我幫你查查看」時，字幕維持這句
工具結果回來後，如果前一句還沒播完，不得立即覆蓋字幕
等前一句結束或進入下一個寵物回合，再顯示工具結果
```

### 可接受實作方向

優先使用最小狀態控制：

```text
pendingToolOutcomeMessage
isSpeakingToolIntro
queuedToolOutcome
```

或等價做法。

要求：

1. 工具結果可以排隊
2. 不能直接 setMessage 蓋掉正在播放的語音字幕
3. 若使用者中斷語音，應安全清理 pending message
4. 不產生無限等待
5. 不影響一般 Realtime 對話
6. 不影響文字聊天
7. 不影響 Care Alert
8. 不新增 fake response

## 必修項 B：判斷是否接正式 Realtime tools

請評估是否能在後端 Realtime sessionConfig 加入正式 tools。

### 如果可以安全接

請提出最小工具清單，例如：

```text
web_search
daily_checkin
daily_task_lookup
marketplace_lookup
```

但本 CR 不一定要全部實作。

先以最小可展示工具為主：

```text
web_search
```

要求：

1. 工具 schema 清楚
2. 不把 API key 放到 Flutter
3. 工具實際執行仍由後端處理
4. 不硬編即時資料
5. 工具失敗時回白話 fallback
6. 不破壞既有 Flutter `AiToolRouter`
7. 若風險高，先不要接正式 Realtime tools，只輸出後續 CR 設計

### 如果現在不適合接正式 Realtime tools

請明確說明原因，例如：

```text
OpenAI Realtime event handling 尚未完整
需要新增 response.function_call_arguments.done 事件處理
需要建立 tool output 回送機制
會動到 locked Realtime 主流程
Demo 前風險過高
```

並提出 Demo 前替代方案：

```text
保留 Flutter AiToolRouter，但修好工具結果排隊與字幕覆蓋問題
```

## 必修項 C：搜尋工具不要再只靠關鍵字單點命中

目前 CR-0080 已擴充關鍵字，但仍有漏接風險。

請評估是否能加入更穩的 intent 判斷：

1. 前端仍可保留快速關鍵字 gate
2. 後端作為最終判斷來源
3. 若前端沒命中但模型回覆出現「需要查詢」「我幫你查」等意圖，是否能再次進工具流程
4. 是否能讓文字與語音共用同一個搜尋 intent 服務

此項若風險高，可只輸出後續 CR，不強制本 CR 完成。

## 嚴格限制

不得改動：

* Auth 主流程
* Care Alert 風險判斷
* Telegram 通知
* Marketplace schema
* Daily Care Tasks schema
* PostgreSQL migration
* production env
* secrets
* App icon / pet image assets

不得新增：

* demo-only fake answer
* mock search fallback
* 硬編天氣、補助、新聞、價格
* 會暴露 API key 的 Flutter 搜尋
* 大型套件

## 鎖定檔案提醒

若需要修改：

```text
lib/services/realtime_voice_service.dart
```

請先做 architecture-agent review / approval。

本 CR 可以修改 Realtime 相關檔案，但必須是最小修正，並在文件中說明：

```text
改了哪裡
為什麼必須改
如何確認沒有破壞 Realtime 主流程
```

## 建議優先順序

請依序處理：

1. 工具結果不要覆蓋正在播的字幕
2. Realtime tools 現況盤點
3. 評估正式 Realtime tool calling 是否適合 Demo 前接
4. 搜尋 intent 統一來源設計
5. 文件與測試

## 測試

請至少執行：

```bash
flutter analyze
flutter test
```

若修改後端，請於 `backend/stt_proxy` 執行：

```bash
npm test
```

或：

```bash
npm run check
```

若測試失敗，請記錄：

* 執行了什麼
* 失敗原因
* 是否與本 CR 有關

## 手動驗收

請列出以下手動驗收：

### 工具字幕覆蓋

```text
[ ] 語音問：今天嘉義天氣如何？
[ ] 寵物說「我幫你查查看」時，字幕不會被工具結果提前蓋掉
[ ] 工具結果出現時，語音與字幕能對上
[ ] 若工具較慢，畫面不會卡死
[ ] 若工具失敗，顯示白話 fallback
```

### Realtime tool calling

```text
[ ] 確認目前 sessionConfig 是否有 tools
[ ] 若本 CR 有加 tools，確認工具可被模型呼叫
[ ] 若本 CR 未加 tools，文件需清楚說明原因與後續 CR
```

### 搜尋可靠性

```text
[ ] 語音問天氣不會直接回不能查
[ ] 語音問長照補助不會直接回不能查
[ ] 搜尋失敗時不硬編資料
[ ] 一般陪伴聊天不會被誤判為搜尋
```

## 文件輸出

請新增或更新：

```text
docs/REALTIME_TOOL_CALLING_CR0083.md
```

內容包含：

1. 修改摘要
2. Realtime tool calling 現況
3. Flutter AiToolRouter 現況
4. 工具字幕覆蓋原因
5. 本 CR 修正內容
6. 沒有修的原因與後續 CR
7. 測試結果
8. 手動驗收清單
9. Demo 風險與備援說法

## Commit

若只改 Flutter：

```bash
git add lib test docs tasks
git commit -m "Stabilize realtime tool subtitles"
```

若同時改後端：

```bash
git add lib test backend/stt_proxy docs tasks
git commit -m "Stabilize realtime tool subtitles and audit tool calling"
```

不得加入：

* `.env`
* Firebase private key
* `google-services.json`
* `GoogleService-Info.plist`
* keystore
* `key.properties`
* Render env
* OpenAI API key
* search API key
* `ADMIN_API_TOKEN`
* 未確認用途的 asset PNG 變動

## 驗收標準

完成後應能回答：

1. Realtime 目前是否有真正 tool calling？
2. 如果沒有，為什麼本 CR 有或沒有接？
3. Flutter AiToolRouter 目前扮演什麼角色？
4. 工具回稿為什麼會蓋掉字幕？
5. 現在如何避免工具結果提前覆蓋？
6. 語音問天氣 / 補助是否比 CR-0080 前穩？
7. 是否沒有硬編即時資訊？
8. 是否沒有暴露 API key？
9. 是否沒有破壞 Realtime 主流程？
10. 測試是否通過？
