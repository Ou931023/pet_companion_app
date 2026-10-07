const test = require("node:test");
const assert = require("node:assert/strict");

const { analyzeCompanionTurn } = require("./companion_engine");
const {
  NORMAL_VOICE_CADENCE,
  planNextStrategy,
  hasReminderIntent,
  hasMemoryRecallIntent,
  hasEventCue,
  isTiredContent,
  isAmbiguous,
  recentReplyInstruction,
} = require("./next_strategy_planner");

function analyze(transcript, extra = {}) {
  return analyzeCompanionTurn({
    userId: "demo-user",
    sessionId: "session-001",
    turnId: `turn-${transcript}`,
    petName: "咕咕",
    transcript,
    languageHint: "zh",
    recentTurns: [],
    ...extra,
  });
}

// 模板化罐頭話：回覆策略指引不應「叫 AI 一直用陪伴 / 鼓勵罐頭話」。
const TEMPLATE_PHRASES = ["一起加油", "不要難過", "別難過"];

test("情境①：『今天我跟朋友吵架了』→ 針對事件追問，不是只說會陪你", () => {
  const r = analyze("今天我跟朋友吵架了");
  assert.equal(r.nextStrategy.mode, "comfort_lightly");
  // 指引要求針對事件本身回應 / 追問，而不是只給安慰。
  assert.match(r.nextStrategy.instruction, /事|追問|後來|感覺/);
  assert.match(r.nextStrategy.instruction, /不要只給安慰|不要只安慰|不要過度安慰|不要只給安慰或鼓勵/);
  for (const phrase of TEMPLATE_PHRASES) {
    assert.ok(
      !r.nextStrategy.instruction.includes(phrase),
      `指引不應出現罐頭話「${phrase}」`,
    );
  }
});

test("情境②：『我今天好累』→ 接住就停，不直接長篇鼓勵或繼續追問", () => {
  const r = analyze("我今天好累");
  assert.equal(r.nextStrategy.mode, "comfort_lightly");
  assert.match(r.nextStrategy.instruction, /讓他休息|說完就停/);
  assert.match(r.nextStrategy.instruction, /不邀聊、不追問/);
  assert.match(r.nextStrategy.instruction, /不要.*長篇|別.*長篇|不要說教|最多/);
});

test("分享市場番茄與想聊時，可同話題觀察或邀請但不例行追問", () => {
  for (const transcript of ["今天去市場買番茄，很紅很漂亮", "我想聊聊今天去市場買菜"]) {
    const strategy = analyze(transcript).nextStrategy;
    assert.equal(strategy.mode, "normal_chat");
    assert.match(strategy.instruction, /同話題的小觀察或可拒絕的小邀請/);
    assert.match(strategy.instruction, /不必每次追問/);
    assert.match(strategy.instruction, /不把話題拉回任務/);
  }
});

test("近期問句已答或未答均不重問，承接使用者具體答案", () => {
  const recentTurns = [{ userText: "市場的番茄很紅", petReply: "你打算煮什麼呢？" }];
  const answered = analyze("我要煮番茄蛋湯", { recentTurns }).nextStrategy;
  assert.match(answered.instruction, /最近使用者說過「市場的番茄很紅」/);
  assert.match(answered.instruction, /已回答就承接答案，不再重問/);
  assert.match(answered.instruction, /未回答或拒絕也不要重問或催答/);
  const unanswered = analyze("我只是想說今天市場很熱鬧", { recentTurns }).nextStrategy;
  assert.match(unanswered.instruction, /未回答或拒絕也不要重問或催答/);
});

