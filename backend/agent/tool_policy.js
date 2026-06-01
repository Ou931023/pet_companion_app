const { RISK_LEVELS, getToolDefinition } = require("./tool_schemas");

function sanitizeArguments(toolName, rawArguments = {}) {
  const definition = getToolDefinition(toolName);
  if (!definition) return {};
  const input =
    rawArguments && typeof rawArguments === "object" && !Array.isArray(rawArguments)
      ? rawArguments
      : {};
  const allowed = new Set(definition.allowedArguments);
  return Object.fromEntries(
    Object.entries(input)
      .filter(([key]) => allowed.has(key))
      .map(([key, value]) => [key, sanitizeValue(value)]),
  );
}

function sanitizeValue(value) {
  if (value == null) return "";
  if (typeof value === "number" || typeof value === "boolean") return value;
  return value.toString().trim().slice(0, 500);
}

function validateIntentDraft(draft) {
  const toolName = draft?.toolName?.toString().trim();
  const definition = getToolDefinition(toolName);
  if (!definition) {
    return {
      ok: false,
      reason: "unknown_tool",
      message: "這個工具目前不支援，我先不執行。",
    };
  }
  const riskLevel = draft?.riskLevel || definition.riskLevel;
  if (!RISK_LEVELS.includes(riskLevel)) {
    return {
      ok: false,
      reason: "invalid_risk_level",
      message: "工具風險設定不正確，我先不執行。",
    };
  }
  if (riskLevel !== definition.riskLevel) {
    return {
      ok: false,
      reason: "risk_policy_mismatch",
      message: "工具風險設定不符合安全規則，我先不執行。",
    };
  }
  return {
    ok: true,
    toolName,
    definition,
    riskLevel,
    requiresConfirmation: definition.requiresConfirmation,
    arguments: sanitizeArguments(toolName, draft.arguments),
  };
}

function buildSafeIntent(draft) {
  const validation = validateIntentDraft(draft);
  if (!validation.ok) return validation;
  return {
    ok: true,
    intent: {
      id: draft.id || `agent_tool_${Date.now()}`,
      toolName: validation.toolName,
      displayName: draft.displayName || validation.definition.displayName,
      arguments: validation.arguments,
      requiresConfirmation: validation.requiresConfirmation,
      riskLevel: validation.riskLevel,
      status: "pending",
      userFacingMessage:
        draft.userFacingMessage ||
        defaultUserFacingMessage(validation.toolName, validation.definition),
      createdAt: new Date().toISOString(),
    },
  };
}

// 高影響操作的白話確認文字（給長者看 / 寵物口語確認；只問一個清楚問題）。
const CONFIRMATION_MESSAGES = Object.freeze({
  open_phone_dialer: "要幫你開啟撥號畫面嗎？不會自動撥出。",
  send_message: "要幫你傳這則訊息嗎？傳出前你再確認一次內容。",
  create_email_draft: "要幫你建立 Email 草稿嗎？不會自動寄出。",
  notify_caregiver: "要我通知照護人員嗎？",
  delete_memory: "要刪掉這個記憶嗎？刪掉就找不回來囉。",
  logout: "要幫你登出嗎？",
  purchase_pet_skin: "要購買這個寵物造型嗎？",
});

function defaultUserFacingMessage(toolName, definition) {
  if (CONFIRMATION_MESSAGES[toolName]) {
    return CONFIRMATION_MESSAGES[toolName];
  }
  if (definition.requiresConfirmation) {
    return `要執行「${definition.displayName}」嗎？`;
  }
  return `我可以幫你執行「${definition.displayName}」。`;
}

module.exports = {
  sanitizeArguments,
  validateIntentDraft,
  buildSafeIntent,
  defaultUserFacingMessage,
};
