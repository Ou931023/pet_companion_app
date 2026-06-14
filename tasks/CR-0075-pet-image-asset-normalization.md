# CR-0075 Pet Image Asset Normalization

## 背景

目前 App 已進入展示收尾階段，剩餘主要工作是寵物圖片素材統一。App icon 已完成，本 CR 只處理寵物素材規格與放置，不新增功能、不改後端、不改 Realtime/Auth/Marketplace/Daily Care Tasks。

## 目標

將寵物素材統一為正式展示規格：

- 1024 × 1024 px
- PNG
- 透明背景
- 寵物置中
- 同一隻寵物所有狀態圖主體比例一致
- talk/rest 動畫不跳動
- Flutter assets 可正常載入

## 統一規格

所有寵物圖片統一：

```text
尺寸：1024×1024 px
格式：PNG
背景：透明
主體寬度：約 760～820 px
主體高度：約 780～860 px
上方留白：約 80～120 px
下方留白：約 60～100 px
腳底位置一致
左右置中
```

---

## 盤點結果（2026-06-12 audit）

實際素材與規格落差（用 sips + 純 Python 解碼確認，非估計）：

| 寵物 | 張數（現況） | 實際尺寸 | 背景 | 符合規格？ |
|------|-------------|---------|------|-----------|
| dog | talk6 / rest3 / listen1 / states8 | 677×369 橫式 | **真透明**（角 alpha=0） | ✗ 橫式、解析度過低，放大到 1024² 會糊 |
| fox | talk6 / rest3 / listen1 / states8 | 2816×1536 橫式 | 有 alpha 但**整片不透明近白**（alpha=255） | ✗ 橫式、背景其實不透明，需去背 |
| guinea_pig | talk3（程式用到）/ rest3 / listen1 / states8 | 1560×1008 橫式（talk_02 為 1561×1008，差 1px） | **不透明白底**（無 alpha 通道） | ✗ 橫式、白底，需去背 |
| guinea_pig_talk_04/05/06（新增、未追蹤） | 程式未載入 | 1254×1254 正方 | **烤死的透明網格**（242/254 交錯方格，opaque RGB） | ✗✗ 匯出錯誤的壞檔，且與 01–03 風格/比例不符 |

### 重要結論

1. **App 目前畫面正常、不跳動。** `pet_avatar.dart` 用固定正方框 + `BoxFit.contain`；同一隻寵物每張動畫尺寸一致（dog 全 677×369、fox 全 2816×1536、guinea_pig 用到的 01–03 全 1560×1008）。沒有現存 bug 需要修。
2. **`guinea_pig_talk_04/05/06` 不可接入。** `lib/utils/asset_paths.dart` 的 `_talkFrameCount[guineaPig]=3`，所以這 3 張根本沒被載入。它們背景是烤死的透明網格、又是正方比例（和 01–03 橫式不同），一旦把張數改成 6 接進去，天竺鼠講話會出現灰棋盤底 + 比例跳動。**決議：排除，不接入，建議移除這 3 個未追蹤檔。**
3. **規格化需先安裝影像工具。** 本機只有 `sips`（不能去背 / 邊界裁切 / 合成），無 ImageMagick、無 Pillow。純 sips 補成 1024² 在 `BoxFit.contain` 下對畫面是無效操作。
4. **不生圖。** 依 CLAUDE.md「不要亂生成缺圖」，dog（太小）與 fox/guinea_pig（不透明）都只能重處理既有素材，不用 AI 生成。

### 規格化方案（待工具安裝後執行）

- 腳本：`scripts/normalize_pet_assets.sh`（ImageMagick；`brew install imagemagick`）。
- 流程：四角 floodfill 去背 → 修邊 → 縮放主體至 ~820px 高 / ≤800px 寬 → 置中補白到 1024×1024、底邊留白約 80px。
- 安全：輸出到 `assets/pets_normalized/`（不覆蓋原檔）+ 產 `_review_montage.png` 供肉眼檢查；確認 OK 才搬移覆蓋。
- 已知限制：fox / guinea_pig 為不透明白底，floodfill 去背對毛邊與內凹處效果有限，需肉眼檢查並微調 fuzz；dog 解析度低，放大有上限。
- 排除清單：`guinea_pig_talk_04/05/06`。

### 決策紀錄

- 2026-06-12：使用者選擇「安裝工具後由 Claude 處理」。等待 `brew install imagemagick` 完成後執行上述腳本並逐張檢查微調。
- 2026-06-12：使用者安裝 ImageMagick 7.1.2 完成 → 執行規格化 → 使用者確認覆蓋正式素材。**完成。**

---

## 執行結果（2026-06-12 完成）

- 工具：ImageMagick 7.1.2（`magick`）。
- 腳本：`scripts/normalize_pet_assets.sh`，採「每隻寵物單一固定縮放比例 + 腳底為錨點」避免動畫跳動。
  - 固定縮放：dog 255% / fox 61% / guinea_pig 99%。
- 產出 51 張全部 1024×1024 / RGBA 透明；腳底線一致鎖在 y=944；無頂部裁切（最緊 fox_excited 仍留 84px）；去背乾淨無白邊。
- 已覆蓋正式 `assets/pets/`（51 張，路徑/檔名不變 → 不需改 `asset_paths.dart`）。
- 已移除壞檔 `guinea_pig_talk_04/05/06`（烤死透明網格、風格/比例不符），guineaPig talk 維持 3 張。
- 驗證：`flutter analyze`（asset_paths + pet_avatar）No issues；`flutter test`（pet_skin + pet_avatar）14 項全過（含 guineaPig talk=3 斷言）。
- 原檔有 git 追蹤，需要時 `git checkout -- assets/pets/` 即可還原。