test("短嗯喔僅在近期普通敘事聊天接應，不批准動作且不注入記憶", () => {
  const recentTurns = [{ userText: "今天去市場買番茄", petReply: "紅紅的番茄，市場看起來很熱鬧。", emotionTag: "happy" }];
  for (const transcript of ["嗯", "嗯嗯。", "喔", "哦…"]) {
    const strategy = analyze(transcript, { recentTurns, retrievedMemories: [{ content: "synthetic-private-health" }] }).nextStrategy;
    assert.equal(strategy.mode, "normal_chat", transcript);
    assert.match(strategy.instruction, /不要求他重說/);
    assert.match(strategy.instruction, /不得把接應視為任何動作的批准/);
    assert.match(strategy.instruction, /不加新問題或話題/);
    assert.doesNotMatch(strategy.instruction, /synthetic-private-health/);
  }
  for (const transcript of ["嗯", "喔", "那個", "嗯那個", "蛤", "啊"]) {
    assert.equal(analyze(transcript).nextStrategy.mode, "clarify", transcript);
  }
  assert.equal(analyze("那個", { recentTurns }).nextStrategy.mode, "clarify");
});

test("工具、敏感、問句及欠缺內容脈絡不將短語當聊天批准", () => {
  const ordinary = { userText: "今天去市場買菜", petReply: "市場很熱鬧。" };
  const blocked = [
    [{ userText: "提醒我八點吃藥", petReply: "要設定嗎？" }],
    [{ userText: "市場番茄", petReply: "可以幫你通知女兒。" }],
    [{ userText: "今天去市場", petReply: "番茄要煮什麼？" }],
    [{ userText: "今天去市場", petReply: "要煮什麼呢。" }],
    [{ userText: "今天去公園很孤單", petReply: "慢慢說。" }],
    [{ userText: "今天去市場", petReply: "已設定提醒。" }],
    [{ userText: "今天去市場", petReply: "市場很熱鬧。", emotionTag: "sad" }],
    [{ userText: "今天去市場", petReply: "市場很熱鬧。", nextStrategy: { mode: "tool_action" } }],
    [{ petReply: "市場很熱鬧。" }],
    [{ userText: "今天去市場", petReply: "" }],
    [ordinary, { userText: "幫我買商城飼料", petReply: "請確認商品數量。" }],
    [ordinary, { userText: "我生病了", petReply: "慢慢休息。" }],
  ];
  for (const recentTurns of blocked) {
    assert.equal(analyze("嗯", { recentTurns }).nextStrategy.mode, "clarify", JSON.stringify(recentTurns));
  }
});

test("累、拒絕和台語想安靜不邀聊、不注入敏感記憶，安全工具仍優先", () => {
  for (const transcript of ["我今天好累", "好無聊但我好累", "今天吵架了，好累", "好無聊但我不想聊天", "我想安靜", "今仔日毋想閣講話"]) {
    const strategy = analyze(transcript, { retrievedMemories: [{ content: "synthetic-family-conflict" }] }).nextStrategy;
    assert.match(strategy.instruction, /不邀聊、不追問|不提新話題、不問問題、不邀請活動/);
    assert.doesNotMatch(strategy.instruction, /synthetic-family-conflict/);
  }
  for (const riskLevel of ["high", "urgent"]) {
    const strategy = planNextStrategy({ transcript: "嗯", recentTurns: [{ userText: "今天去市場", petReply: "很熱鬧。" }], safety: { riskLevel } });
    assert.equal(strategy.mode, "safety_check");
  }
  const tool = analyze("好累，提醒我八點吃藥").nextStrategy;
  assert.equal(tool.mode, "tool_action");
  assert.match(tool.instruction, /不得提前聲稱成功/);
  assert.equal(analyze("你還記得我上次說很累嗎").nextStrategy.mode, "memory_recall");
  assert.equal(planNextStrategy({ transcript: "很累的時候為什麼想休息？", emotion: "neutral", safety: { riskLevel: "low" }, searchIntent: { needsSearch: true } }).mode, "knowledge_response");
});

