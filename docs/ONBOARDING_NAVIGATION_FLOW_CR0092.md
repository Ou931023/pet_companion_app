# CR-0092 — Onboarding Navigation Flow Polish

讓新手導覽「實際帶長者走一遍 App」：講到商城就切到商城頁、講到紀錄就切到紀錄頁、講到設定/換造型就切到設定頁，最後回首頁。改動最小、沿用既有跨頁機制，不重構導航。

---

## 1. 問題盤點

導覽大多停在首頁：步驟 10/11/12（商城/紀錄/設定）只是高亮**底部分頁按鈕**（用 `navBarSlot` 切出那一格），使用者沒真的看到該頁面，展示時很抽象。

盤點後關鍵發現：**跨頁基礎建設早已存在**——
- `CoachMarkStep` 已有 `shellTabIndex` 欄位（要切到哪個底部分頁）。
- `CoachMarkHost._onControllerChanged` 已會在 step 變更時呼叫 `AppNavigationController.selectShellIndex(tab)`。
- overlay（`CoachMarkOverlay`）mount 在 `MainShell` 之上（body + 底部列），可覆蓋任一分頁。
- overlay 取 target 會 poll `GlobalKey.currentContext` 最多 18 個 frame，取不到就**安全降級為置中說明卡**，不 crash。
- 既有第 13 步（家人聯絡人）就是 home→settings 的跨頁示範。

缺的只是：把 10/11/12 從「亮按鈕」改成「真的切過去並高亮頁內目標」，並補回首頁收尾步驟。

---

## 2. 舊導覽流程（13 步，全在首頁）

1 寵物 → 2 說話 → 3 先聽牠說完 → 4 狀態 → 5 親密度 → 6 飽足 → 7 點寵物玩遊戲 → 8 簽到 → 9 金幣 → **10 商城(亮按鈕) → 11 紀錄(亮按鈕) → 12 設定(亮按鈕) → 13 家人聯絡人(切設定頁)**。

## 3. 新跨頁導覽流程（16 步）

首頁段 1–9 不變。之後改為真正切頁：

| # | 頁面 | shellTabIndex | 高亮目標 key | 內容 |
|---|---|---|---|---|
| 1–9 | 首頁 | null（不切） | pet / voice / status… | 寵物、說話、先聽、狀態×3、玩遊戲、簽到、金幣 |
| 10 | 商城 | 1 | `shopKey`（商城頁標題） | 商城可用金幣解鎖外觀 / 買東西 |
| 11 | 紀錄 | 2 | `historyTitleKey`（紀錄頁標題） | 回顧和寵物聊過的話 |
| 12 | 紀錄 | 2 | `historySearchKey`（CR-0091 搜尋框） | 可搜尋過去聊過的內容 |
| 13 | 設定 | 3 | `settingsAppearanceKey`（換一隻夥伴） | 幫寵物換造型（dog/fox/guinea_pig/ferret/mochi） |
| 14 | 設定 | 3 | `settingsContactKey`（家人聯絡人） | 新增家人 / 照護人員 |
| 15 | 設定 | 3 | `settingsReplayKey`（重看導覽鈕） | 之後可從這裡重看導覽 |
| 16 | 首頁 | 0 | `petKey` | 回到寵物身邊，開始使用 |

切頁由 `CoachMarkHost` 在 step 變更時依 `shellTabIndex` 呼叫 `selectShellIndex`；`_lastTabSwitchIndex` 確保同分頁連續步驟不重複切。完成 / 略過後 Host 會切回首頁(0) 並寫入「已看過」旗標。

商城 / 紀錄 / 設定皆為**底部分頁**（index 1/2/3）→ 切頁即 `selectShellIndex`，overlay 因 mount 在 shell 之上而存活。**未動導航架構**。

---

## 4. step → page 對應表

見 §3 表格。新增 5 個 `CoachMarkKeys`：`shopKey`（ShopScreen）、`historyTitleKey` / `historySearchKey`（HistoryScreen）、`settingsAppearanceKey` / `settingsReplayKey`（SettingsScreen）；各畫面用 `KeyedSubtree` 掛上。

---

## 5. target ready / fallback 策略

- **切頁後等 render**：`selectShellIndex` 後，overlay 每個 frame 重試取 `targetKey.currentContext`，上限 18 frames（既有機制），**不使用硬編延遲**。
- **取不到 target**：超過重試或該元件未顯示 → overlay 安全降級成**全螢幕遮罩 + 置中說明卡**，導覽照常可按「下一步」，不 crash、不黑屏、不卡 spinner。
- **已知降級點**：第 12 步搜尋框在「尚無任何對話紀錄」時不會顯示（CR-0091）→ 該步顯示置中說明卡（仍說明可搜尋）。
- 不對長者顯示任何 `GlobalKey currentContext null` / `target not found` 等工程訊息。

---

## 6. 測試結果

- `test/onboarding/coach_mark_steps_test.dart`：步數 16；商城(idx9,tab1)/紀錄(idx10,tab2)/搜尋(idx11,tab2)/換造型(idx12,tab3)/聯絡人(idx13,tab3)/重看(idx14,tab3) 對應正確；最後一步回首頁(tab0,petKey)；涵蓋 home/shop/history/settings 四分頁切換；只有「先聽」一步無 target（置中降級）；無工程字樣。
- `test/onboarding/coach_mark_host_test.dart`：自動開始 16 步；逐步驅動驗證 host 依序切到 商城(1)→紀錄(2)→設定(3)→回首頁(0)，完成後回首頁並記錄已看過。
- `test/onboarding/coach_mark_overlay_test.dart`：無 target 步驟 → 置中卡、不 crash（既有，仍綠）。
- 既有 HistoryScreen / ShopScreen widget 測試補上 `CoachMarkKeys` provider（畫面新掛了導覽 key）。
- 結果：`flutter analyze` **No issues**；`flutter test` **685 passed / 0 failed**。

---

## 7. 已知限制

- **只走「底部分頁」**：商城/紀錄/設定都是底部 tab，切頁安全。若未來導覽要指向 **pushed route**（marketplace 內頁、提醒、記憶、Care Alert、拼圖等 `Navigator.pushNamed` 頁），overlay 會被新頁蓋住、無法高亮 → 需另行調整 overlay 掛載層級，屆時應另開 CR、先回報。本 CR 不涉及。
- 第 12 步搜尋框在尚無紀錄時降級為置中卡（見 §5）。
- 沿用既有 18-frame 重試上限；極慢裝置若該頁 render 超過 18 frame，會降級置中卡（不 crash）。
- 首次導覽與「重看導覽」共用同一套 `CoachMarkController` 與步驟，未複製兩套流程。
- 未改 AI persona（CR-0090）、紀錄搜尋（CR-0091）、Realtime / 字幕（CR-0089）、寵物素材（CR-0088）、推播（CR-0087）、後台（CR-0086）、App icon。
