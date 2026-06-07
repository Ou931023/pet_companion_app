<!--# CR-0023 Final UX Polish 任務檔

## SECTION 01/07：任務目標

請處理 CR-0023 final UX polish。

這次只修三個小問題：

1. 記憶小遊戲名稱改成「回憶拼圖」，並讓拼圖塊更像真實拼圖，有凸有凹。
2. 導覽時底部 Home Bar / bottom navigation 高亮框目前沒有對齊，框太大且往下多出一大截，需要修正。
3. 首頁語音按鈕「按住說話」下面的提示字要移除，畫面更乾淨。

不要 push。  
完成前不要 commit。  
測試通過後再 commit。

commit message：

CR-0023 final UX polish

---

## SECTION 02/07：禁止修改範圍

請不要混入以下內容：

1. RealtimeVoiceService 主流程
2. Agent tools
3. conversation strategy
4. Memory greeting
5. onboarding 13 步文案主內容
6. pet skin purchase flow
7. auth / OAuth
8. admin backend
9. Care Alert / Telegram
10. pgvector / database
11. runtime data/*.json
12. raw assets
13. unrelated shop / status panel WIP

如果需要修改 `home_screen.dart`，只 stage 與語音提示字移除、或導覽高亮對位相關的 hunk。不要混入 pet skin / typed text / 其他 WIP。

---

## SECTION 03/07：回憶拼圖名稱與真實拼圖外觀

目前遊戲名稱是「照片拼圖」，請統一改成：

回憶拼圖

需要檢查並修改：

- 遊戲頁標題
- 遊戲入口文字
- 導覽或說明文字
- 完成畫面文字
- 測試中的文字

新名稱：

- 頁面標題：回憶拼圖
- 說明文字可用：選一張照片，拼回屬於你的回憶。
- 完成文字可用：太棒了，回憶拼圖完成！

拼圖塊外觀需求：

1. 現在拼圖塊是方形圖片切片，視覺不像真實拼圖。
2. 請改成有凸有凹的 jigsaw puzzle 風格。
3. 可以使用 CustomClipper<Path> 或 CustomPainter。
4. 每片拼圖至少要有視覺上的凸起 / 凹槽。
5. 3x3 仍是 9 片。
6. 4x4 仍是 16 片。
7. 拖曳邏輯不變：
   - 正確位置吸附
   - 錯誤位置彈回下方
8. 不要回到華容道玩法。
9. 不要把使用者照片存成 asset。
10. 不要新增 raw assets。

如果完整真實拼圖裁切很複雜，請優先做到：
- 每片拼圖以拼圖形狀 mask 顯示
- 邊緣有凸凹視覺
- 保持現有拖曳與完成邏輯穩定

---

## SECTION 04/07：導覽 bottom bar 高亮框對齊

目前導覽 Step 10 / 11 / 12 高亮底部 tab 時，白色高亮框沒有對齊，且往下多出一大截。

請修正：

1. Step 10 高亮「商城」tab。
2. Step 11 高亮「紀錄」tab。
3. Step 12 高亮「設定」tab。
4. Step 13 若保守方案仍高亮「設定」tab，也要對齊。
5. 高亮框應只包住 tab item 本身，不要包住整個 bottom safe area。
6. 不要把 iOS home indicator / native home bar 高度算進高亮框。
7. 高亮框高度要合理，大約包住 icon + label + 背景 capsule 即可。
8. 小螢幕也要對齊。
9. 不可 overflow。

可接受做法：

A. 最佳方案：
- 每個 bottom tab 都有自己的 GlobalKey。
- 導覽直接抓對應 tab 的 rect。

B. 保守方案：
- 若目前用 navBarKey + slot 計算，請修正 slot rect：
  - 排除 safe area
  - clamp 高度
  - top / bottom 對齊實際 tab item
  - 不要讓框往下超出 nav bar 可視區

請優先選擇最小破壞方式。

---

## SECTION 05/07：移除按住說話下方提示字

目前首頁語音按鈕下方會顯示類似：

換你說囉，按住再跟狗子說話

請移除這行提示字。

要求：

1. 保留主要語音按鈕。
2. 保留按鈕文字，例如：
   - 按住說話
   - 用台語按住說話
3. 移除按鈕下方的輔助說明文字。
4. 不要影響 turn-based realtime 狀態機。
5. 不要修改 RealtimeVoiceService。
6. 不要影響 speaking 時的 toast / 提醒，例如「先聽狗子說完，再換你說～」。
7. 首頁畫面要更乾淨。

---

## SECTION 06/07：測試要求

請加入或更新測試，至少覆蓋：

1. 遊戲標題顯示「回憶拼圖」。
2. 不再顯示「照片拼圖」作為頁面標題。
3. 3x3 仍產生 9 片。
4. 4x4 仍產生 16 片。
5. 拼圖塊仍可拖曳，正確位置吸附。
6. 錯誤位置仍彈回。
7. 拼圖塊使用 jigsaw 形狀或至少有凸凹視覺 widget / painter。
8. 導覽 Step 10 / 11 / 12 的 bottom tab 高亮 rect 不包含過多 bottom safe area。
9. 小螢幕 bottom tab 高亮不 overflow。
10. 首頁不再顯示「換你說囉，按住再跟狗子說話」這類按鈕下方提示字。
11. flutter analyze 通過。
12. flutter test 通過。

若測試無法直接驗證視覺凸凹，至少要測試 jigsaw clipper / painter / widget 有被使用。

---

## SECTION 07/07：回報格式

完成後請回報：

完成內容
- 拼圖名稱如何改成回憶拼圖
- 拼圖塊如何改成凸凹真實拼圖風格
- 3x3 / 4x4 邏輯是否保留
- 導覽底部 tab 高亮框如何修正
- 按住說話下方提示字如何移除

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
- 是否有任何和 Realtime / Agent / onboarding / pet skin / auth-admin 糾纏的檔案

---

## 完整性檢查要求

開始修改程式前，請先停止並回報：

1. 你是否讀到 SECTION 01/07 到 SECTION 07/07。
2. 三個要修的小問題是什麼。
3. 拼圖新名稱是什麼。
4. 拼圖外觀要怎麼改。
5. bottom bar 高亮框要修什麼。
6. 語音按鈕下方哪一行要移除。
7. 禁止修改範圍。
8. 預計檢查檔案。
9. 預計不碰哪些檔案。

如果缺任何 SECTION，請不要開始修改。>