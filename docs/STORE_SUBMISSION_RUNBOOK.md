# Store Submission Smoke Runbook — App Store / Google Play

> 狀態：CR-0101A store smoke 可執行化。
> 用途：每次送 TestFlight、Internal testing、App Store Connect 或 Google Play Console 前，都依本 Runbook 跑一次。
> 紅線：任何標示 `BLOCKER` 的項目未完成，不得送審；不得以 localhost、假 URL、假素材、硬編帳號或 demo fallback 代替正式流程。

相關文件：`docs/FINAL_STORE_BLOCKER_BOARD.md`、`docs/INTERNAL_TESTING_SMOKE_RUNBOOK.md`、`docs/STORE_REVIEW_NOTES_TEMPLATE.md`、`docs/STORE_RELEASE_CHECKLIST.md`、`docs/PRODUCTION_CONFIG_CHECKLIST.md`、`docs/STORE_ASSET_CHECKLIST.md`、`docs/APP_STORE_METADATA.md`、`docs/GOOGLE_PLAY_DATA_SAFETY.md`、`docs/E2E_SMOKE_TEST_PLAN.md`。

---

## 1. Run 前必備輸入

以下資料由 owner / 發行負責人提供，只記錄「名稱與狀態」，不可寫入 secret 值。

- [ ] `BLOCKER` production HTTPS API 網域：供 `API_BASE_URL=https://...` 使用，不能是 localhost / LAN IP / ngrok。
- [x] hosted 隱私權政策 URL：`https://ou931023.github.io/pet_companion_app/privacy.html`，供 `PRIVACY_POLICY_URL` 與商店後台使用。
- [x] hosted 服務條款 URL：`https://ou931023.github.io/pet_companion_app/terms.html`，供 `TERMS_OF_SERVICE_URL` 使用。
- [x] hosted 支援頁 URL：`https://ou931023.github.io/pet_companion_app/support.html`，供 `SUPPORT_URL` 與商店後台使用。
- [x] 正式客服信箱：`aicompanion.support@gmail.com`，供 `CONTACT_EMAIL` 與商店後台使用。
- [x] GitHub Pages 已啟用 Source: GitHub Actions，且 `Deploy legal site to GitHub Pages` workflow 成功部署。
- [ ] `BLOCKER` Android release upload keystore / key alias / CI secret；不得提交進 git。
- [ ] `BLOCKER` iOS distribution certificate / provisioning profile / App Store Connect app record。
- [ ] `BLOCKER` Firebase iOS / Android app config 已對應 `tw.edu.ncyu.im.aicompanion`。
- [ ] `BLOCKER` production PostgreSQL migrations 已執行。
- [ ] `BLOCKER` OpenAI / Firebase Admin / Telegram / DB / admin token 等後端正式 env 已由部署平台設定。
- [x] App icon、Android adaptive icon、screenshots、feature graphic、launch screen 已提供正式候選素材。
- [ ] `BLOCKER` 審查用測試帳號已由 Firebase / 後端正式建立，不硬編在 App 或 repo。
- [x] App Store / Play review notes 模板已備妥：`docs/STORE_REVIEW_NOTES_TEMPLATE.md`。

---

## 2. Repo 自動檢查

在送審 branch / commit 上執行：

```bash
flutter analyze
flutter test
flutter test \
  --dart-define=APP_ENV=production \
  --dart-define=API_BASE_URL=https://api.example.com \
  --dart-define=SHOW_DEMO_LOGIN=true \
  --dart-define=SHOW_SOCIAL_SIGN_IN=true \
  --dart-define=SHOW_MARKETPLACE=true \
  --dart-define=SHOW_DAILY_CARE_TASKS=true \
  test/config/app_config_test.dart test/config/legal_config_test.dart test/config/store_readiness_test.dart

bash scripts/check_release_signing_readiness.sh
```

後端 / caregiver web 若本次送審 commit 有相關變更，也必跑：

```bash
cd backend/stt_proxy
npm run check
npm test
```

驗收：

