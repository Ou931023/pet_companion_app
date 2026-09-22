"use strict";

const CHANNELS = Object.freeze(["telegram", "line"]);
const DISCLOSURE = "care_alert_minimal_v1";
const id = (value) => typeof value === "string" && /^[a-zA-Z0-9_-]{1,128}$/.test(value);

// No production resolver exists yet. Implementations must read authoritative,
// current assignments, channel-specific consent and recipient bindings.
function createPolicyResolver() {
  return {
    resolvePolicy: async () => null,
    resolveRecipient: async () => null,
    resolveConsent: async () => null,
  };
}

function validPolicy(policy) {
  return policy && id(policy.facilityId) && id(policy.policyVersion) &&
    Array.isArray(policy.channels) && new Set(policy.channels).size === policy.channels.length &&
    policy.channels.every((channel) => CHANNELS.includes(channel) &&
      id(policy.recipientBindingRefs?.[channel]));
}

async function authorize(resolver, scope) {
  const binding = await resolver.resolveRecipient(scope);
  if (!binding || binding.active !== true || binding.assignmentActive !== true ||
      binding.elderId !== scope.elderId || binding.facilityId !== scope.facilityId ||
      binding.channel !== scope.channel || binding.bindingRef !== scope.bindingRef ||
      typeof binding.recipient !== "string" || !binding.recipient.trim()) {
    return { status: "skipped_binding" };
  }
  const consent = await resolver.resolveConsent({ ...scope, disclosure: DISCLOSURE });
  if (!consent || consent.action !== "granted" || consent.disclosure !== DISCLOSURE ||
      !["elderId", "facilityId", "channel", "bindingRef", "policyVersion"].every(
        (key) => consent[key] === scope[key])) return { status: "skipped_consent" };
  return { recipient: binding.recipient };
}

module.exports = { CHANNELS, DISCLOSURE, id, validPolicy, authorize, createPolicyResolver };
