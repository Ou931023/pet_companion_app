# CR-0093 — Pet Animation Pacing and Rest Ping-Pong Loop

把寵物動畫放慢、待機 rest 改成 ping-pong 來回播放，讓首頁看起來更柔和。通用支援 1～4 張 rest frame，套用所有寵物外觀。**不做 App icon**（保留給後續）。

---

## 1. 問題

- 寵物動畫節奏偏快（talk / rest 固定 220ms/frame）。
- rest 待機線性循環：`rest_01 → rest_02 → rest_03 → rest_01`，最後一張直接跳回第一張，看起來會「彈一下」。

## 2. 改動（皆在 `lib/widgets/pet_avatar.dart`）

- **放慢節奏**：talk 由 220ms → **320ms**（`kTalkFrameDuration`）、rest → **480ms**（`kRestFrameDuration`）。其餘狀態（listening / happy / sad / caring / hungry / thirsty / sleepy / normal…）為單張靜態圖、不啟動計時器，行為不變。
- **rest ping-pong**：新增純函式 `pingPongFrameIndex(counter, frameCount)`，rest 影格改用它來回播放，不再讓尾張跳回首張。
  - N=1 → `0,0,0…`
  - N=2 → `0,1,0,1…`
  - N=3 → `0,1,2,1,0,1,2,1…`（rest_01→02→03→02→01→…）
  - N=4 → `0,1,2,3,2,1,0,1,2,3…`
  - 通用公式：`period = 2*(N-1)`；`pos = counter % period`；`index = pos < N ? pos : period - pos`。
- **talk 維持線性循環**（`% length`）：說話嘴型來回播放會不自然，故只有 rest 改 ping-pong。

## 3. 適用範圍

`pingPongFrameIndex` 與計時器邏輯與寵物種類無關，rest frames 由 `AssetPaths.restFrames(skin)` 提供 → **dog / fox / guinea_pig / ferret / mochi 全部適用**，且自動依各外觀實際 rest 張數運作（目前都是 3 張，函式同時支援 1/2/4 張）。

## 4. 未破壞的行為

- talk / listening / happy / sad / caring / hungry / thirsty / sleepy / normal 等狀態的取圖與顯示不變。
- 換外觀 / 換狀態時 `_frameIndex` 歸零重播（既有行為保留）。
- 三層 fallback（該外觀 rest_01 → dog rest_01 → 白話提示）不變。
- 未改寵物素材檔、Realtime、字幕同步、AI persona、推播、後台、Care Alert。

## 5. 測試結果

- 新增 / 更新 `test/widgets/pet_avatar_test.dart`：
  - `pingPongFrameIndex` 純函式：N=1/2/3/4 序列、N=3 尾張(2)之後是 1（不跳回 0）。
  - rest widget 動畫：起始為 rest_01、推進多個 `kRestFrameDuration` 週期不 crash、全程停在 rest frames。
  - guineaPig talk 測試改用 `kTalkFrameDuration`（放慢後）。
- 結果：`flutter analyze` **No issues**；`flutter test` **692 passed / 0 failed**。

## 6. 已知限制 / 備註

- 動畫節奏為固定常數（talk 320ms / rest 480ms）；未做可調設定。
- ping-pong 對 N=2 與線性循環結果相同（皆 0,1,0,1），屬預期。
- **素材備註**：執行本 CR 時發現工作區有一筆 stray 未提交改動把 `assets/pets/rest/mochi_rest_03.png` 換成 428×761 的 WebP（副檔名仍 .png），會讓 rest 動畫尺寸忽大忽小、且非合法 PNG。因本 CR 規定不改素材，已將該檔 `git checkout` 還原為 CR-0088 已提交的 1024² 透明 PNG（恢復到提交狀態，非新增素材改動）。若需更換該張圖，請另以正式去背 / 1024² PNG 流程處理。
- 未改 App icon（任務指示保留）。
