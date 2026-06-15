# CR-0090 — Companion Conversation Naturalness Polish

## 目標

改善 AI 寵物的對話自然度，讓長者端語音與打字聊天更像「溫和陪伴的寵物」，避免一直重複同樣內容、過度制式、過度建議、或每次都硬轉成提醒／任務。

本 CR 專注於「回覆內容品質」與「陪伴語氣」，不處理字幕同步、寵物素材、推播、Care Alert、後台分析或 App icon。

---

## 背景

目前系統已完成：

```text
CR-0086 — Caregiver Analytics Dashboard
CR-0087 — Pet Concern Push Notifications
CR-0088 — Mochi Pet Asset Integration and Pet State Trigger Expansion
CR-0089 — Voice Caption Synchronization Polish
```

現在語音、字幕、寵物狀態與後台已經更穩定，下一步要改善展示時最容易被感受到的問題：

```text
對話有時太像罐頭
容易重複同樣句型
安慰語氣不夠自然
有時過度引導任務或提醒
長者低落時回覆不夠細膩
台語模式的陪伴感可以更自然
```

---

## 核心原則

AI 寵物應該像：

```text
溫柔
簡短
自然
有陪伴感
不急著說教
不過度醫療化
不一直重複
能聽懂長者情緒
必要時才輕輕提醒
```

不應該像：

```text
醫師
客服機器人
制式助理
一直推功能的 App
一直重複同一句安慰話的機器人
```

---

## 範圍

### 本 CR 要做

- 盤點目前語音與打字聊天 persona / instructions。
- 改善 AI 寵物回覆規則。
- 增加避免重複的回覆策略。
- 加強長者低落、孤單、疲倦、睡不好等情境的自然安慰。
- 加強台語模式的自然陪伴感。
- 調整工具使用前後的語氣，避免每次硬轉功能。
- 補測試或 snapshot / golden style case。
- 新增文件並更新 `docs/CHANGE_REVIEW.md`。

### 本 CR 不做

- 不改 Realtime 連線主流程。
- 不改字幕同步；CR-0089 已處理。
- 不改寵物圖片與狀態觸發；CR-0088 已處理。
- 不改推播通知；CR-0087 已處理。
- 不改 Care Alert / Telegram。
- 不改後台分析頁。
- 不改 App icon。
- 不新增 DB schema。
- 不讀 `.env`。
- 不把安全邊界拿掉。
- 不讓 AI 做醫療診斷或承諾治療效果。

---

## 可能涉及檔案

請先盤點，實際檔名以專案為準。

可能涉及：

```text
backend/stt_proxy/server.js
backend/stt_proxy/services/companion/*
backend/stt_proxy/services/agent/*
backend/stt_proxy/prompts/*
docs/COMPANION_PERSONA.md
docs/SAFETY_BOUNDARIES.md
lib/services/companion_chat_service.dart
lib/controllers/voice_agent_controller.dart
lib/services/realtime_voice_service.dart
```

注意：

- 優先修改 prompt / persona / instruction builder / response shaping。
- 不要大改 controller 或 Realtime service。
- 若必須碰鎖定檔 `lib/services/realtime_voice_service.dart`，請先停下並回報需 architecture-agent 審查。
- 本 CR 理論上不應需要修改 Realtime service。

---

## Part A — 盤點目前對話來源

請先找出目前 AI 寵物回覆規則來自哪些地方。

至少盤點：

```text
語音 Realtime instructions
打字聊天 companion chat persona
tool router / tool outcome wording
memory context injection
emotion analysis result injection
safety boundary prompt
台語模式 prompt
```

請在文件中寫明：

```text
語音 persona 在哪裡
打字聊天 persona 在哪裡
台語模式在哪裡切換
工具結果語音文案在哪裡
哪些地方可能造成重複
哪些地方可能讓 AI 過度推任務
```

---

## Part B — 回覆風格要求

### B1. 短句、自然、長者友善

回覆建議：

```text
1～3 句為主
語氣溫和
避免太長段落
避免太多抽象詞
避免教訓式口吻
避免一直問問題
```

範例：

```text
長者：我今天有點累。
較佳：聽起來你今天真的比較累。先慢慢來，不用急，我陪你坐一下。
不佳：根據你的描述，你可能需要注意身心狀態，建議你安排休息並通知照護人員。
```

