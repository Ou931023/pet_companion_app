# TestFlight / Play Internal Testing Smoke Runbook

> 狀態：CR-0101B internal testing smoke 可執行化。
> 用途：每次上傳 TestFlight 或 Google Play Internal testing 後，用真裝置、真帳號、真後端跑一次。
> 紅線：不貼 `.env`、token、keystore、Apple 憑證、Firebase service account、完整 email、完整對話、Telegram chat id 或 `DATABASE_URL`。所有截圖都要去識別化。

相關文件：`docs/STORE_SUBMISSION_RUNBOOK.md`、`docs/E2E_SMOKE_TEST_PLAN.md`、`docs/E2E_SMOKE_TEST_REPORT.md`、`docs/RELEASE_SIGNING.md`、`docs/GOOGLE_PLAY_DATA_SAFETY.md`、`docs/APP_STORE_METADATA.md`。

---

## 1. Owner 需提供

只提供狀態與後台操作，不要把 secret 值寫進 repo。

- [ ] Production HTTPS API base URL：`API_BASE_URL=https://...`
- [x] Privacy URL：`https://ou931023.github.io/pet_companion_app/privacy.html`
- [x] Terms URL：`https://ou931023.github.io/pet_companion_app/terms.html`
- [x] Support URL：`https://ou931023.github.io/pet_companion_app/support.html`
- [x] Support email：`aicompanion.support@gmail.com`
- [ ] Firebase resident 測試帳號。
- [ ] Firebase caregiver 測試帳號。
- [ ] Firebase super_admin 測試帳號。
- [ ] 後端 production / staging env 已設好 OpenAI、Firebase Admin、PostgreSQL、Telegram、CORS。
- [ ] Android upload keystore 與 Play App Signing。
- [ ] Apple Developer / App Store Connect app record / iOS distribution signing。
- [ ] iPhone 已完成 Xcode Devices pairing。
- [ ] Android 實機可安裝 Internal testing build。

---

## 2. 上傳前 Repo Gate

在上傳 build 前先跑：

```bash
flutter analyze
flutter test
flutter test test/config/android_release_signing_test.dart test/config/store_readiness_test.dart
bash scripts/check_release_signing_readiness.sh
```

後端 / caregiver_web 若本 commit 有改動：

```bash
cd backend/stt_proxy
npm run check
npm test
```

通過標準：
- [ ] Flutter / backend / caregiver_web 測試通過。
- [ ] Android release build 缺 keystore 時會 fail-fast；有 keystore 時可產 AAB。
- [ ] store readiness test 通過。
- [ ] 沒有 `.env`、keystore、Firebase config、Apple signing files 被 git 追蹤。

---

## 3. Build / 上傳

### iOS TestFlight

```bash
flutter build ipa --release \
  --dart-define=APP_ENV=production \
  --dart-define=API_BASE_URL=https://your-production-api.example \
  --dart-define=PRIVACY_POLICY_URL=https://ou931023.github.io/pet_companion_app/privacy.html \
  --dart-define=TERMS_OF_SERVICE_URL=https://ou931023.github.io/pet_companion_app/terms.html \
  --dart-define=SUPPORT_URL=https://ou931023.github.io/pet_companion_app/support.html \
  --dart-define=CONTACT_EMAIL=aicompanion.support@gmail.com
```

若 CLI 簽章失敗，改用 Xcode Archive → Distribute App → App Store Connect → Upload。

### Google Play Internal testing

```bash
flutter build appbundle --release \
  --dart-define=APP_ENV=production \
  --dart-define=API_BASE_URL=https://your-production-api.example \
  --dart-define=PRIVACY_POLICY_URL=https://ou931023.github.io/pet_companion_app/privacy.html \
  --dart-define=TERMS_OF_SERVICE_URL=https://ou931023.github.io/pet_companion_app/terms.html \
  --dart-define=SUPPORT_URL=https://ou931023.github.io/pet_companion_app/support.html \
  --dart-define=CONTACT_EMAIL=aicompanion.support@gmail.com
```

---

## 4. 真機 App Smoke

每平台至少各跑一次。若某平台缺裝置或簽章，狀態寫 `BLOCKED`，不要寫 PASS。

| # | 項目 | iOS | Android | 通過標準 |
|---|---|---|---|---|
| A1 | 安裝 / 首開 |  |  | 可從 TestFlight / Internal testing 安裝並啟動 |
| A2 | 無開發痕跡 |  |  | 無 debug / demo / mock / test mode / Flutter 預設 launch |
| A3 | Privacy consent |  |  | 首次使用說明資料用途、使用紀錄、照護用途 |
| A4 | Email 註冊 / 登入 |  |  | resident 帳號可登入；第三方登入未完成時不顯示 |
| A5 | 首頁易用性 |  |  | 首頁聚焦寵物、狀態、大麥克風、簡潔對話區 |
| A6 | 麥克風權限 |  |  | 權限文案合理；拒絕後不閃退且白話提示 |
| A7 | Realtime 語音 |  |  | 開麥、聽取、partial/final transcript、寵物回覆皆正常 |
| A8 | 打字聊天 |  |  | 可送出、回覆溫暖、無工程字眼 |
| A9 | 後端失敗 |  |  | 斷網或 API 失敗不閃退，不 fallback mock |
| A10 | 法律 / 支援入口 |  |  | Privacy / Terms / Support URL 可開；客服 email 可見 |
| A11 | 帳號刪除 |  |  | 有二次確認，文案說明刪除伺服器與本機資料 |

