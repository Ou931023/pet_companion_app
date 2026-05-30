// Care Alert 人類可讀摘要產生器（CR-0003 Batch 2）。
//
// 產生「單一 triggerSummary 字串」（決策：不新增結構化欄位），供 Telegram 與
// caregiver_web 直接顯示。內容涵蓋：偵測到的風險原因、對話訊號、建議照護行動。
//
// 語氣原則（CLAUDE.md）：
// - 白話、非診斷；不可出現「憂鬱症 / 確診 / 病人 / 診斷」等醫療判定字眼。
// - 不過度嚴重化；low 不誇大警示。
// - urgent 必須建議「立即確認安全」，不可退化為普通關心。

// 由重到輕；同一句可命中多個訊號，組成自然的中文片語。
const SIGNAL_RULES = [
  { key: "self_harm", phrase: "讓人擔心安全的話語", re: /自殺|不想活|傷害自己|活不下去|想死/ },
  { key: "acute", phrase: "身體不適或疑似跌倒", re: /胸痛|呼吸困難|喘不過氣|跌倒|昏倒|嚴重不舒服|很痛/ },
  { key: "despair", phrase: "強烈的無助或難過", re: /好痛苦|撐不下去|沒有人管我|很絕望|沒有人理我|不想拖累|活著沒意義|沒有人需要我|每天都好難過/ },
  { key: "sleep", phrase: "睡眠不佳", re: /睡不好|睡不著|失眠|睏袂去|睏未去/ },
  { key: "appetite", phrase: "食慾下降", re: /吃不下|沒胃口|沒食慾|食慾不好/ },
  { key: "mood", phrase: "情緒低落", re: /心情不好|心情無好|心情低落|提不起勁|好累|好疲憊/ },
  { key: "lonely", phrase: "感到孤單", re: /孤單|無聊|沒人陪|寂寞/ },
];

function detectSignals(transcript = "") {
  const text = (transcript || "").toString();
  const phrases = [];
  for (const rule of SIGNAL_RULES) {
    if (rule.re.test(text)) phrases.push(rule.phrase);
  }
  return phrases;
}

function joinSignals(phrases) {
  if (phrases.length === 0) return "";
  if (phrases.length === 1) return phrases[0];
  return `${phrases.slice(0, -1).join("、")}與${phrases[phrases.length - 1]}`;
}

// 產生單一 triggerSummary 字串。輸入 riskLevel 採權威四級（low/medium/high/urgent）。
function buildCareAlertSummary({ riskLevel = "low", transcript = "" } = {}) {
  const level = (riskLevel || "low").toString();
  const signalText = joinSignals(detectSignals(transcript));

  if (level === "urgent") {
    const what = signalText || "可能有立即危險的狀況";
    return `系統偵測長者提到${what}，建議照護人員儘快直接聯絡長者確認安全，必要時立即尋求協助。`;
  }
  if (level === "high") {
    const what = signalText || "明顯的無助與情緒低落";
    return `系統偵測長者提到${what}，建議照護人員今天主動關心近況，並留意長者是否需要陪伴或進一步協助。`;
  }
  if (level === "medium") {
    const what = signalText || "近況需要留意的狀況";
    return `系統偵測長者提到${what}，目前狀況需要持續觀察。建議照護人員找機會關心近況，留意長者是否需要陪伴。`;
  }
  // low：一般狀態，不誇大、不警示。
  return "系統觀察到長者目前狀態大致平穩，暫時不需特別處理，可如常陪伴與關心。";
}

module.exports = {
  buildCareAlertSummary,
  detectSignals,
};
