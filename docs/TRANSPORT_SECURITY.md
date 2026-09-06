# TRANSPORT_SECURITY — HTTPS / iOS ATS / Android Cleartext 政策與收斂 patch

> 目的：正式上架前，App 不應全域允許 iOS arbitrary loads，也不應在 Android production 允許 cleartext。本文件定義傳輸安全政策、dev/prod 差異、**可直接套用的收斂 patch**、smoke checklist 與 rollback。
> 建立：CR-0054（Batch 2，PATCH-READY）。
> 狀態：**Android 已於 CR-0096S Batch 2 套用 runtime 收斂；iOS ATS 已於 CR-0096S Batch 3 套用 runtime 收斂；兩平台仍需正式 HTTPS 後端與實體裝置 smoke 才能送審結案**。
> 對照：`docs/E2E_SMOKE_TEST_PLAN.md §5`（A1–A5）、`docs/E2E_SMOKE_TEST_REPORT.md`、`docs/ENVIRONMENT_SETUP.md`、`docs/STORE_RELEASE_CHECKLIST.md`。

> ⚠️ 紅線：本文件只列設定方式與**變數 / 網域名稱**，不含任何 secret / token / keystore / service account / 真實憑證。不得盲套（CR-0054 §5.2 / §11.1）。

---

## 1. 政策（production 必達）

| 平台 | production 要求 | development 允許 |
|---|---|---|
| 後端 | HTTPS 網域 + 有效 TLS 憑證 | 本機 / 區網 HTTP |
| Flutter API base | `https://` 正式網域（localhost/空 → App 守門擋進主流程） | localhost / 10.0.2.2 / LAN HTTP |
| caregiver_web | HTTPS 同源 `/api` 或正式 HTTPS API URL | 本機 HTTP |
| iOS ATS | `NSAllowsArbitraryLoads=false`，無 local-network exception | 使用 staging HTTPS，不連明文 LAN |
| Android cleartext | 禁止（release 無 `usesCleartextTraffic=true`） | debug 經 network security config 允許 loopback/LAN |
| CORS | 僅正式 caregiver_web origin 白名單（**非 allow-all**） | 空清單→本機 allow-all |

> 架構決策（CR-0046 / CR-0054）：**Realtime 媒體走 WebRTC DTLS-SRTP，不受 ATS / cleartext 管制**。ATS / cleartext 只管 SDP 交換與 REST 明文 http。收斂**不影響語音媒體本身**，但 SDP 交換與 API 走的是 App→後端 REST，故後端必須先有 HTTPS。

---

## 2. 現況（CR-0054 盤點）

- ✅ iOS `ios/Runner/Info.plist`：`NSAllowsArbitraryLoads=false`，並已移除 `NSAllowsLocalNetworking` 與本機網路權限文案；release / staging API 一律 HTTPS。
- ✅ Android `android/app/src/main/AndroidManifest.xml`：CR-0096S Batch 2 已移除 `android:usesCleartextTraffic="true"`，改掛 `@xml/network_security_config`；main/release config 禁明文，debug/profile resource overlay 保留本機開發 HTTP。
- ✅ 後端 CORS（CR-0054 Batch 1 已修）：middleware 經 `resolveCorsOrigins` 取白名單，production 因 fail-fast 保證非空 → 不再 allow-all。
- ✅ Flutter `AppConfig.isApiBaseUrlProductionSafe`：production base URL 為 localhost/空 → 友善守門畫面，不進主流程。

---

## 3. 收斂 Patch（Android / iOS 已套用；待實機 smoke）

### 3.1 Android — network security config + debug override

**新增** `android/app/src/main/res/xml/network_security_config.xml`（release 預設禁明文）：

```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <!-- release 預設：禁止所有明文流量，只走 HTTPS。 -->
    <base-config cleartextTrafficPermitted="false" />
</network-security-config>
```

**新增** debug/profile network security config（dev 允許本機 / 模擬器 / LAN）：

```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <!-- 開發 / profile 用：允許本機與 LAN HTTP；release 使用 main config 禁止明文。 -->
    <base-config cleartextTrafficPermitted="true" />
</network-security-config>
```

**改** 主 manifest `android/app/src/main/AndroidManifest.xml`：移除 `android:usesCleartextTraffic="true"`，改指 network security config：

```xml
<application
    android:label="pet_companion_app"
    android:name="${applicationName}"
    android:icon="@mipmap/ic_launcher"
    android:networkSecurityConfig="@xml/network_security_config">
```

