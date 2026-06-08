# Flutter Build Flavors 與 Mock 隔離

本文件說明 Flutter 長者端 App 的環境切換（development / staging / production）、
production build 的 dart-define 範例，以及各 mock service 的隔離現況與 release 前確認。

相關來源：`lib/config/app_config.dart`、`lib/app.dart`、
`docs/ENVIRONMENT_SETUP.md`、`docs/STORE_RELEASE_CHECKLIST.md`、
CHANGE_REVIEW CR-0034 / CR-0048（／延後 CR-0049）。

---

## 1. 環境切換機制

本專案**不使用 Flutter 原生 `--flavor`**（無多套 applicationId / scheme），
而是以 **compile-time dart-define** 控制環境與安全旗標，集中在 `AppConfig`：

| dart-define | 預設 | 說明 |
| --- | --- | --- |
| `APP_ENV` | `development` | `development` / `staging` / `production`。production 觸發守門。 |
| `API_BASE_URL` | `http://127.0.0.1:3001` | 正式版必須是 https 正式網域（舊別名 `BACKEND_BASE_URL`）。 |
| `ALLOW_MOCK_SERVICES` | `false` | 是否允許注入 mock service。production 一律被蓋掉為 false。 |
| `SHOW_DEV_PANELS` | `false` | 開發診斷面板。production 強制隱藏。 |
| `SHOW_DEMO_LOGIN` | `false` | Demo 快速登入按鈕。production 強制隱藏。 |
| `CARE_MALL_URL` | `http://127.0.0.1:5500` | Care Mall 網站位址。 |

核心守門邏輯（`AppConfig`）：

```dart
static bool get isProduction => appEnv == 'production';
static bool get mockServicesEnabled => allowMockServices && !isProduction;
static bool get devPanelsVisible    => showDevPanels    && !isProduction;
static bool get demoLoginVisible    => showDemoLoginButton && !isProduction;
```

即使有人在正式 build 誤帶 `--dart-define=ALLOW_MOCK_SERVICES=true`，
`&& !isProduction` 也會把 `mockServicesEnabled` 蓋回 `false`，正式版不啟用 mock 注入。

---

## 2. 各環境啟動範例

### development（本機開發 / 測試）

```bash
flutter run
# 或讓實機連到開發電腦後端：
flutter run --dart-define=API_BASE_URL=http://<後端電腦區網IP>:3001

# 需要 mock / 開發面板時（僅 dev/test，正式版無效）：
flutter run \
  --dart-define=ALLOW_MOCK_SERVICES=true \
  --dart-define=SHOW_DEV_PANELS=true \
  --dart-define=SHOW_DEMO_LOGIN=true
```

### staging（預備 / 內測）

```bash
flutter run \
  --dart-define=APP_ENV=staging \
  --dart-define=API_BASE_URL=https://staging.your-domain.com
```

### production（送審 / 正式）

```bash
# iOS（無簽章驗證 build）
flutter build ios --release --no-codesign \
  --dart-define=APP_ENV=production \
  --dart-define=API_BASE_URL=https://api.your-domain.com \
  --dart-define=SHOW_DEV_PANELS=false \
  --dart-define=SHOW_DEMO_LOGIN=false \
  --dart-define=ALLOW_MOCK_SERVICES=false

# Android
flutter build apk --release \
  --dart-define=APP_ENV=production \
  --dart-define=API_BASE_URL=https://api.your-domain.com \
  --dart-define=SHOW_DEV_PANELS=false \
  --dart-define=SHOW_DEMO_LOGIN=false \
  --dart-define=ALLOW_MOCK_SERVICES=false
```

> production 下即使省略後三個旗標，`AppConfig` 也會強制關閉；明確列出是為了讓 build
> 指令自我說明（self-documenting）並避免誤會。

---

## 3. Mock 隔離現況（誠實標註，勿聲稱已全數隔離）

