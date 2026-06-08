const assert = require("node:assert/strict");
const { test } = require("node:test");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

// require server 前把 runtime data 導到 temp，絕不污染正式 data/*.json。
process.env.CARE_ALERTS_DATA_FILE = path.join(
  fs.mkdtempSync(path.join(os.tmpdir(), "care_alerts_demo_flow_")),
  "care_alerts.json",
);
process.env.NODE_ENV = "test";
// 預設關閉 cooldown，讓基本觸發測試彼此獨立；需要時於個別測試啟用。
delete process.env.CARE_ALERT_TELEGRAM_COOLDOWN_ENABLED;
delete process.env.CARE_ALERT_TELEGRAM_COOLDOWN_MS;

// CR-0039：Care Alert 讀取 / 狀態變更路由掛了 requireAdmin。
process.env.ADMIN_API_TOKEN = "test-admin-token";

const app = require("../server");
const { resetCooldown } = require("./careAlertCooldown");

// require server 會載入 .env（可能含真 Telegram token）；清掉以確保不真的外送。
delete process.env.TELEGRAM_BOT_TOKEN;
delete process.env.TELEGRAM_CARE_CHAT_ID;

// CR-0039：admin 授權 header（讀取 / 狀態變更路由）。
const ADMIN_HEADERS = { Authorization: "Bearer test-admin-token" };

function startServer() {
  return new Promise((resolve) => {
    const server = app.listen(0, "127.0.0.1", () => resolve(server));
  });
}

function baseBody(over) {
  return Object.assign(
    {
      riskLevel: "urgent",
      riskLevelLabel: "緊急",
      category: "other",
      categoryLabel: "其他",
      triggerSummary: "對話中偵測到需要關心的狀況",
      transcriptSnippet: "我最近好痛苦撐不下去",
      createdAt: "2026-05-31T10:00:00.000",
      source: "companion_analysis",
    },
    over || {},
  );
}

// 攔截對 Telegram 的外連並計數；其餘 fetch（client→本機 server）照常走。
function installTelegramSpy() {
  const realFetch = global.fetch;
  const calls = [];
  process.env.TELEGRAM_BOT_TOKEN = "test-token";
  process.env.TELEGRAM_CARE_CHAT_ID = "123456";
  global.fetch = async (url, options) => {
    if (typeof url === "string" && url.includes("api.telegram.org")) {
      calls.push(JSON.parse(options.body));
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

async function postNotify(baseUrl, body) {
  const res = await fetch(`${baseUrl}/api/care-alerts/notify`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  return { status: res.status, body: await res.json() };
}

test("#1 high 風險會觸發 Telegram 推播（訊息含 triggerSummary 與四級 label）", async () => {
  resetCooldown();
  const spy = installTelegramSpy();
  const server = await startServer();
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    const r = await postNotify(
      base,
      baseBody({
        riskLevel: "high",
        riskLevelLabel: "需通知",
        triggerSummary: "長者多次提到睡不好且情緒低落，建議家人今天主動關心。",
      }),
    );
    assert.equal(r.status, 200);
    assert.equal(r.body.success, true);
    assert.equal(spy.calls.length, 1, "high 應推一次 Telegram");
    assert.ok(spy.calls[0].text.includes("需通知"));
    assert.ok(spy.calls[0].text.includes("長者多次提到睡不好"));
  } finally {
    server.close();
    spy.restore();
  }
});

test("#2 urgent 風險會觸發 Telegram 推播", async () => {
  resetCooldown();
  const spy = installTelegramSpy();
  const server = await startServer();
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    const r = await postNotify(base, baseBody({ riskLevel: "urgent" }));
    assert.equal(r.body.success, true);
    assert.equal(spy.calls.length, 1, "urgent 應推一次 Telegram");
    assert.ok(spy.calls[0].text.includes("緊急"));
  } finally {
    server.close();
    spy.restore();
  }
});

test("#3 medium 風險不觸發 Telegram，但仍持久化供 caregiver_web 查看", async () => {
  resetCooldown();
  const spy = installTelegramSpy();
  const server = await startServer();
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    const r = await postNotify(
      base,
      baseBody({
        riskLevel: "medium",
        riskLevelLabel: "持續觀察",
        transcriptSnippet: "最近都睡不好",
      }),
    );
    assert.equal(r.status, 200);
    assert.equal(r.body.success, true);
    assert.equal(r.body.telegram, "skipped_low_risk");
    assert.equal(spy.calls.length, 0, "medium 不應推 Telegram");

    const list = await fetch(`${base}/api/care-alerts`, {
      headers: ADMIN_HEADERS,
    }).then((x) => x.json());
    assert.ok(
      list.alerts.some((a) => a.riskLevel === "medium"),
      "medium alert 仍應存入 store",
    );
  } finally {
    server.close();
    spy.restore();
  }
});

test("low 風險同樣不觸發 Telegram", async () => {
  resetCooldown();
  const spy = installTelegramSpy();
  const server = await startServer();
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    const r = await postNotify(
      base,
      baseBody({ riskLevel: "low", riskLevelLabel: "一般", transcriptSnippet: "今天去散步" }),
    );
    assert.equal(r.body.success, true);
    assert.equal(r.body.telegram, "skipped_low_risk");
    assert.equal(spy.calls.length, 0);
  } finally {
    server.close();
    spy.restore();
  }
});

