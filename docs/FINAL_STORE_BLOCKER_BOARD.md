# Final Store Blocker Board — AI陪伴

> 狀態：CR-0101B 最後上架作戰表。
> 用途：把 App Store / Google Play 送審前剩餘事項集中到單一頁面。此表是「是否可以送審」的最後 Go / No-Go 入口。
> 紅線：不得把 `.env`、API key、token、keystore、Apple 憑證、Firebase service account、完整 email、完整對話、Telegram chat id、`DATABASE_URL` 寫進 repo 或截圖。

相關文件：`docs/STORE_SUBMISSION_RUNBOOK.md`、`docs/INTERNAL_TESTING_SMOKE_RUNBOOK.md`、`docs/STORE_REVIEW_NOTES_TEMPLATE.md`、`docs/RELEASE_SIGNING.md`、`docs/APP_STORE_METADATA.md`、`docs/GOOGLE_PLAY_DATA_SAFETY.md`、`docs/E2E_SMOKE_TEST_PLAN.md`、`docs/E2E_SMOKE_TEST_REPORT.md`。

---

## 1. 已由 repo 端完成

- [x] App 正式名稱：`AI陪伴` / `AI Companion`。
- [x] Bundle ID / applicationId：`tw.edu.ncyu.im.aicompanion`。
- [x] iOS / Android icon、Android adaptive icon、Play Store listing icon。
- [x] Google Play feature graphic：`store_assets/play_feature_graphic_1024x500.png`。
- [x] iOS / Android store screenshots：`store_assets/screenshots/`。
- [x] iOS / Android launch screen 品牌化。
- [x] GitHub Pages legal/support URL：
  - `https://ou931023.github.io/pet_companion_app/privacy.html`
  - `https://ou931023.github.io/pet_companion_app/terms.html`
  - `https://ou931023.github.io/pet_companion_app/support.html`
- [x] Support email：`aicompanion.support@gmail.com`。
- [x] Production gating：demo / mock / debug panel / unfinished social sign-in / marketplace / daily-care production 入口關閉。
- [x] Store readiness test：`flutter test test/config/store_readiness_test.dart`。
- [x] Release signing readiness script：`bash scripts/check_release_signing_readiness.sh`。
- [x] Internal testing smoke runbook：`docs/INTERNAL_TESTING_SMOKE_RUNBOOK.md`。
- [x] Store review notes / app access template：`docs/STORE_REVIEW_NOTES_TEMPLATE.md`。

---

## 2. Owner 必須提供

| Blocker | 需要提供 / 完成 | 不可做 |
|---|---|---|
| Production API | 正式 HTTPS `API_BASE_URL`，不能是 local / LAN / temporary tunnel | 不可用 localhost、127.0.0.1、10.0.2.2、ngrok 送審 |
| Backend env | 部署平台設定 `DATABASE_URL`、`OPENAI_API_KEY`、Firebase Admin、`ADMIN_API_TOKEN`、`CORS_ALLOWED_ORIGINS`、Telegram 測試通知設定 | 不可貼值到 repo / 文件 / chat |
| PostgreSQL | production migration 已執行，含 `app_usage_events` | 不可用本機 DB 當正式依據 |
| Firebase 測試帳號 | resident / caregiver / super_admin 三種測試帳號，供審查與 smoke；只填在商店後台受保護欄位 | 不可 hardcode 帳密到 App 或 repo |
| Android signing | upload keystore、`android/key.properties` 本機/CI secret、Play App Signing | 不可 commit `.jks`、`.keystore`、`key.properties` |
| iOS signing | Apple Developer、App Store Connect app record、distribution signing / provisioning | 不可 commit `.p8`、`.cer`、`.p12`、`.mobileprovision` |
| iPhone pairing | Xcode Devices 完成 pairing，iPhone 信任這台 Mac | 不可把未配對狀態標 PASS |
| Android device | Play Internal testing 可安裝的實機 | 不可只用 desktop/web 當手機驗收 |

---

## 3. 必須真機驗證

依 `docs/INTERNAL_TESTING_SMOKE_RUNBOOK.md` 執行並把結果記到 `docs/E2E_SMOKE_TEST_REPORT.md`。

