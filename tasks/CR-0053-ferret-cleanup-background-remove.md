# CR-0053 — Ferret Pet Asset Cleanup, Background Removal, and Format Normalization

## 目標

本 CR 要處理新寵物「雪貂 ferret」的圖片素材整理，但目前圖片已經由使用者放入正確目錄，因此本 CR 不需要再搬移或複製圖片。

本次任務重點是：

1. 檢查 ferret 圖片是否已放在既有 `assets/pets/...` 結構中。
2. 將 ferret 圖片去背為透明 PNG。
3. 統一圖片尺寸、留白、主體位置與輸出格式。
4. 確認 Flutter 可以正常讀取 ferret 圖片。
5. 將 ferret 加入寵物換皮系統與商店／換皮 UI。

---

## 目前專案素材目錄

專案目前採用「依狀態分類資料夾」的素材結構，不是每隻寵物各自一個資料夾。

請沿用既有結構：

```text
assets/pets_raw/
assets/pets/
assets/pets/rest/
assets/pets/listening/
assets/pets/talk/
assets/pets/states/
```

其中：

- `assets/pets_raw/`：可作為原始素材備份，不作為 App 正式讀取來源。
- `assets/pets/`：App 正式讀取圖片來源。
- `assets/pets/rest/`：待機動畫圖片。
- `assets/pets/listening/`：聆聽狀態圖片。
- `assets/pets/talk/`：說話動畫圖片。
- `assets/pets/states/`：情緒／狀態圖片。

---

## ferret 圖片現況

使用者已經將 ferret 圖片放入 `assets/pets/...` 底下，因此本 CR 不需要再做圖片搬移或複製。

請先確認以下檔案存在：

```text
assets/pets/rest/ferret_rest_01.png
assets/pets/rest/ferret_rest_02.png
assets/pets/rest/ferret_rest_03.png

assets/pets/listening/ferret_listening.png

assets/pets/talk/ferret_talk_01.png
assets/pets/talk/ferret_talk_02.png
assets/pets/talk/ferret_talk_03.png
assets/pets/talk/ferret_talk_04.png
assets/pets/talk/ferret_talk_05.png
assets/pets/talk/ferret_talk_06.png

assets/pets/states/ferret_hungry.png
assets/pets/states/ferret_sleepy.png
assets/pets/states/ferret_thirsty.png
assets/pets/states/ferret_happy.png
assets/pets/states/ferret_excited.png
assets/pets/states/ferret_sad.png
assets/pets/states/ferret_normal.png
assets/pets/states/ferret_caring.png
```

若檔案不存在，請先回報缺少哪些檔案，不要自行亂改對應關係。

---

## 圖片處理要求

### 1. 去背

請將所有 ferret 圖片處理成透明背景 PNG。

要求：

- 背景必須透明。
- 不要留下白底方框。
- 不要留下明顯白邊、灰邊、鋸齒邊。
- 不要裁掉耳朵、尾巴、腳或手。
- 主體邊緣要乾淨，但不要過度削掉角色外框。

---

### 2. 統一格式

所有 ferret 圖片請統一為：

```text
PNG
透明背景
sRGB
檔名維持不變
```

不要改成 jpg、webp 或其他格式。

---

### 3. 統一尺寸與留白

請依照現有 dog 圖片的尺寸規格與視覺比例調整 ferret。

請先檢查 dog 圖片目前的尺寸，例如：

```text
assets/pets/states/dog_normal.png
assets/pets/rest/dog_rest_01.png
assets/pets/talk/dog_talk_01.png
assets/pets/listening/dog_listening.png
```

再讓 ferret 對齊同類型圖片的尺寸與角色比例。

原則：

- rest 類圖片對齊 dog rest 的畫布大小。
- listening 類圖片對齊 dog listening 的畫布大小。
- talk 類圖片對齊 dog talk 的畫布大小。
- states 類圖片對齊 dog states 的畫布大小。
- 主體盡量置中。
- 底部不要貼太死，保留少量安全留白。
- 角色不要縮太小，避免首頁看起來有太多空白。
- 同一分類內的 ferret 圖片角色高度要接近，避免動畫播放時上下跳動。

---

### 4. 不要破壞既有素材

禁止修改、覆蓋或重新輸出以下既有寵物素材：

```text
dog
fox
guinea_pig
```

本 CR 只能處理：

```text
ferret_*.png
```

---

## Flutter 接入要求

