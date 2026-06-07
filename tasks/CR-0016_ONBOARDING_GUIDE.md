<!--# CR-0016 Onboarding Coach Mark 任務檔

## SECTION 01/09：任務背景

目前 App 已經有 13 步新手導覽，但實機畫面有幾個問題：

1. 導覽卡片目前在畫面下方，和被介紹的功能位置距離太遠。
2. 第 8 步提到每日簽到，但簽到 / 日曆 icon 沒有明顯被高亮。
3. 第 10 步提到商城，但底部 navigation bar 的「商城」沒有被高亮。
4. 第 11 步提到紀錄，但底部 navigation bar 的「紀錄」沒有被高亮。
5. 第 12、13 步提到設定與聯絡人，但底部 navigation bar 的「設定」沒有被高亮。
6. 使用者看文字時，不容易知道畫面上對應的位置在哪裡。
7. 目前導覽形式比較像底部說明彈窗，不像正式產品的新手教學。

本次目標是參考 Livly Island 的導覽形式：

- 統一使用上方提示卡。
- 畫面中被介紹的功能要 spotlight / 高亮。
- 提示卡右下角有小三角按鈕。
- 點擊小三角或畫面任意處都可以進到下一步。
- 每一步都要清楚亮出正在介紹的位置。
- 導覽要像正式產品，不要像工程測試畫面。

---

## SECTION 02/09：本次任務目標

請處理 CR-0016 onboarding / coach mark。

本次需求是「單一 13 步完整新手導覽」，不要分快速導覽與完整導覽。

目標：

1. 首次進首頁自動播放一次 13 步完整導覽。
2. 完成後記住狀態，下次不再自動顯示。
3. 設定頁提供「重新觀看新手導覽」入口。
4. 點擊後回到首頁，重新播放同一套 13 步完整導覽。
5. 移除或停用舊版導覽，避免註冊後跳出舊導覽。
6. 導覽卡片改成上方提示卡，而不是底部大卡片。
7. 每一步要高亮對應的 target。
8. 提到每日簽到時，要高亮簽到 / 日曆 icon。
9. 提到商城、紀錄、設定時，要高亮底部 navigation bar 對應 tab。
10. target 不存在時要安全 fallback，不可 crash。
11. 支援小螢幕 iPhone，不可 overflow。
12. 不要為了跨頁導覽硬改架構；跨頁風險高時，用卡片式說明或高亮首頁入口即可。

---

## SECTION 03/09：已完成背景

目前已完成並已 commit：

- CR-0012 pet skin
- CR-0013 voice turn control
- CR-0013b voice button wiring
- CR-0014 conversation strategy
- CR-0015a agent intent result model
- CR-0015b agent tool execution
- CR-0015c agent integration tests
- CR-0018 turn-based realtime conversation
- docs: pgvector demo setup guide

本次只處理 CR-0016 onboarding / coach mark。

---

## SECTION 04/09：禁止修改範圍

請不要混入以下內容：

