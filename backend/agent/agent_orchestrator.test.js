const test = require("node:test");
const assert = require("node:assert/strict");
const { routeAgentTool } = require("./agent_orchestrator");
const { buildSafeIntent } = require("./tool_policy");

test("phone call routes to high risk dialer with confirmation", () => {
  const result = routeAgentTool({ userText: "幫我打給女兒" });
  assert.equal(result.hasToolIntent, true);
  assert.equal(result.intent.toolName, "open_phone_dialer");
  assert.equal(result.intent.riskLevel, "high");
  assert.equal(result.intent.requiresConfirmation, true);
});

test("email routes to medium risk draft with confirmation", () => {
  const result = routeAgentTool({ userText: "幫我寄 email 給家人說我今天有點累" });
  assert.equal(result.intent.toolName, "create_email_draft");
  assert.equal(result.intent.riskLevel, "medium");
  assert.equal(result.intent.requiresConfirmation, true);
});

test("music routes to low risk play music", () => {
  const result = routeAgentTool({ userText: "幫我播放放鬆音樂" });
  assert.equal(result.intent.toolName, "play_music");
  assert.equal(result.intent.riskLevel, "low");
  assert.equal(result.intent.requiresConfirmation, false);
});

test("broad music requests ask preference instead of auto-playing", () => {
  for (const text of ["我想聽音樂", "放歌予我聽", "播歌", "幫我播放音樂"]) {
    const result = routeAgentTool({ userText: text });
    assert.equal(result.hasToolIntent, false, `「${text}」應交給寵物先追問偏好`);
  }
});

test("reminder routes to low risk reminder, executes directly (no confirmation)", () => {
  const result = routeAgentTool({ userText: "提醒我晚上八點吃藥" });
  assert.equal(result.intent.toolName, "create_reminder");
  assert.equal(result.intent.riskLevel, "low");
  assert.equal(result.intent.requiresConfirmation, false);
});

test("make_call routes to high risk dialer needing confirmation", () => {
  const result = routeAgentTool({ userText: "幫我打給女兒" });
  assert.equal(result.intent.toolName, "open_phone_dialer");
  assert.equal(result.intent.requiresConfirmation, true);
  assert.equal(result.intent.arguments.contactName, "女兒");
});

test("send_message extracts recipient + body and needs confirmation", () => {
  const result = routeAgentTool({ userText: "幫我跟兒子說我今天很好" });
  assert.equal(result.intent.toolName, "send_message");
  assert.equal(result.intent.riskLevel, "high");
  assert.equal(result.intent.requiresConfirmation, true);
  assert.equal(result.intent.arguments.recipient, "兒子");
  assert.equal(result.intent.arguments.body, "我今天很好");
});

test("tell_story is low risk and executes directly", () => {
  const result = routeAgentTool({ userText: "說一個故事給我聽" });
  assert.equal(result.intent.toolName, "tell_story");
  assert.equal(result.intent.requiresConfirmation, false);
});

test("save_memory is low risk and executes directly", () => {
  const result = routeAgentTool({ userText: "幫我記住我女兒週末會回來" });
  assert.equal(result.intent.toolName, "save_memory");
  assert.equal(result.intent.requiresConfirmation, false);
});

test("navigate to game is low risk with natural reply", () => {
  const result = routeAgentTool({ userText: "我要去玩遊戲" });
  assert.equal(result.intent.toolName, "open_app_route");
  assert.equal(result.intent.arguments.route, "/puzzle");
  assert.equal(result.intent.requiresConfirmation, false);
  assert.match(result.intent.userFacingMessage, /帶你去玩遊戲/);
});

test("logout / delete_memory / purchase / notify_caregiver are high risk + confirm", () => {
  const cases = [
    { text: "我要登出", tool: "logout" },
    { text: "幫我刪掉這個記憶", tool: "delete_memory" },
    { text: "我想買新的寵物造型", tool: "purchase_pet_skin" },
    { text: "通知照護員我今天不太舒服", tool: "notify_caregiver" },
  ];
  for (const c of cases) {
    const result = routeAgentTool({ userText: c.text });
    assert.equal(result.intent.toolName, c.tool, `「${c.text}」應走 ${c.tool}`);
    assert.equal(result.intent.riskLevel, "high", `${c.tool} 應為 high`);
    assert.equal(result.intent.requiresConfirmation, true, `${c.tool} 應需確認`);
  }
});

