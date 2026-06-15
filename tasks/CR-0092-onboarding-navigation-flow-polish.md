# CR-0092 — Onboarding Navigation Flow Polish

## 目標

改善長者端新手導覽流程，讓導覽不再全部卡在首頁講完，而是依照介紹內容自動切換到對應頁面。

本 CR 要處理使用者提出的問題：

```text
導覽講到商城就切到商城頁。
導覽講到設定頁的換造型就切到設定頁。
導覽講到紀錄就切到紀錄頁。
導覽不要全部停留在首頁。
```

核心目標是讓新手導覽更像「實際帶使用者走一遍 App」，而不是只在首頁用文字介紹全部功能。

---

## 背景

目前 App 已有 Spotlight / Coach Mark 式新手導覽，先前功能包含：

```text
首次進首頁自動逐步高亮
寵物
語音按鈕
狀態
提醒
設定
拼圖
簽到
金幣
商城
紀錄
設定
聯絡人入口
設定頁可重看導覽
```

但目前導覽大多集中在首頁，導致介紹商城、設定換造型、紀錄頁等功能時，使用者沒有真的看到該頁面。展示時會比較抽象，也不利於老師理解完整流程。

---

## 範圍

### 本 CR 要做

- 盤點現有 onboarding / coach mark 流程。
- 讓導覽步驟支援跨頁切換。
- 導覽講到商城時，自動切到商城頁。
- 導覽講到紀錄時，自動切到紀錄頁。
- 導覽講到設定與換造型時，自動切到設定頁並高亮相關入口。
- 設定頁「重看導覽」仍可正常跨頁播放。
- 修正跨頁 GlobalKey / target not found / render timing 問題。
- 補測試與文件。
- 更新 `docs/CHANGE_REVIEW.md`。

### 本 CR 不做

- 不改 onboarding 文案的大方向，除非跨頁導覽需要微調。
- 不重新設計整個首頁 UI。
- 不改語音 Realtime 主流程。
- 不改 AI persona。
- 不改字幕同步。
- 不改寵物素材。
- 不改推播。
- 不改 Care Alert / Telegram。
- 不改後台。
- 不改 App icon。
- 不讀 `.env`。

---

## 可能涉及檔案

請先盤點，實際檔名以專案為準。

可能涉及：

```text
lib/onboarding/coach_mark_controller.dart
lib/onboarding/coach_mark_keys.dart
lib/onboarding/typewriter_text.dart
lib/onboarding/coach_mark_overlay.dart
lib/screens/home_screen.dart
lib/screens/settings_screen.dart
lib/screens/shop_screen.dart
lib/screens/history_screen.dart
lib/screens/reminder_screen.dart
lib/app.dart
lib/main.dart
lib/controllers/navigation_controller.dart
lib/controllers/home_controller.dart
```

請用 code search 確認實際檔案，不要硬建立重複導覽系統。

---

## Part A — 盤點現有導覽流程

請先盤點目前導覽：

```text
導覽步驟清單在哪裡定義
每一步 target key 在哪裡註冊
目前是否只支援單頁 GlobalKey
底部 navigation 的切頁邏輯在哪裡
設定頁重看導覽如何觸發
首次導覽如何記錄已完成
導覽 step 是否有 step id
導覽是否支援等待 target render
```

請在文件中寫明目前架構與修改策略。

---

## Part B — 建立跨頁導覽能力

### B1. Step 增加頁面資訊

若現有 `CoachMarkStep` 只包含 target key 和文案，請以最小變更增加頁面資訊，例如：

```text
targetPage
targetRoute
bottomNavIndex
beforeShow
```

實際命名依現有架構。

目標是每個 step 可以描述：

```text
這一步要在哪個頁面顯示
顯示前是否需要切頁
切頁後要等目標 widget render
```

---

### B2. 切頁後等待 target ready

跨頁導覽最容易壞在 GlobalKey 還沒 render。

請避免只用硬編碼延遲，例如：

```dart
Future.delayed(Duration(milliseconds: 500))
```

除非沒有更可靠方式且有測試與註解。

較佳策略：

```text
切頁
等待下一個 frame
確認 targetKey.currentContext != null
若 target 尚未出現，短暫 retry 有上限
逾時後顯示友善 fallback 或跳過該步
```

不得讓 App 因找不到 target 而崩潰。

---

### B3. 導覽期間切頁不可打斷流程

請確保：

```text
導覽 step index 不會因切頁重設
overlay 不會殘留在舊頁
切頁後文案仍是正確 step
下一步按鈕正常
上一步若存在也要合理
完成導覽後能關閉 overlay
```

若目前沒有「上一步」，不需新增。

---

## Part C — 建議導覽流程

請依現有 App 頁面實際順序調整。建議流程如下：

### C1. 首頁段

```text
1. 寵物主角：介紹 AI 寵物陪伴。
2. 語音按鈕：介紹可以按住或點擊和寵物說話。
3. 寵物狀態：介紹心情、飽足度、親密度等狀態。
4. 提醒 / 任務入口：介紹日常照護提醒或任務。
```

### C2. 商城頁段

切到商城頁：

```text
5. 商城入口 / 商城頁：介紹可以查看照護用品或長照中心商品。
```

如果商城只是外部連結，請高亮商城卡片或入口，不要自動打開外部網站。

### C3. 紀錄頁段

切到紀錄頁：

