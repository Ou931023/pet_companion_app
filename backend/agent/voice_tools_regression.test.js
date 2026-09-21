const test = require("node:test");
const assert = require("node:assert/strict");
const { routeAgentTool } = require("./agent_orchestrator");
const { classifyAgentIntent } = require("./agent_intent");
const { buildSafeIntent } = require("./tool_policy");

test("specific artists and titles retain their words instead of becoming playlists", () => {
  for (const [text, query] of [
    ["我想聽周杰倫", "周杰倫"],
    ["播放望春風", "望春風"],
    ["幫我播放江蕙的台語歌", "江蕙的台語歌"],
    ["幫我播放聽媽媽的話", "聽媽媽的話"],
    ["播放陳奕迅的放", "陳奕迅的放"],
    ["我欲聽蔡琴的老歌", "蔡琴的老歌"],
    ["播放Taylor Swift Love Story", "Taylor Swift Love Story"],
    ["放雨夜花予我聽", "雨夜花"],
    ["幫我搜尋周杰倫的歌", "周杰倫的歌"],
    ["幫我在 YouTube 搜尋江蕙的歌", "江蕙的歌"],
    ["播放周杰倫，今天我和家人吵架", "周杰倫"],
  ]) {
    const result = routeAgentTool({ userText: text });
    assert.equal(result.intent?.toolName, "play_music", text);
    assert.equal(result.intent.arguments.query, query, text);
    assert.doesNotMatch(result.intent.userFacingMessage, /播放.*了|已播放/);
  }
});

test("preferences, refusals, generic music and spoken content do not auto-play", () => {
  for (const userText of ["不要播放周杰倫的歌", "我喜歡聽台語歌", "幫我記住我喜歡聽老歌", "放歌", "我想聽音樂", "我想聽故事", "我想聽你說話", "我聽說今天會下雨"]) {
    assert.notEqual(routeAgentTool({ userText }).intent?.toolName, "play_music", userText);
  }
});

test("virtual catalog requests are pending high risk intents, never paid orders", () => {
  for (const [text, id, quantity] of [["幫我買小餅乾", "cookie", 1], ["我要買兩個毛線球", "yarn_ball", 2], ["買3本故事書", "story_book", 3], ["買音樂盒", "music_box", 1]]) {
    const result = routeAgentTool({ userText: text });
    assert.equal(result.intent?.toolName, "purchase_shop_item", text);
    assert.equal(result.intent.arguments.itemId, id);
    assert.equal(result.intent.arguments.quantity, quantity);
    assert.equal(result.intent.requiresConfirmation, true);
    assert.equal(result.intent.riskLevel, "high");
    assert.equal(result.intent.status, "pending");
    assert.equal(result.intent.arguments.price, undefined);
    assert.match(result.intent.userFacingMessage, /金幣/);
    assert.doesNotMatch(result.intent.userFacingMessage, /買好了|已付款|已下單/);
    assert.equal(classifyAgentIntent({ userText: text }).intent, "purchase_shop_item");
  }
});

test("unknown, compound, negated and out-of-range orders cannot create purchase intents", () => {
  for (const userText of ["買輪椅", "買音樂專輯", "買小餅乾和牛奶", "不要買小餅乾", "我昨天買小餅乾", "買0個小餅乾", "買100個小餅乾", "買十幾個小餅乾", "買小餅乾寄到我家", "確認購買"]) {
    assert.notEqual(routeAgentTool({ userText }).intent?.toolName, "purchase_shop_item", userText);
  }
});

test("virtual purchase policy cannot be downgraded or carry a model price/payment URL", () => {
  assert.equal(buildSafeIntent({ toolName: "purchase_shop_item", riskLevel: "low" }).ok, false);
  const result = buildSafeIntent({ toolName: "purchase_shop_item", requiresConfirmation: false,
    arguments: { itemId: "cookie", itemName: "小餅乾", quantity: 1, price: 0, url: "https://example.com" } });
  assert.equal(result.intent.requiresConfirmation, true);
  assert.deepEqual(result.intent.arguments, { itemId: "cookie", itemName: "小餅乾", quantity: 1 });
  for (const args of [{}, { itemId: "wheelchair", itemName: "輪椅", quantity: 1 },
    { itemId: "cookie", itemName: "小餅乾", quantity: -1 },
    { itemId: "cookie", itemName: "輪椅", quantity: 1 }]) {
    assert.equal(buildSafeIntent({ toolName: "purchase_shop_item", arguments: args }).ok, false);
  }
});