- [ ] iOS TestFlight build 可安裝、可啟動、無 debug / demo / mock / Flutter 預設 launch。
- [ ] Android Internal testing build 可安裝、可啟動、無 debug / demo / mock / Flutter 預設 launch。
- [ ] Email login / register 可完成；第三方登入未完成時不出現。
- [ ] 首頁符合長者易用性：寵物、狀態、大麥克風、簡潔對話區。
- [ ] Realtime 語音：開麥、聽取、partial/final transcript、寵物回覆、不卡住。
- [ ] 後端失敗或斷網時 App 不閃退，顯示白話錯誤，不 fallback mock。
- [ ] Care Alert medium 會持久化但不推 Telegram。
- [ ] Care Alert high / urgent 會持久化並推 Telegram 測試 chat。
- [ ] `app_usage_events` 真的收到 App 開啟、語音開始/結束、打字、寵物互動、提醒、拼圖等事件。
- [ ] caregiver_web analytics 顯示真實彙整，不是空殼或假資料。
- [ ] 設定頁 Privacy / Terms / Support URL 可開；帳號刪除流程可走且文案清楚。

---

## 4. 商店後台必填

### App Store Connect

- [ ] App 名稱：`AI陪伴`。
- [ ] Subtitle / description 不宣稱診斷、治療、緊急救援或取代醫師。
- [ ] Privacy Policy URL：`https://ou931023.github.io/pet_companion_app/privacy.html`。
- [ ] Support URL：`https://ou931023.github.io/pet_companion_app/support.html`。
- [x] Review notes 模板已備妥：`docs/STORE_REVIEW_NOTES_TEMPLATE.md`。
- [ ] Review notes 後台填寫：提供審查用測試帳號、麥克風用途、Care Alert 非醫療診斷說明、登入路徑。
- [ ] App Privacy：申報帳號資料、語音/文字互動、健康相關推論、App 活動、使用分析。
- [ ] 若第三方登入未完成，審查流程只出現 Email login/register。

### Google Play Console

- [ ] App 名稱：`AI陪伴`。
- [ ] Data Safety 依 `docs/GOOGLE_PLAY_DATA_SAFETY.md` 與 `docs/STORE_REVIEW_NOTES_TEMPLATE.md` 填寫。
- [ ] Health / medical 聲明不宣稱診斷、治療、緊急救援。
- [ ] Privacy Policy URL：`https://ou931023.github.io/pet_companion_app/privacy.html`。
- [ ] Feature graphic / screenshots / icon 預覽無裁切、無 debug/demo/mock。
- [ ] targetSdk / permission declaration 符合當期要求。
- [ ] Play App Signing 已啟用，AAB 使用 upload key 簽章。

---

## 5. 最後執行順序

1. Owner 提供 production HTTPS API 與後端 env，部署 backend / caregiver_web。
2. 跑 production migrations。
3. 建立 Firebase resident / caregiver / super_admin 測試帳號與授權關聯。
4. 完成 Android upload keystore / Play App Signing。
5. 完成 Apple Developer / App Store Connect / iOS distribution signing。
6. 跑 repo gate：
   ```bash
   flutter analyze
   flutter test
   flutter test test/config/android_release_signing_test.dart test/config/store_readiness_test.dart
   bash scripts/check_release_signing_readiness.sh
   ```
7. Build 並上傳 TestFlight / Play Internal testing。
8. 跑 `docs/INTERNAL_TESTING_SMOKE_RUNBOOK.md`，結果寫入 `docs/E2E_SMOKE_TEST_REPORT.md`。
9. 填 App Store Privacy / Google Play Data Safety / metadata。
10. 所有 blocker 清零後送審。

---

## 6. No-Go

任一項成立就不能送審：

- Production API 不是 HTTPS 正式網域。
- Android / iOS release signing 未完成。
- 真機 Realtime 語音未驗證。
- Care Alert / usage tracking / caregiver_web analytics 未在真環境驗證。
- Store privacy / Data Safety 未填或與實際資料收集不一致。
- repo 內出現 `.env`、keystore、Apple signing files、Firebase service account 或 secret。
- 截圖、metadata 或 App 內出現 debug / demo / mock / placeholder。
