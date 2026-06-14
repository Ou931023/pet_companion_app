# CR-0085 — Change Review Backfill and Final Feature Queue Alignment

## 模式

**docs-only / 整理型 CR。本 CR 不改任何程式、不改後端 / Flutter / caregiver_web runtime、不改 API 契約 / DB schema / Realtime 主流程。**

只做兩件事：

1. **補登紀錄**：把先前已完成併入主線、但未完整登錄於 `docs/CHANGE_REVIEW.md` 的變更補上條目。
2. **重新對齊 CR 編號**：解決兩處編號重複（CR-0053、CR-0075 各被用了兩次），為缺號或重號的變更指定唯一「正式編號」，並宣告下一個可用編號，避免未來再撞號。

> 不改寫 git 歷史，也不更名既有 task 檔（保留 commit ↔ 檔名的可追溯性）；正式對應關係以本 CR 與 `CHANGE_REVIEW.md` 的對照表為準。

---

## 動機 / 問題

盤點 `docs/CHANGE_REVIEW.md`、`tasks/`、git log 後發現：

- **編號重複（collision）**
  - `CR-0053`：既有 `tasks/CR-0053-production-e2e-smoke-test-and-deployment-readiness.md`（已登錄）與後來的「雪貂寵物外觀」工作（commit `65a4b8e`，commit 訊息誤用 `CR-0053`）撞號。
  - `CR-0075`：`CHANGE_REVIEW.md` 已登錄 `CR-0075 — 記憶端點身分驗證強化`，但「dog/fox/guinea_pig 素材正規化」工作（commit `2da9baa`，commit 訊息誤用 `CR-0075`）撞號。
- **已完成但未登錄於 `CHANGE_REVIEW.md`**：`CR-0064`、`CR-0065`、`CR-0080`、`CR-0080A`、`CR-0083`。
- **無 CR 編號的變更**：「Demo 期間所有寵物外觀免費」（commit `35e55f2`）。

---

## 正式編號對齊表

| 變更內容 | 來源 commit | 原始標示 | 正式編號 |
|---|---|---|---|
| 寵物素材尺寸 / 留白正規化（dog/fox/guinea_pig） | `2da9baa` | 「CR-0075」（與記憶 auth 撞號） | **CR-0081** |
| 雪貂 ferret 去背 + 換皮 / 商店整合 | `65a4b8e` | 「CR-0053」（與 prod-e2e 撞號） | **CR-0082** |
| Realtime 語音工具呼叫 + 字幕 turn 整合 | `8e838a9` / `c1c52a6` | CR-0083（正確） | CR-0083 |
| Demo：所有寵物外觀免費直接可換 | `35e55f2` | （無編號） | **CR-0084** |
| 本整理型 CR（補登 + 對齊） | — | — | **CR-0085** |

**保留未用的歷史缺號（不再重用）**：`CR-0077`、`CR-0078`。

**下一個可用的新 CR 編號：`CR-0086`**（往後一律遞增，不回填 0077/0078）。

---

## 需補登的既有 CR（編號本身正確，只是漏登 CHANGE_REVIEW.md）

| 編號 | 內容 | 落地佐證 |
|---|---|---|
| CR-0064 | Render 正式環境 caregiver_web CORS 修正（單一白名單 middleware，fail-closed） | `backend/stt_proxy/server.js:166` 標記；commit `aff3027` 等 |
| CR-0065 | caregiver_web 依 featureFlags 在正式版隱藏 marketplace / 今日任務分頁（後端上線後又重新開啟） | `caregiver_web/app.js applyFeatureFlags`；commit `188db05` → `15832a2` |
| CR-0080 | 語音字幕分頁同步 + web-search 意圖判斷放寬 | commit `c6f01ea` |
| CR-0080A | `_ThrowingChatService.reply` 簽章對齊 `CompanionChatService` | commit `32a121e` |
| CR-0083 | Realtime 語音工具呼叫；工具結果延後到語音結束才呈現，避免蓋字幕 | commit `8e838a9` / `c1c52a6` |

---

## 產出

- 於 `docs/CHANGE_REVIEW.md` 末段新增 `## CR-0085` 條目，內含：正式編號對齊表、上述補登 CR 的精簡紀錄、下一個可用編號宣告。
- 本 task 規格檔。

---

## 限制遵守

- 未讀取 / 修改 / 輸出任何 `.env`、token、runtime data。
- 不改 program code、不改 API 契約 / schema / Realtime 主流程、不更名既有 task 檔、不改寫 git 歷史。
- 不偽稱任何測試結果（docs-only，無 runtime 變更，不需跑 backend / flutter test）。

## 驗收標準

- `CHANGE_REVIEW.md` 內每個 CR 編號唯一對應一項變更，無重複歧義。
- 先前漏登的已完成 CR 皆有條目。
- 明確可查到「下一個新 CR 該用哪個編號」（CR-0086）。
- 全程只動 `docs/` 與 `tasks/`，無 runtime / secret 變更。
