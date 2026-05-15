function analyzeImplicitMeaning({ transcript = "", emotion, companionNeed } = {}) {
  const text = transcript.toString().trim();
  if (/家裡.*安靜|安靜/.test(text) && companionNeed === "companionship") {
    return "使用者可能感受到家裡冷清，需要陪伴感。";
  }
  if (/大家.*忙|都很忙/.test(text)) {
    return "使用者可能覺得身邊的人沒有空陪伴，需要被溫柔確認。";
  }
  if (/不知道要做什麼|沒事做/.test(text)) {
    return "使用者可能需要有人陪著開啟一段輕鬆日常對話。";
  }
  if (/以前|從前|很熱鬧|懷念/.test(text)) {
    return "使用者正在觸及過去熱鬧的記憶，適合用懷舊陪伴承接。";
  }
  if (/睡不著|睡不太著|睡不好/.test(text)) {
    return "使用者可能身心還沒有安定，需要慢下來的陪伴。";
  }
  if (/算了|沒關係/.test(text) && emotion === "sad") {
    return "使用者可能把失落感收起來了，需要不逼迫的關心。";
  }
  return "使用者需要自然、簡短且不打擾的陪伴回應。";
}

module.exports = {
  analyzeImplicitMeaning,
};
