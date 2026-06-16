"use strict";

const assert = require("node:assert/strict");
const { test } = require("node:test");

const {
  INVESTMENT_DISCLAIMER,
  isInvestmentRelatedText,
  appendInvestmentDisclaimerIfNeeded,
} = require("./investmentDisclaimer");

test("isInvestmentRelatedText：中文投資關鍵字判為相關", () => {
  for (const text of [
    "我想買股票",
    "幫我看一下台股",
    "最近基金跌很多",
    "0056 高股息值得買嗎",
    "定期定額要怎麼設",
    "ETF 是什麼",
  ]) {
    assert.equal(isInvestmentRelatedText(text), true, `應判為投資相關：${text}`);
  }
});

test("isInvestmentRelatedText：英文 / 大小寫混用也判為相關", () => {
  for (const text of [
    "should I buy this STOCK",
    "what about index funds",
    "my portfolio is down",
    "ETF dividend question",
  ]) {
    assert.equal(isInvestmentRelatedText(text), true, `應判為投資相關：${text}`);
  }
});

test("isInvestmentRelatedText：一般陪伴聊天不誤判", () => {
  for (const text of [
    "今天天氣真好",
    "我有點睡不著",
    "晚餐吃了滷肉飯",
    "今仔日心情袂䆀", // 台語閒聊
    "陪我聊聊天",
  ]) {
    assert.equal(isInvestmentRelatedText(text), false, `不應誤判：${text}`);
  }
});

test("isInvestmentRelatedText：空 / 非字串輸入不 crash 且回 false", () => {
  assert.equal(isInvestmentRelatedText(""), false);
  assert.equal(isInvestmentRelatedText(null), false);
  assert.equal(isInvestmentRelatedText(undefined), false);
  assert.equal(isInvestmentRelatedText(123), false);
  assert.equal(isInvestmentRelatedText({}), false);
});

test("appendInvestmentDisclaimerIfNeeded：投資相關 → 結尾附上免責聲明", () => {
  const out = appendInvestmentDisclaimerIfNeeded(
    "我想買股票",
    "我懂你想為將來多做點準備的心情。",
  );
  assert.ok(out.endsWith(INVESTMENT_DISCLAIMER), "結尾應為免責聲明");
  assert.ok(out.includes("我懂你想"), "原回覆內容應保留");
});

test("appendInvestmentDisclaimerIfNeeded：非投資相關 → 回覆原樣不動", () => {
  const reply = "今天有沒有好好休息呀？";
  assert.equal(appendInvestmentDisclaimerIfNeeded("我有點累", reply), reply);
});

test("appendInvestmentDisclaimerIfNeeded：已含同句 → 不重複追加", () => {
  const reply = `好的，我陪你看看。\n\n${INVESTMENT_DISCLAIMER}`;
  const out = appendInvestmentDisclaimerIfNeeded("基金怎麼選", reply);
  assert.equal(out, reply);
  // 只出現一次。
  assert.equal(out.split(INVESTMENT_DISCLAIMER).length - 1, 1);
});

test("appendInvestmentDisclaimerIfNeeded：空 / 非字串回覆不 crash", () => {
  assert.equal(appendInvestmentDisclaimerIfNeeded("股票", ""), "");
  assert.equal(appendInvestmentDisclaimerIfNeeded("股票", null), null);
  assert.equal(appendInvestmentDisclaimerIfNeeded("股票", undefined), undefined);
});

test("appendInvestmentDisclaimerIfNeeded：台語問股票也加中文免責聲明", () => {
  const out = appendInvestmentDisclaimerIfNeeded(
    "我想欲買股票，敢會使？",
    "我了解你的心意，有我佇遮陪你。",
  );
  assert.ok(out.endsWith(INVESTMENT_DISCLAIMER));
});
