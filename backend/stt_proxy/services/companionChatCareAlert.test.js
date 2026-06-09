"use strict";

// CR-0051 Batch B：POST /api/companion/chat 風險側錄 + Care Alert 串接的 HTTP 層測試。
//
// 比照 careAlertNotifyAuthEndpoint.test.js：stub firebaseAdmin + mock pg（resident token）、
// Telegram spy、temp CARE_ALERTS_DATA_FILE。另以 require.cache 注入假 OpenAI client，
// 讓 generateCompanionReply 回固定回覆（絕不打真 OpenAI）。
//
// 驗證裁決：
//   - 風險 ∈ {medium,high,urgent} 才建 alert；low / neutral 省略 careAlert 欄位、不嘗試寫入。
//   - medium → 持久化但 Telegram skipped_low_risk；high/urgent → Telegram 觸發。
//   - 未授權 / 偽造 token → 401，不建 alert；跨住民 body.elderId → 403，不建 alert。
//   - reply 在所有成功情境都在；careAlert 嚴格為可選。
//   - log / response 不外洩 token / 完整對話 / 完整摘要。

const assert = require("node:assert/strict");
const { test, beforeEach, afterEach } = require("node:test");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

// ---- 注入假 OpenAI client（在 require server 之前覆寫 require.cache）----
const FIXED_REPLY = "我在這裡陪你，慢慢說沒關係。";
class FakeOpenAI {
  constructor() {
    this.chat = {
      completions: {
        create: async () => ({
          choices: [{ message: { content: FIXED_REPLY } }],
        }),
      },
    };
  }
}
const openaiPath = require.resolve("openai");
require.cache[openaiPath] = {
  id: openaiPath,
  filename: openaiPath,
  loaded: true,
  exports: FakeOpenAI,
};

process.env.NODE_ENV = "test";
process.env.ADMIN_API_TOKEN = "test-admin-token";
// 假 client + 有金鑰 → generateCompanionReply 走「成功回覆」分支。
process.env.OPENAI_API_KEY = "test-key";
process.env.CARE_ALERTS_DATA_FILE = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), "companion_chat_alert_")),
  "care_alerts.json",
);

const app = require("../server");
const {
  installResidentCallerStub,
} = require("./auth/residentCallerContext.testsupport");
const { resetCooldown } = require("./careAlertCooldown");

// require server 會載入 .env（可能含真 Telegram token）；清掉以確保預設不外送。
delete process.env.TELEGRAM_BOT_TOKEN;
delete process.env.TELEGRAM_CARE_CHAT_ID;

const ADMIN_HEADERS = { Authorization: "Bearer test-admin-token" };
const ELDER_A = "11111111-1111-1111-1111-111111111111";
const ELDER_B = "22222222-2222-2222-2222-222222222222";
const RES_A = { Authorization: "Bearer res-a-token" };

let restoreResident = null;

beforeEach(() => {
  process.env.CARE_ALERTS_DATA_FILE = path.join(
    fs.mkdtempSync(path.join(os.tmpdir(), "companion_chat_alert_")),
    "care_alerts.json",
  );
  resetCooldown();
  restoreResident = installResidentCallerStub({
    "res-a-token": { uid: "fb-res-a", userId: "user-a", elderId: ELDER_A },
    "res-b-token": { uid: "fb-res-b", userId: "user-b", elderId: ELDER_B },
  });
});

afterEach(() => {
  if (restoreResident) restoreResident();
  restoreResident = null;
});

function startServer() {
  return new Promise((resolve) => {
    const server = app.listen(0, "127.0.0.1", () => resolve(server));
  });
}

