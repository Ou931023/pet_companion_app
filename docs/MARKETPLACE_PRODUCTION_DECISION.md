# MARKETPLACE_PRODUCTION_DECISION — 內建商城正式版策略

> 決策：**A2 — 本版 production 隱藏/停用，保留 development/test；PG 化與正式交易列 post-release。**
> 裁決者：architecture gatekeeper（CR-0056）。日期：2026-06-10。

---

## 1. Production 狀態

- **隱藏**：Flutter 長者端 `shop_screen.dart` 的「長照商城」入口卡片在 production build 完全不顯示（`AppConfig.marketplaceVisible = showMarketplace && !isProduction`）。
- **停用（後端 fail-closed）**：`services/marketplace/marketplaceStore.js` 在 production（`isJsonFallbackAllowed()=false`）回空陣列或拋 `FeatureUnavailableInProductionError`，**不讀 JSON、不出 SEED demo 商品**。
- caregiver_web：商品/訂單管理分頁由 `config.js featureFlags.marketplace`（預設關）隱藏。
- 能力不刪：marketplace 程式、路由（`AppRoute.marketplace`）、PG migration 009 皆保留，dev/test 照常可用。

## 2. 是否使用 PG

否。migration `009_create_marketplace.sql` 已建 `marketplace_products` / `marketplace_orders` 兩表，但 store service 仍為 JSON-only，**未接 PG**。本版不啟用。

## 3. 為何不在本版 PG 化啟用

內建商城交易（下單/金流）會引入 **App Store Guideline 3.1 / Google Play Payments / 財務資料合規** scope，對 solo student 當前 store 送審風險過高，且非論文核心（陪伴/語音/記憶/Care Alert）。

## 4. 上架描述限制

store-facing（App Store / Play 描述、副標、keywords、screenshots）**不得**出現「商城/購買/下單/長照用品」等字樣；App Store App Privacy 不勾 Purchases/Financial；Google Play Data Safety 不申報財務/購買資料（見 `docs/GOOGLE_PLAY_DATA_SAFETY.md`）。內部文件才寫「規劃中/post-release」，store-facing 不出現「即將推出」（避免 placeholder 觀感）。

## 5. 仍需 owner 後續決策（post-release）

若未來要正式開放交易：PG 化 store（接 009 兩表）、金流/IAP 合規、auth/scope（resident/caregiver/super_admin）、重走 Data Safety 評估、解除 production gating（需另開 CR + 架構裁決）。

## 6. Production direct API 行為（CR-0057 已收斂）

CR-0057：production 直接打 marketplace API（即使 CR-0056 隱藏入口後）一律回**乾淨 501 `not_enabled`**，不再誤映 500、不回 stack/file path、不讀 JSON、不回 demo seed：

```json
{ "ok": false, "error": "not_enabled", "message": "..." }
```

- 涵蓋：GET products、GET products/:id、POST orders、admin GET orders(×2)、admin POST/PUT/PATCH products、admin PATCH orders/:id/status。
- status=501（「此部署未啟用」語意；不與 authz-403 / 上游-503 碰撞）。停用路徑不寫 logError（非錯誤）。
- helper：`config/env.js isFeatureUnavailableError()` + `server.js respondFeatureDisabled()`；store 內部碼 `feature_unavailable_in_production` 不改，只在 HTTP 邊界映為 `not_enabled`。
- dev/test 行為位元不變（既有 200/400/404 路徑保留）。

## 7. 仍待 post-release（CR-0042）

PG 化正式開放交易（接 migration 009、金流/IAP 合規、authz、Data Safety 重評、解除 501 停用）需另開 CR + 架構裁決。
