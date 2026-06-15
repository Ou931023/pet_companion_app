# CR-0088 — Mochi Pet Asset Integration and Pet State Trigger Expansion

## 目標

新增「麻吉 mochi」寵物素材支援，並改善目前寵物狀態幾乎只在 `talk` / `listening` 之間切換的問題，讓所有已存在的寵物狀態圖都有合理機會被觸發與顯示。

本 CR 的核心有兩個：

1. **Mochi 新寵物接入**  
   使用者已經把所有 mochi 圖片放入正確資料夾，不需要再搬移圖片；請接入 mochi 的 asset resolver / registry / 商店或換皮 UI。

2. **寵物狀態觸發擴充**  
   目前大多數時候只看到 `talk` 與 `listening` 輪流切換，導致 `happy / sad / excited / sleepy / hungry / thirsty / caring / normal` 等狀態圖很少或幾乎沒有出現。請補齊狀態觸發邏輯，讓所有寵物的狀態圖在合適情境下都有機會顯示。

---

## 背景

目前專案寵物素材採用「依狀態分類資料夾」結構：

```text
assets/pets_raw/
assets/pets/
assets/pets/rest/
assets/pets/listening/
assets/pets/talk/
assets/pets/states/
```

正式 App 應讀取：

```text
assets/pets/rest/
assets/pets/listening/
assets/pets/talk/
assets/pets/states/
```

`assets/pets_raw/` 僅作為原始素材備份，不作為正式 UI 讀取來源。

---

## 重要前提

使用者已經把 mochi 所有圖片放入資料夾。

因此本 CR：

- 不需要重新搬移 mochi 圖片。
- 不需要複製 mochi 圖片。
- 不要建立 `assets/pets/mochi/...` 新結構。
- 不要改成每隻寵物一個資料夾。
- 請直接盤點現有 `assets/pets/...` 內的 `mochi_*.png` 檔案。
- 若缺圖，請明確回報缺少哪些檔案，不要自行拿其他寵物圖片替代。

---

## 正式素材命名規格

請確認 mochi 至少具備以下完整檔案。

### rest

```text
assets/pets/rest/mochi_rest_01.png
assets/pets/rest/mochi_rest_02.png
assets/pets/rest/mochi_rest_03.png
```

### listening

```text
assets/pets/listening/mochi_listening.png
```

### talk

```text
assets/pets/talk/mochi_talk_01.png
assets/pets/talk/mochi_talk_02.png
assets/pets/talk/mochi_talk_03.png
assets/pets/talk/mochi_talk_04.png
assets/pets/talk/mochi_talk_05.png
assets/pets/talk/mochi_talk_06.png
```

### states

```text
assets/pets/states/mochi_normal.png
assets/pets/states/mochi_happy.png
assets/pets/states/mochi_sad.png
assets/pets/states/mochi_excited.png
assets/pets/states/mochi_sleepy.png
assets/pets/states/mochi_hungry.png
assets/pets/states/mochi_thirsty.png
assets/pets/states/mochi_caring.png
```

若實際檔名為 `magi_*`、`maji_*` 或其他拼法，請不要混用。正式 key 請統一使用：

```text
mochi
```

顯示名稱使用：

```text
麻吉
```

---

## Part A — Mochi 新寵物接入

### A1. 盤點 mochi asset

請列出目前 mochi 實際檔案清單，確認：

```text
rest 3 張
listening 1 張
talk 6 張
states 8 張
```

若超過 8 種 states，可以保留並登記為 extended states，但 basic 8 states 必須完整。

### A2. 更新 pet type / skin registry

請找到目前管理寵物種類的 enum、model、registry 或 resolver。

可能名稱包含：

```text
PetType
PetSkin
PetSpecies
PetAssetSet
PetAssetResolver
PetController
PetStoreController
PetCatalog
PetDefinition
```

實際名稱以專案為準，不要硬改不存在的檔案。

新增：

```text
key: mochi
displayName: 麻吉
previewImage: assets/pets/states/mochi_normal.png
```

不得影響既有：

```text
dog
fox
guinea_pig
ferret
```

若目前已有 demo 全寵物免費邏輯，mochi 應依現有 demo 規則處理，不要自行新增衝突的解鎖邏輯。

### A3. 更新商店 / 換皮 UI

請讓 mochi 出現在寵物商店或換皮選單。

要求：

```text
名稱：麻吉
key：mochi
預覽圖：mochi_normal.png
可切換
切換後首頁顯示 mochi
重新開 App 後能保留選擇（若既有寵物已支援持久化）
```

不要破壞既有寵物列表排序。若需排序，建議：

```text
dog
guinea_pig
fox
ferret
mochi
```