function postChat(baseUrl, body, headers = RES_A) {
  return fetch(`${baseUrl}/api/companion/chat`, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
}

async function listAlerts(baseUrl) {
  const res = await fetch(`${baseUrl}/api/care-alerts`, { headers: ADMIN_HEADERS });
  return (await res.json()).alerts || [];
}

// 攔截 Telegram 外連並計數（其餘 fetch 照常）。
function installTelegramSpy() {
  const realFetch = global.fetch;
  const calls = [];
  process.env.TELEGRAM_BOT_TOKEN = "test-token";
  process.env.TELEGRAM_CARE_CHAT_ID = "123456";
  global.fetch = async (url, options) => {
    if (typeof url === "string" && url.includes("api.telegram.org")) {
      calls.push(options && options.body);
      return { ok: true, status: 200, json: async () => ({ ok: true }) };
    }
    return realFetch(url, options);
  };
  return {
    calls,
    restore() {
      global.fetch = realFetch;
      delete process.env.TELEGRAM_BOT_TOKEN;
      delete process.env.TELEGRAM_CARE_CHAT_ID;
    },
  };
}

// ---- medium：孤單 / 睡不好 / 食慾差 → 建 alert、Telegram skipped_low_risk ----

test("孤單（沒人陪）→ careAlert.created, riskLevel medium, Telegram skipped", async () => {
  const spy = installTelegramSpy();
  const server = await startServer();
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    const res = await postChat(base, {
      userText: "家裡好安靜，都沒人陪我",
      petName: "小白",
    });
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.success, true);
    assert.equal(body.reply, FIXED_REPLY);
    assert.equal(body.careAlert.created, true);
    assert.equal(body.careAlert.riskLevel, "medium");
    assert.ok(body.careAlert.id);
    assert.equal(spy.calls.length, 0, "medium 不推 Telegram");
    const alerts = await listAlerts(base);
    assert.equal(alerts.length, 1);
    assert.equal(alerts[0].elderId, ELDER_A);
    assert.equal(alerts[0].riskLevel, "medium");
    assert.equal(alerts[0].source, "companion_chat");
  } finally {
    spy.restore();
    server.close();
  }
});

test("睡不好 → medium alert", async () => {
  const server = await startServer();
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    const res = await postChat(base, { userText: "我晚上都睡不好" });
    const body = await res.json();
    assert.equal(res.status, 200);
    assert.equal(body.reply, FIXED_REPLY);
    assert.equal(body.careAlert.riskLevel, "medium");
    assert.equal(body.careAlert.created, true);
    const alerts = await listAlerts(base);
    assert.equal(alerts.length, 1);
    assert.equal(alerts[0].riskLevel, "medium");
  } finally {
    server.close();
  }
});

test("食慾差（吃不下）→ medium alert", async () => {
  const server = await startServer();
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    const res = await postChat(base, { userText: "最近都吃不下，沒什麼胃口" });
    const body = await res.json();
    assert.equal(res.status, 200);
    assert.equal(body.careAlert.riskLevel, "medium");
    assert.equal(body.careAlert.created, true);
  } finally {
    server.close();
  }
});

// ---- high / urgent：Telegram 觸發 ----

test("胸口很痛 → urgent alert，Telegram 觸發", async () => {
  const spy = installTelegramSpy();
  const server = await startServer();
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    const res = await postChat(base, { userText: "我胸口很痛" });
    const body = await res.json();
    assert.equal(res.status, 200);
    assert.equal(body.reply, FIXED_REPLY);
    assert.equal(body.careAlert.created, true);
    assert.ok(["high", "urgent"].includes(body.careAlert.riskLevel));
    assert.equal(spy.calls.length, 1, "high/urgent 應觸發一次 Telegram");
  } finally {
    spy.restore();
    server.close();
  }
});

test("不想活了 → urgent alert，Telegram 觸發", async () => {
  const spy = installTelegramSpy();
  const server = await startServer();
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    const res = await postChat(base, { userText: "我不想活了" });
    const body = await res.json();
    assert.equal(res.status, 200);
    assert.equal(body.careAlert.created, true);
    assert.equal(body.careAlert.riskLevel, "urgent");
    assert.equal(spy.calls.length, 1);
    const alerts = await listAlerts(base);
    assert.equal(alerts[0].riskLevel, "urgent");
  } finally {
    spy.restore();
    server.close();
  }
});

// ---- low / neutral：無 careAlert、無 Telegram、無 alert row ----

test("天氣不錯（low/neutral）→ 無 careAlert 欄位、無 Telegram、無 alert row", async () => {
  const spy = installTelegramSpy();
  const server = await startServer();
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    const res = await postChat(base, { userText: "今天天氣不錯" });
    const body = await res.json();
    assert.equal(res.status, 200);
    assert.equal(body.success, true);
    assert.equal(body.reply, FIXED_REPLY);
    assert.equal("careAlert" in body, false, "low/neutral 必須省略 careAlert");
    assert.equal(spy.calls.length, 0);
    assert.deepEqual(await listAlerts(base), []);
  } finally {
    spy.restore();
    server.close();
  }
});

