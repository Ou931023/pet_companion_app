# CR-0016 Onboarding Guide

<!-- 內容請# CR-0016 Onboarding Coach Mark 任務檔

## SECTION 01/08：任務目標

請處理 CR-0016 onboarding / coach mark。

目前需求：不要分快速導覽與完整導覽。請改成「單一 13 步完整新手導覽」。

目標：

1. 首次進首頁自動播放一次 13 步完整導覽。
2. 完成後記住狀態，下次不再自動顯示。
3. 設定頁提供「重新觀看新手導覽」入口。
4. 點擊後回到首頁，重新播放同一套 13 步完整導覽。
5. 移除或停用舊版導覽，避免註冊後跳出舊導覽。
6. 導覽視覺要像正式產品，適合長者使用。
7. target 不存在時要安全 fallback，不可 crash。
8. 不要為了跨頁導覽硬改架構；跨頁風險高時，用卡片式說明或高亮首頁入口即可。

---

## SECTION 02/08：已完成背景

目前已完成並已 commit：

- CR-0012 pet skin
- CR-0013 voice turn control
- CR-0013b voice button wiring
- CR-0014 conversation strategy
- CR-0015a agent intent result model
- CR-0015b agent tool execution
- CR-0015c agent integration tests
- docs: pgvector demo setup guide

本次只處理 CR-0016 onboarding / coach mark。

---

## SECTION 03/08：禁止修改範圍

請不要混入以下內容：

1. Agent tools
2. voice turn control
3. conversation strategy
4. auth / OAuth / login backend
5. admin backend
6. runtime data/*.json
7. raw assets
8. docs noise
9. pet skin ownership / purchase 主邏輯
10. RealtimeVoiceService 主流程
11. Care Alert / Telegram / Memory API 主流程

不要 push。

完成前不要 commit。等測試確認後，最後只 commit CR-0016 相關檔案。

---

## SECTION 04/08：需要檢查的檔案範圍

請先檢查：

- lib/onboarding/*
- coach_mark 相關檔案
- feature_tour 舊導覽相關檔案
- lib/screens/home_screen.dart 中導覽 target / trigger
- lib/screens/settings_screen.dart 中重新觀看導覽入口
- lib/screens/onboarding_screen.dart 中導覽 flow
- 相關測試檔案

如果 onboarding_screen.dart 內有 CR-0012 pet-skin 的 purchasable:false 免費選夥伴小尾巴，可以跟 CR-0016 一起處理，但必須明確回報。

如果 home_screen.dart 有 pet-skin _SkinPickerSheet / WalletController 剩餘 hunk，除非它和導覽觸發不可分離，否則不要混入。

---

## SECTION 05/08：13 步完整新手導覽內容

請建立單一 13 步完整導覽。

### Step 01：這是你的 AI 寵物

文案：牠會陪你聊天，也會慢慢記得你喜歡什麼。

### Step 02：按住這裡可以說話

文案：想聊天、提醒、說心情，都可以直接講。

### Step 03：先聽寵物說完

文案：咕咕說話時，先聽牠說完，再換你說。

### Step 04：看看寵物狀態

文案：這裡可以看到寵物的心情、飽足和親密度。

### Step 05：聊天可以增加親密度

文案：常常和寵物聊天，牠會越來越熟悉你。

### Step 06：餵食可以提升飽足感

文案：寵物餓了可以餵牠，讓牠保持好心情。

### Step 07：點擊寵物可以進入遊戲

文案：點一下寵物，可以玩記憶小遊戲，動動腦也很有趣。

### Step 08：每日簽到可以拿金幣

文案：每天來看看寵物，就可以完成簽到並獲得金幣。

### Step 09：金幣可以用來解鎖外觀

文案：金幣可以用來解鎖新的寵物外觀。

### Step 10：商城可以購買或解鎖物品

文案：在商城裡，可以用金幣解鎖寵物外觀或其他物品。

### Step 11：記錄可以查看過去狀態

文案：想回顧以前的心情、提醒或互動紀錄，可以到這裡看看。

### Step 12：設定可以改寵物名稱和語音方式

文案：在設定裡，可以幫寵物改名字，也可以調整語音輸入方式。

### Step 13：設定可以新增聯絡人

文案：可以新增家人或照護人員，讓需要時更方便聯絡。

---

## SECTION 06/08：UI 與互動要求

1. 導覽視覺要像正式產品，不要像工程測試畫面。
2. 使用暖色半透明遮罩。
3. 高亮目前要介紹的區域。
4. 使用白色或奶油色圓角卡片。
5. 字體清楚，不要太小。
6. 支援小螢幕 iPhone，不可 overflow。
7. 第 1～12 步按鈕是「下一步」。
8. 第 13 步按鈕是「開始使用」或「完成」。
9. 如果有逐字列印，點擊時先顯示完整文字，再下一步。
10. 導覽文案不要出現工程字。
11. target 不存在時，用安全 fallback / card 說明，不要 crash。
12. 不要硬做不穩定的跨頁導覽。
13. 如果某些功能入口目前不在首頁，優先高亮首頁可見 target、底部導覽、設定入口、商城入口或記錄入口。
14. 若跨頁風險高，後段功能可用卡片式說明，不要造成 crash 或 overflow。

---

## SECTION 07/08：設定頁重新觀看導覽

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

---

## SECTION 08/08：測試、Commit 與回報格式

請加入或更新測試，至少覆蓋：

1. 首次進首頁會顯示 13 步導覽。
2. 導覽完成後不再自動顯示。
3. 設定頁可以重新播放導覽。
4. 導覽共有 13 步。
5. Step 內容不重複。
6. 不會出現舊版導覽。
7. 小螢幕不 overflow。
8. target 不存在時不會 crash。
9. 逐字列印點擊行為正確。
10. flutter analyze 通過。
11. flutter test 通過。

通過後 commit，commit message 使用：

CR-0016 onboarding coach mark

不要 push。

回報格式：

完成內容
- 13 步導覽如何設計
- 舊導覽如何處理
- 設定頁如何重新觀看
- 小螢幕 overflow 如何避免
- target 不存在時如何處理
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

1. 你是否讀到 SECTION 01/08 到 SECTION 08/08。
2. 你讀到的 13 個導覽步驟標題。
3. 禁止修改範圍。
4. 預計修改檔案。
5. 預計不碰哪些檔案。

如果缺任何 SECTION 或任何 Step，請不要開始修改。直接貼在這裡 -->
