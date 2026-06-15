# CR-0088 — Mochi Pet Asset Integration and Pet State Trigger Expansion

兩件事：(A) 新寵物「麻吉 mochi」接入換皮 / 商店；(B) 擴充寵物狀態觸發，讓 `happy / sad / caring / excited / hungry / sleepy / normal / rest` 等狀態圖都有機會顯示，而不是長時間只在 `talk` / `listening` 之間切換。

---

## Part A — Mochi 接入

### 1. 接入內容
- `PetSkin` 新增 `mochi`（key `mochi`、顯示名稱「麻吉」、tagline「黏人撒嬌型」、解鎖 120 點、預覽圖 `mochi_normal.png`）。
- `AssetPaths` 註冊 mochi：talk 6 / rest 3 / listening 1 / states 8。
- 換皮 / 商店選單由 `PetSkin.values` 驅動 → mochi **自動出現**，排序在 ferret 之後（dog → guineaPig → fox → ferret → mochi）。
- Demo 全寵物免費沿用 CR-0084（`app.dart` `freeAllSkins: true`），mochi 一併免費可換，未新增衝突解鎖邏輯。
- 未更動 dog / fox / guineaPig / ferret 的資料與邏輯。

### 2. 正式素材目錄（沿用既有依狀態分類，未建立 `assets/pets/mochi/`）
```
assets/pets/rest/   assets/pets/listening/   assets/pets/talk/   assets/pets/states/
```

### 3. Mochi asset 清單（共 18 張，皆去背 + 統一為 1024×1024 RGBA）
- rest：`mochi_rest_01/02/03.png`（01/02 為坐姿、03 為趴睡姿，含 Zzz）
- listening：`mochi_listening.png`
- talk：`mochi_talk_01..06.png`
- states：`mochi_normal / happy / sad / excited / sleepy / hungry / thirsty / caring.png`

> 另有一張使用者放入的 `assets/pets/states/mochi_listening.png`（未去背、738×1314），**非標準 8 狀態、resolver 不引用**，保留未動、不影響顯示。

### 4. ferret / mochi 圖片清理狀況
- **mochi**：原圖為 738×1314（部分 856×1522、2354×1314）白底 RGB。以邊緣 flood-fill（fuzz 28%）去背為透明，統一縮放置中、腳底基準線對齊 dog（feet ≈ y944、底部留白 80），輸出 1024² RGBA、無白底方框、無白邊。趴睡的 `rest_03` 為橫幅構圖，獨立貼齊底線（與坐姿輪播時呈「貓咪趴下休息」過渡）。
- **ferret**：CR-0082 已完成去背（1024² RGBA、透明、邊緣乾淨），本 CR 覆查確認**無殘留白邊 / 灰邊、未切到尾巴耳朵腳**，故未再更動 ferret 圖檔。

---

## Part B — 狀態觸發擴充

### 5. 目前實際狀態切換路徑（盤點，非猜測）
- `listening`：語音 `VoiceAgentState.listening/transcribing`、以及多數對話 `_deliverPetReply(petMode: listening)`。
- `talking`：語音 `speaking`、打字對話 TTS `onStart`。
- `rest`：僅初始、`enterInitialRestThenListen`、以及 **PetController 8 秒 idle timer 衰減**。
- 情緒狀態（happy/sad/caring/concerned/smile/excited/sleepy）：語音 `_applyEmotionToPet` / `_applyCompanionPetState`、打字 `_applyPetEmotionState` 會設定，但常被緊接的語音狀態轉換覆蓋、或被 8 秒 idle timer 退回 rest。
- `hungry` / `thirsty` / `normal`：**先前沒有任何地方會設定**（PetStats 的 satiety/mood/intimacy 從未映射成 PetMode）。

**根因**：首頁過去只讀 `petController.mode` 單一欄位顯示；情緒狀態壽命極短，且 satiety/mood 等數值完全沒有進到顯示路徑 → 看起來只在 talk/listening 之間切換。

