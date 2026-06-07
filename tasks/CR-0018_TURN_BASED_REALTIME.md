# CR-0018 Turn-based Realtime Conversation 任務檔

<!--## SECTION 01/07：背景

目前語音對話採用連續 Realtime session 設計。寵物 speaking 完成後會回到 listening，讓使用者自然接著說。

但實測發現這對長者陪伴 App 不夠穩定：寵物說話時，使用者只是咳嗽、嗯一聲、背景有聲音，就可能觸發 barge-in 或下一輪輸入，導致寵物被打斷、思考下一句、對話節奏混亂。

現在需求改為 turn-based 對話：

使用者說一句 → 寵物回答一句 → 寵物講完後回 idle → 使用者再按一次才能說下一句。

---

## SECTION 02/07：目標

請把 Realtime 對話從「連續 listening」調整為「一人一句」的 turn-based flow。

目標流程：

1. idle：等待使用者按語音按鈕。
2. 使用者按下後進入 listening。
3. 使用者說完後進入 thinking。
4. 寵物開始回答進入 speaking。
5. speaking 期間不接受使用者新語音、不 barge-in、不 cancel response。
6. 寵物語音播放完成後回 idle，不回 listening。
7. 使用者要講下一句時，必須再次按語音按鈕。

核心要求：

- 寵物 speaking 時，任何短聲音、咳嗽、背景音都不能打斷寵物。
- speaking 完成後不要自動 listening。
- 不要因為一點聲音就觸發下一輪。
- 不要重寫整個 Realtime WebRTC 主流程。
- 優先用狀態機、mic/input enable/disable、event ignore/gating 來完成。

---

## SECTION 03/07：禁止修改範圍

不要混入：

1. onboarding / coach mark
2. pet skin
3. Agent tools
4. conversation strategy
5. auth / OAuth
6. admin backend
7. Care Alert / Telegram API
8. Memory API / pgvector 設定
9. runtime data/*.json
10. raw assets
11. docs noise

不要 push。

---

## SECTION 04/07：需要檢查的檔案

請檢查：

- lib/services/realtime_voice_service.dart
- lib/controllers/voice_agent_controller.dart
- lib/controllers/conversation_controller.dart
- lib/screens/home_screen.dart 語音按鈕接線
- lib/widgets 或 voice_button_presentation 相關檔案
- realtime_voice_service_test
- voice_agent_controller 相關測試
- conversation_controller 相關測試
- home_screen voice button 相關測試

如果需要改 HomeScreen，請只 stage turn-based 語音相關 hunk，不要混入 pet skin / onboarding hunk。

---

## SECTION 05/07：行為要求

請完成：

1. speaking 狀態下，使用者按語音按鈕不可 start 新 session。
2. speaking 狀態下，不要走 interruptPetForUserTurn。
3. speaking 狀態下，不要 response.cancel。
4. speaking 狀態下，忽略或阻擋 user speech events。
5. AI response audio 完成後，狀態回 idle。
6. idle 狀態才可以開始下一句。
7. listening 狀態只代表正在聽這一句。
8. thinking 狀態不可重新開始。
9. error 狀態可重試。
10. 若目前 Realtime session 維持連線，請只關閉或忽略 mic/input，不要每輪重建連線，除非既有架構已經如此。
11. 若技術上無法完全關閉 mic，至少要保證 speaking 期間的 user speech event 不會觸發下一輪或取消回答。
12. 回覆播放完成後，UI 顯示可以再次說話。

---

## SECTION 06/07：UI 文案

請使用長者看得懂的口語文案。

按鈕狀態：

- idle：按住說話
- listening：正在聽你說
- thinking：咕咕想一下
- speaking：咕咕正在說話
- error：再試一次

speaking 提示：

先聽咕咕說完，再換你說～

回到 idle 後可顯示：

換你說囉，按住再跟咕咕說話

不要出現工程字，例如：

- state
- realtime
- session
- response.cancel
- VAD
- error code

---

## SECTION 07/07：測試與回報

請加入或更新測試，至少覆蓋：

1. idle 可以開始一輪語音。
2. listening 不可重複 start。
3. thinking 不可重複 start。
4. speaking 不可 start。
5. speaking 不會觸發 interruptPetForUserTurn。
6. speaking 不會呼叫 cancelResponse。
7. speaking 期間的 user speech event 會被忽略或阻擋。
8. AI audio 完成後回 idle，不是回 listening。
9. 回 idle 後，使用者可開始下一句。
10. UI 顯示正確文案。
11. flutter analyze 通過。
12. flutter test 通過。

完成後 commit，commit message：

CR-0018 turn-based realtime conversation

不要 push。

回報格式：

完成內容
- Realtime 對話如何改成一句一句
- speaking 期間如何避免被雜音打斷
- 寵物講完後如何回 idle
- 是否保留 Realtime session 或每輪重建
- UI 文案如何調整

修改檔案
- 檔案路徑與用途

測試結果
- flutter analyze
- flutter test
- 單檔測試

Commit
- commit hash
- commit message
- 是否 push：否

注意事項
- 是否需要實機確認
- 是否有任何和 onboarding / pet skin / Agent 糾纏的檔案

---

## 完整性檢查要求

開始修改程式前，請先停止並回報：

1. 你是否讀到 SECTION 01/07 到 SECTION 07/07。
2. 你理解的新 turn-based 流程。
3. 禁止修改範圍。
4. 預計修改檔案。
5. 預計不碰哪些檔案。

如果缺任何 SECTION，請不要開始修改。-->