> manifest 合併：debug build 以 `src/debug/res/xml/network_security_config.xml` 覆蓋 release 版（同名資源 debug 優先），故 debug 取得 LAN 明文、release 取得禁明文。**毋須** `tools:replace`（資源覆蓋層級即可），但若改採 debug manifest 覆蓋 `networkSecurityConfig` 屬性，則需在 debug manifest 的 `<application>` 加 `tools:replace="android:networkSecurityConfig"`。優先採「同名資源覆蓋」較單純。

### 3.2 iOS — ATS HTTPS-only（已套用）

**改** `ios/Runner/Info.plist` 的 `NSAppTransportSecurity`：

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <false/>
</dict>
```

> iOS 正式 target 不保留 localhost / LAN 明文能力，也不要求本機網路權限。開發與驗收使用 staging HTTPS；避免為本機便利擴大 release 網路權限。

---

## 4. 套用前置（owner 須先備齊；對應 CR-0053 blocker）

- [ ] 正式 / staging 後端部署於 **HTTPS** 網域 + 有效 TLS 憑證。
- [ ] 後端 `CORS_ALLOWED_ORIGINS` 含 caregiver_web 正式 origin。
- [ ] Flutter production build 帶 `--dart-define=API_BASE_URL=https://正式網域`。
- [ ] 真 iOS 裝置 + 真 Android 裝置（或至少 Android 模擬器 + iOS 模擬器作初篩，最終仍需實機）。

---

## 5. Smoke Checklist（套用後必跑，沿用 E2E_SMOKE_TEST_PLAN §5 A1–A5）

| # | 驗證 | 通過判準 |
|---|---|---|
| T1 | iOS release 連正式 HTTPS 後端 | App launch / login / API 正常 |
| T2 | iOS Realtime 語音 | 開麥→SDP 交換→DataChannel→partial/final transcript 正常（WebRTC 不受 ATS 影響，但 SDP 走 HTTPS） |
| T3 | iOS staging HTTPS | API / Realtime 正常，無 ATS 例外依賴 |
| T4 | Android release 連正式 HTTPS | API / Realtime 正常，無 cleartext 被擋 |
| T5 | Android debug 連 LAN/10.0.2.2 HTTP | debug network security config 生效，dev 仍可連 |
| T6 | Care Alert medium/high/urgent | persist + (high/urgent) Telegram，medium 不推 |
| T7 | typed chat | 正常回覆 |
| T8 | caregiver_web 正式 origin | 可呼叫 API（CORS 放行）；非白名單 origin 被擋 |
| T9 | logs | 無 token / 完整對話 / secret |

> 任一 T1–T5 失敗 → 立即 rollback（§6），記錄失敗網域 / 平台 / 現象（去敏）於 `E2E_SMOKE_TEST_REPORT`，不可帶傷上架。

---

## 6. Rollback 步驟

收斂改動全部可逆，且彼此獨立：

- **Android**：主 manifest 還原 `android:usesCleartextTraffic="true"`、移除 `networkSecurityConfig` 屬性；刪 `res/xml/network_security_config.xml`（或保留檔案僅還原 manifest）。debug config 留著無害。
- **iOS**：不得以還原 `NSAllowsArbitraryLoads=true` 作為修復；應修正 staging / production TLS、網域或 API 設定。
- **後端 CORS（CR-0054 Batch 1，已套用）**：非本批 rollback 範圍；如需，將 server.js CORS 來源還原為 `process.env.ALLOWED_ORIGINS`（不建議，會重開 allow-all 缺口）。

建議套用時一個平台一個 commit，方便單獨 rollback。

---

## 7. Release Blocker 狀態

| 項目 | 狀態 |
|---|---|
| 後端 CORS allow-all 缺口 | ✅ 已修（CR-0054 Batch 1） |
| iOS ATS 全域明文 | ✅ Runtime 已收斂（CR-0096S Batch 3）；⛔ 待 HTTPS 後端 + iOS 實機 smoke |
| Android cleartext | ✅ Runtime 已收斂（CR-0096S Batch 2）；⛔ 待 HTTPS 後端 + Android 實機 smoke |
| 正式 HTTPS 後端網域 | ⛔ **未確認就緒**（前置 blocker，owner action） |

> 本文件已完成 iOS / Android runtime 設定收斂，但**不**等於 store submission transport smoke 已結案。仍需備齊正式 HTTPS 後端與實體裝置，跑 §5 smoke 後才能將傳輸安全 gate 標為完全通過。
>
> **CR-0055（2026-06-09）落地嘗試 = BLOCKED**：執行環境無正式 HTTPS 後端、無實體 iOS/Android 裝置，§4 前置未齊 → 依 task §2/§12.2 **未套用 patch、未跑 smoke**，`Info.plist` / `AndroidManifest.xml` 維持原樣。詳見 `docs/E2E_SMOKE_TEST_REPORT.md` Run #1。前置齊備後重跑本文件 §3 套用 + §5 smoke。
