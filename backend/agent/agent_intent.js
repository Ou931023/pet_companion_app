// 統一 AI Agent 意圖判斷 + AgentToolResult 結構（CR-0015a）。
//
// 目的：讓「使用者說的話 → 要做什麼」有單一入口與單一結果格式，後續生活工具共用。
// 本模組只做「判斷意圖、產生統一結果」，不執行任何工具（執行屬 CR-0015b 前端 native 層）。
//
// 安全優先：健康危急（health_risk）與情緒危機（emotional_risk）一律優先於一般工具，
// 標記 requiresSafetyFlow=true，交給既有 Care Alert / 安全流程處理，不當成普通工具。
//
// AgentToolResult 結構（單一真相，前後端共用；message 一律白話、無工程字）：
//   {
//     intent: string,            // 友善意圖名（見 AGENT_INTENTS）
//     toolName: string|null,     // 對應後端工具 id（執行用，內部；非工具意圖為 null）
//     needsConfirmation: bool,   // 高影響操作執行前需使用者確認
//     requiresSafetyFlow: bool,  // health_risk / emotional_risk → 走安全流程 / Care Alert
//     message: string,           // 給長者看的白話訊息（不可含工程字）
//     payload: object,           // 工具參數（內部，不直接顯示給使用者）
//     success: bool|null,        // 執行結果；尚未執行為 null
//     error: string|null,        // 失敗代碼（內部，不顯示給使用者）
//   }

const { routeAgentTool } = require("./agent_orchestrator");

/// 統一意圖集合（至少涵蓋本次需求列出的 12 種；額外高影響工具沿用既有偵測）。
const AGENT_INTENTS = Object.freeze([
  "play_music",
  "make_call",
  "send_message",
  "create_reminder",
  "save_memory",
  "recall_memory",
  "navigate",
  "tell_story",
  "search_info",
  "health_risk",
  "emotional_risk",
  "clarify",
  // 額外高影響工具（沿用既有偵測；皆需確認）
  "notify_caregiver",
  "delete_memory",
  "logout",
  "purchase_pet_skin",
  // 沒有工具意圖、交給陪伴對話處理
  "small_talk",
]);

// 後端工具 id → 友善意圖名。
const TOOL_TO_INTENT = Object.freeze({
  play_music: "play_music",
  open_phone_dialer: "make_call",
  send_message: "send_message",
  create_email_draft: "send_message",
  create_reminder: "create_reminder",
  save_memory: "save_memory",
  retrieve_memory: "recall_memory",
  open_app_route: "navigate",
  tell_story: "tell_story",
  search_trusted_info: "search_info",
  notify_caregiver: "notify_caregiver",
  delete_memory: "delete_memory",
  logout: "logout",
  purchase_pet_skin: "purchase_pet_skin",
});

// 情緒危機（自傷 / 活著沒意思 / 沒有人需要我…）。
const EMOTIONAL_RISK_RE =
  /自殺|不想活|活不下去|想死|活著沒意義|活著沒意思|活著沒意|沒有人需要我|沒有人理我|沒有人在乎我|不想拖累/;

// 健康危急（胸痛 / 喘不過氣 / 跌倒 / 劇痛…）。
const HEALTH_RISK_RE =
  /胸口?.{0,3}痛|胸悶|呼吸困難|喘不過氣|喘不過來|喘不過|快喘不|吸不到氣|跌倒|昏倒|劇痛|很痛|嚴重不舒服/;

// 語意不清：只剩語助詞 / 過短沒有可辨識內容。
function isUnclear(text) {
  const stripped = (text || "").toString().replace(/[\s，。、！？!?…．.~～]/g, "");
  if (stripped.length === 0) return true;
  const noFiller = stripped.replace(
    /那個|這個|內個|就是|然後|後來|齁+|蛤+|呃+|欸+|嗯+|啊+|唉+|喔+|嘛+/g,
    "",
  );
  if (noFiller.length === 0) return true;
  if (stripped.length <= 2 && noFiller.length <= 1) return true;
  return false;
}

function buildAgentToolResult({
  intent,
  toolName = null,
  needsConfirmation = false,
  requiresSafetyFlow = false,
  message = "",
  payload = {},
  success = null,
  error = null,
}) {
  return {
    intent,
    toolName,
    needsConfirmation: Boolean(needsConfirmation),
    requiresSafetyFlow: Boolean(requiresSafetyFlow),
    message: (message || "").toString(),
    payload:
      payload && typeof payload === "object" && !Array.isArray(payload)
        ? payload
        : {},
    success: success === null ? null : Boolean(success),
    error: error === null ? null : error.toString(),
  };
}

/// 把一句使用者的話判斷成統一意圖 + AgentToolResult。
function classifyAgentIntent({ userText = "", petName = "陪伴寶" } = {}) {
  const text = (userText || "").toString().trim();
  if (!text) {
    return buildAgentToolResult({
      intent: "clarify",
      message: "我好像沒聽清楚，可以再說一次嗎？",
    });
  }

  // 1) 安全優先：情緒危機 / 健康危急一律優先於一般工具與聊天。
  if (EMOTIONAL_RISK_RE.test(text)) {
    return buildAgentToolResult({
      intent: "emotional_risk",
      requiresSafetyFlow: true,
      message: "我知道你現在很難受，這件事很重要，我們一起找信任的人來陪你，好嗎？",
    });
  }
  if (HEALTH_RISK_RE.test(text)) {
    return buildAgentToolResult({
      intent: "health_risk",
      requiresSafetyFlow: true,
      message: "聽起來身體很不舒服，先別急，我幫你聯絡可以照顧你的人。",
    });
  }

  // 2) 工具意圖：沿用既有 orchestrator / intent builder + 安全政策（確認與否）。
  const routed = routeAgentTool({ userText: text, petName });
  if (routed.hasToolIntent && routed.intent) {
    const toolName = routed.intent.toolName;
    return buildAgentToolResult({
      intent: TOOL_TO_INTENT[toolName] || toolName,
      toolName,
      needsConfirmation: routed.intent.requiresConfirmation,
      message: routed.intent.userFacingMessage,
      payload: routed.intent.arguments || {},
    });
  }

  // 3) 語意不清 → clarify（不要硬猜）。
  if (isUnclear(text)) {
    return buildAgentToolResult({
      intent: "clarify",
      message: "我剛剛沒聽清楚，可以再說一次嗎？",
    });
  }

  // 4) 其餘 → 沒有工具意圖，交給陪伴對話處理。
  return buildAgentToolResult({ intent: "small_talk", message: "" });
}

module.exports = {
  AGENT_INTENTS,
  TOOL_TO_INTENT,
  classifyAgentIntent,
  buildAgentToolResult,
  isUnclear,
};