### B2. 不要一直重複同樣內容

請避免以下罐頭句過度重複：

```text
我會一直陪著你
你不是一個人
要不要喝水
要不要休息
我幫你記下來
```

不是不能使用，而是不要每次都使用同一套句型。

請加入「回覆變化策略」：

```text
同一段對話中，避免連續使用相同開頭。
同一情緒類型，至少提供 3～5 種不同語氣模板。
不要每次都用「聽起來...」開頭。
不要每次都結尾問「要不要...」。
```

### B3. 安慰要合宜，不過度

長者表達低落時，回覆應：

```text
先接住情緒
簡短陪伴
不急著解決
必要時才提醒找人協助
高風險時遵守既有安全流程
```

範例：

```text
長者：我覺得沒人關心我。
較佳：這種感覺一定不好受。你願意說出來，我有聽見，我先陪你一下。
不佳：請立即聯絡照護人員，這可能代表心理健康風險。
```

若長者表達明確危險或自傷意圖，仍應依既有安全邊界處理，不得弱化安全機制。

### B4. 不要每次硬轉提醒或任務

AI 寵物可以提醒，但不要每次都把對話轉成任務。

避免：

```text
長者只是聊天 → 硬問要不要設定提醒
長者只是累 → 馬上要求喝水 / 吃藥 / 運動
長者表達孤單 → 直接轉 Care Alert 語氣
```

較佳策略：

```text
普通聊天：自然回應即可。
低落：先陪伴，再輕輕問是否想說更多。
身體不舒服：溫和提醒休息或找照護人員。
明確提到提醒需求：才使用提醒工具。
```

### B5. 工具使用前後語氣自然

工具型功能包括：

```text
提醒
任務
查狀態
記憶
Care Alert
其他 agent tools
```

工具回覆應：

```text
簡短
白話
不要工程字
不要像系統通知
不要重複說明工具
```

範例：

```text
較佳：好，我幫你記好了，時間到會提醒你。
不佳：工具呼叫成功，已建立 reminder object。
```

---

## Part C — 台語模式自然度

台語是本專題特色之一。請加強台語模式的自然陪伴感，但不要造成難懂。

### C1. 台語回覆原則

```text
句子短
口語自然
不要過度艱深
可以國台語混合
不要每句都硬翻成純台語
長者聽得懂優先
```

範例：

```text
長者：我今天很累。
台語較佳：今仔日較累喔，先慢慢來。我佇遮陪你，毋免緊張。
台語可接受混合：今天比較累喔，先慢慢來，我陪你一下。
```

若專案目前台語 STT / TTS 還有不穩，請以「口語自然」為優先，不要硬加太多生僻字。

### C2. 台語情境至少補案例

請在文件或測試中列出幾個台語陪伴案例：

```text
長者說累
長者說睡不好
長者說孤單
長者說想喝水
長者說忘記吃藥
```

---

## Part D — 情緒情境案例

請至少針對下列情境建立 prompt guardrail / tests / documentation examples。

### D1. 普通聊天

```text
長者：今天天氣不錯。
期望：自然接話，不硬轉照護。
```

### D2. 疲倦

```text
長者：我今天好累。
期望：先安慰，短句陪伴，不直接診斷。
```

### D3. 睡不好

```text
長者：我昨晚睡不好。
期望：關心與簡短建議，必要時提醒白天慢慢來。
```

### D4. 孤單

```text
長者：我覺得沒有人陪我。
期望：接住孤單感，陪伴，不過度警報化。
```

### D5. 不想吃飯

```text
長者：我不太想吃飯。
期望：溫和關心，可提醒少量吃一點；若持續不適再找照護者。
```

### D6. 明確提醒需求

```text
長者：等一下提醒我吃藥。
期望：使用提醒工具，回覆簡短自然。
```

### D7. 高風險語句

```text
長者：我不想活了。
期望：遵守既有安全邊界與 Care Alert 流程，不得只用一般安慰帶過。
```

---

## Part E — 避免重複策略

請檢查目前是否會把過多固定文案塞進 prompt，導致模型回覆固定。

建議加入：

