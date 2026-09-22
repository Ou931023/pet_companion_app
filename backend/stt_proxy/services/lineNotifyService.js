"use strict";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const RISK_LABELS = Object.freeze({ low: "一般關心", medium: "持續觀察", high: "需要關心", urgent: "需要立即協助" });
const TAIPEI_TIME = new Intl.DateTimeFormat("zh-TW", {
  timeZone: "Asia/Taipei", year: "numeric", month: "2-digit", day: "2-digit",
  hour: "2-digit", minute: "2-digit", second: "2-digit", hourCycle: "h23",
});

function buildMinimalMessage(alert) {
  if (!["low", "medium", "high", "urgent"].includes(alert?.riskLevel) ||
      !UUID.test(alert?.eventId) || !Number.isFinite(Date.parse(alert?.createdAt))) return null;
  const parts = Object.fromEntries(TAIPEI_TIME.formatToParts(new Date(alert.createdAt))
    .map(({ type, value }) => [type, value]));
  const time = `${parts.year}/${parts.month}/${parts.day} ${parts.hour}:${parts.minute}:${parts.second}`;
  return `照護提醒\n風險等級：${RISK_LABELS[alert.riskLevel]}\n時間：${time}（Asia/Taipei 台北時間）\n提醒編號：${alert.eventId}\n請查看照護後台，並主動關心長者。`;
}

// Explicit injection only: no environment, database, global recipient or startup IO.
function createLineAdapter({ enabled = false, accessToken, fetchImpl, timeoutMs = 5000 } = {}) {
  return async ({ recipient, alert, retryKey }) => {
    if (enabled !== true || typeof accessToken !== "string" || !accessToken.trim() ||
        typeof fetchImpl !== "function") return { status: "skipped_disabled" };
    const text = buildMinimalMessage(alert);
    if (!text || !UUID.test(retryKey) || !/^[UCR][0-9a-f]{32}$/i.test(recipient)) {
      return { status: "failed", errorCode: "invalid_line_request" };
    }
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(),
      Number.isFinite(timeoutMs) && timeoutMs > 0 ? timeoutMs : 5000);
    try {
      const response = await fetchImpl("https://api.line.me/v2/bot/message/push", {
        method: "POST", redirect: "error", signal: controller.signal,
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${accessToken}`,
          "X-Line-Retry-Key": retryKey },
        body: JSON.stringify({ to: recipient, messages: [{ type: "text", text }] }),
      });
      if (response.status === 200 || (response.status === 409 &&
          response.headers?.get("x-line-accepted-request-id"))) return { status: "accepted" };
      return { status: response.status >= 500 ? "unknown" : "failed", errorCode: "line_request_rejected" };
    } catch (_) {
      return { status: "unknown", errorCode: "line_request_uncertain" };
    } finally {
      clearTimeout(timeout);
    }
  };
}

module.exports = { createLineAdapter, buildMinimalMessage };