test("台語接應保留語言指引；無聊提供一個可拒絕具體選項而非功能清單", () => {
  const taigi = analyze("嗯", { languageHint: "taigi", recentTurns: [{ userText: "今仔日去市場買番茄", petReply: "市場真鬧熱。" }] }).nextStrategy;
  assert.equal(taigi.mode, "normal_chat");
  assert.match(taigi.instruction, /以台語為主/);
  const bored = analyze("好無聊").nextStrategy;
  assert.match(bored.instruction, /一個低壓力、可以拒絕/);
  assert.match(bored.instruction, /不反問他想聊什麼、不列功能清單/);
  assert.match(bored.instruction, /不因沉默繼續說/);
});

test("high／urgent 安全優先但不附加敏感回憶，安靜要求也不改變風險模式", () => {
  for (const riskLevel of ["high", "urgent"]) {
    const strategy = planNextStrategy({
      transcript: "我想安靜，不要提以前的事",
      safety: { riskLevel },
      retrievedMemories: [{ content: "synthetic-sensitive-family-history" }],
    });
    assert.equal(strategy.mode, "safety_check");
    assert.doesNotMatch(strategy.instruction, /synthetic-sensitive-family-history|可自然參考使用者過去/);
    assert.match(strategy.instruction, /不要做醫療診斷/);
    if (riskLevel === "urgent") assert.match(strategy.instruction, /立刻聯絡家人/);
  }
});

test("合成回合6與台語活動拒絕停止邀請，不帶入敏感記憶；引用查詢不當拒絕", () => {
  for (const transcript of ["不要建議活動了", "我今天沒事做，但不要建議活動", "毋免閣建議活動", "毋想做活動", "莫閣推薦話題"]) {
    const strategy = analyze(transcript, {
      languageHint: "taigi",
      retrievedMemories: [{ content: "synthetic-private-family-context" }],
    }).nextStrategy;
    assert.equal(strategy.mode, "normal_chat", transcript);
    assert.match(strategy.instruction, /使用者明確拒絕話題或活動建議/);
    assert.match(strategy.instruction, /不提話題或活動、不追問/);
    assert.doesNotMatch(strategy.instruction, /synthetic-private-family-context|小邀請/);
  }
  for (const transcript of ["『不要建議活動了』是什麼意思？", "「毋免閣建議活動」是什麼意思？", "女兒說「不要建議活動了」，是什麼意思？"]) {
    const strategy = planNextStrategy({ transcript, safety: { riskLevel: "low" } });
    assert.equal(strategy.mode, "answer_directly", transcript);
    assert.doesNotMatch(strategy.instruction, /使用者明確拒絕話題或活動建議|使用者現在不想聊天/);
  }
  assert.equal(analyze("取消喝水提醒").nextStrategy.mode, "tool_action");
});

test("情境③：『提醒我晚上八點吃藥』→ 走 tool_action 交給工具，不只聊天", () => {
  const r = analyze("提醒我晚上八點吃藥");
  assert.equal(r.nextStrategy.mode, "tool_action");
  assert.match(r.nextStrategy.instruction, /提醒|處理|記下/);
  assert.match(r.nextStrategy.instruction, /不要只.*閒聊|工具|功能接手/);
});

test("情境④：『你還記得我上次說我兒子要回來嗎』→ 走 memory_recall 引用記憶", () => {
  const r = analyze("你還記得我上次說我兒子要回來嗎");
  assert.equal(r.nextStrategy.mode, "memory_recall");
  // 自然引用、且不可說出「記憶 / 資料庫」字眼。
  assert.match(r.nextStrategy.instruction, /記得|先前|之前|回想|接話/);
  assert.match(r.nextStrategy.instruction, /不要說出/);
});

test("情境⑤：語句不清楚（只有語助詞）→ 走 clarify 簡短確認，不硬猜", () => {
  const r = analyze("那個…那個就是…齁");
  assert.equal(r.nextStrategy.mode, "clarify");
  assert.match(r.nextStrategy.instruction, /再說一次|說清楚|覆述/);
  assert.match(r.nextStrategy.instruction, /不要硬猜|不要假裝/);
});

