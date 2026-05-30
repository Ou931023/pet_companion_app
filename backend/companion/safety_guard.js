// Care Alert 風險分級（CR-0002 Batch 1）。
//
// 直接輸出權威四級：low / medium / high / urgent（見 PROJECT_ARCHITECTURE.md §5.1）。
// 由重到輕逐層 early-return，確保高風險優先、urgent 門檻不被稀釋。
//
//   urgent：自傷 / 自殺、急性醫療、跌倒昏倒、立即危險（needsHumanSupport=true）
//   high  ：強烈絕望、明顯無助（needsHumanSupport=true 但未達 urgent）
//   medium：需持續觀察——一般低落、睡不好、吃不下、孤單等（needsHumanSupport=false）
//   low   ：一般狀態（needsHumanSupport=false）
function assessSafety({ transcript = "" } = {}) {
  const text = transcript.toString().trim();

  // urgent：維持原有觸發條件，不降低門檻。
  if (/自殺|不想活|傷害自己|活不下去|想死/.test(text)) {
    return { riskLevel: "urgent", needsHumanSupport: true };
  }
  if (/胸痛|呼吸困難|喘不過氣|跌倒|昏倒|嚴重不舒服|很痛/.test(text)) {
    return { riskLevel: "urgent", needsHumanSupport: true };
  }

  // high：強烈絕望 / 明顯無助（原 attention 中達到「需通知」程度者）。
  if (/好痛苦|撐不下去|沒有人管我|很絕望|沒有人理我|不想拖累|活著沒意義|沒有人需要我|每天都好難過/.test(text)) {
    return { riskLevel: "high", needsHumanSupport: true };
  }

  // medium：需持續觀察的一般低落 / 睡眠 / 食慾 / 孤單訊號。
  if (
    /睡不好|睡不著|失眠|睏袂去|睏未去|吃不下|沒胃口|沒食慾|食慾不好|沒力氣|提不起勁|心情不好|心情無好|心情低落|好累|好疲憊|孤單|無聊|沒人陪|寂寞/.test(
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
};
