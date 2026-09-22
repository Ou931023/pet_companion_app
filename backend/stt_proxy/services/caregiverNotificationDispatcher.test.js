"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { createDispatcher } = require("./caregiverNotificationDispatcher");
const { createLineAdapter, buildMinimalMessage } = require("./lineNotifyService");
const { DISCLOSURE } = require("./facilityNotificationPolicy");

const event = { elderId: "resident-a", eventId: "12345678-1234-4234-8234-123456789abc",
  riskLevel: "high", createdAt: "2026-09-22T00:00:00Z", transcriptSnippet: "PRIVATE",
  triggerSummary: "PRIVATE", diary: "PRIVATE", recipient: "UNTRUSTED", facilityId: "UNTRUSTED" };
function fixture(channels = ["telegram", "line"]) {
  const calls = [], logs = [];
  const policy = { facilityId: "facility-a", channels, policyVersion: "v1",
    recipientBindingRefs: { telegram: "tg-binding", line: "line-binding" } };
  const resolver = {
    resolvePolicy: async () => policy,
    resolveRecipient: async (scope) => ({ ...scope, active: true, assignmentActive: true,
      recipient: "U" + "a".repeat(32) }),
    resolveConsent: async (scope) => ({ ...scope, disclosure: DISCLOSURE, action: "granted" }),
  };
  const adapters = Object.fromEntries(["telegram", "line"].map((channel) => [channel,
    async (request) => { calls.push({ channel, request }); return { status: "accepted" }; }]));
  return { calls, logs, policy, resolver, adapters, enabled: true, audit: async (row) => logs.push(row) };
}

test("default disabled and absent authoritative policy produce zero outbound", async () => {
  const f = fixture();
  assert.ok((await createDispatcher({ adapters: f.adapters })(event)).every((r) => r.status === "skipped_disabled"));
  assert.ok((await createDispatcher({ enabled: true, adapters: f.adapters })(event)).every((r) => r.status === "skipped_binding"));
  assert.equal(f.calls.length, 0);
});

for (const refs of [undefined, null]) {
  test(`empty channels without bindings (${refs}) skip both channels without IO`, async () => {
    const f = fixture([]);
    if (refs === undefined) delete f.policy.recipientBindingRefs;
    else f.policy.recipientBindingRefs = refs;
    f.resolver.resolveRecipient = async () => assert.fail("must not resolve recipient");
    f.resolver.resolveConsent = async () => assert.fail("must not resolve consent");
    assert.deepEqual(await createDispatcher(f)(event), [
      { channel: "telegram", status: "skipped_disabled" },
      { channel: "line", status: "skipped_disabled" },
    ]);
    assert.equal(f.calls.length, 0);
  });
}

for (const [riskLevel, label] of Object.entries({ low: "一般關心", medium: "持續觀察", high: "需要關心", urgent: "需要立即協助" })) {
  test(`minimal Traditional Chinese message: ${riskLevel}`, () => {
    assert.equal(buildMinimalMessage({ ...event, riskLevel, riskLevelLabel: "PRIVATE" }),
      `照護提醒\n風險等級：${label}\n時間：2026/09/22 08:00:00（Asia/Taipei 台北時間）\n提醒編號：${event.eventId}\n請查看照護後台，並主動關心長者。`);
  });
}

test("Taipei time handles date rollover and explicit source offset", () => {
  const utc = buildMinimalMessage({ ...event, createdAt: "2026-12-31T16:00:00Z" });
  assert.ok(utc.includes("2027/01/01 00:00:00（Asia/Taipei 台北時間）"));
  assert.equal(utc, buildMinimalMessage({ ...event, createdAt: "2027-01-01T00:00:00+08:00" }));
});

for (const channels of [[], ["telegram"], ["line"], ["telegram", "line"]]) {
  test(`channel selection ${JSON.stringify(channels)} and minimization`, async () => {
    const f = fixture(channels);
    await createDispatcher(f)(event);
    assert.deepEqual(f.calls.map((c) => c.channel), channels);
    assert.equal(JSON.stringify(f.calls).includes("PRIVATE"), false);
    assert.equal(JSON.stringify(f.calls).includes("UNTRUSTED"), false);
    assert.equal(JSON.stringify(f.logs).includes("recipient"), false);
    for (const call of f.calls) assert.deepEqual(Object.keys(call.request.alert).sort(), ["createdAt", "eventId", "riskLevel"]);
  });
}

