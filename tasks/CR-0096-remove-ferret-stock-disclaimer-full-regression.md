# CR-0096 Remove Ferret, Add Stock Disclaimer, Full Regression Test

## 背景

目前寵物素材中「雪貂」去背仍有問題，展示前先移除雪貂相關功能與資源入口，避免使用者看到品質不穩定的素材。

另外，當使用者在 App 中提到或詢問股票、投資、基金、ETF、股價、買賣股票等投資相關內容時，AI 回覆最後必須固定加上：

「投資一定有風險，基金投資有賺有賠，申購前應詳閱公開說明書」

最後需要完整測試所有主要功能正常，包含長者端 App、後端 API、Realtime 語音、Care Alert、任務/提醒/商城/寵物動畫，以及 caregiver_web 管理者網頁。

---

## 目標

1. 移除雪貂寵物，不再出現在任何使用者可見入口。
2. 保留現有狗、天竺鼠、狐狸寵物。
3. 股票/投資相關問題的 AI 回覆結尾固定加入投資風險提醒。
4. 不影響一般聊天、台語對話、照護工具、Care Alert、情緒分析、長期記憶。
5. 執行完整 regression test，包含管理者網頁。
6. 更新文件與 CHANGE_REVIEW。

---

## Part 1：移除雪貂寵物

### 1.1 搜尋所有雪貂相關程式碼與資源

請先全專案搜尋以下關鍵字：

- ferret
- Ferret
- 雪貂
- pet_ferret
- ferret_rest
- ferret_talk
- ferret_listening
- ferret_states
- unlock ferret
- skin ferret

請檢查範圍至少包含：

- Flutter app
  - `lib/`
  - `assets/`
  - `pubspec.yaml`
- 後端
  - `backend/`
- caregiver_web
  - `caregiver_web/`
- 文件
  - `docs/`
  - `README`
  - `CHANGE_REVIEW`
- 測試
  - `test/`
  - `backend/**/test`
  - `caregiver_web` 相關測試

### 1.2 移除雪貂可見入口

雪貂不得再出現在：

- 寵物換皮彈窗
- 商店或解鎖列表
- 寵物選擇頁
- onboarding / 新手導覽
- 預設資料
- 測試資料
- 管理者或 debug 面板
- 文件中的展示功能清單

保留：

- dog / 狗
- guinea pig / 天竺鼠
- fox / 狐狸

### 1.3 資源處理原則

如果雪貂圖片仍在 assets 中但已完全沒有引用，可以選擇：

A. 直接刪除雪貂圖片資源  
或  
B. 暫時搬到不打包、不引用的備份資料夾，例如 `docs/assets_removed/ferret/`

優先選擇 A，避免正式 build 打包到 App 裡。

務必同步更新：

- `pubspec.yaml` assets 宣告
- Flutter asset preload 邏輯
- Pet enum / PetSkin enum / PetType enum
- 寵物商品資料
- 解鎖邏輯
- 測試 snapshot / expected list

### 1.4 防呆

如果使用者過去資料中已經選到 ferret，App 不可以 crash。

請補 fallback：

- 如果本機儲存或後端回傳 `ferret`
- 自動 fallback 成 `dog`
- 並避免 UI 顯示雪貂名稱

建議補測試：

- saved pet skin = `ferret`
- app 啟動後顯示 dog
- 不丟 exception
- 不出現 missing asset

---

## Part 2：股票/投資問題固定加免責聲明

### 2.1 觸發條件

當使用者訊息包含股票或投資相關意圖時，AI 回覆最後必須追加：

「投資一定有風險，基金投資有賺有賠，申購前應詳閱公開說明書」

需要涵蓋中文、英文與常見口語關鍵字。

### 2.2 建議偵測關鍵字

至少包含：

中文：

- 股票
- 股市
- 股價
- 台股
- 美股
- 買股
- 賣股
- 投資
- 基金
- ETF
- 指數型基金
- 配息
- 殖利率
- 報酬率
- 技術分析
- 基本面
- 財報
- 0050
- 0056
- 00878
- 高股息
- 申購
- 定期定額

英文：

- stock
- stocks
- share
- shares
- market
- investing
- investment
- fund
- mutual fund
- ETF
- dividend
- portfolio
- buy stock
- sell stock

### 2.3 套用位置

請檢查目前 AI 回覆來源，至少要涵蓋：

- `/api/companion/chat`
- Realtime 語音回覆文字指令或 transcript 後處理
- typed chat
- tool outcome 回覆，如果工具結果和股票/投資相關，也要加
- 台語模式如果使用者問股票，也要加中文免責聲明

### 2.4 實作建議

建立一個共用 utility，例如：

後端：

`backend/stt_proxy/services/compliance/investmentDisclaimer.js`

功能：

- `isInvestmentRelatedText(text)`
- `appendInvestmentDisclaimerIfNeeded(userText, assistantText)`

規則：

1. 根據使用者輸入判斷是否投資相關。
2. 若是，將免責聲明加在 AI 回覆最後。
3. 如果 AI 回覆已經包含同一句免責聲明，不要重複加。
4. 保留原本 AI 回覆內容，不要覆蓋。
5. 空字串或非字串不應 crash。

範例：

```js
const INVESTMENT_DISCLAIMER =
  '投資一定有風險，基金投資有賺有賠，申購前應詳閱公開說明書';

function isInvestmentRelatedText(text) {
  if (!text || typeof text !== 'string') return false;
  const normalized = text.toLowerCase();

  const keywords = [
    '股票', '股市', '股價', '台股', '美股', '買股', '賣股',
    '投資', '基金', 'etf', '指數型基金', '配息', '殖利率',
    '報酬率', '技術分析', '基本面', '財報', '0050', '0056',
    '00878', '高股息', '申購', '定期定額',
    'stock', 'stocks', 'share', 'shares', 'market',
    'investing', 'investment', 'fund', 'mutual fund',
    'dividend', 'portfolio', 'buy stock', 'sell stock'
  ];

  return keywords.some((keyword) => normalized.includes(keyword.toLowerCase()));
}

function appendInvestmentDisclaimerIfNeeded(userText, assistantText) {
  if (!assistantText || typeof assistantText !== 'string') return assistantText;
  if (!isInvestmentRelatedText(userText)) return assistantText;
  if (assistantText.includes(INVESTMENT_DISCLAIMER)) return assistantText;

  return `${assistantText.trim()}\n\n${INVESTMENT_DISCLAIMER}`;
}

module.exports = {
  INVESTMENT_DISCLAIMER,
  isInvestmentRelatedText,
  appendInvestmentDisclaimerIfNeeded,
};