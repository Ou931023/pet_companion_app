# CR-0058 — Store Metadata, Legal URLs, App Identity, Icon, Screenshots, and Signing Readiness

## 1. 任務定位

本任務接續 CR-0057。

目前已完成：

- CR-0039～CR-0045：授權鏈閉合
- CR-0046：Store readiness 第一輪文件
- CR-0047：Production logging redaction
- CR-0048～CR-0049：production mock 隔離與正式 AI/STT
- CR-0050～CR-0052：companion chat / typed chat / voice Care Alert 對齊
- CR-0053：E2E smoke plan-only
- CR-0054～CR-0055：transport security plan / blocked
- CR-0056～CR-0057：Marketplace / DailyCareTask production 隱藏 + 後端 not_enabled 收斂

目前剩下的非基礎建設上架 blocker：

> App Store / Google Play 所需的 app identity、metadata、legal URLs、icon、screenshots、support contact、review notes、release signing 文件尚未最終化。  
> 這些多半需要 owner 決策或提供素材，但可以先用 docs 與 config 檢查清單整理到可交付狀態。

本 CR 目標是把雙平台商店上架資料、法律文件入口、App identity、icon/screenshot、簽章需求全部整理成明確可執行狀態，並修正程式內仍可離線處理的 app identity / label / metadata 問題。

---

## 2. 本次目標

完成 store metadata 與 release asset readiness：

1. 盤點 iOS Bundle ID / display name。
2. 盤點 Android applicationId / label。
3. 盤點 App icon / adaptive icon / launch screen。
4. 盤點 screenshots 需求。
5. 盤點 Privacy Policy / Terms / Support URL。
6. 盤點 LegalConfig 是否仍有 TODO。
7. 盤點 Apple / Google review notes。
8. 盤點 release signing 與不可提交 secret 的文件。
9. 更新 App Store metadata 草稿。
10. 更新 Google Play Data Safety。
11. 可修的 config / label 直接修；需要 owner 決策的列 blocker。
12. 不假裝已完成商店後台設定。

---

## 3. 必讀文件

請先閱讀：

- `CLAUDE.md`
- `docs/STORE_RELEASE_CHECKLIST.md`
- `docs/APP_STORE_METADATA.md`
- `docs/GOOGLE_PLAY_DATA_SAFETY.md`
- `docs/CHANGE_REVIEW.md`
- `docs/ENVIRONMENT_SETUP.md`
- `pubspec.yaml`
- `ios/Runner/Info.plist`
- `ios/Runner.xcodeproj`
- `android/app/build.gradle` 或 `android/app/build.gradle.kts`
- `android/app/src/main/AndroidManifest.xml`
- Android resource files for app label / icon
- Flutter assets / icon config if exists
- LegalConfig 相關檔案
- AppConfig production 設定

---

## 4. 先盤點

修改前請先盤點並回報：

1. iOS Bundle ID。
2. iOS display name。
3. Android applicationId。
4. Android label。
5. pubspec name / description。
6. app icon 是否為正式圖。
7. Android adaptive icon 是否存在。
8. launch screen 是否正式。
9. privacy policy URL 是否存在。
10. terms URL 是否存在。
11. support URL / email 是否存在。
12. LegalConfig 是否仍有 `TODO_*`。
13. App Store metadata 是否仍有 placeholder。
14. Google Play Data Safety 是否與 production 功能一致。
15. release signing 是否有文件，不可提交 key。
16. screenshots 是否已列規格。
17. app 是否仍有 demo/test/mock 字樣。
18. store description 是否宣稱已停用的 marketplace / daily-care 功能。

---

## 5. App Identity 需求

### 5.1 iOS

請檢查：

- Bundle ID
- CFBundleDisplayName
- CFBundleName
- version / build number
- icon set
- launch screen

要求：

1. 不可保留 default Flutter / demo / test 名稱。
2. Bundle ID 若未決定，列 owner blocker，不要隨便改。
3. display name 可依 owner 已定品牌修改。
4. 若品牌尚未定，維持但列 blocker。
5. 不提交 Apple signing credentials。

### 5.2 Android

請檢查：

- applicationId
- namespace if applicable
- android:label
- versionCode / versionName
- adaptive icon
- launcher icon

要求：

1. 不可保留 `com.example.*`。
2. 若現在為非正式 id，例如臨時 id，列 owner blocker。
3. applicationId 上架後難改，未經 owner 決策不可亂改。
4. 不提交 keystore。

---

## 6. Icon / Screenshot / Launch Screen

請建立或更新 asset checklist。

### 6.1 Icon

需列：

- iOS App Icon sizes
- Android launcher icon sizes
- Android adaptive icon foreground/background
- 是否使用正式寵物圖
- 是否有透明邊留白問題
- 是否符合商店審查，不含誤導醫療圖示

### 6.2 Screenshots

請列：

- iPhone screenshot 尺寸需求
- iPad if supported
- Android phone screenshot
- Android tablet if supported
- 建議截圖頁面：
  1. 首頁 AI 寵物
  2. Realtime 語音陪伴
  3. 對話記錄 / 記憶管理
  4. Care Alert 照護端示意
  5. 設定 / 隱私控制
