# CR-0100 Pet Visual Asset Strategy

> 目標：把 AI 寵物從「目前可用的 PNG 動畫」推進到正式上架可長期維護的素材系統，支援長者偏好、Q 版 / 真實版比較、成長階段、更多互動動畫與後台資料分析。

## 決策摘要

本專案短期不建議立刻改成 3D、Rive 或即時生成寵物。正式上架第一版建議採用：

1. **Production v1：高解析透明 PNG frame sequence**
   - 沿用目前 `PetAvatar` / `AssetPaths` 架構。
   - 每個寵物維持固定畫布、固定腳底基準線、固定 frame count。
   - 優先補齊更多互動狀態與 Q 版 / 真實版對照素材。

2. **Production v1.5：Sprite sheet 或 PNG atlas**
   - 當素材張數變多後，再把同一動作的 PNG frames 合成 atlas，降低載入與檔案管理成本。
   - App 程式仍以 `PetVisualProfile` 管理能力，不讓 UI 寫死路徑。

3. **Production v2：Rive / Lottie 只用於通用特效，不承擔寵物本體**
   - 適合光圈、愛心、呼吸、獎勵粒子、情緒浮動字。
   - 不建議讓主要寵物角色完全改成 Rive，因為目前寵物是圖片風格，改向量會重做所有素材，風險高。

4. **不採用：每次互動即時 AI 生圖**
   - 速度、成本、一致性、審核風險都不適合長者正式 App。
   - AI 生圖可以用於「離線產素材候選」，人工挑選後入庫，不在 App runtime 產圖。

## 現況

目前 production 已有 4 隻寵物：

| petType | 中文 | visualStyle | growthStage | talk | rest | listening | states |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: |
| `dog` | 狗狗 | `cute` | `adult` | 6 | 3 | 1 | 8 |
| `guinea_pig` | 天竺鼠 | `cute` | `adult` | 3 | 3 | 1 | 8 |
| `fox` | 狐狸 | `cute` | `adult` | 6 | 3 | 1 | 8 |
| `mochi` | 麻吉 | `cute` | `adult` | 6 | 3 | 1 | 8 |

資料來源：

- `lib/models/pet_visual_profile.dart`
- `lib/utils/asset_paths.dart`
- `assets/pets/rest/`
- `assets/pets/talk/`
- `assets/pets/listening/`
- `assets/pets/states/`

## 素材資料夾策略

### 目前維持

```text
assets/pets/rest/<pet>_rest_01.png
assets/pets/talk/<pet>_talk_01.png
assets/pets/listening/<pet>_listening.png
assets/pets/states/<pet>_<state>.png
```

### 下一階段建議新增

為了支援 Q 版 / 真實版與成長階段，下一階段可逐步改成：

```text
assets/pets/v2/<visualStyle>/<growthStage>/<pet>/rest/rest_01.png
assets/pets/v2/<visualStyle>/<growthStage>/<pet>/talk/talk_01.png
assets/pets/v2/<visualStyle>/<growthStage>/<pet>/listening/listening.png
assets/pets/v2/<visualStyle>/<growthStage>/<pet>/states/happy.png
assets/pets/v2/<visualStyle>/<growthStage>/<pet>/interactions/pat_01.png
assets/pets/v2/<visualStyle>/<growthStage>/<pet>/interactions/feed_01.png
```

先不要立刻搬現有素材。等第一組 Q/real 對照素材通過後，再擴充 `AssetPaths` 支援 v2 resolver，並保留現有路徑 fallback。

## 必備狀態

每個可上線的寵物風格組合至少需要：

| 類型 | 最低數量 | 用途 |
| --- | ---: | --- |
| normal | 1 | 靜態預覽 / fallback |
| happy | 1 | 正向回饋、任務完成 |
| caring | 1 | 情緒關懷、Care Alert 前台安撫 |
| sad | 1 | 使用者低落時的共感 |
| sleepy | 1 | 疲累或休息脈絡 |
| hungry | 1 | 飽足低 |
| thirsty | 1 | 喝水提醒 |
| excited | 1 | 遊戲、獎勵、簽到 |
| listening | 1 | 聆聽狀態 |
| talk | 6 frames | 說話動畫 |
| rest | 3 frames | 待機呼吸 / 眨眼 |

## 建議互動動畫

上架第一版最值得補的是「讓長者覺得有互動」的低成本動作：

1. **pat / 摸摸**
   - 使用者點寵物或說「摸摸你」時觸發。
   - 3 frames 即可：正常 → 開心閉眼 → 回正常。

2. **feed / 餵食**
   - 使用背包物品或語音說「餵你吃東西」時觸發。
   - 4 frames：看食物 → 吃 → 開心 → normal。

