# Google Play Data Safety / App Store Privacy — AI Pet Companion（草稿）

> 狀態：CR-0046 第一輪草稿；CR-0056/0057 確認 marketplace 停用→**不蒐集財務/購買資料**；CR-0058 確認與 production 功能一致。最終填寫前需與**實際資料蒐集行為**逐項核對，並由負責人/法務確認。
>
> CR-0058 核對結論：帳號/語音/對話/健康相關推論/App 活動 = 蒐集（用途 = App 功能/照護輔助，傳輸加密，可刪除，第三方 = OpenAI/Telegram 已揭露）；財務/購買 = **否**（marketplace 停用）；位置/聯絡人 = 否。仍待 owner/送審前以實際程式核對的 ⛔ 項：notification token、裝置識別碼、crash/diagnostics（若採用第三方崩潰回報需申報；目前未確認啟用）。
> 原則：**據實申報**。表單內容必須與 App 實際行為、隱私政策、知情同意流程一致。

相關文件：`docs/STORE_RELEASE_CHECKLIST.md`、`docs/APP_STORE_METADATA.md`、`docs/AUTHORIZATION_MODEL.md`、`lib/config/legal_content.dart`（同意內文）。

---

## 1. 通則

- **傳輸加密**：✅ production 要求 HTTPS（見 `STORE_RELEASE_CHECKLIST.md` §6 ATS/cleartext 收斂）。OpenAI Realtime 媒體為 WebRTC DTLS-SRTP 加密。
- **可要求刪除**：✅ 提供帳號與資料刪除（`/api/auth/delete` + 前端入口）；記憶可查看 / 刪除 / 封存。
- **知情同意**：✅ 首次使用 consent gate（須同意才進 App）。
- **第三方資料流向**：語音 / 對話文字會傳送至 **OpenAI**（Realtime / 文字 / embedding）以產生回應與記憶；high/urgent Care Alert 摘要會經 **Telegram** 通知授權照護人員。⛔ 此資料流向須於隱私政策與同意內文明確揭露（核對 `legal_content.dart`）。
- **資料是否販售**：否。
- **是否用於廣告 / 追蹤**：否。
- **伺服器日誌去識別化**：✅ 後端 production log 不保存完整對話 / Care Alert summary·reason / email / phone / token / secret / DATABASE_URL（CR-0047）。所有 log 附帶物件經 `services/privacy/redaction.js` 遮蔽，錯誤只記安全摘要（不含 stack）。詳見 `docs/LOGGING_AND_REDACTION.md`。

---

## 2. 資料類型對照（Google Play Data Safety）

| 資料類型 | 是否蒐集 | 是否分享(第三方) | 用途 | 傳輸加密 | 可否要求刪除 | 備註 |
|---|---|---|---|---|---|---|
| 帳號資訊（email、displayName、firebase_uid） | 是 | Firebase Auth（驗證） | App 功能 / 帳號驗證 | 是 | 是 | 走 Firebase；email 在管理端遮蔽顯示 |
| 住民/長者基本資料（暱稱、出生年、性別） | 是 | 否 | App 功能 / 照護輔助 | 是 | 是 | |
| 語音 / 音訊 | 是 | OpenAI（即時語音處理） | App 核心功能（語音陪伴） | 是 | 視政策 | 媒體 DTLS-SRTP；⛔ 須揭露 OpenAI 處理 |
| 訊息 / 對話內容 | 是 | OpenAI（生成回應 / 記憶） | App 功能 / 個人化記憶 | 是 | 是 | 長期記憶可查看/刪除/封存 |
| 健康相關推論（Care Alert 情緒/生活訊號） | 是 | Telegram（high/urgent 通知授權照護者） | 照護輔助提醒（**非醫療診斷**） | 是 | 是 | 通知避免暴露完整原文；依授權關聯推送。來源含**語音對話與打字聊天**（CR-0051：打字 medium+ 亦記錄至 caregiver console，記錄頻率較前提高） |
| App 活動（每日簽到、遊戲、提醒使用） | 是 | 否 | App 功能 / 照護分析 | 是 | 是 | |
| 通知 token | 視實作 | 否 | 推播通知 | 是 | 是 | ⛔ 核對是否已蒐集 notification token |
| 裝置識別碼 | ⛔ 核對 | — | — | — | — | 若未蒐集則申報「否」；Firebase 可能含 install id，需核對 |
| 相片 / 媒體 | 視使用 | 否 | 記憶拼圖 / 任務完成照 | 是 | 是 | 使用者主動選取；相簿權限有說明 |
| 精確/概略位置 | 否 | — | — | — | — | App 不蒐集位置 |
| 聯絡人 | 否 | — | — | — | — | |
| 財務資訊 | 否 | — | — | — | — | **CR-0056 A2**：內建商城 marketplace 於 production 完全隱藏/停用（post-release）→ 本版**不蒐集財務資訊、無 IAP、不申報 Purchase history**。未來若正式開放交易需重走資料安全評估 |

> ⛔ 標記項：送審前需以實際程式行為核對（特別是 notification token、裝置識別碼），不可憑此草稿直接送出。marketplace 金流已由 **CR-0056 A2** 解除（production 隱藏、不申報財務資料）；store-facing 文案不得出現商城/購買/下單/照護任務審核字樣。

---

## 3. App Store Privacy（iOS App Privacy 對應）

iOS「App 隱私」問卷需對應上表，重點：
- **Data Used to Track You**：無（不做跨 App 追蹤）。
- **Data Linked to You**：帳號資訊、住民資料、語音、對話、健康相關推論、App 活動、（視實作）相片。
- **Data Not Linked to You**：⛔ 核對是否有去識別化的診斷/分析資料。
- 每一類需勾選用途（App Functionality / 不含廣告或分析追蹤）。

---

## 4. 與隱私政策 / 同意內文一致性檢查（送審前）

- [ ] 隱私政策（hosted URL，⛔ 待部署）涵蓋上表所有「是」項。
- [ ] 同意內文（`legal_content.dart`）已揭露 OpenAI 與 Telegram 資料流向。
- [ ] 帳號 / 資料刪除流程於政策中說明。
- [ ] Care Alert 明確標示為「照護提醒、非醫療診斷」。
- [ ] 麥克風 / 相機 / 相簿 / 通知權限用途與實際一致。
