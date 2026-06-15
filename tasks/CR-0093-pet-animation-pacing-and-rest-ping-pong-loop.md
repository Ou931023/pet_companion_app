# CR-0093 — Pet Animation Pacing and Rest Ping-Pong Loop

> 任務重點（依使用者指示記錄；原規劃 CR-0093 為 App Icon Replacement，本輪改先做動畫節奏，App icon 先不做、延後）。

## 任務重點

1. 先不做 App icon。
2. 把寵物動畫速度調慢一點，讓待機與互動看起來更柔和。
3. rest 動畫要改成 ping-pong 循環：
   `rest_01 → rest_02 → rest_03 → rest_02 → rest_01 → rest_02 → rest_03 …`
4. 不要再讓 rest_03 直接跳回 rest_01。
5. 請做成通用邏輯，支援 1 / 2 / 3 / 4 張 rest frame，不要只寫死 3 張。
6. dog / fox / guinea_pig / ferret / mochi 都要適用。
7. talk / listening / happy / sad / caring / hungry / thirsty / sleepy 等狀態不要被破壞。
8. 不要改寵物素材檔案，不要改 Realtime、字幕同步、AI persona、推播、後台、Care Alert。
9. 完成後請新增 `docs/PET_ANIMATION_PACING_CR0093.md`，更新 `docs/CHANGE_REVIEW.md`，並宣告下一個可用 CR 為 CR-0094。
10. 測試請跑 `flutter analyze` 和 `flutter test`。

## 實作摘要

見 `docs/PET_ANIMATION_PACING_CR0093.md`：放慢 talk(320ms)/rest(480ms) 節奏；新增純函式 `pingPongFrameIndex`（通用 1~4 張）；只動 `lib/widgets/pet_avatar.dart` 與其測試。