test("高風險健康內容優先於一般聊天：『我胸口很痛』→ safety_check", () => {
  const r = analyze("我胸口很痛");
  assert.equal(r.safety.riskLevel, "urgent");
  assert.equal(r.nextStrategy.mode, "safety_check");
  assert.match(r.nextStrategy.instruction, /安全|聯絡|緊急|醫療/);
  // 不可用醫療診斷語氣（指引明確要求「不要做醫療診斷」）。
  assert.match(r.nextStrategy.instruction, /不要做醫療診斷/);
});

test("強烈無助（high）也走 safety_check，但語氣不診斷", () => {
  const r = analyze("每天都好難過，覺得沒有人需要我");
  assert.equal(r.safety.riskLevel, "high");
  assert.equal(r.nextStrategy.mode, "safety_check");
  assert.match(r.nextStrategy.instruction, /先.*接住|認真在聽|確認/);
  assert.match(r.nextStrategy.instruction, /不要做醫療診斷|不要說教/);
});

test("明確問句（低風險、無情緒）→ answer_directly 直接回答", () => {
  const r = analyze("現在幾點");
  assert.equal(r.nextStrategy.mode, "answer_directly");
  assert.match(r.nextStrategy.instruction, /直接|簡短/);
});

test("一般日常閒聊 → normal_chat，且不堆陪伴罐頭話", () => {
  const r = analyze("今天太陽很好");
  assert.equal(r.nextStrategy.mode, "normal_chat");
  assert.match(r.nextStrategy.instruction, /順著|自然接話|最多問一個問題/);
  assert.match(r.nextStrategy.instruction, /不要每次都用陪伴|罐頭話/);
});

test("知識型問題維持既有 knowledge_response（不被新流程吃掉）", () => {
  const r = analyze("跟我說健康小知識");
  assert.equal(r.needsSearch, true);
  assert.equal(r.nextStrategy.mode, "knowledge_response");
});

test("情境⑥：『我不想活了』→ emotional_risk，走安全流程、非一般聊天", () => {
  const r = analyze("我不想活了");
  assert.equal(r.safety.riskLevel, "urgent");
  assert.equal(r.safety.needsHumanSupport, true);
  assert.equal(r.nextStrategy.mode, "safety_check");
  assert.notEqual(r.nextStrategy.mode, "normal_chat");
});

test("回覆指引不堆過度模板化陪伴句（我會陪你 / 不要難過 / 一起加油）", () => {
  // 各輸入類型代表句：emotion / event / request / small_talk / memory /
  // health_risk / emotional_risk / unclear。
  const inputs = [
    "今天我跟朋友吵架了",
    "我今天好累",
    "提醒我晚上八點吃藥",
    "今天太陽很好",
    "你還記得我上次說的事嗎",
    "我胸口很痛",
    "我不想活了",
    "那個…就是…齁",
    "我剛吃飽",
    "我很煩",
  ];
  const banned = ["我會陪你", "不要難過", "別難過", "一起加油"];
  for (const text of inputs) {
    const instruction = analyze(text).nextStrategy.instruction;
    for (const phrase of banned) {
      assert.ok(
        !instruction.includes(phrase),
        `「${text}」的指引不應含模板化陪伴句「${phrase}」：${instruction}`,
      );
    }
  }
});

// ---- 意圖偵測純函式（邊界）----

test("hasReminderIntent / hasMemoryRecallIntent / hasEventCue 基本判斷", () => {
  assert.ok(hasReminderIntent("提醒我吃藥", "daily_chat"));
  assert.ok(!hasReminderIntent("隨便講", "reminder_support"));
  assert.ok(!hasReminderIntent("今天天氣不錯", "daily_chat"));

  assert.ok(hasMemoryRecallIntent("你還記得我兒子嗎"));
  assert.ok(hasMemoryRecallIntent("我上次說的那件事"));
  assert.ok(!hasMemoryRecallIntent("我今天很開心"));

  assert.ok(hasEventCue("我跟鄰居吵架"));
  assert.ok(!hasEventCue("天氣很好"));
});

