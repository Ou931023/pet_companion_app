# Store Review Notes / Console Submission Template — AI陪伴

> 狀態：CR-0101B store review notes 可執行化。
> 用途：送 App Store Connect / Google Play Console 前，複製本文件內容到後台欄位並填入 owner 提供的審查帳號資訊。
> 紅線：本文件不放真密碼、token、完整 email、API key、Telegram chat id、`DATABASE_URL` 或任何 secret。

相關文件：`docs/FINAL_STORE_BLOCKER_BOARD.md`、`docs/APP_STORE_METADATA.md`、`docs/GOOGLE_PLAY_DATA_SAFETY.md`、`docs/INTERNAL_TESTING_SMOKE_RUNBOOK.md`。

參考政策：
- Apple App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- Google Play User Data policy: https://support.google.com/googleplay/android-developer/answer/10144311
- Google Play account deletion requirements: https://support.google.com/googleplay/android-developer/answer/13327111
- Google Play Data safety form: https://support.google.com/googleplay/android-developer/answer/10787469

---

## 1. App Store Connect Review Notes

以下文字可貼到 App Review notes，括號內由 owner 於後台填寫，不寫入 repo。

```text
AI陪伴是一款以長者陪伴為核心的 AI 語音寵物 App。使用者登入後，可以按首頁的大麥克風與 AI 寵物進行即時語音互動，也可以使用打字聊天。App 會提供陪伴式回應、長期記憶、日常提醒與 Care Alert 照護輔助提醒。

麥克風用途：
App 需要麥克風權限以提供 OpenAI Realtime 語音陪伴。使用者按下麥克風後，音訊會用於即時語音辨識與回覆生成。

Care Alert 說明：
Care Alert 是照護輔助提醒，不是醫療診斷，也不取代醫師、長照人員或緊急服務。App 不會宣稱診斷、治療或預測疾病；高風險提醒僅供授權照護者留意。

登入方式：
本版 production 提供 Email、Google 與 Sign in with Apple。三種方式都會經 Firebase Authentication 驗證，再由正式後端建立使用者 session；Email 使用者也可由登入頁寄送密碼重設信。

審查測試帳號：
Resident account: [由 owner 在 App Store Connect 填入，不寫入 repo]
Password: [由 owner 在 App Store Connect 填入，不寫入 repo]

測試路徑：
1. 使用 resident 測試帳號登入。
2. 首次進入時閱讀並同意隱私 / 資料使用說明。
3. 在首頁按下大麥克風，說一句簡短問候，確認寵物語音回覆。
4. 使用打字聊天送出一句話，確認寵物回覆。
5. 進入設定頁，確認 Privacy / Terms / Support 與帳號刪除入口。

後端：
本 build 使用 production HTTPS API_BASE_URL：[由 owner 填入正式網域，不寫入 repo]

支援：
Support URL: https://ou931023.github.io/pet_companion_app/support.html
Privacy Policy: https://ou931023.github.io/pet_companion_app/privacy.html
Terms of Service: https://ou931023.github.io/pet_companion_app/terms.html
Support Email: aicompanion.support@gmail.com
Account deletion web resource: https://ou931023.github.io/pet_companion_app/support.html
```

---

## 2. Google Play Review / App Access Instructions

若 Play Console 要求提供登入資訊或 App access instructions，使用下列模板：

```text
AI陪伴 requires sign-in to test the core app flow.

Test account:
Resident email: [owner fills in Play Console only]
Password: [owner fills in Play Console only]

Testing steps:
1. Sign in with the resident test account.
2. Accept the privacy and data-use consent.
3. Tap the large microphone button on the home screen and speak a short greeting.
4. Confirm the AI pet replies through the realtime voice flow.
5. Send one typed chat message and confirm a warm companion response.
6. Open Settings and confirm Privacy, Terms, Support, and Account deletion entries.

Care Alert is a caregiving support feature, not medical diagnosis, treatment, emergency response, or a substitute for professional care.

Production backend:
This build uses a hosted HTTPS API endpoint. The endpoint is not localhost, LAN IP, or temporary tunnel.
```

---

## 3. Data Safety / App Privacy Owner Checklist

### Google Play Data Safety

勾選方向需與 `docs/GOOGLE_PLAY_DATA_SAFETY.md` 一致：

- [ ] Collects account information.
- [ ] Collects user-provided profile / resident information.
- [ ] Collects voice/audio for app functionality.
- [ ] Collects messages / conversation content for app functionality and personalization.
- [ ] Collects health-related inferences for caregiving support, clearly marked non-diagnostic.
- [ ] Collects app activity / usage analytics via `app_usage_events`.
- [ ] Allows account and data deletion in-app.
- [ ] Provides external account / data deletion resource: `https://ou931023.github.io/pet_companion_app/support.html`.
- [ ] Data is encrypted in transit.
- [ ] Data is not sold and not used for ads or cross-app tracking.

### App Store Privacy

Owner 需依實際 App Store Connect UI 填寫，至少核對：

- [ ] Account information.
- [ ] User content: audio and messages.
- [ ] Health and fitness or sensitive inferences only as caregiving support, not medical diagnosis.
- [ ] App activity / analytics linked to user or resident where applicable.
- [ ] Third-party processing disclosed: OpenAI for AI voice/text, Telegram only for high/urgent care notification to authorized caregiver channel.
- [ ] Account deletion path documented in review notes and in-app Settings.

---

## 4. 審查帳號建立規則

- [ ] 建立一組 resident 測試帳號。
- [ ] 此帳號對應測試 resident / elder profile。
- [ ] 若要展示 caregiver_web，另建 caregiver / super_admin 測試帳號，但不要提供 super_admin token 給一般 app review，除非後台審查需要。
- [ ] 測試帳號不可使用真長者個資。
- [ ] 測試帳號密碼只填在 App Store Connect / Play Console 的受保護欄位，不寫入 repo。
- [ ] 測試資料可清理，清理方式依 `docs/E2E_SMOKE_TEST_PLAN.md`。

---

## 5. No-Go

下列任一項未完成，不要送審：

- Review notes 沒有測試帳號或登入路徑。
- Privacy / Terms / Support URL 無法公開開啟。
- Data Safety / App Privacy 未申報 `app_usage_events`、語音、對話、Care Alert 相關資料。
- Care Alert 文案被寫成診斷、治療、緊急救援或醫療判斷。
- 審查帳號或後端 URL 寫進 repo。