### 6. 解法：純函式狀態選擇器（不改 Realtime / 不改控制器內部）
新增 `lib/utils/pet_state_selector.dart`，首頁 build 時呼叫，**消費既有訊號**決定顯示哪個 PetMode：

**優先序**
1. **listening** — 麥克風收音中（`voiceState listening/transcribing`）。
2. **talking** — 寵物語音播放中（`voiceState speaking` 或既有 `talking` 模式）。
3. **transient（短暫情緒）** — 互動剛結束的 happy/caring/sad…（由 `PetController.showTransientState` 持有計時，預設 4 秒）。
4. **care state（照護狀態）** — 由寵物數值推得。
5. **rest** — 以上皆非的閒置待機（rest frames 輪播）。

### 7. 狀態 mapping
**情緒標籤 → 短暫狀態**（對齊 `ConversationTurn.emotionTag`）：
```
happy → happy    excited → excited
sad → sad        lonely / anxious / angry → caring
tired → sleepy   neutral / 未知 → 不觸發
```
首頁監聽對話，新一則含情緒的對話結束後呼叫 `showTransientState`，由選擇器在非收音 / 非播放時顯示。

**照護數值 → care state**（只接目前真實存在的數值，缺資料不硬觸發）：
```
satiety < 30  → hungry
mood < 30     → sad
intimacy < 30 → caring
深夜（22:00–06:00，依真實時鐘）→ sleepy
```
care 內優先序：hungry > sad > caring > sleepy。

### 8. 同一套 mapping 套用所有寵物
選擇器只回 PetMode，與寵物種類無關 → dog / fox / guineaPig / ferret / mochi 皆適用同一套邏輯。缺某狀態圖時 `AssetPaths.stateImage` fallback 至該寵物 `normal`（最終保底 dog rest_01），不會 asset missing。

### 9. Idle / rest
無收音、無播放、無 transient、無 care state → 回 `rest`（rest frames 輪播）。既有 8 秒 idle timer 仍負責把 mode 衰減回 rest，本 CR 不重寫首頁動畫。

---

## 10. 測試結果
- 新增 `test/models/mochi_skin_test.dart`：mochi 註冊、rest3/talk6/listening/states8 路徑、出現在換皮清單、不覆蓋既有寵物、**全寵物 8 狀態可解析**、18 張圖存在且為 1024² RGBA、pubspec 註冊。
- 新增 `test/utils/pet_state_selector_test.dart`：優先序（listening>talking>transient>care>rest）、各 care state、深夜 sleepy、缺資料不硬觸發、不卡在 talk/listening、情緒→狀態 mapping。
- 新增 `test/controllers/pet_controller_transient_test.dart`：transient 設定 + 到期自動清除 + 覆蓋。
- 既有 pet_avatar / pet_skin / ferret / picker 測試全綠（未覆蓋既有寵物）。
- 結果：`flutter analyze` **No issues**；`flutter test` **665 passed / 0 failed**。

---

## 11. 已知限制
- **mochi rest_03 為趴睡姿**（源圖如此），與坐姿 rest_01/02 輪播時體型較不同；屬源素材內容，未重畫。
- **thirsty 目前缺乏觸發來源**：無 hydration / 喝水提醒未完成的資料，依規格不硬觸發；thirsty 狀態圖已備好但少有機會自動出現（可由日後喝水任務資料接入）。
- **sleepy** 目前由「真實深夜時鐘」與情緒 `tired` 觸發；無 energy / 睡眠感測資料，不硬觸發。
- **連續語音通話中**：麥克風持續收音時 listening 會穩定顯示（符合「收音中才 listening」）；短暫情緒主要在語音停止 / 打字對話後浮現。
- 字幕同步細節（`response.done` 與實際語音播放結束的對齊）**不在本 CR**，留待 CR-0089；本 CR 僅以 `voiceState speaking` 對齊 talk 顯示，未改 Realtime 主流程。
- 未改 Telegram / Care Alert 後端通知 / 管理端分析頁 / 推播通知（CR-0087）。
