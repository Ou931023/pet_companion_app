# DAILY_CARE_TASK_PRODUCTION_DECISION — 每日照護任務正式版策略

> 決策：**B2 — 本版 production 隱藏/停用，保留 development/test；PG 化與正式照護任務審核列 post-release。**
> 裁決者：architecture gatekeeper（CR-0056）。日期：2026-06-10。

---

## 1. Production 狀態

- **隱藏**：Flutter 長者端 `settings_screen.dart` 的「今日任務」入口在 production build 完全不顯示（`AppConfig.dailyCareTasksVisible = showDailyCareTasks && !isProduction`）。
- **停用（後端 fail-closed）**：`services/dailyCareTask/dailyCareTaskStore.js` 在 production 拋 `FeatureUnavailableInProductionError` 或回 `{success:false}`，**不讀 JSON**。
- caregiver_web：日常任務分頁由 `config.js featureFlags.dailyCareTasks`（預設關）隱藏。
- 能力不刪：dailyCareTask 程式、路由（`AppRoute.dailyCareTasks`）、狀態機保留，dev/test 照常可用。

## 2. 是否使用 PG

否。**無任何 daily_care_task migration / table**；store service 為 JSON-only。本版不啟用。

## 3. 為何不在本版 PG 化啟用

無現成 migration，且 submit 走 AI Vision 照片驗證、有 pending/submitted/completed/needs_review/rejected/missed 狀態機，PG 化為實質工作量；本 release 主軸為陪伴 + Care Alert。列 post-release。

## 4. 上架描述限制

store-facing 不得出現「拍照完成照護任務/任務審核」等字樣。未來若開啟，AI Vision 照片驗證文案不得暗示醫療判斷/確診，須沿用 CLAUDE.md §7.3 安全用語（照護提醒、非醫療診斷）。

## 5. 仍需 owner 後續決策（post-release）

PG 化需新建 migration（`daily_care_tasks` / `daily_care_task_submissions` / 視需要 reviews）、AI Vision proof 儲存與權限（resident 看自己、caregiver 看授權住民、super_admin 全域）、解除 production gating（另開 CR + 架構裁決）。提醒功能（reminders）與本決策無關、不受影響、照常運作。

## 6. 與 Care Alert 的關係

DailyCareTask 與 Care Alert 為**獨立功能**；本 CR 隱藏 DailyCareTask 入口**不影響** Care Alert（語音/打字風險分析→persist→Telegram）、Realtime、Memory、Auth scope。