```text
6. 紀錄頁：介紹可以查看和寵物的對話紀錄。
7. 搜尋紀錄：介紹可搜尋過去對話。
```

若 CR-0091 已新增搜尋框，請高亮搜尋框。

### C4. 設定頁段

切到設定頁：

```text
8. 設定頁：介紹可以調整 App。
9. 更換外觀 / 寵物換造型：介紹可切換 dog / fox / guinea_pig / ferret / mochi。
10. 重看導覽：介紹之後可以回來重看。
```

### C5. 回首頁或完成

導覽最後可：

```text
回到首頁並顯示「開始使用」
```

或停在設定頁完成。建議回到首頁，方便正式開始使用。

---

## Part D — 設定頁重看導覽

設定頁重看導覽必須支援跨頁。

要求：

```text
點設定頁「重看導覽」
導覽從第一步開始
可以自動切回首頁
後續照流程切商城 / 紀錄 / 設定
導覽完成後不重複標記成首次流程異常
```

若首次導覽和重看導覽使用不同入口，請共用同一套 controller，不要複製兩套流程。

---

## Part E — 錯誤與 fallback

若某個 target 在該設備或條件下不存在，例如商城關閉、紀錄頁無搜尋框、設定項被隱藏：

```text
不要崩潰
不要卡在空白 overlay
不要一直 spinner
```

建議：

```text
找不到 target → 顯示置中說明卡片，或跳到下一步
文件記錄 fallback 行為
```

錯誤訊息需白話，不要顯示：

```text
GlobalKey currentContext null
RenderBox was not laid out
target not found
```

---

## Part F — UX 要求

導覽應符合長者友善：

```text
文字大
每步文案短
按鈕清楚
不閃爍
切頁不要太快
背景遮罩不要太暗
可以略過
完成後不再自動出現
設定頁可重看
```

若現有逐字列印 typewriter 仍保留，請確認跨頁後不會重複列印錯誤文字。

---

## Part G — 測試要求

請依現有 Flutter 測試架構新增或更新測試。

至少涵蓋：

1. 首次導覽可從首頁開始。
2. 導覽 step 可要求切換到商城頁。
3. 導覽 step 可要求切換到紀錄頁。
4. 導覽 step 可要求切換到設定頁。
5. 切頁後等待 target render，不因 `currentContext == null` 崩潰。
6. 設定頁重看導覽可從第一步開始並跨頁。
7. 導覽完成後可關閉。
8. 略過導覽後不再自動顯示。
9. 找不到 target 時有 fallback，不崩潰。
10. 不影響首頁、商城、紀錄、設定頁既有功能。
11. 不影響 CR-0091 紀錄搜尋。
12. 不影響寵物換造型功能。

若 widget test 難以完整測實際 overlay，請至少測 controller 的 step/page transition 邏輯與 target waiting helper。

---

## 手動驗收

請在模擬器或實機測試：

```text
全新安裝或清除 onboarding flag
首次進首頁
按照導覽一步一步點
確認講到商城會切到商城
確認講到紀錄會切到紀錄
確認講到搜尋紀錄會看到搜尋框
確認講到設定會切到設定
確認講到換造型會看到更換外觀入口
完成後回到首頁或正確結束
再次打開 App 不自動重播
到設定頁按重看導覽可重播
```

請特別檢查：

```text
不 overflow
不黑屏
不找不到 target
不卡住
不閃爍
不把 overlay 留在舊頁
```

---

## 文件要求

請新增：

```text
docs/ONBOARDING_NAVIGATION_FLOW_CR0092.md
```

內容至少包含：

1. 問題盤點。
2. 舊導覽流程。
3. 新跨頁導覽流程。
4. step → page 對應表。
5. target ready / fallback 策略。
6. 測試結果。
7. 已知限制。

請更新：

```text
docs/CHANGE_REVIEW.md
```

新增：

```text
## CR-0092 — Onboarding Navigation Flow Polish
```

並宣告下一個可用 CR：

```text
CR-0093
```

---

## 建議執行指令

若只改 Flutter：

```bash
flutter analyze
flutter test
```

若沒有改後端，不需要執行 backend npm 測試。

---

## 驗收標準

完成後需符合：

- 導覽可跨頁。
- 講到商城會切商城頁。
- 講到紀錄會切紀錄頁。
- 講到設定 / 換造型會切設定頁。
- 設定頁重看導覽可正常跨頁。
- 找不到 target 不會崩潰。
- 導覽完成或略過後狀態正確。
- 不影響首頁、商城、紀錄、設定、寵物換造型。
- Flutter analyze 通過。
- 相關 Flutter tests 通過。
- 新增 `docs/ONBOARDING_NAVIGATION_FLOW_CR0092.md`。
- 更新 `docs/CHANGE_REVIEW.md` 並宣告 CR-0093。

---

## 注意事項

- 不要讀 `.env`。
- 不要改 AI persona；CR-0090 已處理。
- 不要改紀錄搜尋；CR-0091 已處理。
- 不要改 Realtime / 字幕同步；CR-0089 已處理。
- 不要改寵物素材；CR-0088 已處理。
- 不要改推播；CR-0087 已處理。
- 不要改後台分析頁；CR-0086 已處理。
- 不要更換 App icon；後續 CR 會處理。
- 不要用大量固定延遲硬撐跨頁導覽。
- 不要讓 GlobalKey 找不到時造成 crash。
- 如果必須大幅重構導航架構，請先停下回報，不要直接大改。
