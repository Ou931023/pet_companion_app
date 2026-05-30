const assert = require("node:assert/strict");
const test = require("node:test");

const {
  sendCareAlertNotification,
  buildMessage,
  riskLevelDisplay,
  shouldNotify,
  truncateSnippet,
  SNIPPET_MAX_LENGTH,
} = require("./telegramNotifyService");

test("shouldNotify：只有 high / urgent 推 Telegram，low / medium 不推", () => {
  assert.equal(shouldNotify({ riskLevel: "high" }), true);
  assert.equal(shouldNotify({ riskLevel: "urgent" }), true);
  assert.equal(shouldNotify({ riskLevel: "medium" }), false);
  assert.equal(shouldNotify({ riskLevel: "low" }), false);
  // legacy 值經正規化：attention→medium（不推）、normal→low（不推）
  assert.equal(shouldNotify({ riskLevel: "attention" }), false);
  assert.equal(shouldNotify({ riskLevel: "normal" }), false);
  // 未知 → low → 不推
  assert.equal(shouldNotify({ riskLevel: "bogus" }), false);
});

const ORIGINAL_FETCH = global.fetch;
const ORIGINAL_TOKEN = process.env.TELEGRAM_BOT_TOKEN;
const ORIGINAL_CHAT_ID = process.env.TELEGRAM_CARE_CHAT_ID;

function restore() {
  global.fetch = ORIGINAL_FETCH;
  if (ORIGINAL_TOKEN === undefined) delete process.env.TELEGRAM_BOT_TOKEN;
  else process.env.TELEGRAM_BOT_TOKEN = ORIGINAL_TOKEN;
  if (ORIGINAL_CHAT_ID === undefined) delete process.env.TELEGRAM_CARE_CHAT_ID;
  else process.env.TELEGRAM_CARE_CHAT_ID = ORIGINAL_CHAT_ID;
}

function configure() {
  process.env.TELEGRAM_BOT_TOKEN = "test-token";
  process.env.TELEGRAM_CARE_CHAT_ID = "123456";
}

const samplePayload = {
  riskLevel: "urgent",
  riskLevelLabel: "緊急",
  category: "other",
  categoryLabel: "其他",
  triggerSummary: "對話中偵測到需要關心的狀況",
  transcriptSnippet: "我昨天晚上都睡不好，今天有點頭暈。",
  createdAt: "2026-05-28T16:30:00.000Z",
  source: "companion_analysis",
};

test("token / chat id 缺失時回 telegram_not_configured，且不呼叫 fetch", async () => {
  try {
    delete process.env.TELEGRAM_BOT_TOKEN;
    delete process.env.TELEGRAM_CARE_CHAT_ID;
    let called = false;
    global.fetch = async () => {
      called = true;
      throw new Error("fetch should not be called when not configured");
    };
    const result = await sendCareAlertNotification(samplePayload);
    assert.deepEqual(result, { success: false, error: "telegram_not_configured" });
    assert.equal(called, false);
  } finally {
    restore();
  }
});

test("只有 chat id 缺失時也回 telegram_not_configured", async () => {
  try {
    process.env.TELEGRAM_BOT_TOKEN = "test-token";
    delete process.env.TELEGRAM_CARE_CHAT_ID;
    const result = await sendCareAlertNotification(samplePayload);
    assert.deepEqual(result, { success: false, error: "telegram_not_configured" });
  } finally {
    restore();
  }
});

test("transcriptSnippet 超過 200 字會截斷", () => {
  const long = "甲".repeat(250);
  const truncated = truncateSnippet(long);
  assert.equal(truncated, "甲".repeat(SNIPPET_MAX_LENGTH) + "…");
  assert.equal(truncated.length, SNIPPET_MAX_LENGTH + 1);

  const message = buildMessage({ ...samplePayload, transcriptSnippet: long });
  assert.ok(message.includes(truncated), "訊息應包含截斷後片段");
  assert.ok(!message.includes(long), "訊息不應包含未截斷的完整片段");
});

