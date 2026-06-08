// CR-0047 B1 — redaction.js 單元測試（任務 §9.1）。
// 紅線：測試**不得硬編真 secret**，一律用假值（sk-test-*, example.com 等）。

"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  redactToken,
  redactEmail,
  redactPhone,
  redactDatabaseUrl,
  redactObject,
  safeErrorMessage,
  safeLogPayload,
  REDACTED,
} = require("./redaction");

// NODE_ENV=test → isProduction()===false（env.js 保證 test 不解析為 production）。
// 故以下斷言為 dev/staging 行為：secret 恆遮、自由文字截斷上限 200。

test("redactToken 不輸出完整 token（保留可辨識前後綴）", () => {
  const fake = "sk-test-ABCDEFGHIJKLMNOP1234";
  const out = redactToken(fake);
  assert.ok(!out.includes("ABCDEFGHIJKLMNOP"), "不可含 token 主體");
  assert.notEqual(out, fake);
  assert.ok(out.includes("***"));
});

test("redactEmail 遮蔽 local part、不輸出完整 email", () => {
  const out = redactEmail("caregiver@example.com");
  assert.equal(out, "ca***@example.com");
  assert.ok(!out.includes("caregiver"));
});

test("redactPhone 遮蔽中段", () => {
  const out = redactPhone("0912345789");
  assert.ok(out.includes("***"));
  assert.ok(!out.includes("345"));
});

test("redactDatabaseUrl 只保留 scheme", () => {
  const out = redactDatabaseUrl(
    "postgres://user:secretpass@db.internal:5432/appdb",
  );
  assert.equal(out, "postgres://***");
  assert.ok(!out.includes("secretpass"));
  assert.ok(!out.includes("appdb"));
});

test("redactObject 遞迴遮蔽敏感 key", () => {
  const input = {
    accessToken: "sk-test-ZZZZZZZZ9999",
    nested: {
      apiKey: "sk-test-INNERKEY0000",
      email: "elder@example.com",
      phone: "0912345789",
      databaseUrl: "postgres://u:p@h:5432/d",
      chatId: "123456789",
    },
    ok: true,
    count: 3,
  };
  const out = redactObject(input);
  assert.equal(out.accessToken, REDACTED);
  assert.equal(out.nested.apiKey, REDACTED);
  assert.equal(out.nested.chatId, REDACTED);
  assert.equal(out.nested.email, "el***@example.com");
  assert.ok(out.nested.phone.includes("***"));
  assert.equal(out.nested.databaseUrl, "postgres://***");
  // 非敏感原樣保留。
  assert.equal(out.ok, true);
  assert.equal(out.count, 3);
});

test("redactObject 不 mutate 原物件", () => {
  const input = {
    token: "sk-test-MUTATECHECK11",
    nested: { email: "a@example.com" },
  };
  const snapshot = JSON.stringify(input);
  const out = redactObject(input);
  assert.equal(JSON.stringify(input), snapshot, "原物件須維持不變");
  assert.notEqual(out.token, input.token);
  assert.notEqual(out.nested.email, input.nested.email);
});

test("redactObject 處理循環參照不爆炸", () => {
  const a = { token: "sk-test-CYCLE000000" };
  a.self = a;
  const out = redactObject(a);
  assert.equal(out.token, REDACTED);
  assert.equal(out.self, "[Circular]");
});

test("redactObject 截斷過長自由文字（transcript）", () => {
  const longText = "我".repeat(500);
  const out = redactObject({ transcript: longText });
  // dev 上限 200；故不應完整出現。
  assert.ok(out.transcript.length < longText.length);
  assert.ok(out.transcript.includes("truncated"));
});

test("safeErrorMessage 不含 stack / token", () => {
  const err = new Error(
    "request to OpenAI failed with key sk-test-LEAKEDKEY999 boom",
  );
  err.code = "ECONNRESET";
  err.stack = "Error: secret stack\n  at evil (/x.js:1:1)";
  const out = safeErrorMessage(err);
  assert.ok(out.includes("ECONNRESET"));
  assert.ok(!out.includes("sk-test-LEAKEDKEY999"), "不可含金鑰");
  assert.ok(!out.includes("evil"), "不可含 stack");
  assert.ok(!out.includes("/x.js"), "不可含 stack 路徑");
});

test("safeErrorMessage 缺 message 時不落回完整 error 物件", () => {
  const weird = { foo: "bar", stack: "deep stack info" };
  const out = safeErrorMessage(weird);
  assert.equal(typeof out, "string");
  assert.ok(!out.includes("deep stack"));
  assert.ok(!out.includes("bar"));
});

test("safeErrorMessage 遮蔽 message 內嵌 email / JWT", () => {
  const err = new Error("auth failed for user elder@example.com");
  const out = safeErrorMessage(err);
  assert.ok(!out.includes("elder@example.com"));
});

test("Care Alert summary / reason 不在 safe log 完整出現", () => {
  const fullSummary =
    "長者表示整夜都沒辦法入睡而且情緒非常低落，反覆提到身邊沒有人可以陪伴，" +
    "一直重複說自己很沒用、活著沒有意義，語氣聽起來相當無助讓人擔心";
  const fullReason =
    "系統偵測到連續多日的睡眠異常與強烈孤單訊號，並出現疑似自我貶低語句，" +
    "建議照護人員儘快主動關心並依實際情況判斷是否需要進一步協助，" +
    "此為照護提醒並非醫療診斷請依現場狀況審慎評估後續處理方向";
  const payload = {
    elderId: "elder-42",
    riskLevel: "high",
    summary: fullSummary,
    reason: fullReason,
  };
  const out = safeLogPayload(payload);
  // 非敏感識別子可保留（供除錯）。
  assert.equal(out.elderId, "elder-42");
  assert.equal(out.riskLevel, "high");
  // 自由文字內容不可完整出現（dev 僅保留短前綴 + truncated 標記）。
  assert.ok(!String(out.summary).includes(fullSummary), "summary 不可完整出現");
  assert.ok(!String(out.reason).includes(fullReason), "reason 不可完整出現");
  assert.ok(String(out.summary).includes("truncated"));
  assert.ok(String(out.reason).includes("truncated"));
});

test("safeLogPayload 對非物件值安全處理", () => {
  assert.equal(safeLogPayload(null), null);
  assert.equal(safeLogPayload(42), 42);
  assert.equal(typeof safeLogPayload("short string"), "string");
});

test("describeMaskedConfig（env.js）不輸出 secret 明文（覆核既有）", () => {
  const { describeMaskedConfig } = require("../../config/env");
  const summary = describeMaskedConfig({
    NODE_ENV: "test",
    DATABASE_URL: "postgres://u:secretpw@h:5432/d",
    OPENAI_API_KEY: "sk-test-CONFIGKEY0000",
    TELEGRAM_BOT_TOKEN: "123456:fake-bot-token-AAAA",
    ADMIN_API_TOKEN: "admintok-fake-1234",
    FIREBASE_CLIENT_EMAIL: "svc@project.iam.gserviceaccount.com",
  });
  const blob = JSON.stringify(summary);
  assert.ok(!blob.includes("secretpw"));
  assert.ok(!blob.includes("CONFIGKEY"));
  assert.ok(!blob.includes("fake-bot-token-AAAA"));
});
