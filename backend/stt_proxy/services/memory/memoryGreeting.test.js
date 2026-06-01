const test = require("node:test");
const assert = require("node:assert/strict");

const {
  extractMemoryContent,
  isLowQualityGreetingMemory,
  greetingFromMemory,
  pickGreetingMemory,
} = require("./memoryContextService");

// SECTION 06/C：首頁開場絕對不能出現的工程感 / 標籤語句。
const BANNED = [
  "使用者提到", "根據記憶", "記憶資料", "系統", "分析", "情緒支持", "風險",
  "標籤", "metadata", "API", "JSON", "database", "payload", "toolName",
  "pgvector", "fallback", "可能需要",
];
function assertNoBanned(text) {
  assert.equal(typeof text, "string");
  assert.ok(text.trim().length > 0, "greeting 不可為空");
  for (const w of BANNED) {
    assert.ok(!text.includes(w), `greeting 不應出現「${w}」，實際：${text}`);
  }
}

const GENTLE = [
  "今天也想陪你慢慢聊聊。你現在心情還好嗎？",
  "我在這裡陪你，今天想先聊聊什麼？",
  "今天想輕鬆聊聊，還是先休息一下？",
];

// --- 低品質記憶（不可進入首頁開場） ---
const lowAllOfIt = {
  id: "m1", memoryType: "emotion_event", importance: 4, isActive: true,
  memoryText: "使用者提到「所有的。」，可能需要情緒支持。",
  memorySummary: "使用者提到「所有的。」，可能需要情緒支持。",
};
const fillerHmm = { id: "m2", memoryType: "emotion", importance: 3, isActive: true, memoryText: "嗯", memorySummary: "嗯" };
const fillerOk = { id: "m3", memoryType: "routine", importance: 3, isActive: true, memoryText: "好的", memorySummary: "好的" };
const fillerDontKnow = { id: "m4", memoryType: "emotion", importance: 3, isActive: true, memoryText: "不知道", memorySummary: "不知道" };
const labelOnly = {
  id: "m5", memoryType: "emotion_event", importance: 4, isActive: true,
  memoryText: "需要情緒支持", memorySummary: "使用者提到「需要情緒支持」，可能需要情緒支持。",
};

// --- 高品質記憶 ---
const prefMemory = {
  id: "p1", memoryType: "preference", importance: 3, isActive: true, confidence: 0.7,
  memoryText: "喜歡聽老歌", memorySummary: "使用者偏好：喜歡聽老歌",
};
const familyMemory = {
  id: "f1", memoryType: "relationship", importance: 4, isActive: true, confidence: 0.75,
  memoryText: "女兒週末會回來看我", memorySummary: "女兒週末會回來看我",
};
const careMemory = {
  id: "c1", memoryType: "care_need", importance: 4, isActive: true, confidence: 0.78,
  memoryText: "每天晚上八點吃藥", memorySummary: "使用者需要照護提醒：每天晚上八點吃藥",
};
const emotionMemory = {
  id: "e1", memoryType: "emotion", importance: 4, isActive: true, confidence: 0.78,
  memoryText: "我最近常常覺得孤單，晚上一個人在家",
  memorySummary: "使用者近期情緒狀態：我最近常常覺得孤單，晚上一個人在家",
};
const archivedPref = { ...prefMemory, id: "a1", isActive: false };

test("低品質「所有的。」被判為低品質、不會被選為開場", () => {
  assert.equal(extractMemoryContent(lowAllOfIt), "所有的。");
  assert.equal(isLowQualityGreetingMemory(lowAllOfIt), true);
  assert.equal(pickGreetingMemory([lowAllOfIt]), null);
});

test("純語助詞「嗯」「好的」「不知道」都是低品質", () => {
  for (const m of [fillerHmm, fillerOk, fillerDontKnow]) {
    assert.equal(isLowQualityGreetingMemory(m), true);
  }
  assert.equal(pickGreetingMemory([fillerHmm, fillerOk, fillerDontKnow]), null);
});

test("只有分類標籤「需要情緒支持」是低品質，不被引用", () => {
  assert.equal(isLowQualityGreetingMemory(labelOnly), true);
});

test("喜好記憶 → 自然引用，且無工程字", () => {
  const g = greetingFromMemory(prefMemory);
  assertNoBanned(g);
  assert.ok(g.includes("你之前說"), g);
  assert.ok(g.includes("喜歡"), g);
});

test("家人記憶 → 自然引用，且無工程字", () => {
  const g = greetingFromMemory(familyMemory);
  assertNoBanned(g);
  assert.ok(g.includes("女兒週末會回來"), g);
});

test("照護提醒記憶 → 詢問是否提醒，不假裝已設定提醒", () => {
  const g = greetingFromMemory(careMemory);
  assertNoBanned(g);
  assert.ok(g.includes("提醒"), g);
  assert.ok(/需要我.*提醒你嗎/.test(g), g);
  for (const fake of ["已設定", "已經幫你設", "已經設好", "幫你設定好"]) {
    assert.ok(!g.includes(fake), `不可假裝已設提醒：${g}`);
  }
});

test("情緒記憶 → 只用溫和開場，不貼標籤、不回放孤單等內容", () => {
  const g = greetingFromMemory(emotionMemory);
  assertNoBanned(g);
  assert.ok(GENTLE.includes(g), `應為溫和開場其一：${g}`);
  for (const label of ["孤單", "寂寞", "負面", "情緒", "你最近很", "我知道你"]) {
    assert.ok(!g.includes(label), `情緒記憶不可標籤化：${g}`);
  }
});

test("archived（isActive:false）記憶不會被選用", () => {
  assert.equal(pickGreetingMemory([archivedPref]), null);
});

test("沒有合格記憶時回 null（呼叫端走一般 fallback 問候）", () => {
  assert.equal(pickGreetingMemory([]), null);
  assert.equal(pickGreetingMemory([lowAllOfIt, fillerHmm, labelOnly]), null);
});

test("具體正向記憶優先於情緒殘片；選用後產生的問候不含原始摘要原文", () => {
  const picked = pickGreetingMemory([emotionMemory, prefMemory]);
  assert.equal(picked.id, prefMemory.id, "喜好應優先於情緒");
  const g = greetingFromMemory(picked);
  assertNoBanned(g);
  // 不可把後端 memorySummary 原文塞進 UI。
  assert.ok(!g.includes("使用者偏好"), g);
  assert.ok(!g.includes(prefMemory.memorySummary), g);
});

test("所有高品質記憶產生的開場都不含任何禁用字", () => {
  for (const m of [prefMemory, familyMemory, careMemory, emotionMemory]) {
    assertNoBanned(greetingFromMemory(m));
  }
});
