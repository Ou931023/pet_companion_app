# TRANSPORT_SECURITY — HTTPS / iOS ATS / Android Cleartext 政策與收斂 patch

> 目的：正式上架前，App 不應全域允許 iOS arbitrary loads，也不應在 Android production 允許 cleartext。本文件定義傳輸安全政策、dev/prod 差異、**可直接套用的收斂 patch**、smoke checklist 與 rollback。
> 建立：CR-0054（Batch 2，PATCH-READY）。
> 狀態：**設計就緒、尚未套用 runtime**。落地依賴 CR-0053 兩項 blocker（正式 HTTPS 後端就緒 + 實體裝置 smoke），須**另開 CR** 套用並驗證。
> 對照：`docs/E2E_SMOKE_TEST_PLAN.md §5`（A1–A5）、`docs/E2E_SMOKE_TEST_REPORT.md`、`docs/ENVIRONMENT_SETUP.md`、`docs/STORE_RELEASE_CHECKLIST.md`。

> ⚠️ 紅線：本文件只列設定方式與**變數 / 網域名稱**，不含任何 secret / token / keystore / service account / 真實憑證。不得盲套（CR-0054 §5.2 / §11.1）。

---

## 1. 政策（production 必達）

| 平台 | production 要求 | development 允許 |
|---|---|---|
| 後端 | HTTPS 網域 + 有效 TLS 憑證 | 本機 / 區網 HTTP |
| Flutter API base | `https://` 正式網域（localhost/空 → App 守門擋進主流程） | localhost / 10.0.2.2 / LAN HTTP |
| caregiver_web | HTTPS 同源 `/api` 或正式 HTTPS API URL | 本機 HTTP |
| iOS ATS | `NSAllowsArbitraryLoads=false`（無全域明文） | 走 `NSAllowsLocalNetworking` 允許 loopback/LAN |
| Android cleartext | 禁止（release 無 `usesCleartextTraffic=true`） | debug 經 network security config 允許 loopback/LAN |
| CORS | 僅正式 caregiver_web origin 白名單（**非 allow-all**） | 空清單→本機 allow-all |

> 架構決策（CR-0046 / CR-0054）：**Realtime 媒體走 WebRTC DTLS-SRTP，不受 ATS / cleartext 管制**。ATS / cleartext 只管 SDP 交換與 REST 明文 http。收斂**不影響語音媒體本身**，但 SDP 交換與 API 走的是 App→後端 REST，故後端必須先有 HTTPS。

---

## 2. 現況（CR-0054 盤點）

- iOS `ios/Runner/Info.plist`：`NSAppTransportSecurity` = `{ NSAllowsArbitraryLoads: true }`（全域明文，**未收斂**）。單一 plist、單一 Runner.xcscheme，未用 build-var 區分 dev/prod。
- Android `android/app/src/main/AndroidManifest.xml`：`<application ... android:usesCleartextTraffic="true">`（**未收斂**）。無 `res/xml/network_security_config.xml`。已有 `src/debug/AndroidManifest.xml`、`src/profile/AndroidManifest.xml`（目前僅 INTERNET 權限）。`build.gradle.kts` 只有 `buildTypes.release`、無 productFlavors。
- ✅ 後端 CORS（CR-0054 Batch 1 已修）：middleware 經 `resolveCorsOrigins` 取白名單，production 因 fail-fast 保證非空 → 不再 allow-all。
- ✅ Flutter `AppConfig.isApiBaseUrlProductionSafe`：production base URL 為 localhost/空 → 友善守門畫面，不進主流程。

---

## 3. 收斂 Patch（就緒、待套用）

### 3.1 Android — network security config + debug override

**新增** `android/app/src/main/res/xml/network_security_config.xml`（release 預設禁明文）：

```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <!-- release 預設：禁止所有明文流量，只走 HTTPS。 -->
    <base-config cleartextTrafficPermitted="false" />
</network-security-config>
```

**新增** debug-only network security config `android/app/src/debug/res/xml/network_security_config.xml`（dev 允許 loopback / 模擬器 / LAN）：

```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <!-- 開發用：僅對本機 / 模擬器 / 區網開放明文，正式網域仍走 HTTPS。 -->
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="true">localhost</domain>
        <domain includeSubdomains="true">127.0.0.1</domain>
        <domain includeSubdomains="true">10.0.2.2</domain>   <!-- Android emulator → host -->
        <!-- 若用實機 + 區網後端，於此加該 LAN IP（dev 專用，勿進 release） -->
    </domain-config>
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

### 3.2 iOS — ATS 收斂 + 本機網路例外

**改** `ios/Runner/Info.plist` 的 `NSAppTransportSecurity`：

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <false/>
    <!-- 允許 loopback / *.local / 區網（RFC1918、link-local），供 dev 連本機 HTTP 後端；
         正式後端走 HTTPS 不需任何 arbitrary load。 -->
    <key>NSAllowsLocalNetworking</key>
    <true/>
</dict>
```

> 採 `NSAllowsLocalNetworking=true`（架構裁決 D）：已涵蓋 loopback、`*.local`、RFC1918（10/8、172.16/12、192.168/16）與 link-local，dev LAN IP 後端**無需列舉動態 IP**。不採 xcconfig 驅動（避免引入變數替換 + per-config scheme 的結構性擴張）。
> 取捨：`NSAllowsLocalNetworking` 在 release build 仍生效（無法用單一 plist 依 build config 關閉）。但它**只**放行本機 / 區網，**不**放行任意公網明文 → 正式對外流量仍強制 HTTPS，符合 App Store ATS 審查（Apple 對 local networking 例外是接受的）。若日後要求 release 完全無本機例外，再引 xcconfig（另開 CR）。
> 權限文案不動（既有 `NSLocalNetworkUsageDescription` 已是長者友善中文、無 demo/test/mock 字樣）。

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
| T3 | iOS dev 連本機 HTTP 後端 | `NSAllowsLocalNetworking` 生效，dev 仍可連 |
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
- **iOS**：`NSAllowsArbitraryLoads` 還原為 `true`（或移除 `NSAllowsLocalNetworking`）。
- **後端 CORS（CR-0054 Batch 1，已套用）**：非本批 rollback 範圍；如需，將 server.js CORS 來源還原為 `process.env.ALLOWED_ORIGINS`（不建議，會重開 allow-all 缺口）。

建議套用時一個平台一個 commit，方便單獨 rollback。

---

## 7. Release Blocker 狀態

| 項目 | 狀態 |
|---|---|
| 後端 CORS allow-all 缺口 | ✅ 已修（CR-0054 Batch 1） |
| iOS ATS 全域明文 | ⛔ **未收斂**（patch 就緒，待 HTTPS 後端 + 裝置 smoke） |
| Android cleartext | ⛔ **未收斂**（patch 就緒，同上） |
| 正式 HTTPS 後端網域 | ⛔ **未確認就緒**（前置 blocker，owner action） |

> 本文件**不**等於 transport 已硬化。iOS/Android 收斂為 runtime 變更，依架構裁決須另開 CR、備齊前置、跑 §5 smoke 後落地。
