const SUPPORTED_EMOTIONS = new Set([
  "happy",
  "neutral",
  "sad",
  "lonely",
  "anxious",
  "tired",
  "nostalgic",
]);

function clampConfidence(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) return 0.5;
  return Number(Math.min(1, Math.max(0, number)).toFixed(2));
}

function supportedEmotion(value) {
  return SUPPORTED_EMOTIONS.has(value) ? value : "neutral";
}

function hasUsefulVoice(features = {}) {
  return Number(features.confidence || 0) > 0 && (
    features.pauseDensity != null ||
    features.estimatedSpeechRate != null ||
    features.volumeVariance != null ||
    features.volumeMean != null
  );
}

function fuseEmotion({
  textEmotion = "neutral",
  textConfidence = 0.5,
  voiceFeatures = {},
  companionNeed = "unknown",
} = {}) {
  const emotion = supportedEmotion(textEmotion);
  let finalEmotion = emotion;
  let confidence = clampConfidence(textConfidence);
  const pauseDensity = Number(voiceFeatures.pauseDensity);
  const speechRate = Number(voiceFeatures.estimatedSpeechRate);
  const volumeVariance = Number(voiceFeatures.volumeVariance);

  if (!hasUsefulVoice(voiceFeatures)) {
    return {
      finalEmotion,
      confidence,
      reason: "語音特徵不足，以文字情緒推測為主。",
    };
  }

  const highPause = Number.isFinite(pauseDensity) && pauseDensity >= 0.45;
  const slowSpeech = Number.isFinite(speechRate) && speechRate > 0 && speechRate <= 1.6;
  const fastSpeech = Number.isFinite(speechRate) && speechRate >= 4.0;
  const unstableVolume = Number.isFinite(volumeVariance) && volumeVariance >= 0.35;

  if (emotion === "lonely" && highPause) {
    confidence += 0.1;
    return {
      finalEmotion: "lonely",
      confidence: clampConfidence(confidence),
      reason: "文字內容偏孤單，且停頓密度較高。",
    };
  }

  if (emotion === "anxious" && (fastSpeech || unstableVolume)) {
    confidence += fastSpeech && unstableVolume ? 0.12 : 0.08;
    return {
      finalEmotion: "anxious",
      confidence: clampConfidence(confidence),
      reason: "文字內容偏焦慮，語速或音量變化也較明顯。",
    };
  }

  if (emotion === "happy" && fastSpeech) {
    confidence += 0.07;
    return {
      finalEmotion: "happy",
      confidence: clampConfidence(confidence),
      reason: "文字內容偏正向，語速也較有精神。",
    };
  }

  if (emotion === "neutral" && slowSpeech && highPause) {
    finalEmotion = companionNeed === "companionship" ? "sad" : "tired";
    confidence = Math.max(confidence, 0.62);
    return {
      finalEmotion,
      confidence: clampConfidence(confidence),
      reason: "文字情緒不明顯，但語速較慢且停頓較多，可能感受偏疲憊或低落。",
    };
  }

  if ((emotion === "sad" || emotion === "tired") && slowSpeech) {
    confidence += 0.06;
    return {
      finalEmotion: emotion,
      confidence: clampConfidence(confidence),
      reason: "文字內容與較慢語速方向一致。",
    };
  }

  return {
    finalEmotion,
    confidence,
    reason: "語音特徵未明顯改變文字情緒推測。",
  };
}

module.exports = {
  fuseEmotion,
  SUPPORTED_EMOTIONS,
};
