// Telegram 長照通知服務。
//
// 當 App 偵測到長者異常並建立 CareAlert 後，後端透過 Telegram Bot API
// 將「摘要 + 對話片段」推播給長照人員或家屬。
//
// 安全限制：
// - Bot token 只在後端從 process.env 讀取，絕不回傳給前端、絕不寫進 log。
// - 不在 log 印出含 token 的完整 Telegram URL。
// - 只傳 CareAlert 的摘要與片段，不傳完整對話紀錄；片段過長會截斷。

const TELEGRAM_API_BASE = "https://api.telegram.org";
const REQUEST_TIMEOUT_MS = 5000;
const SNIPPET_MAX_LENGTH = 200;

function truncateSnippet(text) {
  const value = typeof text === "string" ? text.trim() : "";
  if (value.length <= SNIPPET_MAX_LENGTH) return value;
  return `${value.slice(0, SNIPPET_MAX_LENGTH)}…`;
}

// 直接採用 ISO 字串裡的牆上時間（不做時區換算），確保顯示與來源一致。
function formatTimestamp(value) {
  if (typeof value === "string") {
    const match = value.match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/);
    if (match) {
      const [, year, month, day, hour, minute] = match;
      return `${year}/${month}/${day} ${hour}:${minute}`;
    }
  }
  const date = value ? new Date(value) : new Date();
  if (Number.isNaN(date.getTime())) return "";
  const pad = (n) => String(n).padStart(2, "0");
  return `${date.getFullYear()}/${pad(date.getMonth() + 1)}/${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

function buildMessage(payload = {}) {
  const riskLevel = payload.riskLevelLabel || payload.riskLevel || "未知";
  const category = payload.categoryLabel || payload.category || "其他";
  const summary =
    (typeof payload.triggerSummary === "string" ? payload.triggerSummary.trim() : "") ||
    "對話中偵測到需要關心的狀況";
  const snippet = truncateSnippet(payload.transcriptSnippet);
  const time = formatTimestamp(payload.createdAt);

  const lines = [
    "【智慧小黑豆照護提醒】",
    "",
    "長者可能需要關心。",
    "",
    `風險等級：${riskLevel}`,
    `類型：${category}`,
    `摘要：${summary}`,
    `對話片段：${snippet}`,
  ];
  if (time) lines.push(`時間：${time}`);
  lines.push("", "建議：請長照人員或家屬主動關心。");
  return lines.join("\n");
}

async function sendCareAlertNotification(payload = {}) {
  const token = process.env.TELEGRAM_BOT_TOKEN;
  const chatId = process.env.TELEGRAM_CARE_CHAT_ID;
  if (!token || !chatId) {
    return { success: false, error: "telegram_not_configured" };
  }

  const text = buildMessage(payload);
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  try {
    const response = await fetch(`${TELEGRAM_API_BASE}/bot${token}/sendMessage`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ chat_id: chatId, text }),
      signal: controller.signal,
    });
    if (!response.ok) {
      return { success: false, error: "telegram_send_failed", status: response.status };
    }
    return { success: true };
  } catch (_error) {
    // 含 timeout（AbortError）與網路錯誤。不回傳 error 物件，避免洩漏含 token 的 URL。
    return { success: false, error: "telegram_request_failed" };
  } finally {
    clearTimeout(timeout);
  }
}

module.exports = {
  sendCareAlertNotification,
  buildMessage,
  truncateSnippet,
  formatTimestamp,
  SNIPPET_MAX_LENGTH,
};
