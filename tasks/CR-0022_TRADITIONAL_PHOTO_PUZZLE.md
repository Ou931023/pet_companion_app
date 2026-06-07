<!--# CR-0022 Traditional Photo Puzzle Game 任務檔

## SECTION 01/08：任務目標

目前記憶小遊戲是華容道拼圖。請改成傳統照片拼圖。

新遊戲流程：

1. 使用者從圖庫選一張照片。
2. 選擇難度：3x3 或 4x4。
3. 系統把照片切成拼圖塊。
4. 上方顯示空白拼圖板。
5. 下方顯示打亂後的小拼圖塊。
6. 使用者拖曳拼圖塊到上方正確位置。
7. 如果位置正確，拼圖塊吸附到該格。
8. 如果位置錯誤，拼圖塊彈回下方。
9. 3x3 產生 9 塊。
10. 4x4 產生 16 塊。
11. 全部完成後顯示完成訊息。

---

## SECTION 02/08：設計原則

1. 操作要直覺，適合長者。
2. 拼圖塊要夠大，不要太小。
3. 下方拼圖區可捲動或自動換行。
4. 拖曳時要有明顯 feedback。
5. 正確位置要吸附。
6. 錯誤位置要彈回。
7. 不要做華容道滑塊邏輯。
8. 不要保留空格滑動玩法。
9. 完成後可記錄遊戲結果，供退化指標或管理者分析使用。
10. 若既有退化指標已有記錄結構，請沿用，不要另開第二套。

---

## SECTION 03/08：需要檢查的檔案

請檢查：

- 記憶小遊戲頁面
- puzzle / game 相關 screen
- game controller
- game result model
- image picker 相關 dependency
- pubspec.yaml
- assets / permissions
- 退化指標 / game analytics 相關檔案
- 相關測試

請先找出目前華容道拼圖的實作位置，然後評估是否：
1. 直接替換原頁面
2. 或保留原檔名但改玩法
3. 或新增新 widget 再由原頁面導入

優先選擇最小破壞既有 routing 的方式。

---

## SECTION 04/08：功能要求

### A. 選照片

1. 使用 image_picker 或既有圖片選擇能力。
2. 使用者可以從圖庫選照片。
3. 若使用者取消選圖，不要 crash。
4. 若沒有權限，顯示白話提示。
5. 不要提交使用者選的照片到 git。
6. 不要把照片存成 raw asset。
7. 照片只在本地遊戲使用。

### B. 選難度

1. 支援 3x3。
2. 支援 4x4。
3. 3x3 = 9 塊。
4. 4x4 = 16 塊。
5. 預設可使用 3x3。
6. UI 文案：
   - 簡單：3 x 3
   - 挑戰：4 x 4

### C. 切圖

1. 將使用者選的圖片裁成正方形顯示區。
2. 依難度切成 N x N。
3. 每個 piece 要知道自己的正確 row / col / index。
4. 產生拼圖塊時要打亂順序。
5. 不要讓打亂後順序剛好是完成狀態。
6. 圖片比例不同時，請用安全裁切或 contain/cover，避免變形。

### D. 拼圖板

1. 上方顯示 N x N 空白格。
2. 每格可以接收拖曳。
3. 若拖到正確格，piece 吸附。
4. 若拖到錯誤格，piece 回到底部拼圖區。
5. 已放對的 piece 不可再亂移，或可允許移動但仍需維持正確判斷；優先選擇不可再移動，降低長者誤操作。
6. 格線要清楚。

### E. 下方拼圖區

1. 顯示尚未放置的拼圖塊。
2. 順序打亂。
3. 支援捲動或換行。
4. 拼圖塊可拖曳。
5. 被正確放置後，從下方區域移除。
6. 放錯時回到下方原區域。

### F. 完成判斷

1. 所有 piece 都正確放置後完成。
2. 顯示完成訊息：
   - 太棒了，拼圖完成！
3. 顯示用時與步數。
4. 可提供「再玩一次」。
5. 可提供「換一張照片」。

---

## SECTION 05/08：遊戲數據與退化指標

若目前專案已有遊戲退化指標或 game analytics，請沿用。

建議記錄：

1. difficulty：3x3 或 4x4
2. totalPieces：9 或 16
3. elapsedSeconds
4. moveAttempts
5. correctDrops
6. wrongDrops
7. completed
8. completedAt

這些資料之後可給管理者端分析：

- 完成時間是否變長
- 錯誤拖曳是否增加
- 難度完成率是否下降

如果目前沒有後端 API，先本地保存或沿用既有 game result store，不要硬開新後端。

---

## SECTION 06/08：UI 文案

請使用繁體中文，文字簡單。

建議文案：

- 選一張照片來玩拼圖
- 選擇難度
- 簡單：3 x 3
- 挑戰：4 x 4
- 把下面的小拼圖拖到上面正確的位置
- 位置不對，拼圖會回到下面喔
- 太棒了，拼圖完成！
- 再玩一次
- 換一張照片

不要出現工程字，例如：

- index
- row
- column
- image bytes
- drag target
- state
- debug

---

## SECTION 07/08：禁止修改範圍

不要混入：

1. Realtime
2. Agent tools
3. Memory greeting
4. onboarding
5. pet skin
6. auth/admin
7. Care Alert
8. pgvector
9. runtime data
10. raw assets
11. unrelated UI cleanup

不要 push。

---

## SECTION 08/08：測試與 Commit

請加入或更新測試，至少覆蓋：

1. 3x3 會產生 9 塊。
2. 4x4 會產生 16 塊。
3. pieces 會被打亂，不能一開始就是完成狀態。
4. piece 拖到正確位置會吸附。
5. piece 拖到錯誤位置會回到底部。
6. 全部放對會完成遊戲。
7. 完成後有 elapsedSeconds / moveAttempts / wrongDrops。
8. 取消選圖不 crash。
9. 小螢幕不 overflow。
10. flutter analyze 通過。
11. flutter test 通過。

通過後 commit，commit message：

CR-0022 traditional photo puzzle game

不要 push。

回報格式：

完成內容
- 原本華容道在哪裡
- 如何改成傳統拼圖
- 如何從圖庫選照片
- 3x3 / 4x4 如何產生拼圖塊
- 正確位置如何吸附
- 錯誤位置如何彈回
- 是否記錄遊戲結果 / 退化指標

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
- 是否需要實機確認圖片權限
- 是否有任何和 Realtime / Agent / onboarding / pet skin 糾纏的檔案

---

## 完整性檢查要求

開始修改程式前，請先停止並回報：

1. 你是否讀到 SECTION 01/08 到 SECTION 08/08。
2. 你理解新遊戲不是華容道，而是傳統照片拼圖。
3. 3x3 與 4x4 分別要產生幾塊。
4. 錯誤位置要如何處理。
5. 正確位置要如何處理。
6. 預計檢查檔案。
7. 預計不碰哪些檔案。

如果缺任何 SECTION，請不要開始修改。>