# CR-0100F Stable Pet Renderer

## Production decision

AI 陪伴的寵物必須先讓使用者認得「牠一直是同一隻」，才有陪伴與依附感。
正式 renderer 採以下順序：

1. 每個寵物與風格只有一張 canonical full-body master。
2. 待機、聆聽與說話以 Flutter 連續 motion 呈現，不快速切換不同全身圖。
3. happy、caring、sad 等情緒圖片只在狀態真正改變時短暫 crossfade。
4. 第二階段只新增嘴型、眼睛、耳朵、尾巴等透明局部圖層。
5. 不在 runtime 即時生成圖片，不使用未經人工驗收的 AI frame。

## Root cause fixed

舊版每 320ms 輪播 talking 全身圖、每 480ms 輪播 rest 全身圖。這些圖的頭身比、
腳底基準線、表情與姿勢並不完全一致，因此會產生閃爍、瞬間換臉與身體跳動。
增加更多同類 frame 只會放大問題。

CR-0100F 改為：

- talking：固定主圖，做小幅上浮、呼吸與極小角度律動。
- listening：固定 listening 圖，做緩慢側傾與呼吸。
- rest / normal：固定主圖，做低幅度呼吸。
- happy / excited：固定情緒圖，做一次可讀但不刺眼的輕彈動態。
- 狀態圖片更換：220ms crossfade。

## Canonical art direction

第一隻正式主寵物是奶油色柴犬，固定特徵如下：

- 奶油色毛、白色口鼻與胸口。
- 深棕圓眼、溫和眉型、清楚但不幼稚的表情。
- 淺藍針織圍巾，作為跨 Q 版／半寫實版的身分錨點。
- 四肢完整、腳底基準線一致、尾巴保持右側捲尾輪廓。
- 背景透明，1024 x 1024 sRGBA。

角色方向板：

`docs/asset_candidates/cr0100f_stable_renderer/dog_canonical_style_sheet_v1.png`

方向板僅供角色比例與風格審查，不直接打包進 App。

五隻首發角色 A/B 方向板：

- 半寫實版：`launch_five_semirealistic_lineup_v1.png`
- Q 版：`launch_five_cute_lineup_v1.png`

兩張方向板使用同一組角色身分，正式偏好測試才不會把「畫風偏好」與「不同角色
偏好」混在一起：

| 寵物 | 固定身分特徵 |
| --- | --- |
| 狗狗 | 奶油柴犬、白口鼻與胸口、捲尾、淺藍針織圍巾 |
| 貓咪 | 橘白虎斑、綠眼、青綠項圈與小鈴鐺 |
| 兔兔 | 奶油垂耳、深色圓眼、淡紫頸部蝴蝶結 |
| 小鳥 | 黃綠虎皮鸚鵡、藍色頰斑、不穿擬人服裝 |
| 天竺鼠 | 栗白深棕三花、圓潤清楚輪廓、鼠尾草綠領巾 |

單體母稿候選：

`docs/asset_candidates/cr0100f_stable_renderer/dog_canonical_master_candidate_v1.png`

- 1214 x 1295 RGBA，角色比例、四肢與身分特徵通過方向審查。
- 透明毛髮邊緣仍有少量彩色 fringe，尚未進入 production assets。
- `dog_canonical_master_cleanup_rejected_v2.png` 把棋盤格烤進圖片且沒有 alpha，
  已明確淘汰，不得打包進 App。

## Asset authoring pipeline

1. 鎖定 canonical normal master，人工確認臉、圍巾、身形與腳底。
2. 由同一 master 製作 Q 版與半寫實版，不重新隨機生成角色。
3. 優先產透明局部圖層：`mouth_open`、`blink`、`ear_left/right`、`tail`。
4. 情緒狀態以同一 master 做局部表情與姿勢調整。
5. 通過尺寸、透明度、邊緣、中心點、小尺寸可讀性與裝置截圖測試後才進 assets。

## Release acceptance criteria

- 說話 30 秒內不換臉、不跳腳、不忽大忽小。
- talking/rest 期間 `Image.asset` 路徑保持不變。
- 80、120、180、220 px 下臉與物種特徵可辨識。
- iPhone 實機保持流暢，切換狀態不出現白閃或破圖。
- 每個開放的寵物都需有一致的 normal、listening 與核心情緒圖。
- 未通過上述驗收的真實版寵物不得出現在正式 picker。

## Bundle size budget

2026-09 盤點現有 `assets/pets`：87 張 PNG，共約 45.9 MB。主要空間來自每隻
寵物重複的 full-body talk/rest/state 圖。

新素材預算：

- 每隻寵物的 Q 版 + 半寫實 canonical body：合計不超過 3 MB。
- 嘴型、眼睛、耳朵、尾巴與核心情緒局部圖層：合計不超過 3 MB。
- 每隻雙風格完整素材包目標：4–6 MB。
- 五隻首發寵物總目標：20–30 MB。

方向板與 rejected candidates 只放在 `docs/asset_candidates`，不註冊進
`pubspec.yaml`，因此不會增加正式 App bundle。舊 full-body frames 要等新素材與
實機 QA 完成後才移除，不能為了縮小容量提前破壞 fallback。

## Rollout order

1. 奶油柴犬：完成穩定 renderer 與 canonical master。
2. 柴犬局部嘴型／眨眼圖層。
3. 狗狗 Q 版／半寫實版同角色 A/B。
4. 依序完成貓、兔、鳥、天竺鼠的透明 canonical master。
5. 每隻通過小尺寸與實機 QA 後才開放 picker，不用一次塞入大量全身 frame。

比起同時提供很多不一致的寵物，第一版應先讓一隻主寵物真正有生命感；其他寵物
只有在同樣通過 QA 後才逐隻開放。