for (const mode of ["missing", "withdrawn", "cross-facility", "assignment", "exception", "wrong-disclosure"]) {
  test(`authorization fail closed: ${mode}`, async () => {
    const f = fixture();
    if (mode === "missing") f.resolver.resolveConsent = async () => null;
    if (mode === "withdrawn") f.resolver.resolveConsent = async (s) => ({ ...s, action: "withdrawn" });
    if (mode === "wrong-disclosure") f.resolver.resolveConsent = async (s) => ({ ...s, action: "granted", disclosure: "privacy_terms" });
    if (mode === "exception") f.resolver.resolveRecipient = async () => { throw Error("PRIVATE"); };
    if (mode === "cross-facility" || mode === "assignment") f.resolver.resolveRecipient = async (s) => ({ ...s,
      facilityId: mode === "cross-facility" ? "other" : s.facilityId, active: true,
      assignmentActive: mode !== "assignment", recipient: "some-recipient" });
    const result = await createDispatcher(f)(event);
    assert.equal(f.calls.length, 0);
    assert.ok(result.every((r) => r.status.startsWith("skipped_")));
    assert.equal(JSON.stringify(result).includes("PRIVATE"), false);
  });
}

test("partial failure retries only failed channel with stable key and current consent", async () => {
  const f = fixture();
  f.adapters.line = async (request) => { f.calls.push({ channel: "line", request }); return { status: "failed", errorCode: "PRIVATE" }; };
  const dispatch = createDispatcher(f);
  assert.deepEqual((await dispatch(event)).map((r) => r.status), ["accepted", "failed"]);
  assert.deepEqual((await dispatch(event)).map((r) => r.status), ["skipped_duplicate", "failed"]);
  assert.equal(f.calls[1].request.retryKey, f.calls[2].request.retryKey);
  f.resolver.resolveConsent = async () => null;
  assert.ok((await dispatch(event)).every((r) => r.status === "skipped_consent"));
  assert.equal(f.calls.length, 3);
  assert.equal(JSON.stringify(f.logs).includes("PRIVATE"), false);
});

test("concurrent duplicate, resident and risk escalation isolation", async () => {
  const f = fixture();
  const dispatch = createDispatcher(f);
  await Promise.all([dispatch(event), dispatch(event)]);
  assert.equal(f.calls.length, 2);
  await dispatch({ ...event, elderId: "resident-b" });
  await dispatch({ ...event, riskLevel: "urgent" });
  assert.equal(f.calls.length, 6);
  await dispatch({ ...event, riskLevel: "medium" });
  assert.equal(f.calls.length, 6);
});

test("unknown is not retried, audit failure cannot resend, capacity fails closed", async () => {
  const f = fixture(["line"]);
  f.adapters.line = async () => { f.calls.push(1); throw Error("PRIVATE"); };
  f.audit = async () => { throw Error("PRIVATE"); };
  const dispatch = createDispatcher({ ...f, maxEntries: 1 });
  assert.equal((await dispatch(event))[1].status, "unknown");
  assert.equal((await dispatch(event))[1].status, "skipped_duplicate");
  assert.equal((await dispatch({ ...event, elderId: "other" }))[1].errorCode, "dispatcher_capacity");
  assert.equal(f.calls.length, 1);
});

test("failed attempts cannot retry outside conservative LINE retry window", async () => {
  const f = fixture(["line"]);
  let time = 0;
  f.adapters.line = async () => { f.calls.push(1); return { status: "failed" }; };
  const dispatch = createDispatcher({ ...f, now: () => time });
  await dispatch(event);
  time = 24 * 60 * 60 * 1000;
  assert.equal((await dispatch(event))[1].errorCode, "retry_window_expired");
  assert.equal(f.calls.length, 1);
});

