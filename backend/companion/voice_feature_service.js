function numberOrNull(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function clamp(value, min, max) {
  if (value == null) return null;
  return Math.min(max, Math.max(min, value));
}

function estimateVoiceFeatures({ transcript = "", audioFeatures = {} } = {}) {
  const normalized = {
    volumeMean: numberOrNull(audioFeatures.volumeMean),
    volumeVariance: numberOrNull(audioFeatures.volumeVariance),
    pauseDensity: numberOrNull(audioFeatures.pauseDensity),
    estimatedSpeechRate: numberOrNull(
      audioFeatures.estimatedSpeechRate ?? audioFeatures.speechRate,
    ),
    speechDuration: numberOrNull(audioFeatures.speechDuration),
    silenceDuration: numberOrNull(audioFeatures.silenceDuration),
    confidence: numberOrNull(audioFeatures.confidence),
  };

  const speechDuration = normalized.speechDuration;
  if (normalized.estimatedSpeechRate == null && speechDuration && speechDuration > 0) {
    normalized.estimatedSpeechRate = transcript.trim().length / speechDuration;
  }

  if (
    normalized.pauseDensity == null &&
    normalized.silenceDuration != null &&
    speechDuration != null &&
    speechDuration > 0
  ) {
    normalized.pauseDensity = normalized.silenceDuration / speechDuration;
  }

  const hasSignals = [
    normalized.volumeMean,
    normalized.volumeVariance,
    normalized.pauseDensity,
    normalized.estimatedSpeechRate,
    normalized.speechDuration,
    normalized.silenceDuration,
  ].some((value) => value != null);

  normalized.volumeMean = clamp(normalized.volumeMean, 0, 1);
  normalized.volumeVariance = clamp(normalized.volumeVariance, 0, 1);
  normalized.pauseDensity = clamp(normalized.pauseDensity, 0, 1);
  normalized.estimatedSpeechRate = clamp(normalized.estimatedSpeechRate, 0, 20);
  normalized.speechDuration = clamp(normalized.speechDuration, 0, 600);
  normalized.silenceDuration = clamp(normalized.silenceDuration, 0, 600);
  normalized.confidence = clamp(
    normalized.confidence ?? (hasSignals ? 0.55 : 0),
    0,
    1,
  );

  return normalized;
}

module.exports = {
  estimateVoiceFeatures,
};
