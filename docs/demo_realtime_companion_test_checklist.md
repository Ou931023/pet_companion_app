# 畢業專題 Demo 前測試清單

## 1. Realtime 連線測試

- [ ] App 冷啟動後，首頁正常載入，沒有卡在 loading 或 error 狀態
- [ ] 進入對話頁後，點擊開始對話可以進入 connecting / listening 流程
- [ ] 連續快速點擊開始對話，不會建立多條重複連線，也不會造成 UI 卡死
- [ ] App 切到背景再回到前景後，Realtime 狀態能正確恢復或回到可重試狀態
- [ ] 斷網時能顯示可理解的錯誤或 recovering 狀態
- [ ] 斷網後恢復網路，可以重新開始對話
- [ ] 連線 failed 後再次點擊開始對話，可以成功重試

## 2. 語音 Transcript 測試

- [ ] 使用者說話時，partial bubble 會同步顯示目前辨識到的內容
- [ ] partial transcript 為空時，temporary bubble 顯示「正在聽你說話…」或等效提示
- [ ] final transcript 收到後，temporary bubble 會消失
- [ ] final transcript 會轉成正式 user message
- [ ] final transcript 為空時，不會新增正式 user message
- [ ] 同一段 final transcript 不會被重複新增成兩筆 user message
- [ ] assistant 語音 transcript 不可被誤判成 user message
- [ ] assistant 回覆播放時，不會覆蓋上一筆正式 user message

## 3. 文字輸入測試

- [ ] 使用者在文字輸入框打字時，draft bubble 會同步顯示目前輸入內容
- [ ] draft bubble 會標示「輸入中」或等效 temporary 狀態
- [ ] 使用者正在語音輸入時，speech partial bubble 優先於 draft bubble
- [ ] 按送出後，draft bubble 會清空
- [ ] 按送出後，文字會顯示為正式 user message
- [ ] 正式文字訊息會加入 conversation history
- [ ] 空白文字送出時，不會新增正式 user message

## 4. 台語輸入輸出測試

逐句測試以下輸入：

- [ ] 「今仔日厝內足安靜」
- [ ] 「我袂好睏」
- [ ] 「無人陪我講話」

每句都確認：

- [ ] final transcript 能正常進入正式 user message
- [ ] languageHint / routeReason 顯示合理
- [ ] replyLanguage 為 `mixed-zh-taigi`
- [ ] 回覆使用自然台語口吻搭配繁體中文
- [ ] 回覆避免大量羅馬拼音
- [ ] 回覆不要硬翻成不自然台語

## 5. 陪伴策略測試

測試情境：

- [ ] 孤單：例如「今天都沒有人陪我說話」
- [ ] 疲累：例如「我今天覺得很累」
- [ ] 睡不好：例如「昨晚一直睡不著」
- [ ] 沒胃口：例如「最近都不太想吃飯」

每個情境確認：

- [ ] 回覆先做情緒承接，而不是立刻給建議
- [ ] 每次最多只問一個問題
- [ ] 不會太快跳搜尋、工具查詢或條列建議
- [ ] 語氣像陪伴寵物，不像客服或一般助理
- [ ] 能延續上一輪狀態，記得使用者剛剛表達的情緒或處境
- [ ] 多輪對話中，能保持陪伴優先，不急著結束話題

## 6. Demo 成功標準

- [ ] Realtime 能穩定連線、重試、恢復
- [ ] 使用者說話時，UI 能同步顯示 partial transcript
- [ ] 使用者打字時，UI 能同步顯示 draft bubble
- [ ] final transcript 和文字送出後，都能正確成為正式 user message
- [ ] temporary bubble 不會被存入長期 conversation history
- [ ] 台語輸入能得到台語口吻回覆
- [ ] 台語回覆符合 `mixed-zh-taigi`，且避免大量羅馬拼音
- [ ] 回覆呈現陪伴優先、情緒承接與多輪關心
- [ ] Demo 過程沒有明顯 UI 卡死、重複訊息或錯誤狀態殘留