或依現有 UI 排序規則。

### A4. pubspec.yaml 檢查

確認 Flutter assets 已包含正式素材資料夾。

若已有：

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

若是逐資料夾註冊，請確認有：

```yaml
flutter:
  assets:
    - assets/pets/rest/
    - assets/pets/listening/
    - assets/pets/talk/
    - assets/pets/states/
```

---

## Part B — 寵物狀態觸發擴充

## 問題描述

目前使用者觀察到：

```text
大部分時候寵物只在 talk 和 listening 之間切換。
其他 states 圖片很少出現，甚至幾乎沒有機會出現。
```

這會讓寵物素材雖然完整，但展示時看起來狀態很單調，也無法呈現照護陪伴感。

### B1. 盤點目前狀態來源

請先盤點目前寵物狀態由哪些來源決定：

```text
語音聆聽中 → listening
AI 說話中 → talk frames
閒置中 → rest frames
情緒分析 → states ?
任務 / 提醒 / 喝水 / 餵食 → hungry / thirsty ?
寵物數值 mood / satiety / intimacy → states ?
Care Alert risk → sad / caring ?
Conversation emotionTag → happy / sad / caring ?
```

請在文件中說明目前實際狀態切換路徑，不要猜。

### B2. 建立清楚的狀態優先序

請建立或整理一套狀態顯示優先序，避免 `talk/listening` 永遠蓋掉 states。

建議優先序：

```text
1. listening：使用者正在說話 / 麥克風收音中
2. talk：寵物正在播放語音 / AI 回覆中
3. transient state：剛完成互動後的短暫情緒狀態，例如 happy、sad、caring
4. care state：由寵物數值或照護狀態決定，例如 hungry、thirsty、sleepy
5. idle rest：無互動時輪播 rest frames
6. normal：fallback
```

重點不是移除 `talk/listening`，而是避免它們在非聆聽 / 非說話時繼續佔用畫面。

### B3. 新增「短暫狀態顯示」機制

當一次對話、任務或提醒結束後，寵物應短暫顯示對應狀態，而不是立刻回到 rest 或 listening。

建議：

```text
對話情緒正向 → happy / excited 顯示 2~4 秒
長者低落 / 疲倦 → caring 或 sad 顯示 2~4 秒
完成任務 → happy 或 excited 顯示 2~4 秒
低風險關懷 → caring 顯示 2~4 秒
寵物飽足度太低 → hungry 可持續顯示
寵物喝水需求 / 口渴 → thirsty 可持續顯示
夜間或低活力 → sleepy 可顯示
```

若目前已有 transient expression 機制，請擴充既有機制，不要重寫整套狀態機。

### B4. 情緒 / 狀態 mapping 建議

請依現有 emotionTag / mood / riskLevel 命名調整。以下為建議 mapping：

```text
happy / joy / positive / grateful -> happy
excited / energetic -> excited
sad / lonely / depressed / tired -> sad 或 caring
anxious / worried / fear -> caring
angry / frustrated -> sad 或 caring
neutral -> normal
```

照護數值 mapping：

```text
satiety < 30 -> hungry
hydration 或 waterNeed 低 / reminder missed drink water -> thirsty
energy low / late night / sleep reminder -> sleepy
mood < 30 -> sad 或 caring
intimacy < 30 -> caring
```

注意：

- 若沒有 hydration 資料，不要硬觸發 thirsty。
- 若沒有 energy / sleep 資料，不要硬觸發 sleepy。
- 如果目前只有 satiety / mood / intimacy，就先接這三個。
- 不要用假資料硬讓狀態出現。

### B5. 避免狀態永遠被 talk/listening 蓋掉

請確認：

```text
麥克風沒有在收音時，不應顯示 listening。
寵物語音沒有播放時，不應顯示 talk。
AI response.done 不等於語音播放完成；不要提早切字幕或 talk 狀態。
工具語音 / filler / AI 語音若正在播，talk 狀態應與實際播放一致。
語音結束後，應允許 transient state 顯示一小段時間。
```

注意：完整字幕同步會在 CR-0089 處理，本 CR 只處理「狀態圖不要永遠停在 talk/listening」。不要大改 Realtime 主流程。

如果發現必須修改 🔒 Realtime 相關檔案，請先停下並回報需要 architecture-agent 審查。

### B6. 狀態觸發要套用所有寵物

狀態邏輯不應只對 mochi 有效。請讓以下寵物都能使用同一套 state mapping：

```text
dog
fox
guinea_pig
ferret
mochi
```

但如果某寵物缺少某狀態圖，請 fallback：

```text
同寵物該狀態圖
→ 同寵物 normal
→ dog normal
```