test("isTiredContent / isAmbiguous 邊界", () => {
  assert.ok(isTiredContent("好累", "neutral"));
  assert.ok(isTiredContent("還好", "tired"));
  assert.ok(!isTiredContent("我很開心", "happy"));

  assert.ok(isAmbiguous("那個…就是…"));
  assert.ok(isAmbiguous("嗯嗯嗯"));
  assert.ok(!isAmbiguous("我今天去公園散步"));
  assert.ok(!isAmbiguous("")); // 空字串交由 engine 上游處理
});

test("planNextStrategy 永遠回傳 {mode, instruction} 兩個欄位（schema 不變）", () => {
  const r = planNextStrategy({
    emotion: "neutral",
    companionNeed: "daily_chat",
    replyStrategy: "normal_chat",
    safety: { riskLevel: "low", needsHumanSupport: false },
    transcript: "今天太陽很好",
  });
  assert.deepEqual(Object.keys(r), ["mode", "instruction"]);
  assert.ok(r.instruction.length > 0);
});

test("台語 languageHint 仍附上自然台語與溫和追問指引", () => {
  const r = analyze("睡不太著", { languageHint: "taigi" });
  assert.match(r.nextStrategy.instruction, /台灣長者自然聽得懂/);
  assert.match(r.nextStrategy.instruction, /溫和追問/);
});

test("CR-0105D 中文／台語／混合語言一般語音共用 1–3 句節奏", () => {
  const corpus = [
    { text: "今天太陽很好", languageHint: "zh" },
    { text: "我今天有點難過", languageHint: "zh" },
    { text: "今仔日天氣真好", languageHint: "taigi" },
    { text: "我昨暝袂好睏，今仔日足累", languageHint: "taigi" },
    { text: "提醒我暗時八點食藥", languageHint: "taigi" },
    { text: "你還記得我頂擺講的代誌嗎", languageHint: "taigi" },
  ];

  for (const item of corpus) {
    const result = analyze(item.text, { languageHint: item.languageHint });
    assert.notEqual(result.safety.riskLevel, "urgent", item.text);
    assert.ok(
      result.nextStrategy.instruction.includes(NORMAL_VOICE_CADENCE),
      `「${item.text}」缺少一般語音節奏：${result.nextStrategy.instruction}`,
    );
    assert.match(result.nextStrategy.instruction, /1–3 句/);
    assert.match(result.nextStrategy.instruction, /第一句先接住情緒/);
    assert.match(result.nextStrategy.instruction, /最多一個問題/);
    assert.match(result.nextStrategy.instruction, /不要在同一問句塞入多題/);
    assert.match(result.nextStrategy.instruction, /避免連續使用/);
  }
});

test("urgent 保留完整安全提醒，不套一般 1–3 句裁切", () => {
  const result = analyze("我胸口很痛，喘不過氣");

  assert.equal(result.safety.riskLevel, "urgent");
  assert.equal(result.nextStrategy.mode, "safety_check");
  assert.doesNotMatch(result.nextStrategy.instruction, /1–3 句/);
  assert.match(result.nextStrategy.instruction, /接住/);
  assert.match(result.nextStrategy.instruction, /安不安全/);
  assert.match(result.nextStrategy.instruction, /立刻聯絡家人/);
  assert.match(result.nextStrategy.instruction, /緊急 \/ 醫療電話/);
});

test("最近寵物回覆會進入避重指引，空值與重複內容會被清理", () => {
  const hint = recentReplyInstruction([
    { petReply: "聽起來你今天有點累，我在這裡陪你。" },
    { petReply: "聽起來你今天有點累，我在這裡陪你。" },
    { petReply: "那我們慢慢說，今天發生什麼事了？" },
    { petReply: "" },
  ]);

  assert.match(hint, /最近幾次已經回過/);
  assert.match(hint, /聽起來你今天有點累/);
  assert.match(hint, /那我們慢慢說/);
  assert.match(hint, /不要逐字重複上述開頭或完整句子/);
  assert.equal((hint.match(/聽起來你今天有點累/g) || []).length, 1);
});

