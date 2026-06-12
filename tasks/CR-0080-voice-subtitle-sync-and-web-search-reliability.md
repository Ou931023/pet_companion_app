# CR-0080 Voice Subtitle Sync and Web Search Reliability

## 背景

目前 App 已進入正式 Demo 前收尾階段。CR-0076 UX Audit 已指出 App 整體價值鏈成立，但使用者又發現兩個會直接影響 Demo 觀感的問題：

1. 寵物語音字幕會分成兩頁，但寵物第一頁還沒說完，字幕就跳到第二頁，造成語音與字幕不同步。
2. 上網搜尋功能尚不完整，使用者詢問需要即時資訊時，寵物常回覆「不能馬上查資訊」或類似拒絕句，讓 AI Agent 能力看起來不足。

本 CR 目標是修正這兩個 Demo 前高優先問題，讓語音互動與即時查詢更像正式陪伴 App，而不是工程展示版。

## 本 CR 核心目標

### 目標 1：修正字幕與語音不同步

寵物說話時，字幕應該跟語音節奏一致。

目前問題：

```text
字幕第 1 頁還沒念完 → UI 自動跳到字幕第 2 頁
```

修正後應達成：

```text
寵物正在講第 1 頁內容時，畫面維持第 1 頁。
等第 1 頁語程

## 重要安全原則

如果需要搜尋功能，必須由後端處理，不可把外部搜尋 API key 放到 Flutter。

Flutter 端只能呼叫後端既有或新增的安全 endpoint，例如：

```text
/api/agent/tools
/api/agent/search
```

不可在 App 內直接放：

* OpenAI API key
* search provider API key
* browser automation secret
* backend admin token

---

# Paread -100
```

請確認：

1. 寵物說話文字在哪裡儲存？
2. 字幕如何分頁？
3. 字幕何時自動跳下一頁？
4. 語音播放完成事件在哪裡觸發？
5. `finishPetTurn` / `pauseMicInput` / audio completion 是否可用來同步字幕？
6. Realtime 與一般 chat/TTS 是否共用字幕 UI？

## A2. 問題判斷

目前禁止用純 timer 直接翻頁，因為 timer 不一定和語音長度一致。

錯誤做法：

```text
每隔固定秒數自動跳下一頁
文字顯示完就立即跳下一頁，不管語音是否播完
依照字數估算後強制跳頁，但沒有等待 audio completion
```

正確方向：

```text
同一個完整回答再分頁，請改成：

```text
以句號、逗號、換行、台語/中文標點切成短段落
每段字幕搭配一段語音或一段顯示狀態
```

每頁字幕建議限制：

```text
中文 28～42 字
最多 2 行
長者閱讀友善
```

### 策略 3：若無法精準取得 audio completion

如果目前拿不到每段語音完成事件，請使用保守估算，但不得提前翻頁：

```text
estimatedDuration = max(2.5s, 字數 / 每秒 4～5 字)
```

並且：

```text
ce、Daily Care Tasks。

---

# Part B：上網搜尋功能可靠性修正

## B1. 先盤點目前搜尋能力

請先搜尋：

```bash
grep -R "search\|web\|browse\|tool\|agent" -n lib backend/stt_proxy | head -200
```

請確認：

1. App 是否已有搜尋入口？
2. 使用者問即時資訊時，目前走哪個 service？
3. 是否走 `agent_router_service.dart`？
4. 後端是否已有 `/api/agent/tools`？
5. tool calling 是否有 web search 類工具？
6. 目前為什麼會回「不能馬上查資訊」？
7. 是 prompt 問題、routing 問題、tool 未接上，還是 fallback 文案問題？

## B2. 搜尋功能應支援的問題類型

至少要能正確判斷以下問題需要即時資訊：

```text
今天嘉義使用者問即時資訊時，要進入 search/tool route。
2. 不可讓模型直接拒絕「不能馬上查」。
3. tool 失敗時，要回白話 fallback。
4. fallback 不得假裝查到了。
5. 回覆要像陪伴 App，不像搜尋引擎。

### 若後端尚未有正式 search tool

請至少做到：

1. 明確判斷需要搜尋的 intent。
2. 回覆白話且可行動。
3. 不使用「我不能馬上查資訊」這 再補充 1～3 點。
3. 適合長者閱讀，不要太長。
4. 若資訊有時間性，提醒「這是目前查到的結果」。
5. 不要列太多網址。
6. 不要用工程格式 JSON。
7. 不要讓寵物語氣變成客服。

範例：

```text
阿明，我幫你查到了。今天嘉義天氣偏熱，外出散步記得帶水，也可以選早上或傍晚比較舒服的時間。
```

## B5. 搜尋功能驗收標準

完成後至少測試：

1. 問「今天嘉義天氣如何？」不應直接回不能查。
2. 問「最近有什麼長照補助？」不應直接回不能查。
3. 搜尋工具不可用時，應顯示白話 fallback。
4. 不可硬編即時資訊。
5. 不可顯示 API error / stack trace / tool raw error。
6. Flutter 不可持有搜尋 API secret。
7. 不影響一般陪伴聊天。
8. 不影響 Care Alert 風險分析。

---

# Part C：文件輸出

請新增：

```text
docs/VOICE_SUBTITLE_AND_SEARCH_CR0080.md
```

內容包含：

1. 修改摘要
2. 字幕不同步原搜尋

1. 問：「今天嘉義天氣如何？」
2. 問：「最近有什麼長照補助？」
3. 問：「現在有什麼重要新聞？」
4. 模擬搜尋失敗，確認不會出現工程錯誤。
5. 確認不會硬編即時資料。
6. 確認一般陪伴聊天不會被誤判成搜尋。

---

# Part F：Commit

若只改 Flutter：

```bash
git add lib docs tasks
git commit -m "Fix voice subtitle sync and search fallback UX"
```

若同時改後端：

```bash
git add lib backend/stt_proxy docs tasks
git commit -m "Fix voice subtitle sync and search reliability"
```

不得加入：

* `.env`
* Firebase private key
* `google-services.json`
* `在搜尋成功與失敗分別怎麼回？
6. 是否沒有硬編即時資訊？
7. 是否沒有改動 Realtime 主流程？
8. `flutter analyze` 是否通過？
9. 若改後端，backend tests 是否通過？