1. Agent tools
2. voice turn control
3. turn-based realtime conversation
4. conversation strategy
5. auth / OAuth / login backend
6. admin backend
7. runtime data/*.json
8. raw assets
9. docs noise
10. pet skin ownership / purchase 主邏輯
11. RealtimeVoiceService 主流程
12. Care Alert / Telegram / Memory API 主流程
13. pgvector / database 設定

不要 push。

完成前不要 commit。  
等測試確認後，最後只 commit CR-0016 onboarding / coach mark 相關檔案。

如果 `home_screen.dart` 內仍有 pet-skin `_SkinPickerSheet` / `WalletController` 剩餘 hunk，除非它和導覽 target 或導覽觸發不可分離，否則不要混入本次 commit。

如果 `onboarding_screen.dart` 內有 CR-0012 pet-skin 的 `purchasable:false` 免費選夥伴小尾巴，可以跟 CR-0016 一起處理，但必須在回報中明確說明。

---

## SECTION 05/09：需要檢查的檔案範圍

請先檢查：

- `lib/onboarding/*`
- coach mark 相關檔案
- feature tour 舊導覽相關檔案
- `lib/screens/home_screen.dart` 中導覽 target / trigger / bottom nav target
- `lib/screens/settings_screen.dart` 中重新觀看導覽入口
- `lib/screens/onboarding_screen.dart` 中導覽 flow
- bottom navigation bar 相關 widget
- voice button target key
- calendar / check-in icon target key
- coin display target key
- shop / records / settings bottom tab target key
- 相關測試檔案

請先盤點目前有哪些導覽 target key。  
若缺少 target key，請補上清楚命名的 key，例如：

- `petTargetKey`
- `voiceButtonTargetKey`
- `petStatusTargetKey`
- `dailyCheckInTargetKey`
- `coinTargetKey`
- `skinChangeTargetKey`
- `bottomNavHomeTargetKey`
- `bottomNavShopTargetKey`
- `bottomNavRecordsTargetKey`
- `bottomNavSettingsTargetKey`
- `settingsContactTargetKey`

實際命名請配合專案既有命名，不要硬開第二套混亂 registry。

---

## SECTION 06/09：13 步完整新手導覽內容與 target

請建立單一 13 步完整導覽。

### Step 01：這是你的 AI 寵物

文案：

牠會陪你聊天，也會慢慢記得你喜歡什麼。

高亮 target：

- 寵物圖片 / pet avatar / pet stage

備註：

- 若寵物 target 可取得，spotlight 寵物。
- 若寵物 target 不存在，使用卡片式說明，不 crash。

---

### Step 02：按住這裡可以說話

文案：

想聊天、提醒、說心情，都可以直接講。

高亮 target：

- 語音按鈕

備註：

- 這一步要讓使用者知道語音按鈕在哪裡。
- 文字不要說 Realtime、session、VAD 等工程字。

---

### Step 03：先聽寵物說完

文案：

咕咕說話時，先聽牠說完，再換你說。

高亮 target：

- 語音按鈕或對話區

備註：

- 這一步要符合 CR-0018 turn-based realtime conversation。
- 寵物說話時不能被打斷，說完後使用者再按一次說下一句。

---

### Step 04：看看寵物狀態

文案：

這裡可以看到寵物的心情、飽足和親密度。

高亮 target：

- 寵物狀態卡片 / pet status panel

備註：

- 要高亮包含親密、飽足、心情的狀態區。

---

### Step 05：聊天可以增加親密度

文案：

常常和寵物聊天，牠會越來越熟悉你。

高亮 target：

- 親密度欄位，或寵物狀態卡片中的親密值

備註：

- 若沒有單獨親密度 target，就高亮整個狀態卡片。
- 不要硬改狀態功能主邏輯。

---

### Step 06：餵食可以提升飽足感

文案：

寵物餓了可以餵牠，讓牠保持好心情。

高亮 target：

- 飽足感欄位，或寵物狀態卡片中的飽足值

備註：

- 若目前首頁沒有餵食按鈕，不要硬新增餵食功能。
- 可以高亮飽足感欄位，說明這是寵物狀態的一部分。

---

### Step 07：點擊寵物可以進入遊戲

文案：

點一下寵物，可以玩記憶小遊戲，動動腦也很有趣。

高亮 target：

- 寵物圖片 / pet avatar / pet stage

備註：

- 若目前點擊寵物確實能進遊戲，保留。
- 若尚未接線，請不要在本次硬改遊戲主流程，先只做導覽 target。

---

### Step 08：每日簽到可以拿金幣

文案：

每天回來看看寵物，就能完成每日簽到，拿到金幣。

高亮 target：

- 每日簽到 / 日曆 icon / calendar icon

重要要求：

- 這一步目前實機問題是文案有提到每日簽到，但日曆 / 簽到圖示沒有亮。
- 請補正 target，讓日曆 / 簽到 icon 明顯 spotlight。
- 可以加 glow、外框、明亮背景或浮起效果。
- 不要只顯示文字，必須讓使用者看得出來在講哪個 icon。

---

### Step 09：金幣可以用來解鎖外觀

文案：

存下來的金幣，可以用來解鎖新的寵物外觀。

高亮 target：

- 金幣區
- 必要時也可一起高亮「更換外觀」按鈕

重要要求：

- 這一步應該讓使用者看到目前金幣數。
- 若可支援多 target，金幣區為主，更換外觀為輔。
- 若只支援單 target，優先高亮金幣區。

---

### Step 10：商城可以購買或解鎖物品

文案：

最下面的「商城」，可以用金幣解鎖外觀或其他物品。

高亮 target：

- 底部 navigation bar 的「商城」tab

重要要求：

- 這一步目前實機問題是文字提到商城，但底部 bar 沒有亮。
- 請讓底部「商城」tab 明顯被高亮。
- 高亮效果可以包含：背景亮起、文字/圖示主色、外框 glow、spotlight。
- 不要真的切到商城頁，除非既有導覽架構已支援且穩定。

---

### Step 11：記錄可以查看過去狀態

文案：

旁邊的「記錄」可以回顧以前的心情、提醒和互動。

高亮 target：

- 底部 navigation bar 的「記錄」tab

重要要求：

- 這一步目前實機問題是文字提到記錄，但底部 bar 沒有亮。
- 請讓底部「記錄」tab 明顯被高亮。
- 不要硬切頁造成導覽不穩。

---

### Step 12：設定可以改寵物名稱和語音方式

文案：

「設定」可以幫寵物改名字，也可以調整說話的語音方式。

高亮 target：

- 底部 navigation bar 的「設定」tab

重要要求：

- 這一步目前實機問題是文字提到設定，但底部 bar 沒有亮。
- 請讓底部「設定」tab 明顯被高亮。

---

### Step 13：設定可以新增聯絡人

文案：

在「設定」裡還能新增家人或照護人員，需要時更方便聯絡。

高亮 target：

優先方案：

- 若跨頁穩定，切到設定頁並高亮「聯絡人管理」或「新增聯絡人」入口。

保守方案：

- 若跨頁導覽風險高，不要硬切頁。
- 保持在首頁，高亮底部 navigation bar 的「設定」tab。
- 文案清楚說明聯絡人是在設定裡新增。

重要要求：

- 不要為了這一步硬改設定頁主流程。
- 不要讓跨頁導覽造成 crash 或 overflow。
- 若採用保守方案，請在回報中說明原因。

---

## SECTION 07/09：導覽 UI 與互動要求

請將導覽形式改成參考 Livly Island 的風格。

### A. 提示卡位置

1. 統一使用上方提示卡。
2. 不要再使用底部大卡片。
3. 提示卡放在 safe area 下方。
4. 避免遮住 status bar。
5. 避免遮住被高亮的 target。
6. 若上方 target 被遮住，提示卡可自動改到下方或中間安全區，但預設應以上方為主。

### B. 提示卡內容

提示卡需要顯示：

1. 第幾步 / 共 13 步
2. 主要文案
3. 右下角小三角下一步按鈕

例如：

第 8 步 / 共 13 步  
每天回來看看寵物，就能完成每日簽到，拿到金幣。  
右下角：小三角

### C. 小三角按鈕

1. 右下角要有小三角。
2. 點小三角進入下一步。
3. 小三角視覺要清楚，但不要太搶眼。
4. 最後一步可以仍用小三角，也可以顯示「開始使用」按鈕；若保留按鈕，需符合整體視覺。

### D. 點擊任意處下一步

1. 點擊畫面任意處可以進到下一步。
2. 點擊高亮 target 也可以進到下一步。
3. 點擊提示卡也可以進到下一步，但不能造成點擊事件穿透到下層功能。
4. 若有逐字列印：
   - 第一次點擊先顯示完整文字。
   - 文字完整後再次點擊才下一步。
5. 不要讓使用者卡在某一步。

### E. Spotlight / 高亮效果

每一步都要有明確 target 或 fallback card。

高亮效果可以包含：

1. 目標區域維持清楚亮度。
2. 其他區域加半透明遮罩。
3. 目標區域加外框或 glow。
4. 目標區域可微微放大或浮起。
5. bottom navigation tab 要能被單獨高亮。

不要只有文字說明，卻沒有畫面上的對應位置。

### F. 小螢幕支援

1. 支援 iPhone 小螢幕，例如 320x568。
2. 提示卡不可 overflow。
3. 文案最多顯示 2～4 行，可自動換行。
4. 字體清楚，不要太小。
5. 不要因為 13 步文案導致卡片高度過大。
6. 若文字過長，請調整文案或卡片 padding，而不是讓它 overflow。

### G. 文案要求

1. 使用繁體中文。
2. 面向長者，簡單自然。
3. 不要工程字。
4. 不要出現：
   - state
   - realtime
   - session
   - response.cancel
   - VAD
   - API
   - JSON
   - database
   - payload
   - toolName
5. 不要說「系統」太多，盡量用「這裡」「寵物」「設定」等白話詞。

---

## SECTION 08/09：設定頁重新觀看導覽

設定頁請提供清楚入口：

「重新觀看新手導覽」

點擊後：

1. 回到首頁。
2. 重設導覽 replay 狀態。
3. 播放同一套 13 步完整導覽。
4. 不要新增第二套導覽系統。
5. 不要碰登入 / OAuth 主流程。

完成導覽後：

1. 首次自動導覽不再顯示。
2. replay 導覽也要正常結束。
3. 舊版導覽不得再於註冊後跳出。

若目前已經有設定頁入口，請修正其行為，不要重複新增多個入口。

---

## SECTION 09/09：測試、Commit 與回報格式

請加入或更新測試，至少覆蓋：

1. 首次進首頁會顯示 13 步導覽。
2. 導覽完成後不再自動顯示。
3. 設定頁可以重新播放導覽。
4. 導覽共有 13 步。
5. Step 內容不重複。
6. 不會出現舊版導覽。
7. 小螢幕不 overflow。
8. target 不存在時不會 crash。
9. 點擊畫面任意處可以進到下一步。
10. 點擊小三角可以進到下一步。
11. 若有逐字列印，第一次點擊先顯示完整文字，第二次才下一步。
12. Step 8 會高亮每日簽到 / 日曆 icon。
13. Step 9 會高亮金幣區。
14. Step 10 會高亮底部「商城」tab。
15. Step 11 會高亮底部「記錄」tab。
16. Step 12 會高亮底部「設定」tab。
17. Step 13 至少會高亮底部「設定」tab；若實作跨頁，則高亮設定頁聯絡人入口。
18. flutter analyze 通過。
19. flutter test 通過。

通過後 commit，commit message 使用：

CR-0016 onboarding coach mark

不要 push。

回報格式：

完成內容
- 13 步導覽如何設計
- 導覽卡片如何改成上方提示卡
- 小三角與點擊任意處下一步如何處理
- 舊導覽如何處理
- 設定頁如何重新觀看
- 小螢幕 overflow 如何避免
- target 不存在時如何處理
- Step 8 如何高亮每日簽到 / 日曆 icon
- Step 9 如何高亮金幣區
- Step 10 / 11 / 12 如何高亮底部 tab
- Step 13 是否有切到設定頁；若沒有，如何高亮設定 tab
- 是否包含 onboarding_screen.dart 的 pet-skin purchasable:false 小尾巴

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
- 是否有任何和 pet skin / home_screen / Agent 糾纏的檔案

---

## 完整性檢查要求

開始修改程式前，請先停止並回報：

1. 你是否讀到 SECTION 01/09 到 SECTION 09/09。
2. 你讀到的 13 個導覽步驟標題。
3. Step 8、9、10、11、12、13 分別要高亮哪個 target。
4. 禁止修改範圍。
5. 預計修改檔案。
6. 預計不碰哪些檔案。
7. 你是否理解：導覽卡片要改成上方提示卡、小三角下一步、點擊畫面任意處下一步。
8. 你是否理解：若跨頁風險高，Step 13 可以先高亮底部設定 tab，不要硬切頁。

如果缺任何 SECTION 或任何 Step，請不要開始修改。-->