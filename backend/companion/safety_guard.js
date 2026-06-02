// Care Alert 風險分級（CR-0002 Batch 1）。
//
// 直接輸出權威四級：low / medium / high / urgent（見 PROJECT_ARCHITECTURE.md §5.1）。
// 由重到輕逐層 early-return，確保高風險優先、urgent 門檻不被稀釋。
//
//   urgent：自傷 / 自殺、急性醫療、跌倒昏倒、立即危險（needsHumanSupport=true）
//   high  ：強烈絕望、明顯無助（needsHumanSupport=true 但未達 urgent）
//   medium：需持續觀察——一般低落、睡不好、吃不下、孤單等（needsHumanSupport=false）
//   low   ：一般狀態（needsHumanSupport=false）
//
// 注意：OpenAI Realtime 的語音轉文字常回「简体字」（睡不着 / 心情无好 / 难过…），
// 但下方關鍵字皆為繁體。若不先正規化，简体高風險語句會整句漏接而被低估。
// 因此比對前先把安全相關字做简→繁正規化，繁體 regex 維持單一真相來源。

// 安全關鍵字會用到的简→繁對照（僅涵蓋分級用字，避免誤改其他語意）。
const SIMPLIFIED_TO_TRADITIONAL = {
  着: "著",
  没: "沒",
  无: "無",
  单: "單",
  惫: "憊",
  劲: "勁",
  绝: "絕",
  义: "義",
  难: "難",
  过: "過",
  杀: "殺",
  伤: "傷",
  气: "氣",
  严: "嚴",
  东: "東",
  撑: "撐",
  觉: "覺",
  飞: "飛",
};

function normalizeForSafety(text) {
  let out = "";
  for (const ch of text) {
    out += SIMPLIFIED_TO_TRADITIONAL[ch] || ch;
  }
  return out;
}

function assessSafety({ transcript = "" } = {}) {
  const raw = transcript.toString().trim();
  const text = normalizeForSafety(raw);

  // urgent：維持原有觸發條件，不降低門檻。
  if (/自殺|不想活|傷害自己|活不下去|想死/.test(text)) {
    return { riskLevel: "urgent", needsHumanSupport: true };
  }
  if (/胸痛|呼吸困難|喘不過氣|跌倒|昏倒|嚴重不舒服|很痛/.test(text)) {
    return { riskLevel: "urgent", needsHumanSupport: true };
  }

  // high：強烈絕望 / 明顯無助（原 attention 中達到「需通知」程度者）。
  // 含被動式絕望語：「活著好累 / 活得好累 / 不想吃東西 / 什麼都不想做」等——
  // 雖未直接提到自傷，但已是需通知家屬或長照人員的求救訊號。
  if (
    /好痛苦|撐不下去|沒有人管我|很絕望|沒有人理我|不想拖累|活著沒意義|活著好累|活得好累|活著好難|活得好難|沒意思活|人生沒意思|不想吃東西|不想吃飯|什麼都不想做|什麼都不想吃|沒有人需要我|每天都好難過/.test(
      text,
    )
  ) {
    return { riskLevel: "high", needsHumanSupport: true };
  }

  // medium：需持續觀察的一般低落 / 睡眠 / 食慾 / 孤單訊號。
  if (
    /睡不好|睡不著|失眠|睏袂去|睏未去|吃不下|沒胃口|沒食慾|食欲|食慾不好|沒力氣|提不起勁|心情不好|心情無好|心情低落|好累|好疲憊|孤單|無聊|沒人陪|寂寞/.test(
      text,
    )
  ) {
    return { riskLevel: "medium", needsHumanSupport: false };
  }

  // low：一般狀態（原 normal）。
  return { riskLevel: "low", needsHumanSupport: false };
}

module.exports = {
  assessSafety,
  normalizeForSafety,
};
