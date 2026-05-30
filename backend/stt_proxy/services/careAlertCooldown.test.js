const assert = require("node:assert/strict");
const { test, beforeEach } = require("node:test");

const cd = require("./careAlertCooldown");

beforeEach(() => cd.resetCooldown());

test("cooldown 關閉時一律可推、且不記錄狀態", () => {
  const opts = { enabled: false };
  assert.equal(cd.canSendTelegram("k", opts), true);
  cd.markTelegramSent("k", opts);
  assert.equal(cd.canSendTelegram("k", opts), true);
});

test("#4 cooldown 期間重複同 key 不可再推", () => {
  const base = { enabled: true, cooldownMs: 60000 };
  assert.equal(cd.canSendTelegram("urgent", { ...base, nowMs: 1000 }), true);
  cd.markTelegramSent("urgent", { ...base, nowMs: 1000 });
  // 冷卻期內（4 秒後 < 60 秒）
  assert.equal(cd.canSendTelegram("urgent", { ...base, nowMs: 5000 }), false);
});

test("不同 key（不同風險等級）互不阻擋", () => {
  const base = { enabled: true, cooldownMs: 60000, nowMs: 1000 };
  cd.markTelegramSent("companion_analysis::high", base);
  assert.equal(
    cd.canSendTelegram("companion_analysis::urgent", base),
    true,
    "urgent 不應被 high 的冷卻擋住",
  );
});

test("#5 cooldown 到期後可再次推播（>= 視為到期）", () => {
  const base = { enabled: true, cooldownMs: 1000 };
  cd.markTelegramSent("k", { ...base, nowMs: 1000 });
  assert.equal(cd.canSendTelegram("k", { ...base, nowMs: 1500 }), false, "仍在冷卻");
  assert.equal(cd.canSendTelegram("k", { ...base, nowMs: 2000 }), true, "剛好到期");
  assert.equal(cd.canSendTelegram("k", { ...base, nowMs: 2500 }), true, "已過期");
});

test("env 設定可關閉 / 調整冷卻時間", () => {
  const origEnabled = process.env.CARE_ALERT_TELEGRAM_COOLDOWN_ENABLED;
  const origMs = process.env.CARE_ALERT_TELEGRAM_COOLDOWN_MS;
  try {
    process.env.CARE_ALERT_TELEGRAM_COOLDOWN_ENABLED = "false";
    assert.equal(cd.isCooldownEnabled(), false);
    process.env.CARE_ALERT_TELEGRAM_COOLDOWN_ENABLED = "true";
    process.env.CARE_ALERT_TELEGRAM_COOLDOWN_MS = "1234";
    assert.equal(cd.isCooldownEnabled(), true);
    assert.equal(cd.cooldownMs(), 1234);
  } finally {
    if (origEnabled === undefined) delete process.env.CARE_ALERT_TELEGRAM_COOLDOWN_ENABLED;
    else process.env.CARE_ALERT_TELEGRAM_COOLDOWN_ENABLED = origEnabled;
    if (origMs === undefined) delete process.env.CARE_ALERT_TELEGRAM_COOLDOWN_MS;
    else process.env.CARE_ALERT_TELEGRAM_COOLDOWN_MS = origMs;
  }
});

test("預設 cooldown 為 10 分鐘", () => {
  assert.equal(cd.DEFAULT_COOLDOWN_MS, 10 * 60 * 1000);
});

test("options.cooldownMs 優先於 env，nowMs 可注入", () => {
  // 不依賴真實時鐘：cooldownMs=100、兩個 now 相差 50 → 仍冷卻
  cd.markTelegramSent("x", { enabled: true, cooldownMs: 100, nowMs: 10_000 });
  assert.equal(cd.canSendTelegram("x", { enabled: true, cooldownMs: 100, nowMs: 10_050 }), false);
  assert.equal(cd.canSendTelegram("x", { enabled: true, cooldownMs: 100, nowMs: 10_100 }), true);
});