test("ambiguous / pure chat returns no tool intent (let companion handle)", () => {
  for (const text of ["今天天氣真好", "那個…就是…", "我有點累"]) {
    const result = routeAgentTool({ userText: text });
    assert.equal(result.hasToolIntent, false, `「${text}」不應觸發工具`);
  }
});

test("fraud news routes to trusted search", () => {
  const result = routeAgentTool({ userText: "幫我查今天的防詐騙新聞" });
  assert.equal(result.intent.toolName, "search_trusted_info");
  assert.equal(result.intent.riskLevel, "low");
});

test("mixed Mandarin/Taigi voice commands route to real tools", () => {
  const cases = [
    {
      text: "放台語老歌予我聽",
      toolName: "play_music",
      argument: ["query", "台語老歌 放鬆"],
    },
    {
      text: "八點記咧提醒我食藥",
      toolName: "create_reminder",
      argument: ["text", "八點記咧提醒我食藥"],
    },
    {
      text: "共兒子講我今仔日很好",
      toolName: "send_message",
      argument: ["recipient", "兒子"],
    },
    {
      text: "講古給我聽",
      toolName: "tell_story",
    },
    {
      text: "你愛記得我喜歡散步",
      toolName: "save_memory",
    },
    {
      text: "你有記得我女兒啥時欲回來嗎",
      toolName: "retrieve_memory",
    },
  ];

  for (const c of cases) {
    const result = routeAgentTool({ userText: c.text });
    assert.equal(result.hasToolIntent, true, `「${c.text}」應觸發工具`);
    assert.equal(result.intent.toolName, c.toolName, `「${c.text}」工具不符`);
    if (c.argument) {
      const [key, expected] = c.argument;
      assert.equal(result.intent.arguments[key], expected);
    }
  }
});

test("broad Taigi news requests ask preference instead of searching", () => {
  for (const text of ["今仔日有啥新聞", "有啥物新聞", "新聞予我聽"]) {
    const result = routeAgentTool({ userText: text });
    assert.equal(result.hasToolIntent, false, `「${text}」應交給寵物先追問新聞類型`);
  }
});

test("specific Taigi news requests route to trusted search", () => {
  for (const text of ["今仔日有啥防詐新聞", "嘉義地方新聞予我聽", "健康新聞有啥物"]) {
    const result = routeAgentTool({ userText: text });
    assert.equal(result.hasToolIntent, true, `「${text}」應觸發搜尋`);
    assert.equal(result.intent.toolName, "search_trusted_info");
    assert.equal(result.intent.arguments.query, text);
  }
});

test("Taigi caregiver notification is not confused with family message", () => {
  const notify = routeAgentTool({ userText: "共照護員講我今仔日不太舒服" });
  assert.equal(notify.intent.toolName, "notify_caregiver");
  assert.equal(notify.intent.requiresConfirmation, true);

  const message = routeAgentTool({ userText: "共家人講我今仔日很好" });
  assert.equal(message.intent.toolName, "send_message");
  assert.equal(message.intent.arguments.recipient, "家人");
  assert.equal(message.intent.arguments.body, "我今仔日很好");
});

test("assistant navigation covers care tasks, photo album, alerts, and puzzle", () => {
  const cases = [
    ["帶我去看今天的照護任務", "/daily-care-tasks"],
    ["我要做拍照驗證", "/daily-care-tasks"],
    ["打開相簿看照片", "/album"],
    ["我要看關心紀錄", "/care-alerts"],
    ["帶我去玩拼圖", "/puzzle"],
  ];

  for (const [text, route] of cases) {
    const result = routeAgentTool({ userText: text });
    assert.equal(result.intent.toolName, "open_app_route", `「${text}」應導頁`);
    assert.equal(result.intent.arguments.route, route);
    assert.equal(result.intent.requiresConfirmation, false);
  }
});

test("unknown tools are rejected by policy", () => {
  const result = buildSafeIntent({ toolName: "delete_everything", arguments: {} });
  assert.equal(result.ok, false);
  assert.equal(result.reason, "unknown_tool");
});