- [ ] `flutter analyze` 通過，無 production-facing warning。
- [ ] `flutter test` 通過。
- [ ] production dart-define 反向測試通過：即使外部誤開 demo / social / marketplace / daily-care，production gating 仍強制關閉。
- [ ] release signing readiness script 通過，且未讀取 / 輸出任何 secret 值。
- [ ] backend `npm run check` / `npm test` 通過，或明確記錄未跑原因。

---

## 3. Release Build 指令

iOS：

```bash
flutter build ipa --release \
  --dart-define=APP_ENV=production \
  --dart-define=API_BASE_URL=https://api.your-production-domain.example \
  --dart-define=PRIVACY_POLICY_URL=https://ou931023.github.io/pet_companion_app/privacy.html \
  --dart-define=TERMS_OF_SERVICE_URL=https://ou931023.github.io/pet_companion_app/terms.html \
  --dart-define=SUPPORT_URL=https://ou931023.github.io/pet_companion_app/support.html \
  --dart-define=CONTACT_EMAIL=aicompanion.support@gmail.com
```

Android：

```bash
flutter build appbundle --release \
  --dart-define=APP_ENV=production \
  --dart-define=API_BASE_URL=https://api.your-production-domain.example \
  --dart-define=PRIVACY_POLICY_URL=https://ou931023.github.io/pet_companion_app/privacy.html \
  --dart-define=TERMS_OF_SERVICE_URL=https://ou931023.github.io/pet_companion_app/terms.html \
  --dart-define=SUPPORT_URL=https://ou931023.github.io/pet_companion_app/support.html \
  --dart-define=CONTACT_EMAIL=aicompanion.support@gmail.com
```

驗收：

- [ ] build 使用 production HTTPS API，不能使用 `127.0.0.1`、`localhost`、`10.0.2.2`、LAN IP、ngrok。
- [ ] Android release signing 不是 debug key。
- [ ] iOS archive 使用 distribution signing。
- [ ] build artifact 對應正確 version / build number。

---

## 4. 實機 App Smoke

完整逐項表請跑 `docs/INTERNAL_TESTING_SMOKE_RUNBOOK.md`。本節只列送審前最小摘要。

每平台至少各一台實機。iOS 用 TestFlight 或 ad hoc；Android 用 Internal testing 或 release-signed AAB/APK。

- [ ] 首次開啟會顯示隱私 / 同意內容，且提到使用紀錄與照護用途。
- [ ] Email 註冊 / 登入可完成；production 不顯示 Demo 登入、Google / Apple placeholder、debug panel。
- [ ] 首頁第一眼只有核心操作：寵物、寵物狀態、大麥克風、簡潔對話區。
- [ ] 麥克風權限提示合理，拒絕權限時顯示長者看得懂的訊息。
- [ ] Realtime 語音：按麥克風 → 連線 → 聽取 → partial / final transcript → 寵物回覆 → 不卡住。
- [ ] 斷網 / 後端暫時失敗時，App 不閃退，顯示白話錯誤。
- [ ] 打字聊天可送出，寵物回覆不使用工程字眼。
- [ ] 寵物互動、提醒建立、任務完成、照片驗證、小遊戲開始 / 完成後，後端收到 usage event。
- [ ] 設定頁可查看隱私 / 條款、重新檢視同意、看到支援說明。
- [ ] `SUPPORT_URL` / `CONTACT_EMAIL` 注入後，設定頁外部支援入口可開啟。
- [ ] 刪除帳號流程有二次確認，文字明確說明刪除伺服器帳號資料與本機 App 紀錄。

---

## 5. 後端 / 管理者後台 Smoke

必須接正式 Firebase、PostgreSQL、OpenAI、Telegram 設定；不可用 mock DB 當上架依據。

- [ ] `/health` 回正常，不輸出 secret。
- [ ] production 啟動缺必要 env 時 fail-fast，只列變數名稱，不列值。
- [ ] `app_usage_events` migration 已套用，App 操作會寫入 `app_usage_events`。
- [ ] 管理者 / 照護者後台 analytics 顯示真實彙整數據，不是空殼或假資料。
- [ ] caregiver scope 正確：照護者只能看授權長者資料。
- [ ] Care Alert medium 會持久化但不推 Telegram。
- [ ] Care Alert high / urgent 會持久化並推 Telegram。
- [ ] log 不輸出完整對話、email、phone、token、secret、DATABASE_URL 或 stack 給 production log。
- [ ] 管理者後台不顯示 debug / demo / mock / placeholder 字樣。