同時在測試或文件標註缺圖狀況。

### B7. Idle / rest 顯示規則

請確認非互動時會顯示 rest frames，而不是停在 listening 或 talk。

建議：

```text
無語音播放
無麥克風收音
無 transient state
無 urgent care state
→ 輪播 rest frames
```

若目前 rest 輪播已存在，請修正觸發條件即可，不要重寫整個首頁動畫。

---

## Part C — 圖片格式與視覺清理

### C1. mochi 圖片格式

請確認 mochi 圖片：

```text
PNG
透明背景
檔名全小寫
無白底方塊
無黑邊
尺寸與同類型寵物接近
```

若 mochi 圖片仍是白底或有黑邊，請清理後覆蓋正式素材檔。

### C2. ferret 去背清理

請同步檢查 ferret 圖片去背。

重點：

```text
透明背景
不要白邊
不要殘留灰邊
不要切掉尾巴 / 耳朵 / 腳
留白不要過大
```

只處理 `ferret_*.png` 與必要的 `mochi_*.png`，不要大範圍改 dog / fox / guinea_pig，除非有明確問題。

---

## 測試要求

請依現有 Flutter 測試架構新增或更新測試。

### Asset 測試

至少涵蓋：

1. mochi rest frames = 3。
2. mochi listening 存在。
3. mochi talk frames = 6。
4. mochi basic states 8 張都可 resolver。
5. mochi 出現在寵物商店 / 換皮清單。
6. dog / fox / guinea_pig / ferret 既有清單未被覆蓋。
7. 每隻寵物可取得 normal / happy / sad / excited / sleepy / hungry / thirsty / caring。
8. 缺少非必要狀態時 fallback 不崩潰。
9. pubspec assets 註冊不缺正式資料夾。

### 狀態觸發測試

至少涵蓋：

1. 正在收音時顯示 listening。
2. 正在播放寵物語音時顯示 talk。
3. 語音結束後，正向情緒可短暫顯示 happy / excited。
4. 低落情緒可短暫顯示 sad / caring。
5. satiety 低時可顯示 hungry。
6. intimacy 低時可顯示 caring。
7. 無互動時回到 rest frames。
8. listening / talk 不應在非收音 / 非播放時持續卡住。
9. 同一套 mapping 對 mochi 與其他寵物皆適用。
10. fallback 不造成 asset missing。

若現有測試不易直接測 UI 動畫，請將 state selection 邏輯抽成純函式或 service 進行測試，UI 只消費結果。

---

## 手動驗收

請在模擬器或實機確認：

```text
mochi 可在換皮頁看到
mochi 可切換成功
mochi 首頁顯示正常
mochi rest / listening / talk / states 可正常顯示
ferret 去背更乾淨
寵物不再長時間卡在 listening
寵物不再長時間卡在 talk
對話結束後會短暫出現 happy / caring / sad 等狀態
飽足度低時能顯示 hungry
無互動時能回到 rest 動畫
切換 dog / fox / guinea_pig / ferret / mochi 不崩潰
```

---

## 文件要求

請新增或更新：

```text
docs/PET_ASSET_STATE_EXPANSION_CR0088.md
```

內容至少包含：

1. mochi 接入內容。
2. 正式素材目錄。
3. mochi asset 清單。
4. ferret / mochi 圖片清理狀況。
5. 狀態觸發 mapping。
6. talk / listening / rest / states 的優先序。
7. 測試結果。
8. 已知限制。

請更新：

```text
docs/CHANGE_REVIEW.md
```

新增：

```text
## CR-0088 — Mochi Pet Asset Integration and Pet State Trigger Expansion
```

並宣告下一個可用 CR：

```text
CR-0089
```

---

## 建議執行指令

```bash
flutter analyze
flutter test
```

若本 CR 沒有觸及後端，不需要執行後端 npm 測試。

---

## 注意事項

- 不要讀 `.env`。
- 不要改 Telegram。
- 不要改 Care Alert 後端通知規則。
- 不要改管理者後台分析頁。
- 不要改推播通知邏輯；CR-0087 已處理。
- 不要處理字幕同步細節；CR-0089 會處理。
- 不要處理 AI 對話自然度；CR-0090 會處理。
- 不要更換 App icon；後續 CR 會處理。
- 不要建立 `assets/pets/mochi/...` 新資料夾結構。
- 不要讓正式 UI 讀取 `assets/pets_raw/`。
- 若需觸及 🔒 Realtime 相關檔案，請先停下並回報需要 architecture-agent 審查。
- 若圖片缺少透明背景，請只處理圖片輸出，不要改成用白底遮掩。
