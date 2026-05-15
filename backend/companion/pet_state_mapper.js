function mapReplyStrategy({ emotion, companionNeed }) {
  if (companionNeed === "reminiscence") return "reminiscence_followup";
  if (companionNeed === "grounding") return "calm_down";
  if (companionNeed === "companionship") return "soft_companion";
  if (companionNeed === "emotional_support") return "gentle_checkin";
  if (companionNeed === "daily_chat") return "keep_company";
  if (companionNeed === "encouragement") return "encourage_small_step";
  if (emotion === "anxious") return "calm_down";
  if (emotion === "lonely") return "soft_companion";
  if (emotion === "sad") return "gentle_checkin";
  return "normal_chat";
}

function mapPetState({ emotion, companionNeed, replyStrategy }) {
  if (replyStrategy === "reminiscence_followup") {
    return { petExpression: "calm", petAction: "nod" };
  }
  if (replyStrategy === "calm_down") {
    return { petExpression: emotion === "tired" ? "sleepy" : "calm", petAction: "comfort" };
  }
  if (replyStrategy === "soft_companion" || companionNeed === "companionship") {
    return { petExpression: "concerned", petAction: "move_closer" };
  }
  if (replyStrategy === "gentle_checkin") {
    return { petExpression: "concerned", petAction: "comfort" };
  }
  if (replyStrategy === "encourage_small_step") {
    return { petExpression: "happy", petAction: "cheer" };
  }
  if (emotion === "happy") {
    return { petExpression: "happy", petAction: "wag_tail" };
  }
  if (emotion === "tired") {
    return { petExpression: "sleepy", petAction: "rest" };
  }
  return { petExpression: "idle", petAction: "stay" };
}

module.exports = {
  mapReplyStrategy,
  mapPetState,
};