---

## 6. 商店素材與 Legal Owner Blockers

### Icon / Launch

- [x] iOS `ios/Runner/Assets.xcassets/AppIcon.appiconset/` 已換成正式寵物 icon，含 1024x1024，非 Flutter 預設圖。
- [x] Android legacy `mipmap-*dpi/ic_launcher.png` 已換成正式 icon。
- [x] Android adaptive icon 已補：`mipmap-anydpi-v26/ic_launcher.xml` + foreground / background。
- [x] launch screen 品牌一致，無 Flutter 預設感、無 demo / debug 字樣。

### Screenshots / Store Graphics

- [x] iOS 6.7" screenshots 已輸出；6.5" 可由 6.7" 素材於 App Store Connect 預覽裁切或後續補尺寸。
- [x] Android phone screenshots 5 張已輸出。
- [x] Android feature graphic 1024x500 已輸出。
- [ ] screenshots 不含真實長者個資、真 email、真電話、真對話原文。
- [ ] screenshots 不截 production 隱藏功能：marketplace / daily-care。

### Hosted Legal URL

- [x] 隱私權政策、服務條款、支援頁皆為公開 HTTPS。
- [x] GitHub Pages URL 可開：
  - `https://ou931023.github.io/pet_companion_app/privacy.html`
  - `https://ou931023.github.io/pet_companion_app/terms.html`
  - `https://ou931023.github.io/pet_companion_app/support.html`
- [ ] hosted 隱私權政策內容與 App 內同意內容、Google Play Data Safety、App Store Privacy Nutrition Labels 一致。
- [ ] 商店後台 URL / email 與 dart-define 值一致。

---

## 7. 商店後台 Smoke

- [ ] App Store Connect：metadata 無醫療診斷或過度宣稱。
- [ ] App Store Connect：若未啟用第三方登入，審查流程只出現 Email login / register。
- [x] App Store Connect：Review notes 模板已備妥於 `docs/STORE_REVIEW_NOTES_TEMPLATE.md`。
- [ ] App Store Connect：Review notes 後台填入測試帳號、Care Alert 非醫療診斷說明、麥克風用途。
- [ ] App Store Privacy Nutrition Labels 已申報帳號資料、語音 / 文字互動、App 使用紀錄與照護分析用途。
- [ ] Google Play Console：Data Safety 依 `docs/GOOGLE_PLAY_DATA_SAFETY.md` 填寫。
- [ ] Google Play Console：Health / medical 類聲明不宣稱診斷、治療或緊急救援。
- [ ] Google Play Console：targetSdk / permission declaration 符合當期要求。
- [ ] 外部連結只導向隱私、條款、支援，不導向未完成服務或付款頁。

---

## 8. Smoke Run 記錄模板

每次正式 smoke 後在 release note 或 `docs/E2E_SMOKE_TEST_REPORT.md` 補一筆摘要：

```text
Run ID:
日期:
Git commit:
平台 / build:
API_BASE_URL:
PRIVACY_POLICY_URL:
TERMS_OF_SERVICE_URL:
SUPPORT_URL:
CONTACT_EMAIL:
iOS device / OS:
Android device / OS:
Backend environment:
Firebase project:
PostgreSQL migration status:
OpenAI Realtime smoke:
Care Alert Telegram smoke:
Admin analytics smoke:
結果: PASS / FAIL
剩餘 blocker:
負責人:
```

---

## 9. Go / No-Go Gate

可以送審的最低條件：

- [ ] 本 Runbook §1–§7 全部通過，且無 `BLOCKER`。
- [ ] repo 自動檢查通過。
- [ ] iOS / Android release build 皆通過。
- [ ] 真環境實機 Realtime 語音、Care Alert、usage tracking、管理者 analytics 皆通過。
- [ ] icon / screenshots / legal URL / support URL / email / signing / store privacy 表單皆完成。

只要任一項未通過，結果就是 **No-Go**，不得送 App Store / Google Play 審查。
