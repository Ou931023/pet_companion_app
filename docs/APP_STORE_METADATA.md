# App Store / Google Play Metadata — AI Pet Companion（草稿）

> 狀態：CR-0046 第一輪草稿。所有 `⛔ 待定` 項需負責人 / 法務確認後填入，**禁止以假值送審**。
> 本檔為文案草稿，實際送審以商店後台為準。

相關文件：`docs/STORE_RELEASE_CHECKLIST.md`、`docs/GOOGLE_PLAY_DATA_SAFETY.md`。

---

## 1. 共用（iOS + Android）

| 欄位 | 草稿值 | 備註 |
|---|---|---|
| App 正式名稱 | ✅ 中文「AI陪伴」/ 英文 "AI Companion"（CR-0061 owner 拍板） | 與 iOS CFBundleDisplayName（`AI Companion`）/ Android label（`AI Companion`）一致 |
| 開發者 / 發行者名稱 | ✅ 國立嘉義大學資訊管理學系專題第四組（CR-0061） | 機構 / 團隊正式名稱（商店後台 / 著作權顯示用） |
| 主分類 | Health & Fitness 或 Medical（建議 Health & Fitness，避免醫療宣稱） | Care Alert 為「照護提醒」非醫療診斷 |
| 次分類 | Lifestyle | |
| 年齡分級 | 建議 4+（iOS）/ Everyone（Google）；最終依問卷 | 無暴力/成人內容；含使用者生成語音對話 |
| 隱私政策 URL | ✅ `https://ou931023.github.io/pet_companion_app/privacy.html` | GitHub Pages 公開 HTTPS URL；production build / 商店後台需使用同一值 |
| 服務條款 URL | ✅ `https://ou931023.github.io/pet_companion_app/terms.html` | GitHub Pages 公開 HTTPS URL；production build / 商店後台需使用同一值 |
| 支援 URL | ✅ `https://ou931023.github.io/pet_companion_app/support.html` | GitHub Pages 公開 HTTPS URL；production build / 商店後台需使用同一值 |
| 行銷 / 客服 Email | ✅ `aicompanion.support@gmail.com` | App 內設定頁可透過 `CONTACT_EMAIL` 顯示客服信箱入口；商店後台與 production build 應使用同一信箱 |
| 版本 | 1.0.0（pubspec `1.0.0+1`） | |

---

## 2. App Store（iOS）

- **App 名稱（≤30 字元）**：✅「AI陪伴」（英文顯示名 `AI Companion`，CR-0061；副標題可補充定位）
- **副標題 Subtitle（≤30 字元）**：草稿「用說的，就有人陪你聊天」
- **簡短描述 / Promotional text**：草稿「對著手機裡的陪伴寵物說說話，牠會聽你說、記得你，也讓家人與照護人員適時關心你。」
- **完整描述 Full description**：草稿——
  > 「陪伴寵物」是一款為長者設計的 AI 語音陪伴 App。只要對手機裡的寵物說話，牠就會像朋友一樣聽你說話、回應你的心情，也會記得你之前提過的事。
  >
  > • 即時語音陪伴：按下按鈕就能自然說話，不必打字。
  > • 溫暖回應：先接住你的心情，再陪你聊。
  > • 長期記憶：記得你喜歡的稱呼、家人、生活習慣。
  > • 貼心關懷：當你提到睡不好、吃不下、心情低落時，系統會在後台整理成「關懷提醒」，讓家人或照護人員適時留意。
  > • 隱私優先：首次使用會說明資料用途並徵求同意，你可以隨時查看或刪除自己的記憶與資料。
  >
  > 註：本 App 的關懷提醒是「照護輔助提醒」，不是醫療診斷，不能取代專業醫療或照護人員的判斷。
- **關鍵字（≤100 字元，逗號分隔）**：草稿「長者,陪伴,語音,AI,寵物,關懷,照護,記憶,聊天,孤單,長照,family」
- **What's New（首版）**：草稿「首次推出：即時語音陪伴、長期記憶、關懷提醒。」
- **審查備註 Review notes**：⛔ 待定——需說明：(1) 需麥克風做即時語音；(2) Care Alert 為照護提醒非醫療；(3) 後端需正式 URL/金鑰；(4) 若需審查用測試帳號，提供 demo 帳號策略（見下）。
- **Demo / 測試帳號策略（審查用）**：⛔ 待定——建議提供一組「審查專用」Firebase 帳號 + 預先指派的住民資料，讓審查員能走完登入→語音→Care Alert；**不可用 production super_admin token、不可 hardcode**。
- **Sign in with Apple**：若上架時提供第三方登入（Google），Apple 規範要求同時提供 Sign in with Apple。✅ CR-0101A 決策：Apple Sign in 完成前，production build 隱藏 Google / Apple 第三方登入入口，只保留 Email login / Email register；未完成入口不得出現在送審截圖或審查流程。
- **App Privacy 補充（CR-0097）**：隱私問卷需申報 App 活動 / 使用分析（App 開啟與使用時間、語音/打字互動、寵物互動、提醒/任務、照片驗證、小遊戲等）。用途限 App Functionality / Analytics / Product Personalization（若後台選項適用），不得填成 tracking 或 advertising。
- **帳號刪除 / 支援備註（CR-0101A）**：設定頁提供「刪除帳號」入口與二次確認，文案說明會刪除伺服器帳號資料與本機 App 紀錄。審查備註可指出：登入後進入設定 → 帳號 → 刪除帳號。正式支援 URL / 客服信箱需由 `SUPPORT_URL` / `CONTACT_EMAIL` 注入並與商店後台一致。