test("一般情境帶最近回覆避重，urgent 不讓去重干擾必要安全話術", () => {
  const recentTurns = [
    { userText: "我好累", petReply: "我在這裡陪你，慢慢說。" },
  ];
  const ordinary = analyze("今天還是很累", { recentTurns });
  assert.match(ordinary.nextStrategy.instruction, /最近幾次已經回過/);
  assert.match(ordinary.nextStrategy.instruction, /不要重新自我介紹/);

  const urgent = analyze("我胸口很痛，喘不過氣", { recentTurns });
  assert.equal(urgent.nextStrategy.mode, "safety_check");
  assert.doesNotMatch(urgent.nextStrategy.instruction, /最近幾次已經回過/);
  assert.match(urgent.nextStrategy.instruction, /立刻聯絡家人/);
});

test("CR-0110 B: mentions, denials, reports, quotes and hypotheticals do not authorize reminders", () => {
  const inputs = [
    "我今天有喝水", "我已吃藥", "今天回診", "我量血壓了",
    "不用提醒我喝水", "不要幫我設鬧鐘", "我不需要提醒", "我沒有要提醒",
    "女兒提醒我吃藥了", "醫生說提醒我喝水", "你提醒過我了", "提醒我吃藥了嗎",
    "提醒是什麼意思", "要怎麼設定鬧鐘", "喝水有什麼好處？",
    "如果提醒我喝水會怎樣", "假如明天提醒我吃藥", "例如提醒我喝水",
    "他說「提醒我喝水」", "『提醒我吃藥』", "取消了喝水提醒", "我已經取消鬧鐘",
    "如果可以，提醒我明天八點吃藥", "我不是說，提醒我喝水",
    "假如明天下雨，提醒我帶傘", "例如，提醒我喝水", "女兒說，提醒我喝水",
    "提醒我喝水，不用了", "提醒我喝水，不要提醒了", "幫我設鬧鐘，取消吧",
    "提醒我喝水，不要真的設定", "提醒我八點吃藥，算了不用提醒了",
    "我明天八點要吃藥", "不用幫我提醒明天八點吃藥", "女兒幫我提醒明天八點吃藥",
    "你幫我提醒過吃藥了", "他說「幫我提醒明天八點吃藥」", "幫我提醒明天八點吃藥，不用了",
  ];
  for (const transcript of inputs) {
    assert.equal(hasReminderIntent(transcript, "reminder_support"), false, transcript);
    const strategy = planNextStrategy({ transcript, companionNeed: "reminder_support", safety: { riskLevel: "low" } });
    assert.notEqual(strategy.mode, "tool_action", transcript);
    assert.notEqual(analyze(transcript).nextStrategy.mode, "tool_action", `engine: ${transcript}`);
  }
  assert.equal(planNextStrategy({ transcript: "我今天有喝水", emotion: "neutral", safety: { riskLevel: "low" } }).mode, "normal_chat");
});