test("LINE opt-in, fixed endpoint, minimized body, no network defaults", async () => {
  let calls = 0;
  const input = { recipient: "U" + "a".repeat(32), alert: event, retryKey: event.eventId };
  assert.equal((await createLineAdapter()(input)).status, "skipped_disabled");
  const send = createLineAdapter({ enabled: true, accessToken: "test-placeholder", fetchImpl: async (url, options) => {
    calls++;
    assert.equal(url, "https://api.line.me/v2/bot/message/push");
    assert.equal(options.headers["X-Line-Retry-Key"], event.eventId);
    assert.equal(options.redirect, "error");
    assert.equal(options.body.includes("PRIVATE"), false);
    return { status: 200 };
  } });
  assert.equal((await send(input)).status, "accepted");
  assert.equal((await send({ ...input, recipient: "https://invalid" })).status, "failed");
  assert.equal(calls, 1);
});

for (const [httpStatus, acceptedId, expected] of [[409, "accepted-id", "accepted"], [409, null, "failed"], [401, null, "failed"], [429, null, "failed"], [500, null, "unknown"]]) {
  test(`LINE HTTP ${httpStatus} ${acceptedId || ""}`, async () => {
    const send = createLineAdapter({ enabled: true, accessToken: "test-placeholder",
      fetchImpl: async () => ({ status: httpStatus, headers: { get: () => acceptedId } }) });
    assert.equal((await send({ recipient: "U" + "a".repeat(32), alert: event, retryKey: event.eventId })).status, expected);
  });
}

test("LINE abort returns unknown without leaking exception", async () => {
  const send = createLineAdapter({ enabled: true, accessToken: "test-placeholder", timeoutMs: 1,
    fetchImpl: async (_, { signal }) => new Promise((_, reject) => signal.addEventListener("abort", () => reject(Error("PRIVATE")))) });
  const result = await send({ recipient: "U" + "a".repeat(32), alert: event, retryKey: event.eventId });
  assert.equal(result.status, "unknown");
  assert.equal(JSON.stringify(result).includes("PRIVATE"), false);
});

test("retry refuses changed content or recipient under the same binding", async () => {
  const f = fixture(["line"]);
  f.adapters.line = async () => { f.calls.push(1); return { status: "failed" }; };
  const dispatch = createDispatcher(f);
  await dispatch(event);
  assert.equal((await dispatch({ ...event, createdAt: "2026-09-23T00:00:00Z" }))[1].status, "skipped_binding");
  f.resolver.resolveRecipient = async (s) => ({ ...s, active: true, assignmentActive: true, recipient: "U" + "b".repeat(32) });
  assert.equal((await dispatch(event))[1].status, "skipped_binding");
  assert.equal(f.calls.length, 1);
});

test("policy changes before send prevent outbound", async () => {
  const f = fixture(["line"]);
  let reads = 0;
  f.resolver.resolvePolicy = async () => ++reads === 1 ? f.policy : { ...f.policy, facilityId: "other" };
  assert.equal((await createDispatcher(f)(event))[1].status, "skipped_binding");
  assert.equal(f.calls.length, 0);
});

for (const mode of ["hanging", "rejected", "throws"]) {
  test(`audit ${mode} never blocks either channel or changes results`, { timeout: 1000 }, async () => {
    const f = fixture();
    const audited = [];
    f.audit = (record) => {
      audited.push(record.channel);
      if (mode === "hanging") return new Promise(() => {});
      if (mode === "throws") throw Error("PRIVATE");
      return Promise.reject(Error("PRIVATE"));
    };
    const result = await createDispatcher(f)(event);
    // Let detached rejection handlers run; node:test detects unhandled rejections.
    await new Promise((resolve) => setImmediate(resolve));
    assert.deepEqual(result, [
      { channel: "telegram", status: "accepted" },
      { channel: "line", status: "accepted" },
    ]);
    assert.deepEqual(f.calls.map((call) => call.channel), ["telegram", "line"]);
    assert.deepEqual(audited, ["telegram", "line"]);
  });
}
