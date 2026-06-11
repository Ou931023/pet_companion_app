// 正式陪伴聊天回覆服務（CR-0049-B1）。
//
// 目的：
// - 為「長者打字 / 非即時文字訊息」提供正式的陪伴 AI 回覆來源，
//   取代 Flutter 端 MockAiService 罐頭回覆。OpenAI 由後端代理，金鑰留後端。
//
// 設計原則：
// - persona / system prompt 由呼叫端（server.js `buildRealtimeInstructions`）組裝後注入，
//   本服務**不自創 persona、不硬寫罐頭**，只負責「驗證輸入 → 代理 OpenAI → 回正式回覆」。
// - 純函式風格，OpenAI client / model / logger 皆由 deps 注入，方便 node --test 以 mock 驗證、不需真 key。
// - 失敗時回明確 error code（`invalid_input` / `openai_unavailable`），
//   **不回 fake/罐頭回覆假裝成功、不回 stack**。
// - log 經 redaction（safeErrorMessage），**不輸出完整 userText / reply / token**。

"use strict";

const { safeErrorMessage } = require("./privacy/redaction");

const DEFAULT_MODEL = "gpt-4o-mini";
const DEFAULT_TEMPERATURE = 0.6;
const DEFAULT_MAX_TOKENS = 220;

// 對話歷史防禦上限：最多保留最後 N 則、每則內容截斷字數（控 token / 防濫用）。
const MAX_HISTORY_MESSAGES = 12;
const MAX_HISTORY_CONTENT_CHARS = 1000;

// 清洗呼叫端帶入的對話歷史：只留 role∈{user,assistant} 且 content 為非空字串；
// content 去空白並截長；取最後 MAX_HISTORY_MESSAGES 則（保留時間序）。
// 任何非陣列 / 髒值都安全降級為空陣列（無 history → 與既有單則行為一致）。
function sanitizeHistory(history) {
  if (!Array.isArray(history)) return [];
  const cleaned = [];
  for (const item of history) {
    if (!item || typeof item !== "object") continue;
    const role = item.role;
    if (role !== "user" && role !== "assistant") continue;
    const content = (item.content == null ? "" : String(item.content)).trim();
    if (!content) continue;
    cleaned.push({ role, content: content.slice(0, MAX_HISTORY_CONTENT_CHARS) });
  }
  return cleaned.length > MAX_HISTORY_MESSAGES
    ? cleaned.slice(-MAX_HISTORY_MESSAGES)
    : cleaned;
}

// 產生一則正式陪伴回覆。
//
// input:
//   - userText：長者輸入的文字（必填，去空白後不可為空）。
//   - systemPrompt：呼叫端組裝好的 persona / instructions（含記憶脈絡與語言指示）。
// deps:
//   - client：OpenAI client（需具備 chat.completions.create）。
//   - hasApiKey：是否具備 OpenAI 金鑰（boolean）。
//   - model / temperature / maxTokens：可選覆寫。
//   - logError：錯誤記錄函式（已套 redaction）。
//
// 回傳：
//   - 成功：{ success: true, reply }
//   - 失敗：{ success: false, error: 'invalid_input' | 'openai_unavailable' }
async function generateCompanionReply(
  { userText, systemPrompt, history } = {},
  deps = {},
) {
  const text = (userText || "").toString().trim();
  if (!text) {
    return { success: false, error: "invalid_input" };
  }

  const client = deps.client;
  const hasApiKey =
    deps.hasApiKey === undefined ? Boolean(client) : Boolean(deps.hasApiKey);
  const logError = typeof deps.logError === "function" ? deps.logError : () => {};

  if (!client || !hasApiKey || typeof client?.chat?.completions?.create !== "function") {
    return { success: false, error: "openai_unavailable" };
  }

  const model = deps.model || DEFAULT_MODEL;
  const temperature =
    deps.temperature === undefined ? DEFAULT_TEMPERATURE : deps.temperature;
  const maxTokens = deps.maxTokens || DEFAULT_MAX_TOKENS;

  // messages 順序：system（persona+記憶摘要）→ 最近對話歷史 → 當前 user 訊息。
  // 帶歷史讓模型有 session 內短期脈絡（不再每則重新打招呼）；無歷史時與既有單則行為一致。
  const messages = [];
  if (systemPrompt && systemPrompt.toString().trim()) {
    messages.push({ role: "system", content: systemPrompt.toString() });
  }
  for (const turn of sanitizeHistory(history)) {
    messages.push({ role: turn.role, content: turn.content });
  }
  messages.push({ role: "user", content: text });

  try {
    const response = await client.chat.completions.create({
      model,
      temperature,
      max_tokens: maxTokens,
      messages,
    });
    const reply = response?.choices?.[0]?.message?.content?.toString().trim();
    if (!reply) {
      // OpenAI 回空內容：不假裝成功、不退罐頭。
      return { success: false, error: "openai_unavailable" };
    }
    return { success: true, reply };
  } catch (error) {
    // log 只留遮蔽過的錯誤摘要（不含 userText / reply / token / stack）。
    logError("companion chat failed", { error: safeErrorMessage(error) });
    return { success: false, error: "openai_unavailable" };
  }
}

module.exports = {
  generateCompanionReply,
  sanitizeHistory,
};
