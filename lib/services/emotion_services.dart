import '../models/emotion_result.dart';
import '../models/pet_status.dart';

class VoiceFeatures {
  const VoiceFeatures({
    this.lowVolume = false,
    this.slowSpeech = false,
    this.manyPauses = false,
    this.largeVolumeChange = false,
  });

  final bool lowVolume;
  final bool slowSpeech;
  final bool manyPauses;
  final bool largeVolumeChange;
}

class TextEmotionService {
  const TextEmotionService();

  EmotionResult analyze(String text) {
    final normalized = text.trim();
    if (_hasAny(normalized, ['開心', '快樂', '很好', '高興', '太好了'])) {
      return const EmotionResult(
        emotion: 'happy',
        confidence: 0.88,
        reason: '出現開心相關詞',
        source: 'text',
      );
    }
    if (_hasAny(normalized, ['難過', '想哭', '心情不好', '傷心', '累'])) {
      return const EmotionResult(
        emotion: 'sad',
        confidence: 0.86,
        reason: '出現難過相關詞',
        source: 'text',
      );
    }
    if (_hasAny(normalized, ['孤單', '寂寞', '無聊', '沒人陪', '沒有人陪', '一個人'])) {
      return const EmotionResult(
        emotion: 'lonely',
        confidence: 0.9,
        reason: '出現孤單陪伴需求',
        source: 'text',
      );
    }
    if (_hasAny(normalized, ['擔心', '害怕', '緊張', '焦慮', '不安'])) {
      return const EmotionResult(
        emotion: 'anxious',
        confidence: 0.84,
        reason: '出現焦慮擔心詞',
        source: 'text',
      );
    }
    if (_hasAny(normalized, ['累', '疲倦', '沒力', '想睡', '睡不好'])) {
      return const EmotionResult(
        emotion: 'tired',
        confidence: 0.82,
        reason: '出現疲憊相關詞',
        source: 'text',
      );
    }
    if (_hasAny(normalized, ['生氣', '火大', '氣死', '不爽'])) {
      return const EmotionResult(
        emotion: 'angry',
        confidence: 0.84,
        reason: '出現生氣相關詞',
        source: 'text',
      );
    }
    return EmotionResult.neutral;
  }

  bool _hasAny(String text, List<String> keywords) {
    return keywords.any(text.contains);
  }
}

class VoiceFeatureService {
  const VoiceFeatureService();

  EmotionResult analyze(VoiceFeatures? features) {
    if (features == null) return EmotionResult.neutral;
    if (features.lowVolume && features.slowSpeech) {
      return const EmotionResult(
        emotion: 'tired',
        confidence: 0.58,
        reason: '音量偏低且語速偏慢',
        source: 'voice',
      );
    }
    if (features.lowVolume && features.manyPauses) {
      return const EmotionResult(
        emotion: 'sad',
        confidence: 0.55,
        reason: '音量偏低且停頓較多',
        source: 'voice',
      );
    }
    if (features.largeVolumeChange) {
      return const EmotionResult(
        emotion: 'anxious',
        confidence: 0.5,
        reason: '音量變化較大',
        source: 'voice',
      );
    }
    return EmotionResult.neutral;
  }
}

class EmotionFusionService {
  const EmotionFusionService({
    this.textEmotionService = const TextEmotionService(),
    this.voiceFeatureService = const VoiceFeatureService(),
  });

  final TextEmotionService textEmotionService;
  final VoiceFeatureService voiceFeatureService;

  EmotionResult analyze({
    required String text,
    VoiceFeatures? voiceFeatures,
  }) {
    try {
      final textResult = textEmotionService.analyze(text);
      final voiceResult = voiceFeatureService.analyze(voiceFeatures);
      if (textResult.emotion != 'neutral') {
        final confidence = voiceResult.emotion == textResult.emotion
            ? (textResult.confidence + 0.08).clamp(0.0, 1.0)
            : textResult.confidence;
        return EmotionResult(
          emotion: textResult.emotion,
          confidence: confidence,
          reason: voiceResult.emotion == textResult.emotion
              ? '${textResult.reason}，語音特徵也接近'
              : textResult.reason,
          source: voiceResult.emotion == textResult.emotion ? 'fusion' : 'text',
        );
      }
      if (voiceResult.emotion != 'neutral') return voiceResult;
      return EmotionResult.neutral;
    } catch (_) {
      return EmotionResult.neutral;
    }
  }
}

class PetEmotionMapper {
  const PetEmotionMapper();

  PetMode modeFor(String emotion) {
    return switch (emotion) {
      'happy' => PetMode.happy,
      'sad' => PetMode.caring,
      'lonely' => PetMode.concerned,
      'anxious' => PetMode.concerned,
      'tired' => PetMode.sleepy,
      'angry' => PetMode.caring,
      _ => PetMode.listening,
    };
  }

  String comfortPrefix(String emotion) {
    return switch (emotion) {
      'sad' => '我聽得出來你有點難過，我陪著你。',
      'lonely' => '你不是一個人，我在這裡陪你。',
      'anxious' => '先慢慢呼吸，我陪你一起穩下來。',
      'tired' => '今天辛苦了，可以先讓身體休息一下。',
      'angry' => '我知道你現在不太舒服，我們先慢慢說。',
      _ => '',
    };
  }
}