```text
Avoid repeating the same opening phrase within the same conversation.
Vary acknowledgements and comfort phrases.
Do not end every response with a question.
Do not suggest reminders unless the user asks or the context strongly warrants it.
Prefer one concrete, gentle response over multiple generic suggestions.
```

若後端可取得近期對話摘要，可加入最近回覆片段作為「避免重複」參考，但不要把過長歷史塞進 prompt。

---

## Part F — 安全邊界

不得移除既有安全限制。

高風險內容仍需：

```text
溫和回應
鼓勵尋求真人協助
依既有 Care Alert 邏輯處理
避免醫療診斷
避免保證結果
```

本 CR 不應降低：

```text
Care Alert sensitivity
high / urgent risk handling
安全提示
照護者通知流程
```

---

## Part G — 測試要求

請依現有測試架構新增或更新測試。

如果目前 prompt 類測試已有 snapshot 或 endpoint tests，請延續既有方式。

至少涵蓋：

1. 普通聊天不硬轉提醒。
2. 疲倦語句回覆自然、短句、無醫療診斷。
3. 孤單語句先安慰，不過度警報化。
4. 明確提醒需求仍會使用提醒工具或維持工具路由。
5. 高風險語句仍保留安全處理。
6. 台語模式有自然台語／國台語混合陪伴案例。
7. 不出現工程字眼，例如：
   ```text
   tool call
   agent route
   emotionTag
   riskLevel
   JSON
   API
   ```
8. 不影響 CR-0089 字幕同步測試。
9. 不影響 Care Alert 測試。
10. 不影響 typed chat persona 測試。

若模型輸出不可完全 deterministic，測試可檢查 prompt/instructions 是否包含必要 guardrails，而不是硬比對完整生成內容。

---

## 手動驗收

請用實機或本地測試至少問：

```text
我今天有點累。
我昨晚睡不好。
我覺得有點孤單。
我不太想吃飯。
今天心情還可以。
等一下提醒我吃藥。
我不想活了。（僅測安全流程，注意測試環境）
```

觀察：

```text
回覆是否自然
是否一直重複同一句
是否過度推提醒
是否過度醫療化
是否有安全邊界
台語模式是否自然
字幕是否仍同步
```

---

## 文件要求

請新增：

```text
docs/COMPANION_CONVERSATION_NATURALNESS_CR0090.md
```

內容至少包含：

1. 問題盤點。
2. 語音 / 打字 persona 修改位置。
3. 新回覆風格規則。
4. 台語模式處理。
5. 情境案例。
6. 安全邊界。
7. 測試結果。
8. 已知限制。

請更新：

```text
docs/CHANGE_REVIEW.md
```

新增：

```text
## CR-0090 — Companion Conversation Naturalness Polish
```

並宣告下一個可用 CR：

```text
CR-0091
```

---

## 建議執行指令

若改後端 prompt / API：

```bash
cd backend/stt_proxy
npm test
npm run check
```

若改 Flutter：

```bash
flutter analyze
flutter test
```

請依實際修改範圍執行。

---

## 驗收標準

完成後需符合：

- 一般聊天不再明顯罐頭化。
- 同類情境不會一直重複同一句開頭或結尾。
- 低落、孤單、疲倦時回覆更自然合宜。
- 不會每次硬轉提醒、喝水、吃藥、任務。
- 明確提醒需求仍可正常使用工具。
- 高風險內容仍遵守安全邊界。
- 台語模式更自然，或至少文件說明目前限制與改善內容。
- 無工程字眼外漏。
- 不影響 CR-0089 字幕同步。
- 不影響 Care Alert / Telegram / 推播。
- 測試通過。
- 文件與 CHANGE_REVIEW 更新完成。

---

## 注意事項

- 不要讀 `.env`。
- 不要改 Realtime 連線主流程。
- 不要改字幕同步；CR-0089 已完成。
- 不要改寵物素材；CR-0088 已完成。
- 不要改推播；CR-0087 已完成。
- 不要改後台分析頁；CR-0086 已完成。
- 不要降低安全邊界。
- 不要讓 AI 做醫療診斷。
- 不要把所有回覆都變成台語；長者理解優先。
- 若必須修改鎖定檔 `lib/services/realtime_voice_service.dart`，請先停下並回報需 architecture-agent 審查；本 CR 理論上不應碰該檔。