test("buildMessage 採用 ISO 牆上時間且含必要欄位", () => {
  const message = buildMessage(samplePayload);
  assert.ok(message.startsWith("【智慧小黑豆照護提醒】"));
  assert.ok(message.includes("風險等級：緊急"));
  assert.ok(message.includes("類型：其他"));
  assert.ok(message.includes("時間：2026/05/28 16:30"));
  assert.ok(message.includes("建議：請長照人員或家屬主動關心。"));
});

// ---- CR-0002 Batch 2：四級中文 label 與向下相容 ----

test("riskLevelDisplay 由權威四級推導中文 label（無 riskLevelLabel 時）", () => {
  assert.equal(riskLevelDisplay({ riskLevel: "low" }), "一般");
  assert.equal(riskLevelDisplay({ riskLevel: "medium" }), "持續觀察");
  assert.equal(riskLevelDisplay({ riskLevel: "high" }), "需通知");
  assert.equal(riskLevelDisplay({ riskLevel: "urgent" }), "緊急");
});

test("riskLevelDisplay 對舊代碼也能推導（normal→一般、attention→持續觀察）", () => {
  assert.equal(riskLevelDisplay({ riskLevel: "normal" }), "一般");
  assert.equal(riskLevelDisplay({ riskLevel: "attention" }), "持續觀察");
  // 未知 → low → 一般
  assert.equal(riskLevelDisplay({ riskLevel: "bogus" }), "一般");
});

test("riskLevelDisplay 優先採用前端帶來的 riskLevelLabel", () => {
  assert.equal(
    riskLevelDisplay({ riskLevel: "high", riskLevelLabel: "需通知" }),
    "需通知",
  );
  // 即使與 level 不一致也以前端 label 為準（前端已是顯示來源）
  assert.equal(
    riskLevelDisplay({ riskLevel: "attention", riskLevelLabel: "需注意" }),
    "需注意",
  );
});

test("buildMessage 對 high（無 label）顯示『風險等級：需通知』", () => {
  const message = buildMessage({
    ...samplePayload,
    riskLevel: "high",
    riskLevelLabel: undefined,
  });
  assert.ok(message.includes("風險等級：需通知"));
});

test("fetch 成功時回 success:true，並送到 sendMessage", async () => {
  try {
    configure();
    let capturedUrl;
    let capturedBody;
    global.fetch = async (url, options) => {
      capturedUrl = url;
      capturedBody = JSON.parse(options.body);
      return { ok: true, status: 200, json: async () => ({ ok: true }) };
    };
    const result = await sendCareAlertNotification(samplePayload);
    assert.deepEqual(result, { success: true });
    assert.ok(capturedUrl.endsWith("/sendMessage"));
    assert.equal(capturedBody.chat_id, "123456");
    assert.ok(capturedBody.text.includes("【智慧小黑豆照護提醒】"));
  } finally {
    restore();
  }
});

test("Telegram 回非 2xx 時回 telegram_send_failed 並帶 status", async () => {
  try {
    configure();
    global.fetch = async () => ({ ok: false, status: 403, json: async () => ({}) });
    const result = await sendCareAlertNotification(samplePayload);
    assert.deepEqual(result, {
      success: false,
      error: "telegram_send_failed",
      status: 403,
    });
  } finally {
    restore();
  }
});

test("fetch throw / timeout 時回 telegram_request_failed", async () => {
  try {
    configure();
    global.fetch = async () => {
      throw new Error("network down");
    };
    const result = await sendCareAlertNotification(samplePayload);
    assert.deepEqual(result, { success: false, error: "telegram_request_failed" });
  } finally {
    restore();
  }
});

test("AbortError（timeout）時回 telegram_request_failed", async () => {
  try {
    configure();
    global.fetch = async () => {
      const error = new Error("aborted");
      error.name = "AbortError";
      throw error;
    };
    const result = await sendCareAlertNotification(samplePayload);
    assert.deepEqual(result, { success: false, error: "telegram_request_failed" });
  } finally {
    restore();
  }
});