- 不得顯示真個資、真電話、真 email、真對話。

### 6.3 Launch Screen

確認：

- 不出現 Flutter default
- 不出現 demo/test
- 品牌一致
- 不誤導為醫療診斷產品

---

## 7. Legal URLs / Policies

請檢查並整理：

1. Privacy Policy URL
2. Terms of Service URL
3. Support URL
4. Support email
5. Data deletion instruction URL or in-app path
6. Third-party AI processing disclosure
7. Telegram notification disclosure
8. Voice/audio data processing disclosure
9. Care Alert is care reminder, not medical diagnosis

若 URL 尚未部署，請列 owner blocker，不得填假 URL。

---

## 8. Store Metadata

請更新 `docs/APP_STORE_METADATA.md`：

至少包含：

1. App name
2. Subtitle
3. Promotional text if applicable
4. Short description
5. Full description
6. Keywords
7. Category
8. Age rating recommendation
9. Review notes
10. Test account strategy
11. Privacy policy URL placeholder or final
12. Support URL placeholder or final
13. Contact email
14. Medical / health disclaimer
15. Disabled features note：
    - marketplace production hidden
    - daily-care task production hidden if relevant

不可宣稱：

- 醫療診斷
- 疾病偵測
- 取代醫師
- 取代照護人員
- marketplace 交易已正式可用
- daily-care AI proof review 已正式可用

---

## 9. Google Play Data Safety

請更新 `docs/GOOGLE_PLAY_DATA_SAFETY.md`：

確認以下資料類型：

1. Account info
2. Name / email if used
3. Voice/audio
4. Messages / conversation
5. App activity
6. Inferred care signals / health-related information
7. Notifications
8. Device identifiers if used
9. Crash logs / diagnostics if used
10. Financial info should be not collected if marketplace disabled

需說明：

- collected or not
- shared or not
- purpose
- encrypted in transit
- deletion support
- third-party processing
- no sale of data

---

## 10. Release Signing 文件

請建立或更新 release signing 文件：

- iOS signing owner action
- Apple Developer account requirement
- Android keystore generation checklist
- Google Play App Signing
- 不提交 keystore
- 不提交 passwords
- CI secret storage guidance if needed

建議新增：

- `docs/RELEASE_SIGNING.md`

---

## 11. 測試與檢查

請盡可能執行：

```bash
flutter analyze
flutter test
```

若有 Android config 改動：

```bash
flutter build apk --release
```

若有 iOS config 改動且環境允許：

```bash
flutter build ios --release --no-codesign
```

若只改 docs，請明確說明不跑程式測試原因。

---

## 12. 文件需求

請更新：

- `docs/CHANGE_REVIEW.md`
- `docs/STORE_RELEASE_CHECKLIST.md`
- `docs/APP_STORE_METADATA.md`
- `docs/GOOGLE_PLAY_DATA_SAFETY.md`
- `docs/ENVIRONMENT_SETUP.md` if needed

請新增或更新：

- `docs/RELEASE_SIGNING.md`
- `docs/STORE_ASSET_CHECKLIST.md`

---

## 13. 限制

本 CR 不得：

1. 偽造已部署的 privacy policy URL。
2. 偽造已完成 App Store / Google Play 後台設定。
3. 擅自決定不可逆 applicationId / Bundle ID，除非 owner 已明確提供。
4. 提交 keystore / signing key / passwords。
5. 提交 Apple credentials。
6. 使用真使用者個資作 screenshots。
7. 在 store metadata 宣稱醫療診斷。
8. 宣稱 marketplace / daily-care task 已正式啟用。
9. 破壞 Realtime / Care Alert / Auth。
10. 重新啟用 production hidden features。

---

## 14. 驗收標準

完成後必須符合：

1. App identity 狀態明確。
2. Legal URLs 狀態明確。
3. Icon / screenshot / launch screen 狀態明確。
4. Release signing 狀態明確。
5. Store metadata 不誤宣稱。
6. Google Play Data Safety 與 production 功能一致。
7. owner blockers 清楚列出。
8. 可修的 config 已修。
9. 不提交 secret。
10. CHANGE_REVIEW / STORE_RELEASE_CHECKLIST 已更新。

---

## 15. 完成回報格式

請用以下格式回報：

```md
## CR-0058 完成回報

### 1. 本次目標
-

### 2. 修改檔案
-

### 3. App identity 盤點 / 改動
-

### 4. Icon / screenshot / launch screen 狀態
-

### 5. Legal URLs / policies 狀態
-

### 6. Store metadata 更新
-

### 7. Google Play Data Safety 更新
-

### 8. Release signing 文件
-

### 9. 測試與 build 結果
-

### 10. 正式版風險檢查
- 是否仍有 demo/test/mock metadata：
- 是否偽造 URL：
- 是否宣稱醫療診斷：
- 是否宣稱 hidden feature 已啟用：
- 是否提交 signing secret：
- 是否破壞 app config：

### 11. Owner blockers
-

### 12. 下一個建議 CR
-
```
