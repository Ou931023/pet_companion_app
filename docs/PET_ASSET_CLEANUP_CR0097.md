# CR-0097 — Pet Asset 去背 Audit + Mochi Reprocess

> 寵物動畫軌道的素材內容檢查與修復。**只動素材檔與文件**，不改 enum / resolver / 動畫程式（沿用 CR-0093 ping-pong + CR-0088/0094 狀態選擇），不擴大成重做素材系統。不碰 AI persona / Realtime / 字幕 / 推播 / Care Alert / 後台 / App icon。

## 背景

使用者回報目前寵物素材狀況並要求一併檢查：
1. guinea_pig：原 rest 會多出難過狀態圖，已放入新的 rest_03。
2. mochi：去背把貓本身顏色也挖掉了，請勿再用錯誤去背圖。
3. ferret：也有去背吃掉本體顏色的問題。
4. fox：原 rest 多出睡覺狀態，已放入新的 rest_03。

## 關鍵釐清：rest「多出難過/睡覺狀態」不是程式 bug

`AssetPaths.restFrames(skin)` 永遠解析為 `<prefix>_rest_01/02/03.png`（frame count = 3），**從不**引用 states 的 sad/sleepy 圖。CR-0093 的 ping-pong 也只在這 3 張間 1→2→3→2→1。所以「rest 出現難過/睡覺」是**該 `*_rest_03.png` 檔案內容**本身畫的是難過/睡覺，使用者已替換成新的 rest pose 圖 → 問題在素材內容，不在程式。

## 審計結果

用「疊在洋紅底 flatten」目視（破洞會透出洋紅）：

| 寵物 | 狀況 |
|---|---|
| dog | rest 1024² RGBA 正常，1→2→3→2→1 OK。 |
| fox | rest_01/02/03 皆乾淨 rest pose，**無睡覺圖**；rest_03 為使用者新圖（已是合格 PNG）。 |
| guinea_pig | rest_01/02 乾淨；rest_03 為使用者新圖但**原為白底 WebP**（未去背）→ 已處理。rest_03 內容是 content pose，**無難過臉**。 |
| mochi | **rest_01/02 + 全部 8 states + listening + talk 全部被去背吃掉白胸腹毛**（半透明破洞）；只有 CR-0095 重做的 rest_03 乾淨。 |
| ferret | rest 正常；`ferret_sad` / `ferret_caring` 下腹白毛輕微半透明，其餘正常。 |

另外發現使用者新放但**未去背**的白底 WebP（會在 App 顯示白框）：`fox_hungry`、`fox_thirsty`、`guinea_pig_excited`、`guinea_pig_hungry`、`guinea_pig_sleepy`、`guinea_pig_rest_03`。

## 處理（統一用 CR-0095 驗證過的流程）

去背：edge flood-fill **四角**、**fuzz 12%**（淺色毛；28% 會吃掉白胸腹）；置版：`-trim → resize 高 800（states 取 fit 740x800）→ 腳底 y944、水平置中、1024² RGBA`。每張都用洋紅底目視驗證無破洞才採用。

- **guinea_pig_rest_03**：白底 WebP → 1024² RGBA PNG（bbox 690×726+167+218）。
- **mochi 共 16 張**從使用者 `~/Downloads` 乾淨原圖（738×1314 白底）重做：rest_01/02、states happy/sad/excited/sleepy/hungry/thirsty/caring、listening、talk_01–06。
  - rest_01/02 對齊 rest_03（高 800、feet 944、置中），ping-pong 一致。
  - talk_01–06 用**聯集 bbox**（union 668×1020+58+185）裁切，6 幀維持對位、不抖動。
- **fox/guinea_pig 5 張白底 WebP states** 去背為 1024² RGBA：fox_hungry/thirsty、guinea_pig_excited/hungry/sleepy（feet 944）。
- **fox_rest_03**：使用者新圖已是合格 1024² RGBA PNG，不需重做（原樣納入）。

## 已知限制（缺乾淨原圖，本次未修，待補）

- **mochi_normal**：`~/Downloads` 無乾淨原圖 → 維持現狀（仍是去背吃色的舊圖，但仍是合格 1024² RGBA PNG，測試可過）。待使用者提供原圖再用同流程重做。
- **ferret_sad / ferret_caring**：`~/Downloads` 無任何 ferret 原圖、無法從原圖重做；損傷輕微，依使用者決定**先不動、僅記錄**。其餘 ferret 圖正常。
- 觀察：使用者新放的 fox/guinea_pig chibi 風 states 與既有較細緻畫風略不同，屬使用者素材選擇，本 CR 不介入美術方向。

## 驗收對照

- dog / fox / guinea_pig / ferret / mochi 的 rest 都跑 1→2→3→2→1 ✓（frame count 3 + ping-pong；所有 rest_03 皆合格 PNG）。
- guinea_pig rest 不出現難過狀態 ✓（rest_03 為 content pose）。
- fox rest 不出現睡覺狀態 ✓（rest_03 為站姿）。
- mochi 不出現去背吃掉本體的圖 ✓（除 mochi_normal 無原圖，已記錄）。
- ferret：sad/caring 輕微、無原圖，依決定僅記錄。
- 未改 AI persona / Realtime / 字幕 / 推播 / Care Alert / 後台 / App icon ✓。

## 測試

`flutter test` **699 passed / 0 failed**（含 `mochi_skin_test` / `ferret_skin_test` / `pet_skin_test`：存在、1024² RGBA、透明背景、路徑解析）。素材內容正確性以洋紅底目視驗證（測試只驗格式/透明度）。