### 1. 檢查 pubspec.yaml

確認 Flutter 已註冊目前使用的 assets 路徑。

如果已經有：

```yaml
flutter:
  assets:
    - assets/pets/
```

或：

```yaml
flutter:
  assets:
    - assets/
```

通常不需要新增。

如果目前是逐資料夾註冊，請確認包含：

```yaml
flutter:
  assets:
    - assets/pets/rest/
    - assets/pets/listening/
    - assets/pets/talk/
    - assets/pets/states/
```

---

### 2. 擴充寵物模型／枚舉

請找到目前管理寵物種類的 enum、model 或 registry。可能名稱包含：

```text
PetType
PetSkin
PetSpecies
PetAssetSet
PetAssetResolver
PetController
PetStoreController
```

實際名稱以專案為準，不要硬改不存在的檔案。

新增寵物：

```text
key: ferret
displayName: 雪貂
```

---

### 3. 註冊 ferret 圖片路徑

ferret 應支援：

```text
rest:
- assets/pets/rest/ferret_rest_01.png
- assets/pets/rest/ferret_rest_02.png
- assets/pets/rest/ferret_rest_03.png

listening:
- assets/pets/listening/ferret_listening.png

talk:
- assets/pets/talk/ferret_talk_01.png
- assets/pets/talk/ferret_talk_02.png
- assets/pets/talk/ferret_talk_03.png
- assets/pets/talk/ferret_talk_04.png
- assets/pets/talk/ferret_talk_05.png
- assets/pets/talk/ferret_talk_06.png

states:
- assets/pets/states/ferret_normal.png
- assets/pets/states/ferret_happy.png
- assets/pets/states/ferret_sad.png
- assets/pets/states/ferret_excited.png
- assets/pets/states/ferret_sleepy.png
- assets/pets/states/ferret_hungry.png
- assets/pets/states/ferret_thirsty.png
- assets/pets/states/ferret_caring.png
```

---

### 4. 更新商店／換皮 UI

請讓 ferret 出現在寵物商店或換皮選單。

建議設定：

```text
id/key: ferret
displayName: 雪貂
previewImage: assets/pets/states/ferret_normal.png
unlock rule: 沿用 fox / guinea_pig 的既有規則，或依現有商店邏輯設定
```

不得影響既有：

```text
dog
fox
guinea_pig
```

---

## 測試要求

請依專案既有測試架構補測，至少確認：

1. ferret asset resolver 可以取得 rest/listening/talk/states 路徑。
2. ferret rest frames 數量為 3。
3. ferret talk frames 數量為 6。
4. ferret states 包含 8 種狀態。
5. ferret 出現在寵物商店／換皮清單。
6. dog / fox / guinea_pig 既有資料未被覆蓋。
7. 所有 ferret 圖片檔案存在且 Flutter 可載入。
8. ferret 圖片去背後仍為 PNG 且支援透明背景。
9. 首頁切換 ferret 不會出現 asset missing 或紅字錯誤。

---

## 驗收標準

完成後需符合：

- ferret 圖片皆為透明背景 PNG。
- ferret 圖片沒有白底方框。
- ferret 圖片留白與大小接近 dog 同類型素材。
- `flutter pub get` 成功。
- `flutter analyze` 無錯誤。
- `flutter test` 通過。
- 首頁可切換到 ferret。
- 待機狀態可輪播 3 張 rest 圖。
- 聆聽狀態可顯示 `ferret_listening.png`。
- 說話狀態可輪播 6 張 talk 圖。
- 情緒狀態可顯示 normal、happy、sad、excited、sleepy、hungry、thirsty、caring。
- 不影響 dog、fox、guinea_pig。

---

## 建議執行指令

```bash
flutter pub get
flutter analyze
flutter test
```

若專案有自訂測試指令，請依 README 或既有 package script 執行。

---

## 注意事項

- 使用者已經把圖片放好，不需要再搬移或複製圖片。
- 本 CR 可以重新輸出 ferret 圖片本身，以完成去背、裁切、尺寸統一與格式標準化。
- 請只處理 `ferret_*.png`。
- 不要改 dog、fox、guinea_pig 圖片。
- 不要把正式 UI 改成讀取 `assets/pets_raw/`。
- 不要建立 `assets/pets/ferret/...` 新結構。
- 本 CR 若發現圖片品質不足，請列出哪幾張需要人工重出圖，不要用錯誤圖片硬塞。