3. **heart / 愛心陪伴**
   - 使用者孤單、難過或完成每日互動時觸發。
   - 寵物本體可用 `caring/happy` PNG，愛心用 Flutter/Rive/Lottie overlay。

4. **celebrate / 完成任務**
   - 簽到、任務、拼圖完成。
   - 3 frames + 金幣/星星 overlay。

## Q 版 / 真實版策略

### 不要一次做所有寵物

先選 **一隻主寵物** 做完整 Q/real 對比。建議順序：

1. `dog`
   - 長者接受度最高。
   - 真實版參考最容易穩定。
   - 最適合 App Store screenshot 和 feature graphic。

2. `mochi`
   - 若想保留品牌感與可愛差異，可作第二組。

### 真實版定義

真實版不是照片，也不是暗色、逼真到像醫療或監控產品。正式方向應是：

- 半寫實、柔和、溫暖。
- 仍維持透明背景與同一姿勢語言。
- 臉部表情清楚，長者一眼看得懂。
- 不使用恐怖谷、過度擬真眼神、雜亂毛髮。

### App 內選擇

第一版可在「更換外觀」加入風格分段：

- Q版
- 真實版

選擇後上報：

```json
{
  "eventType": "pet_style_changed",
  "metadata": {
    "petType": "dog",
    "visualStyle": "realistic",
    "growthStage": "adult",
    "source": "home_skin_picker"
  }
}
```

目前 `pet_style_changed`、`visualStyle`、`growthStage` 已可由 App 上報並在 caregiver analytics 顯示。

## 成長階段策略

不建議第一版就做完整養成數值與多套圖，因為素材量會膨脹。

建議分三階段：

1. **Phase G1：資料先行**
   - 已有 `PetGrowthStage`：`baby / young / adult`。
   - 目前 production profile 誠實標示 `adult`。

2. **Phase G2：只替主寵物補 baby / adult**
   - 先不要補 young。
   - baby 用於新手 onboarding 與早期互動。
   - adult 用於互動累積後解鎖。

3. **Phase G3：完整 baby / young / adult**
   - 需要後端持久化 growth progress。
   - 管理者 analytics 顯示使用者在哪個階段、成長速度與互動關聯。

## 素材驗收標準

每張正式素材必須：

- PNG。
- 1024 x 1024。
- RGBA alpha 透明背景。
- 主體完整，不切腳、不切耳、不切尾。
- 角色視覺中心一致。
- 同一動畫 frame 的腳底基準線一致。
- 同一組 talk/rest 不可忽大忽小。
- 不含浮水印、文字、Logo、UI 邊框。
- 不含第三方 IP 或可能侵權風格。
- 不含醫療診斷、藥物、監控、病患標籤等敏感暗示。

## 產圖流程

正式建議：

1. 先產「角色設計板」
   - normal / happy / caring / sad 四宮格。
   - 人工挑一版。

2. 再產「完整 state sheet」
   - 8 states + listening。
   - 確認角色一致。

3. 再產「動畫 frame」
   - rest 3 frames。
   - talk 6 frames。
   - pat / feed / celebrate 3-4 frames。

4. 最後用腳本檢查
   - PNG header。
   - 1024 x 1024。
   - alpha channel。
   - 檔名完整。
   - pubspec 註冊。

## 實作順序

建議下一步：

1. **CR-0100A：主寵物 Q/real 素材候選**
   - 產 dog Q版 / dog 真實版 normal + happy + caring + sad。
   - 只做人選，不接程式。

2. **CR-0100B：v2 AssetPaths resolver**
   - 新增 v2 path support。
   - 保留現有 v1 fallback。
   - 測試 v1/v2 都能解析。

3. **CR-0100C：App 內風格選擇 UI**
   - 更換外觀 sheet 加「Q版 / 真實版」分段。
   - 上報 `pet_style_changed`。

4. **CR-0100D：互動動畫 overlay**
   - 先做 pat / feed / celebrate。
   - 不急著大量改寵物本體圖。

5. **CR-0100E：成長階段**
   - 先只做 dog baby/adult。
   - 補 growth progress storage 與後台顯示。

## 上架注意事項

- App Store / Google Play 截圖不要展示未實作的真實版或成長階段。
- 若使用 AI 生圖，必須人工挑選並作為 app bundled asset，不要 runtime 生成。
- Store metadata 可以說「可選擇不同寵物外觀」，但在真實版素材未上線前，不要宣稱「Q版/真實版任選」。
- 若後台顯示使用者偏好，隱私政策與 Data Safety 已涵蓋 app usage analytics；後續若新增更細緻偏好欄位，文件要同步更新。
