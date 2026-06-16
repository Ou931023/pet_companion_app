// 投資 / 股票合規免責聲明（CR-0096）。
//
// 目的：
// - 當長者在 App 裡提到或詢問股票、投資、基金、ETF、股價、買賣股票等
//   投資相關內容時，AI 回覆結尾必須固定附上法定風險提醒，避免被當成投資建議。
//
// 設計原則：
// - 純函式、無副作用、不依賴 .env / 網路，方便 node --test 直接驗證。
// - 只「附加」不「覆蓋」：保留原本 AI 回覆內容，只在結尾補一句免責聲明。
// - 不重複：若回覆已含同一句免責聲明，不再追加。
// - 防呆：空字串 / 非字串輸入不可 crash。
// - 偵測依「使用者輸入」判斷意圖，而不是看 AI 回覆，避免 AI 沒提到股票卻硬加。

"use strict";

const INVESTMENT_DISCLAIMER =
  "投資一定有風險，基金投資有賺有賠，申購前應詳閱公開說明書";

// 偵測關鍵字：中文、英文與常見口語 / 代號。全部以小寫比對（含中文原樣）。
const INVESTMENT_KEYWORDS = [
  // 中文
  "股票", "股市", "股價", "台股", "美股", "買股", "賣股",
  "投資", "基金", "指數型基金", "配息", "殖利率",
  "報酬率", "技術分析", "基本面", "財報", "高股息", "申購", "定期定額",
  // 台股常見代號
  "0050", "0056", "00878",
  // 英文 / 縮寫
  "etf", "stock", "stocks", "share", "shares", "market",
  "investing", "investment", "fund", "mutual fund",
  "dividend", "portfolio", "buy stock", "sell stock",
];

// 判斷一段文字是否為投資 / 股票相關。
// 非字串 / 空字串一律回 false（不 crash）。
function isInvestmentRelatedText(text) {
  if (!text || typeof text !== "string") return false;
  const normalized = text.toLowerCase();
  return INVESTMENT_KEYWORDS.some((keyword) =>
    normalized.includes(keyword.toLowerCase()),
  );
}

// 若使用者輸入屬於投資相關，於 AI 回覆結尾追加免責聲明。
//   - userText：用來判斷意圖的使用者輸入。
//   - assistantText：原始 AI 回覆（保留不覆蓋）。
// 規則：
//   1. assistantText 非字串 → 原樣回傳（含 null / undefined），不 crash。
//   2. userText 非投資相關 → 原樣回傳。
//   3. assistantText 已含同一句免責聲明 → 不重複追加。
//   4. 其餘情況 → 在 trim 後的回覆結尾換兩行接上免責聲明。
function appendInvestmentDisclaimerIfNeeded(userText, assistantText) {
  // 空字串 / null / undefined / 非字串一律原樣回傳（不追加、不 crash）。
  if (!assistantText || typeof assistantText !== "string") return assistantText;
  if (!isInvestmentRelatedText(userText)) return assistantText;
  if (assistantText.includes(INVESTMENT_DISCLAIMER)) return assistantText;
  return `${assistantText.trim()}\n\n${INVESTMENT_DISCLAIMER}`;
}

module.exports = {
  INVESTMENT_DISCLAIMER,
  INVESTMENT_KEYWORDS,
  isInvestmentRelatedText,
  appendInvestmentDisclaimerIfNeeded,
};
