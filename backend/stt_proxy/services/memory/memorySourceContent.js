"use strict";

// Deliberately bounded language recognition, not sentence splitting. A projection
// is accepted only when the WHOLE turn fits a direct instruction + independent
// assertion. Every retained character comes from the user; no pronoun expansion,
// tense conversion, free-form summary, or assembly of unrelated fragments.
const FAMILY = "(?:我(?:的)?)?(?:女兒|兒子|孫女|孫子|老伴|先生|太太|媽媽|爸爸)";
const PLACE = "(?:台|臺)(?:北|中|南|東)|高雄|桃園|新竹|苗栗|彰化|南投|雲林|嘉義|屏東|宜蘭|花蓮|澎湖|基隆";
const PREFERENCE = "我(?:不)?喜歡(?:散步|運動|聽老歌|聽音樂|看書|種花|唱歌|台灣地方故事|恐怖故事)";
const preference = new RegExp(`^${PREFERENCE}$`);
// Recognize a complete declaration, without stripping or rewriting its source.
// A single full stop or exclamations are declarative; ellipses are not.
const declarativePreference = new RegExp(`^\\s*${PREFERENCE}\\s*(?:[。.]|[!！]+)?\\s*$`);
const preferenceQuestion = new RegExp(`^\\s*${PREFERENCE}\\s*(?:[。.!！]\\s*)*(?:[?？]|嗎|呢)`);
const familyFact = new RegExp(`^${FAMILY}(?:住(?:在)?(?:${PLACE})|(?:可能|已經?|確定)?搬(?:去|到)(?:${PLACE}))(?:[，,](?:她喜歡散步|他喜歡散步|後來確定下週搬|後來取消了|還沒決定))?$`);
const appointment = /^明天我(?:要)?去醫院回診$/;
const direct = "(?:我)?(?:今天|現在|這次|這回)(?:先|暫時)?(?:不想|不太想|不|不要)(?:再)?(?:聊|談)(?:我(?:的)?)?(?:女兒|兒子|她|他|這個)(?:的事)?";
const join = "(?:[，,。；;]\\s*(?:但是|但|不過|可是)?|但是|但|不過|可是)";
const instructionLast = new RegExp(`^(.+?)${join}(${direct})[。！!]?$`);
const instructionFirst = new RegExp(`^(${direct})${join}(.+?)[。！!]?$`);
const boundaryCue = /(?:先不|暫時不|不想|不太想|不要|不)(?:再)?(?:聊|談|說話|講話)|(?:不要再|別(?:再)?)(?:問|追問)/g;
const storageExclusion = /(?:不要|不用|不必|別|不想)[^，,。；;！？!?\n]{0,12}(?:保存|記住|記錄|記下|儲存|留存)/g;
const excludedAddress = new RegExp(`^(${PREFERENCE})[。；;]我的住址是[^，,。；;「」『』!?！？\\n]{1,80}[，,]住址(?:不要|不用|別)(?:保存|記住|記錄|儲存)[。！!]?$`);
const twoPreferences = new RegExp(`^(${PREFERENCE})[。；;](${PREFERENCE})[。]?$`);

function unquotedText(text) {
  // Removing quotes is only for detection. It never changes persisted content.
  return text.replace(/「[^」]*」|『[^』]*』|“[^”]*”|"[^"]*"/g, "");
}

function independentSource(text) {
  if (preference.test(text) || familyFact.test(text) || appointment.test(text)) return text;
  // A preceding first-person preference is independently stated. The later
  // orphan pronoun is NOT equated with a topic mentioned afterwards.
  const match = text.match(new RegExp(`^(${PREFERENCE})[，,]她住(?:在)?(?:${PLACE})$`));
  return match?.[1] || null;
}

function projectMemorySource(userText) {
  // These bounded interrogatives are not asserted preferences or care needs.
  // Abstain before provider/fallback can reinterpret them as an established fact.
  if (preferenceQuestion.test(userText)) return { text: null, projected: true };
  // Saving exclusions concern eligibility, not conversational topic boundaries.
  // Only this explicit disjoint scope is projected; "this part" is unresolved.
  const exclusions = [...userText.matchAll(storageExclusion)];
  if (exclusions.length) {
    const allowed = exclusions.length === 1 && userText.match(excludedAddress);
    return { text: allowed ? allowed[1] : null, projected: true };
  }
  const visible = unquotedText(userText);
  const cues = [...visible.matchAll(boundaryCue)];
  if (!cues.length) {
    if (declarativePreference.test(userText)) return { text: userText, projected: false };
    // Do not let a keyword rule save every statement when eligibility differs.
    if (/[。！？!?；;\n].+/.test(userText.trim())) return { text: userText, projected: false, requiresSelection: true };
    return { text: userText, projected: false };
  }

  // Preserve a single reported/negated scope in full, including punctuation.
  // A second refusal, or a contrasting scope, is not proven to be the same speech.
  const scoped = new RegExp(`^(?:${FAMILY}(?:說|表示|提到)|我不是說)[，,:：\\s]*(?:我|她|他)?(?:今天|現在|這次|這回)?(?:先|暫時)?(?:不想|不太想|不|不要|別)(?:再)?(?:聊|談|問|追問)`);
  if (cues.length === 1 && scoped.test(userText) && !/但是|不過|可是|但|另外|而且/.test(visible)) {
    return { text: userText, projected: false };
  }
  // Preserve explicit enduring requests and the existing unscoped refusal
  // behavior. This does not interpret an unscoped refusal as permanent.
  if ((/^(?:以後|永遠)/.test(userText) && cues.length === 1 && !/今天|現在|這次|這回/.test(visible)) || /^我不聊女兒$/.test(userText)) {
    return { text: userText, projected: false };
  }

  const last = userText.match(instructionLast);
  const first = userText.match(instructionFirst);
  const candidate = last?.[1] || first?.[2];
  const text = candidate && independentSource(candidate);
  if (text) return { text, projected: true };
  // No guessed subject, deletion across reported scope, or fallback to the
  // original mixed turn. Unsupported language remains current-turn context only.
  return { text: null, projected: true };
}

function validateMemorySelection(userText, selectedText) {
  if (typeof selectedText !== "string" || !selectedText.trim()) return null;
  const selected = selectedText.trim();
  const source = projectMemorySource(userText);
  if (source.projected) return null; // handled before provider invocation
  if (!source.requiresSelection && selected === userText) return selected;
  // An exact substring alone does not prove scope: a suffix may cancel or
  // qualify it. Accept only a complete independent unit in this bounded form.
  const pair = userText.match(twoPreferences);
  if (!pair || ![pair[1], pair[2]].includes(selected)) return null;
  if (pair[1].replace(/^我不?喜歡/, "") === pair[2].replace(/^我不?喜歡/, "")) return null;
  return selected;
}

module.exports = { projectMemorySource, validateMemorySelection, isIndependentPreference: text => declarativePreference.test(text) };