---

## 5. Data / Admin Smoke

這段確認「管理者網頁不是形式」，必須看到真 App 操作產生的資料。

| # | App 操作 | 後端 / 管理端驗收 |
|---|---|---|
| D1 | App 開啟並停留 1 分鐘 | `app_usage_events` 有 `app_open` / session 相關事件 |
| D2 | Realtime 語音開始 / 結束 | 有 `voice_interaction_start` / `voice_interaction_end` |
| D3 | 打字聊天送出 | 有 `typed_chat_sent` |
| D4 | 寵物互動 | 有 `pet_interaction` |
| D5 | 建立提醒 | 有 `reminder_created` |
| D6 | 任務完成 | 有 `daily_task_completed`，若本版 production 隱藏則標 `not_applicable` |
| D7 | 照片驗證 | 有 `photo_verification_submitted`，若本版 production 隱藏則標 `not_applicable` |
| D8 | 拼圖開始 / 完成 | 有 `puzzle_started` / `puzzle_completed` |
| D9 | 字體大小調整 | 有設定保存；若 tracking 尚未接入則列後續 CR |
| D10 | 寵物切換 | 有偏好保存；若 A/B 尚未接入則列 CR-0100 |
| D11 | 管理者 analytics | caregiver_web 顯示真實彙整，不是空殼 / 假資料 |

---

## 6. Care Alert Smoke

使用測試帳號與測試 Telegram chat。不要使用真照護群組。

| # | 測試 | 通過標準 |
|---|---|---|
| C1 | medium 語音句 | care alert 持久化，Telegram 不推 |
| C2 | high / urgent 語音句 | care alert 持久化，Telegram 測試 chat 收到 |
| C3 | medium 打字句 | care alert 持久化，Telegram 不推 |
| C4 | high / urgent 打字句 | care alert 持久化，Telegram 測試 chat 收到 |
| C5 | 長者端呈現 | 長者端仍是陪伴語氣，不顯示監控感或 raw riskLevel |
| C6 | 管理端呈現 | caregiver_web 顯示風險重點、時間、狀態；無完整對話外洩 |

建議測試句需去敏、簡短，執行報告只記「medium sleep/lonely scenario」這類摘要，不貼完整原句。

---

## 7. Store Console Smoke

| # | 平台 | 項目 |
|---|---|---|
| S1 | App Store Connect | App 名稱 `AI陪伴`；描述無醫療診斷宣稱 |
| S2 | App Store Connect | Review notes 含測試帳號、麥克風用途、Care Alert 非醫療診斷說明 |
| S3 | App Store Connect | App Privacy 申報帳號資料、語音/文字互動、App 使用紀錄與照護分析用途 |
| S4 | Google Play | Data Safety 依 `docs/GOOGLE_PLAY_DATA_SAFETY.md` 填寫 |
| S5 | Google Play | Health / medical 類聲明不宣稱診斷、治療、緊急救援 |
| S6 | 兩平台 | screenshots / icon / feature graphic 預覽無裁切、無 debug/demo/mock |
| S7 | 兩平台 | Legal URLs 與 app build dart-define 一致 |

---

## 8. Run Report Template

複製到 `docs/E2E_SMOKE_TEST_REPORT.md`，一輪一段。

```text
## Run #X — TestFlight / Play Internal Testing Smoke

日期:
commit:
後端 URL: https://...
caregiver_web URL:
iOS build: TestFlight build number / version
Android build: Play Internal testing versionCode / versionName
iOS device / OS:
Android device / OS:
測試帳號: resident / caregiver / super_admin 已建立（不貼 email 完整值）
結果: PASS / FAIL / BLOCKED

Repo gate:
- flutter analyze:
- flutter test:
- store readiness:
- release signing readiness:
- backend check/test:

App smoke A1-A11:
- iOS:
- Android:

Data/Admin D1-D11:
-

Care Alert C1-C6:
-

Store console S1-S7:
-

剩餘 blocker:
-

下一步:
-
```

---

## 9. Go / No-Go

可以送審的最低條件：
- [ ] iOS TestFlight 真機 smoke PASS。
- [ ] Android Internal testing 真機 smoke PASS。
- [ ] Realtime、Care Alert、usage tracking、管理者 analytics 皆有真環境佐證。
- [ ] Release signing 完成，且 secret 未進 repo。
- [ ] Store privacy / Data Safety / metadata / legal URL 完成且一致。

任一項未通過就是 **No-Go**。
