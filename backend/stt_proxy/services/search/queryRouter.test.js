const test = require("node:test");
const assert = require("node:assert/strict");
const { classifyQuery } = require("./queryRouter");

test("classifies health questions as local health tips", () => {
  assert.equal(classifyQuery("給我一個睡眠健康小知識").mode, "health_tip");
  const latestHealth = classifyQuery("最近老人運動有什麼建議？");
  assert.equal(latestHealth.mode, "health_tip");
  assert.equal(latestHealth.needsWebSearch, true);
});

test("classifies news and web-search intent", () => {
  assert.equal(classifyQuery("今天有什麼新聞？").mode, "news");
  assert.equal(classifyQuery("查一下最近科技新聞").mode, "news");
});

test("keeps companionship and stories off web search", () => {
  const lonely = classifyQuery("我今天有點孤單");
  assert.equal(lonely.mode, "companion_chat");
  assert.equal(lonely.needsWebSearch, false);

  const story = classifyQuery("說一個故事給我聽");
  assert.equal(story.mode, "story");
  assert.equal(story.storyType, "creative_story");
  assert.equal(story.needsWebSearch, false);
});

test("classifies sourced stories as web stories", () => {
  const story = classifyQuery("說一個真實故事給我聽");
  assert.equal(story.mode, "story");
  assert.equal(story.storyType, "web_story");
  assert.equal(story.needsWebSearch, true);
});
