# CR-0095 — Mochi rest_03 Asset Reprocess

使用者提供新的 mochi（貓）rest 圖，重做 `assets/pets/rest/mochi_rest_03.png`，對齊既有 mochi rest_01/02 的去背與 1024² 幾何。純素材，不動任何程式。

---

## 來源

- 新圖：428×761 **WebP**、白底、無 alpha（srgb 3 channel）。
- 參考：`mochi_rest_01.png` (429×800 content) / `mochi_rest_02.png` (477×800)，皆 1024² RGBA、腳底 y944。

## 去背（關鍵：fuzz 要配合淺色毛）

mochi 是淺色貓、線稿偏細。

- **fuzz 28%（既有慣例值）→ 失敗**：flood-fill 跳過輪廓、吃掉白色胸口/臉/腳掌（疊在洋紅底上目視全是破洞，mean alpha 僅 0.135）。
- **fuzz 12% → 成功**：停在深色輪廓，貓身完整、白色部位保留、背景全透明（mean alpha 0.221）。
- 從**四個角**做 edge flood-fill（底部兩角為 247/249 灰，單從左上角碰不到）。

```sh
magick mochi_rest_03.png -alpha set -bordercolor white -border 1 \
  -fuzz 12% -fill none \
  -draw "alpha 1,1 floodfill" \
  -draw "alpha %[fx:w-2],1 floodfill" \
  -draw "alpha 1,%[fx:h-2] floodfill" \
  -draw "alpha %[fx:w-2],%[fx:h-2] floodfill" \
  -shave 1x1 -trim +repage -resize x800 \
  -background none -gravity South -extent 1024x944 \
  -gravity North -extent 1024x1024 \
  PNG32:mochi_rest_03.png
```

## 結果

- `assets/pets/rest/mochi_rest_03.png`：**1024×1024 RGBA PNG**，content bbox `478×800+273+144`（腳底 y944、水平置中、底部留白 80px）。
- 真 PNG（magic bytes `\211PNG`），不再是 WebP。

## 測試

`flutter test test/models/mochi_skin_test.dart` → **31 passed**（含 1024² RGBA + 透明背景檢查）。

## 限制遵守

未讀 `.env`；純素材重做；未改程式 / Realtime / 字幕 / persona / 推播 / 後台 / Care Alert / Telegram / App icon / pubspec。