---

## 3. Google Play（Android）

- **App 名稱（≤30 字元）**：✅「AI陪伴」（英文 `AI Companion`，與 iOS 一致，CR-0061）
- **簡短描述（≤80 字元）**：草稿「對 AI 寵物說說話，牠陪你聊、記得你，也讓家人適時關心。」
- **完整描述（≤4000 字元）**：同 §2 完整描述（可加長）。
- **分類**：Health & Fitness
- **內容分級問卷**：⛔ 待定（依 IARC 問卷，含使用者語音對話）
- **Data Safety 表單**：見 `docs/GOOGLE_PLAY_DATA_SAFETY.md`（⛔ 需於後台逐項填寫）
- **目標客群 / 兒童政策**：本 App 面向成人（長者），非兒童導向。
- **Feature graphic / screenshots**：✅ feature graphic 與兩平台候選 screenshots 已輸出於 `store_assets/`；送審前仍需商店後台人工預覽裁切。

---

## 4. Screenshots（兩平台共用規劃）

✅ 已輸出去識別化候選截圖：
1. 首頁語音陪伴入口。
2. 即時語音陪伴。
3. 長期記憶。
4. Care Alert 照護輔助提醒（明確標示非醫療診斷）。
5. 隱私、支援與帳號刪除。

檔案位置：
- Android phone：`store_assets/screenshots/android_phone/*.png`（1080×1920）。
- iPhone 6.7"：`store_assets/screenshots/ios_6_7/*.png`（1290×2796）。
- 產出腳本：`scripts/generate_store_screenshots.sh`。

> 截圖不得出現真實長者個資、不得出現 debug/demo 字樣。

---

## 5. 醫療安全用語（送審文案紅線）

App 名稱、描述、截圖、審查備註**不得宣稱**：已診斷 / 確診 / 醫療判斷 / 疾病推論 / 取代醫師或照護人員。
建議用語：建議關心 / 可能需要留意 / 系統偵測到需照護人員確認的訊號。

---

## 6. 本版停用功能（送審文案不得宣稱）— CR-0056/0057

下列功能本版 **production 隱藏 / 停用**（見 `docs/MARKETPLACE_PRODUCTION_DECISION.md`、`docs/DAILY_CARE_TASK_PRODUCTION_DECISION.md`）。store 文案、截圖、審查備註**不得**出現、不得宣稱已可用：

- **內建商城（marketplace）交易 / 下單 / 購買 / 長照用品**：production 入口隱藏、後端回 501 `not_enabled`。→ 不申報 IAP / 財務資料（見 `docs/GOOGLE_PLAY_DATA_SAFETY.md`）。
- **每日照護任務（daily-care）拍照完成 / AI 任務審核**：production 隱藏、後端 501。→ 文案不得提「拍照完成任務 / 任務審核」。

> 現行草稿描述（§2/§3）僅涵蓋語音陪伴 / 記憶 / 關懷提醒，未提及上述停用功能 → 一致、無需改文案。新增文案時務必維持此界線。

---

## 7. App Identity 現況（CR-0058 盤點 → CR-0061 owner 拍板定值）

| 項目 | 現況 | 狀態 |
|---|---|---|
| iOS Bundle ID | `tw.edu.ncyu.im.aicompanion` | ✅ **CR-0061 定值**（國立嘉義大學反向網域）；已寫入 `ios/Runner.xcodeproj/project.pbxproj`（app target + `<id>.RunnerTests`）。上架後**不可改**。 |
| Android applicationId | `tw.edu.ncyu.im.aicompanion`（對齊 iOS） | ✅ **CR-0061 定值**；已寫入 `android/app/build.gradle.kts`。上架後不可改。 |
| Android namespace | `com.example.pet_companion_app` | 🔵 內部 R/BuildConfig 套件名（**非**發布 ID、不影響送審）；Flutter 模板殘留。owner 明確要求**維持不動**（避免移動 `MainActivity` 套件），與 applicationId 互相獨立。 |
| iOS CFBundleDisplayName | `AI Companion` | ✅ **CR-0061 定值**；已寫入 `ios/Runner/Info.plist`。 |
| Android android:label | `AI Companion`（CR-0061 由 interim `Pet Companion App` 定值） | ✅ **CR-0061 定值**；已寫入 `AndroidManifest.xml`。 |
| App 中文名 | `AI陪伴` | ✅ **CR-0061 定值**（store metadata §1/§2/§3 用；非寫入 build 設定）。 |
| 開發者 / 發行者 | 國立嘉義大學資訊管理學系專題第四組 | ✅ **CR-0061 定值**（商店後台 / 著作權顯示）。 |
| pubspec name | `pet_companion_app` | 🔵 套件名（非 store 名稱、改動會破壞 import），維持。 |
| version | `1.0.0+1` | ✅ 首版可用。 |

> App identity（Bundle ID / applicationId / 顯示名 / 品牌 / 發行者）已於 **CR-0061 由 owner 拍板定值**。Bundle ID / applicationId 為**不可逆**，後續 Apple 憑證、Firebase iOS/Android App、Sign in with Apple 設定皆須對應 `tw.edu.ncyu.im.aicompanion`。剩餘 owner blocker 移至法律 URL（§1）、icon / screenshots、簽章與商店後台。
