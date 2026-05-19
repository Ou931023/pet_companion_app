const { listTools } = require("./tool_schemas");
const { buildSafeIntent } = require("./tool_policy");
const { buildIntentDraft } = require("./tool_intent_builder");

function routeAgentTool(request = {}) {
  const userText = request.userText?.toString().trim() || "";
  const petName = request.petName?.toString().trim() || "陪伴寶";
  const draft = buildIntentDraft({ userText, petName });
  if (!draft) {
    return {
      hasToolIntent: false,
      assistantMessage: "",
      intent: null,
    };
  }
  const safe = buildSafeIntent({
    ...draft,
    id: `agent_tool_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
  });
  if (!safe.ok) {
    return {
      hasToolIntent: false,
      assistantMessage: safe.message,
      intent: null,
      rejectionReason: safe.reason,
    };
  }
  return {
    hasToolIntent: true,
    assistantMessage: safe.intent.requiresConfirmation
      ? "我可以幫你準備，不過執行前需要你確認。"
      : "我可以幫你處理這件事。",
    intent: safe.intent,
  };
}

module.exports = {
  routeAgentTool,
  listTools,
};