| Mock | 注入點 | runtime consumer | 隔離狀態 |
| --- | --- | --- | --- |
| `MockShopService` | `app.dart`（`if (mockServicesEnabled)`） | 無正式路徑依賴 | ✅ 已隔離（CR-0034） |
| `MockTaigiAsrStrategy` | `app.dart` `AsrStrategyService.strategies`（`if (mockServicesEnabled)`） | 不被 `context.read`；缺席時 `AsrStrategyService` / `LanguageRoutingService` graceful fallback 回 OpenAI Realtime | ✅ 已隔離（CR-0048） |
| `MockAiService` | `app.dart`（無條件 `Provider`） | `AiToolRouter._chat()` 於按住說話與 Realtime 本地指令路由 **always** 取用 | ⛔ **尚未隔離**，production 仍用到，延後 **CR-0049** |
| `MockSpeechToTextService` | `app.dart`（無條件 `Provider`） | `ConversationController` 於 `sttMode != openAiProxy`（預設 `mock`）取用 | ⛔ **尚未隔離**，production 仍用到，延後 **CR-0049** |

重點：

- **目前 production build 仍然會建立並選用 `MockAiService` 與 `MockSpeechToTextService`。**
  本系統 mock 隔離**尚未完成**，不可對外聲稱「正式版已完全移除 mock」。
- 這兩個是「被 production runtime 選用」的 live 依賴，純從 provider 樹移除會造成
  `ProviderNotFoundException` 崩潰，或讓按住說話 / Realtime 本地指令失去回覆與 STT。
  安全隔離必須先讓 consumer 在 production 改用正式回覆引擎 / 正式 STT proxy
  （`_chat` 接正式來源、`sttMode` production 預設改 `openAiProxy`），再 gating 注入。
  此屬陪伴回覆策略與對話 / Realtime owner 的權責，已切出 **CR-0049** 另批處理。

### CR-0048 已完成的 `MockTaigiAsrStrategy` 隔離

- `app.dart`：`AsrStrategyService` 的 strategies 改為
  `[const OpenAiRealtimeAsrStrategy(), if (AppConfig.mockServicesEnabled) const MockTaigiAsrStrategy()]`。
  production 只剩正式 Realtime ASR strategy。
- `settings_screen.dart`：手動指定 ASR strategy 下拉中的「台語 ASR adapter」
  (`mockTaigiAsr`) 選項，於 `!AppConfig.mockServicesEnabled`（正式版）隱藏，
  避免殘留無實效的 mock 選項。
- 行為保證：正式版若仍收到 `mockTaigiAsr` 字串，`AsrStrategyService.strategyFor()`
  與 `LanguageRoutingService` 會 graceful fallback 回 OpenAI Realtime，
  語音路由不會中斷或丟例外。

---

## 4. Release 前確認 mock 已關（checklist）

正式 build 前逐項確認：

1. build 指令帶 `--dart-define=APP_ENV=production`。
2. `--dart-define=API_BASE_URL=https://正式網域`（非 localhost / 127.0.0.1 / 10.0.2.2 / 空，
   否則 App 進入「服務暫時無法使用」守門畫面）。
3. `ALLOW_MOCK_SERVICES` / `SHOW_DEV_PANELS` / `SHOW_DEMO_LOGIN` 不靠它們開啟任何正式功能；
   即使誤帶 true，production 也會強制關閉。
4. App 內無 demo / test / mock / debug 對長者可見字樣，無 Debug banner。
5. **不可在正式 build 使用 demo login 或 mock service 作為正式資料來源。**
6. 跑回歸：`flutter analyze`、`flutter test`（含
   `test/config/asr_strategy_mock_gating_test.dart`、`test/config/app_config_test.dart`）。
   驗 production 模式：
   `flutter test test/config/asr_strategy_mock_gating_test.dart --dart-define=APP_ENV=production --dart-define=API_BASE_URL=https://api.example.com`
   應確認不含台語 mock strategy 且 Realtime ASR fallback 正常。
7. ⛔ 送審前的最終 blocker：完成 **CR-0049**，隔離 `MockAiService` /
   `MockSpeechToTextService`。在那之前，本 App **尚未達成完整 mock 隔離**。