test("#6 alert status 可從 new → acknowledged → resolved", async () => {
  resetCooldown();
  const spy = installTelegramSpy();
  const server = await startServer();
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    await postNotify(base, baseBody({ riskLevel: "urgent" }));
    const list = await fetch(`${base}/api/care-alerts?limit=1`, {
      headers: ADMIN_HEADERS,
    }).then((x) => x.json());
    const id = list.alerts[0].id;
    assert.equal(list.alerts[0].status, "new");

    const ack = await fetch(`${base}/api/care-alerts/${id}/status`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json", ...ADMIN_HEADERS },
      body: JSON.stringify({ status: "acknowledged" }),
    }).then((x) => x.json());
    assert.equal(ack.success, true);
    assert.equal(ack.alert.status, "acknowledged");
    assert.ok(ack.alert.acknowledgedAt);

    const resolved = await fetch(`${base}/api/care-alerts/${id}/status`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json", ...ADMIN_HEADERS },
      body: JSON.stringify({ status: "resolved" }),
    }).then((x) => x.json());
    assert.equal(resolved.success, true);
    assert.equal(resolved.alert.status, "resolved");
    assert.ok(resolved.alert.resolvedAt);
  } finally {
    server.close();
    spy.restore();
  }
});

test("#4(整合) cooldown 啟用時，冷卻期內重複 urgent 不重複推播", async () => {
  resetCooldown();
  process.env.CARE_ALERT_TELEGRAM_COOLDOWN_ENABLED = "true";
  process.env.CARE_ALERT_TELEGRAM_COOLDOWN_MS = "60000";
  const spy = installTelegramSpy();
  const server = await startServer();
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    const first = await postNotify(base, baseBody({ riskLevel: "urgent", source: "cooldown_demo" }));
    const second = await postNotify(base, baseBody({ riskLevel: "urgent", source: "cooldown_demo" }));
    assert.equal(first.body.success, true);
    assert.equal(spy.calls.length, 1, "第一次 urgent 應推播");
    assert.equal(second.body.success, true);
    assert.equal(second.body.telegram, "skipped_cooldown");
    assert.equal(spy.calls.length, 1, "冷卻期內第二次不應再推");
  } finally {
    server.close();
    spy.restore();
    delete process.env.CARE_ALERT_TELEGRAM_COOLDOWN_ENABLED;
    delete process.env.CARE_ALERT_TELEGRAM_COOLDOWN_MS;
    resetCooldown();
  }
});
