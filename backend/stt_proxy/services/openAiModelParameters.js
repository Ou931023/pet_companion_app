"use strict";

const DEFAULT_TEXT_MODEL = "gpt-6-luna";
const DEFAULT_REALTIME_MODEL = "gpt-realtime-2.1";

// Preserve the previous non-reasoning workload and legacy override request shape.
// Low reasoning is an evaluation candidate, not an unmeasured production default.
function chatModelParameters(model, { temperature, maxTokens, lunaMaxTokens = 2048 } = {}) {
  const parameters = { model };
  if (temperature !== undefined) parameters.temperature = temperature;
  if (model === DEFAULT_TEXT_MODEL) {
    parameters.reasoning_effort = "none";
    parameters.max_completion_tokens = maxTokens ?? lunaMaxTokens;
  } else if (maxTokens !== undefined) {
    parameters.max_tokens = maxTokens;
  }
  return parameters;
}

function fileTranscriptionParameters(env = process.env) {
  const model = env.STT_MODEL || "gpt-transcribe";
  const parameters = { model, response_format: "json" };
  // Leave language detection automatic unless the operator supplies hints.
  // These hints belong only to completed-file transcription, never WebRTC.
  if (model === "gpt-transcribe" && env.STT_LANGUAGES?.trim()) {
    const languages = [...new Set(env.STT_LANGUAGES.split(",").map(value => value.trim()))];
    if (languages.some(value => !["zh", "zh-tw", "cmn", "en"].includes(value))) {
      throw new Error("Unsupported STT_LANGUAGES configuration");
    }
    parameters.languages = languages;
  }
  return parameters;
}

function realtimeModelParameters(model) {
  return model === DEFAULT_REALTIME_MODEL
    ? { model, reasoning: { effort: "low" }, max_output_tokens: 1024 }
    : { model };
}

// Inspect the same choice callers consume, before parsing or persisting content.
// A bounded response may contain parseable JSON despite being incomplete.
function completionContent(response) {
  const choice = response?.choices?.[0];
  if (["length", "content_filter"].includes(choice?.finish_reason) || choice?.message?.refusal) {
    throw new Error("Incomplete or refused model response");
  }
  return choice?.message?.content;
}

module.exports = { DEFAULT_TEXT_MODEL, DEFAULT_REALTIME_MODEL, chatModelParameters, fileTranscriptionParameters, realtimeModelParameters, completionContent };