test("CR-0110 B: explicit requests retain tools, missing details need confirmation, cancellation is not creation", () => {
  for (const transcript of ["提醒我晚上八點吃藥", "明天早上提醒我喝水", "幫我設鬧鐘", "請幫我設定八點的鬧鐘", "你可以提醒我嗎", "提醒我", "不用提醒我喝水，請提醒我吃藥", "今天回診，請提醒我晚上吃藥", "不要跟我說話，提醒我八點吃藥", "我不是說提醒我喝水，但現在請提醒我吃藥", "如果明天下雨就不出門。請提醒我晚上吃藥", "幫我提醒明天八點吃藥", "請幫我提醒明天八點吃藥", "麻煩你替我提醒晚上喝水"]) {
    assert.equal(hasReminderIntent(transcript), true, transcript);
    const strategy = analyze(transcript).nextStrategy;
    assert.equal(strategy.mode, "tool_action", transcript);
    assert.match(strategy.instruction, /缺少時間或內容時最多確認一個必要重點/);
    assert.match(strategy.instruction, /不得提前聲稱成功/);
  }
  for (const transcript of ["取消喝水提醒", "幫我取消明天的鬧鐘", "請關掉鬧鐘"]) {
    assert.equal(hasReminderIntent(transcript), false, transcript);
    const strategy = analyze(transcript).nextStrategy;
    assert.equal(strategy.mode, "tool_action", transcript);
    assert.match(strategy.instruction, /取消既有提醒，不是新增提醒/);
    assert.match(strategy.instruction, /不支援時坦白說明/);
  }
});

test("CR-0110 B: explicit no-topic turns offer one optional topic without adding a mode", () => {
  const recentTurns = [{ petReply: "聊聊你喜歡的菜好嗎？" }];
  for (const transcript of ["我不知道要聊什麼", "不知道要說什麼", "想不到聊什麼", "好無聊", "我沒事做", "我不知道要做什麼"]) {
    const strategy = analyze(transcript, { recentTurns }).nextStrategy;
    assert.equal(strategy.mode, "normal_chat", transcript);
    assert.deepEqual(Object.keys(strategy), ["mode", "instruction"]);
    assert.match(strategy.instruction, /先用短句接住當下感受/);
    assert.match(strategy.instruction, /一個低壓力、可以拒絕/);
    assert.match(strategy.instruction, /最多問一個問題/);
    assert.match(strategy.instruction, /不反問他想聊什麼/);
    assert.match(strategy.instruction, /不重推最近已提過或被拒絕/);
    assert.match(strategy.instruction, /聊聊你喜歡的菜/);
    assert.match(strategy.instruction, /不因沉默繼續說/);
  }
});

test("CR-0110 B: ordinary chat, silence, refusal and safety never get the no-topic instruction", () => {
  for (const transcript of ["今天天氣很好", "", "   ", "我不無聊", "我不是沒事做", "我不是不知道要聊什麼", "他說「好無聊」", "『我不知道要聊什麼』是什麼意思", "他說\"沒事做\"", "她說“我沒有話題”", "女兒說好無聊", "我今天沒事做，但不要建議活動"]) {
    const strategy = planNextStrategy({ transcript, safety: { riskLevel: "low" } });
    assert.doesNotMatch(strategy.instruction, /使用者明確表示無話題或無聊/);
  }
  const quiet = analyze("好無聊，但我不想聊天", {
    retrievedMemories: [{ content: "喜歡散步" }],
  }).nextStrategy;
  assert.equal(quiet.mode, "normal_chat");
  assert.match(quiet.instruction, /不提新話題、不問問題、不邀請活動/);
  assert.doesNotMatch(quiet.instruction, /喜歡散步|使用者明確表示無話題或無聊/);
  assert.doesNotMatch(analyze("我不是不想聊天").nextStrategy.instruction, /使用者現在不想聊天/);
  const noSuggestions = analyze("我今天沒事做，但不要建議活動").nextStrategy;
  assert.match(noSuggestions.instruction, /使用者明確拒絕話題或活動建議/);
  assert.match(noSuggestions.instruction, /不提話題或活動、不追問/);
  assert.ok(!noSuggestions.instruction.includes(NORMAL_VOICE_CADENCE));
  for (const riskLevel of ["high", "urgent"]) {
    const strategy = planNextStrategy({ transcript: "好無聊，不想聊天，提醒我吃藥", safety: { riskLevel } });
    assert.equal(strategy.mode, "safety_check");
    assert.doesNotMatch(strategy.instruction, /使用者明確表示無話題或無聊/);
  }
});
