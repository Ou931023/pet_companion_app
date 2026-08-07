# STORE_ASSET_CHECKLIST — Icon / Screenshot / Launch Screen 素材檢查

> 建立：CR-0058。狀態：**icon / feature graphic / screenshots / launch screen 已輸出**。
> 對照：`docs/STORE_SUBMISSION_RUNBOOK.md`、`docs/APP_STORE_METADATA.md`、`docs/STORE_RELEASE_CHECKLIST.md`。

---

## 1. 現況（CR-0101B store asset 輸出後）

- iOS：✅ `ios/Runner/Assets.xcassets/AppIcon.appiconset/` 已輸出正式候選 icon 全尺寸組（含 `Icon-App-1024x1024@1x.png`）。
- Android：✅ `mipmap-{m,h,xh,xxh,xxxh}dpi/ic_launcher.png` 已輸出正式候選 legacy launcher icon。
- Android adaptive icon：✅ 已補 `mipmap-anydpi-v26/ic_launcher.xml`、`mipmap-*/ic_launcher_foreground.png`、`values/colors.xml` 背景色。
- Play Store listing icon：✅ `store_assets/play_store_icon_512.png` 已輸出。
- Google Play feature graphic：✅ `store_assets/play_feature_graphic_1024x500.png` 已輸出。
- launch screen：✅ 已使用正式候選 icon + `#FFF8EA` 品牌底色；仍需實機/商店後台預覽確認裁切與過場。
- 無 `flutter_launcher_icons` 設定（icon 為手動放置）。
- screenshots：✅ 已輸出去識別化商店候選截圖：
  - Android phone：`store_assets/screenshots/android_phone/*.png`（5 張，1080×1920）
  - iPhone 6.7"：`store_assets/screenshots/ios_6_7/*.png`（5 張，1290×2796）
  - 產出腳本：`scripts/generate_store_screenshots.sh`

---

## 2. Icon 規格

### iOS App Icon
- 1024×1024（App Store，無透明、無圓角，sRGB）+ appiconset 各尺寸（20/29/40/60/76/83.5pt @1x/2x/3x）。
- ✅ 使用正式候選美術：奶奶擁抱 AI 寵物、溫暖陪伴意象，非 Flutter 預設佔位。

### Android Launcher / Adaptive Icon
- legacy：✅ `ic_launcher.png` 各密度已輸出。
- adaptive icon：✅ `mipmap-anydpi-v26/ic_launcher.xml` + `ic_launcher_foreground` 各密度 + `ic_launcher_background` 色值已補。仍需真機檢查各家 launcher mask 裁切效果。
- Play Store listing icon：✅ `store_assets/play_store_icon_512.png`（512×512 PNG）。

### 紅線
- ⛔ 不含誤導醫療圖示（紅十字、聽診器、藥丸暗示診斷）— Care Alert 非醫療。
- 透明邊 / 留白：iOS 不可透明；Android adaptive 前景須含足夠 padding。

---

## 3. Screenshots 規格

### iOS（App Store Connect，至少 6.7" 與 6.5"，或最新要求尺寸）
- iPhone 6.7"（1290×2796）、6.5"（1242×2688）必備；iPad 若支援另備 12.9"。

### Android（Play Console）
- phone：≥2 張，1080×1920 級別（直）；tablet 若支援另備。
- Feature graphic：✅ `store_assets/play_feature_graphic_1024x500.png`（1024×500）。
- Phone screenshots：✅ `store_assets/screenshots/android_phone/`（5 張，1080×1920）。

### 建議截圖頁面（5）
1. 首頁 AI 寵物 + 大麥克風按鈕（一眼看出能否說話）。
2. Realtime 語音陪伴中（partial transcript）。
3. 對話記錄 / 長期記憶管理。
4. 「今日關心紀錄」（長者端溫暖呈現、**不顯風險等級**）。
5. 設定 / 隱私控制（同意、資料刪除入口）。

### 紅線
- ⛔ 不得出現真實長者個資 / 真電話 / 真 email / 真對話原文（用去識別化假資料）。
- ⛔ 不得出現 debug / demo / test / mock / 工程字樣。
- ⛔ 不得截 production 已隱藏的 marketplace / daily-care 畫面（CR-0056）。
- caregiver_web 管理端若入截圖須去識別化。

---

## 4. Launch Screen
- ✅ iOS：`ios/Runner/Assets.xcassets/LaunchImage.imageset/` 已由 1×1 預設空圖替換為正式候選 icon 圖資。
- ✅ Android：`android/app/src/main/res/drawable*/launch_background.xml` 已使用 `@color/launch_background` + `@drawable/launch_brand`，不再是 Flutter 模板白底空畫面。
- 🔁 送審前仍需於 iOS / Android 實機確認啟動過場不閃白、不裁切、不出現舊圖。

---

## 5. Owner action 摘要（blocker）
- [x] 正式候選 App icon 美術（iOS 1024 + Android adaptive 前景/背景）。
- [x] Play Store listing icon 512×512 PNG：`store_assets/play_store_icon_512.png`。
- [x] Android feature graphic 1024×500 PNG：`store_assets/play_feature_graphic_1024x500.png`。
- [x] 5 組去識別化 screenshots（兩平台尺寸）：`store_assets/screenshots/`。
- [x] 確認 launch screen 非 Flutter 預設、品牌一致。

---

## 6. Runbook 對應檔位

送審前依 `docs/STORE_SUBMISSION_RUNBOOK.md` §6 驗收，素材落點如下：

- iOS icon：`ios/Runner/Assets.xcassets/AppIcon.appiconset/`
- Android legacy icon：`android/app/src/main/res/mipmap-*/ic_launcher.png`
- Android adaptive icon：`android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`
- Android adaptive foreground/background：建議放在 `android/app/src/main/res/drawable/` 或 `android/app/src/main/res/values/`，依實際素材型態決定。
- Play Store listing icon：`store_assets/play_store_icon_512.png`
- Google Play feature graphic：`store_assets/play_feature_graphic_1024x500.png`
- Android phone screenshots：`store_assets/screenshots/android_phone/`
- iPhone 6.7" screenshots：`store_assets/screenshots/ios_6_7/`
- iOS launch：`ios/Runner/Base.lproj/LaunchScreen.storyboard`
- iOS launch images：`ios/Runner/Assets.xcassets/LaunchImage.imageset/`
- Android launch：`android/app/src/main/res/drawable*/launch_background.xml` 與 theme 設定。
- Android launch brand image：`android/app/src/main/res/drawable-nodpi/launch_brand.png`

若上述檔案尚未存在或仍為預設素材，狀態維持 `BLOCKER`，不得在 store checklist 標為完成。