// ---- 授權邊界 ----

test("無 token → 401，不建 alert", async () => {
  const spy = installTelegramSpy();
  const server = await startServer();
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    const res = await postChat(base, { userText: "我胸口很痛" }, {});
    assert.equal(res.status, 401);
    assert.equal(spy.calls.length, 0);
    assert.deepEqual(await listAlerts(base), []);
  } finally {
    spy.restore();
    server.close();
  }
});

test("偽造 token → 401，不建 alert", async () => {
  const spy = installTelegramSpy();
  const server = await startServer();
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    const res = await postChat(
      base,
      { userText: "我不想活了" },
      { Authorization: "Bearer forged-token" },
    );
    assert.equal(res.status, 401);
    assert.equal(spy.calls.length, 0);
    assert.deepEqual(await listAlerts(base), []);
  } finally {
    spy.restore();
    server.close();
  }
});

test("跨住民 body.elderId != caller → 403，不建 alert、reply", async () => {
  const spy = installTelegramSpy();
  const server = await startServer();
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    const res = await postChat(base, {
      userText: "我胸口很痛",
      elderId: ELDER_B,
    });
    assert.equal(res.status, 403);
    const body = await res.json();
    assert.deepEqual(body, { success: false, error: "forbidden_resident" });
    assert.equal(spy.calls.length, 0);
    assert.deepEqual(await listAlerts(base), []);
  } finally {
    spy.restore();
    server.close();
  }
});

test("body.elderId == caller（相符）→ 放行、以 caller elderId 建 alert", async () => {
  const server = await startServer();
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    const res = await postChat(base, {
      userText: "我晚上都睡不好",
      elderId: ELDER_A,
    });
    assert.equal(res.status, 200);
    const alerts = await listAlerts(base);
    assert.equal(alerts.length, 1);
    assert.equal(alerts[0].elderId, ELDER_A);
  } finally {
    server.close();
  }
});

// ---- 向後相容 / 不外洩 ----

test("response 向後相容：reply 永遠在、careAlert 嚴格可選", async () => {
  const server = await startServer();
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    const neutral = await (await postChat(base, { userText: "今天天氣不錯" })).json();
    assert.ok(neutral.reply);
    assert.equal("careAlert" in neutral, false);

    const risky = await (await postChat(base, { userText: "我晚上都睡不好" })).json();
    assert.ok(risky.reply);
    assert.ok(risky.careAlert);
    // 只暴露 riskLevel / created / id，不外洩摘要 / 風險 debug。
    assert.deepEqual(Object.keys(risky.careAlert).sort(), ["created", "id", "riskLevel"]);
  } finally {
    server.close();
  }
});

// ---- legacy 風險碼正規化（seam）----

test("legacy 正規化：normal→low（不建 alert）、attention→medium（會建 alert）", () => {
  const { normalizeRiskLevel } = require("./careAlertStoreService");
  // engine failure-fallback 吐 normal → low → predicate 不建 alert。
  assert.equal(normalizeRiskLevel("normal"), "low");
  // 舊 attention → medium → predicate 會建 alert（無 attention 進新資料）。
  assert.equal(normalizeRiskLevel("attention"), "medium");
  assert.equal(normalizeRiskLevel("urgent"), "urgent");
  // 確認 SEND 述詞集合不含 normal / attention（只放行 medium/high/urgent）。
  const warrants = (lvl) => ["medium", "high", "urgent"].includes(normalizeRiskLevel(lvl));
  assert.equal(warrants("normal"), false);
  assert.equal(warrants("low"), false);
  assert.equal(warrants("attention"), true);
});

test("回應不外洩 token / 完整摘要文字", async () => {
  const server = await startServer();
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    const res = await postChat(base, { userText: "我晚上都睡不好" });
    const textBody = await res.text();
    assert.ok(!textBody.includes("res-a-token"), "不可含 token");
    assert.ok(!textBody.includes("triggerSummary"), "不可外洩摘要欄位");
    assert.ok(!/stack|Error:/i.test(textBody), "不可含 stack");
  } finally {
    server.close();
  }
});
