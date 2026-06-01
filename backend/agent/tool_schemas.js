// Agent Tool 風險分級（low/medium/high）— 與 Care Alert 的 riskLevel 是兩套不同分類，
// 這裡衡量的是「執行某個工具動作本身的風險」（見 PROJECT_ARCHITECTURE §5.2）。
//
// requiresConfirmation 規則（本次需求 #4 / #5）：
// - 高影響操作（會對外溝通 / 花錢 / 不可逆 / 改變身分狀態）→ requiresConfirmation=true，
//   執行前一定要使用者確認：make_call(open_phone_dialer)、send_message、create_email_draft、
//   notify_caregiver、delete_memory、logout、purchase_pet_skin。
// - 低風險操作可直接執行：create_reminder、play_music(搜尋)、open_app_route(navigate)、
//   tell_story、save_memory(直接做但要讓使用者知道已記住)、search_trusted_info、retrieve_memory。
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
  send_message: {
    displayName: "傳訊息",
    riskLevel: "high",
    requiresConfirmation: true,
    allowedArguments: ["recipient", "contactName", "body"],
  },
  create_email_draft: {
    displayName: "建立 Email 草稿",
    riskLevel: "medium",
    requiresConfirmation: true,
    allowedArguments: ["to", "subject", "body"],
  },
  create_reminder: {
    displayName: "建立提醒",
    riskLevel: "low",
    requiresConfirmation: false,
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
  tell_story: {
    displayName: "說個故事",
    riskLevel: "low",
    requiresConfirmation: false,
    allowedArguments: ["topic"],
  },
  save_memory: {
    displayName: "記住這件事",
    riskLevel: "low",
    requiresConfirmation: false,
    allowedArguments: ["memoryText"],
  },
  retrieve_memory: {
    displayName: "查詢長期記憶",
    riskLevel: "low",
    requiresConfirmation: false,
    allowedArguments: ["query"],
  },
  notify_caregiver: {
    displayName: "通知照護人員",
    riskLevel: "high",
    requiresConfirmation: true,
    allowedArguments: ["reason", "riskLevel"],
  },
  delete_memory: {
    displayName: "刪除記憶",
    riskLevel: "high",
    requiresConfirmation: true,
    allowedArguments: ["target"],
  },
  logout: {
    displayName: "登出",
    riskLevel: "high",
    requiresConfirmation: true,
    allowedArguments: [],
  },
  purchase_pet_skin: {
    displayName: "購買寵物造型",
    riskLevel: "high",
    requiresConfirmation: true,
    allowedArguments: ["skinId", "skinName", "price"],
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
