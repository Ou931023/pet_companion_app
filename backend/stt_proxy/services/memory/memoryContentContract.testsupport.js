"use strict";

// A finite, hand-reviewed semantic oracle for synthetic fixtures, not a general
// entailment detector. Alternatives deliberately admit reasonable paraphrases.
const contracts = {
  "fact first": [/喜歡|愛好/, /散步/],
  "boundary first": [/喜歡|愛好/, /散步/],
  "family fact and pronoun boundary": [/女兒/, /住(?:在|於)?.*(?:台中|臺中)/],
  "retained reference": [/女兒/, /住(?:在|於)?.*(?:台中|臺中)/, /喜歡.*散步/],
  "reference to removed topic": [/女兒/, /住(?:在|於)?.*(?:台中|臺中)/],
  "reference after independent preference": [/喜歡.*散步/],
  "reference before another person": [/女兒(?:說|表示|提到)/, /媽媽.*住.*(?:台中|臺中)/],
  "uncertain move": [/女兒/, /可能|或許|也許/, /搬.*(?:台南|臺南)/],
  "move confirmed": [/女兒/, /確定|確認/, /下週|下周/, /搬/],
  "move cancelled": [/女兒/, /取消|不搬/, /搬/],
  "move unresolved": [/女兒/, /還沒決定|尚未決定|未定/, /搬/],
  "completed move": [/女兒/, /已.*搬/, /台南|臺南/],
  "future appointment": [/明天|明日/, /回診|複診/],
  "reported boundary": [/女兒(?:說|表示|提到)/, /(?:不聊|不談).*工作/],
  "reported boundary after punctuation": [/女兒(?:說|表示|提到)/, /今天|今日/, /不聊|不談/],
  "quoted boundary": [/女兒(?:說|表示|提到)/, /(?:不聊|不談).*工作/, /還沒決定|尚未決定|未定/, /搬家/],
  "negated boundary": [/不是說|否認/, /不要再問|不再追問/, /睡不好/],
  "negated boundary after punctuation": [/不是說|否認/, /不聊|不談/, /女兒/],
  "reopened topic": [/現在.*(?:想聊|願意談)/, /女兒/, /住.*(?:台中|臺中)/],
  "permanent preference": [/永遠|永久|以後都/, /不要聊|不談/, /女兒/],
  "legacy unscoped refusal": [/不聊|不談/, /女兒/],
};

for (const [alias, original] of Object.entries({
  "uncertain move control": "uncertain move",
  "confirmed future control": "move confirmed",
  "cancelled control": "move cancelled",
  "unresolved control": "move unresolved",
  "completed control": "completed move",
  "appointment control": "future appointment",
})) contracts[alias] = contracts[original];

const mixed = new Set([
  "fact first", "boundary first", "family fact and pronoun boundary", "retained reference",
  "reference to removed topic", "reference after independent preference", "reference before another person",
  "uncertain move", "move confirmed", "move cancelled", "move unresolved", "completed move", "future appointment",
]);

const neutralGreetings = new Set([
  "今天也想陪你慢慢聊聊。你現在心情還好嗎？",
  "我在這裡陪你，今天想先聊聊什麼？",
  "今天想輕鬆聊聊，還是先休息一下？",
]);

function canonical(text) {
  return text.replace(/^使用者(?:自我介紹|提到家人|需要照護提醒|提到未來事項|近期情緒狀態|近期睡眠或精神狀態|的生活習慣或近期狀況|偏好)[:：]/, "")
    .replace(/[\s，,。.!！?？；;「」]/g, "")
    .replace(/使用者/g, "我").replace(/愛好/g, "喜歡").replace(/臺/g, "台")
    .replace(/或許會搬到/g, "可能搬去").replace(/尚未決定/g, "還沒決定").replace(/下周/g, "下週");
}

function assertContentContract(assert, content, label, { greeting = false, context = false, expected } = {}) {
  assert.equal(typeof content, "string");
  // A neutral invitation makes no remembered claim: safe consumer abstention.
  if (greeting && neutralGreetings.has(content)) return;
  if (context) {
    const start = content.indexOf("1. ");
    const end = content.indexOf(" 使用規則：");
    assert.ok(start >= 0 && end > start, "inspect the actual context memory line");
    content = content.slice(start + 3, end);
  }
  if (greeting) {
    content = content.replace(/^你之前(?:說|提過)/, "")
      .replace(/，今天(?:需要我晚點提醒你嗎？|想聊聊這個嗎？|也慢慢來，想聊聊嗎？|也想陪你慢慢聊聊。)$/, "");
  }
  const patterns = contracts[label];
  assert.ok(patterns, `missing contract: ${label}`);
  for (const pattern of patterns) assert.match(content, pattern, `missing semantic qualifier: ${pattern}`);
  assert.doesNotMatch(content, /高雄|買房|每天跑十公里/, "unsupported or assistant-only claim");
  if (mixed.has(label)) assert.doesNotMatch(content, /今天.*不聊|先不聊/, "temporary boundary leaked");
  if (/uncertain|unresolved|cancelled|confirmed|move confirmed/.test(label)) {
    assert.doesNotMatch(content, /已經?搬|搬好了|已完成搬家/, "pending/cancelled/future move asserted complete");
  }
  if (/appointment/.test(label)) assert.doesNotMatch(content, /已.*回診|昨天.*回診/, "future appointment asserted past");
  if (expected != null) assert.equal(canonical(content), canonical(expected), "complete grounded content, allowing explicit equivalent wording but no added claims");
}

module.exports = { assertContentContract };
