function assessSafety({ transcript = "" } = {}) {
  const text = transcript.toString().trim();
  if (/自殺|不想活|傷害自己|活不下去|想死/.test(text)) {
    return { riskLevel: "urgent", needsHumanSupport: true };
  }
  if (/胸痛|呼吸困難|喘不過氣|跌倒|昏倒|嚴重不舒服|很痛/.test(text)) {
    return { riskLevel: "urgent", needsHumanSupport: true };
  }
  if (/好痛苦|撐不下去|沒有人管我|很絕望/.test(text)) {
    return { riskLevel: "attention", needsHumanSupport: true };
  }
  return { riskLevel: "normal", needsHumanSupport: false };
}

module.exports = {
  assessSafety,
};
