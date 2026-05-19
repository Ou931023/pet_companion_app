const TOOL_DEFINITIONS = Object.freeze({
  play_music: {
    displayName: "播放音樂",
    riskLevel: "low",
    requiresConfirmation: false,
    allowedArguments: ["query"],
  },
  open_phone_dialer: {
    displayName: "開啟撥號畫面",
    riskLevel: "high",
    requiresConfirmation: true,
    allowedArguments: ["phoneNumber", "contactName"],
  },
  create_email_draft: {
    displayName: "建立 Email 草稿",
    riskLevel: "medium",
    requiresConfirmation: true,
    allowedArguments: ["to", "subject", "body"],
  },
  create_reminder: {
    displayName: "建立提醒",
    riskLevel: "medium",
    requiresConfirmation: true,
    allowedArguments: ["text", "title", "hour", "minute"],
  },
  search_trusted_info: {
    displayName: "查詢可信資訊",
    riskLevel: "low",
    requiresConfirmation: false,
    allowedArguments: ["query"],
  },
  open_app_route: {
    displayName: "前往 App 頁面",
    riskLevel: "low",
    requiresConfirmation: false,
    allowedArguments: ["route"],
  },
  save_memory: {
    displayName: "記住這件事",
    riskLevel: "medium",
    requiresConfirmation: true,
    allowedArguments: ["memoryText"],
  },
  retrieve_memory: {
    displayName: "查詢長期記憶",
    riskLevel: "low",
    requiresConfirmation: false,
    allowedArguments: ["query"],
  },
});

const RISK_LEVELS = Object.freeze(["low", "medium", "high"]);

function listTools() {
  return Object.entries(TOOL_DEFINITIONS).map(([toolName, definition]) => ({
    toolName,
    displayName: definition.displayName,
    riskLevel: definition.riskLevel,
    requiresConfirmation: definition.requiresConfirmation,
    allowedArguments: definition.allowedArguments,
  }));
}

function getToolDefinition(toolName) {
  return TOOL_DEFINITIONS[toolName] || null;
}

module.exports = {
  TOOL_DEFINITIONS,
  RISK_LEVELS,
  listTools,
  getToolDefinition,
};
