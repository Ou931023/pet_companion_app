"use strict";

const { randomUUID, createHash } = require("node:crypto");
const { CHANNELS, id, validPolicy, authorize, createPolicyResolver } = require("./facilityNotificationPolicy");
const { buildMinimalMessage } = require("./lineNotifyService");

// Isolated only. No imports of server, legacy senders, DB, dotenv or runtime data.
// Entries are never evicted: at maxEntries, new identities remain fail-closed for
// this instance's lifetime. Restarting loses dedupe history, not a safe recovery.
// Production requires a separately approved durable queue/dedupe store, retention
// and capacity monitoring. Do not wire this in-memory implementation into the pipeline.
function createDispatcher({ enabled = false, resolver = createPolicyResolver(), adapters = {},
  audit = async () => {}, maxEntries = 10000, now = Date.now } = {}) {
  const attempts = new Map();
  return async (event = {}) => {
    if (enabled !== true) return CHANNELS.map((channel) => ({ channel, status: "skipped_disabled" }));
    if (!id(event.elderId) || !buildMinimalMessage(event)) {
      return CHANNELS.map((channel) => ({ channel, status: "skipped_binding" }));
    }
    let policy;
    try { policy = await resolver.resolvePolicy(event.elderId); } catch (_) { /* fail closed */ }
    if (!validPolicy(policy)) return CHANNELS.map((channel) => ({ channel, status: "skipped_binding" }));
    const results = [];
    for (const channel of CHANNELS) {
      const scope = { elderId: event.elderId, facilityId: policy.facilityId,
        policyVersion: policy.policyVersion, bindingRef: policy.recipientBindingRefs?.[channel], channel };
      let result;
      if (!policy.channels.includes(channel) || typeof adapters[channel] !== "function") {
        result = { status: "skipped_disabled" };
      } else if (!["high", "urgent"].includes(event.riskLevel)) {
        result = { status: "skipped_low_risk" };
      } else {
        try {
          // Re-read policy and consent for each attempt, including retry after failure.
          const current = await resolver.resolvePolicy(event.elderId);
          if (!validPolicy(current) || current.facilityId !== policy.facilityId ||
              current.policyVersion !== policy.policyVersion || !current.channels.includes(channel) ||
              current.recipientBindingRefs?.[channel] !== scope.bindingRef) {
            result = { status: "skipped_binding" };
          } else {
            const auth = await authorize(resolver, scope);
            if (auth.status) result = { status: auth.status };
            else {
              const key = JSON.stringify([scope.facilityId, scope.elderId, event.eventId,
                event.riskLevel, scope.bindingRef, channel]);
              let attempt = attempts.get(key);
              const fingerprint = createHash("sha256").update(JSON.stringify([
                auth.recipient, event.eventId, event.riskLevel,
                new Date(event.createdAt).toISOString(),
              ])).digest("hex");
              if (attempt && ["pending", "accepted", "unknown"].includes(attempt.status)) {
                result = { status: "skipped_duplicate" };
              } else if (attempt && attempt.fingerprint !== fingerprint) {
                result = { status: "skipped_binding" };
              } else if (attempt && now() - attempt.createdAt >= 23 * 60 * 60 * 1000) {
                result = { status: "unknown", errorCode: "retry_window_expired" };
              } else if (!attempt && attempts.size >= maxEntries) {
                result = { status: "failed", errorCode: "dispatcher_capacity" };
              } else {
                attempt = attempt || { retryKey: randomUUID(), createdAt: now(), fingerprint };
                attempt.status = "pending";
                attempts.set(key, attempt);
                try {
                  const reply = await adapters[channel]({ recipient: auth.recipient,
                    retryKey: attempt.retryKey, alert: { eventId: event.eventId,
                      riskLevel: event.riskLevel, createdAt: new Date(event.createdAt).toISOString() } });
                  const status = ["accepted", "failed", "unknown", "skipped_disabled"].includes(reply?.status)
                    ? reply.status : "unknown";
                  result = { status };
                  if (status === "failed" || status === "unknown") result.errorCode = "channel_request_unsuccessful";
                } catch (_) { result = { status: "unknown", errorCode: "channel_request_uncertain" }; }
                attempt.status = result.status;
              }
            }
          }
        } catch (_) { result = { status: "skipped_binding" }; }
      }
      const safeResult = { channel, ...result };
      results.push(safeResult);
      // Audit must not delay another channel or delivery results, even if it hangs.
      const auditRecord = { ...safeResult, elderId: scope.elderId, facilityId: scope.facilityId,
        eventId: event.eventId, bindingRef: scope.bindingRef };
      void Promise.resolve().then(() => audit(auditRecord)).catch(() => {});
    }
    return results;
  };
}

module.exports = { createDispatcher };
