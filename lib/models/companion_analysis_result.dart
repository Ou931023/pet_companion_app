class CompanionAnalysisResult {
  const CompanionAnalysisResult({
    required this.turnId,
    required this.emotion,
    required this.emotionConfidence,
    required this.companionNeed,
    required this.needConfidence,
    required this.replyStrategy,
    required this.implicitMeaning,
    required this.petExpression,
    required this.petAction,
    required this.memory,
    required this.safety,
    required this.nextStrategy,
    required this.voiceFeatures,
    required this.fusion,
    this.careAlertSummary = '',
    this.needsSearch = false,
    this.searchTopic = 'none',
    this.knowledgeAnswer = '',
    this.sourceReferences = const [],
  });

  final String turnId;
  final String emotion;
  final double emotionConfidence;
  final String companionNeed;
  final double needConfidence;
  final String replyStrategy;
  final String implicitMeaning;
  final String petExpression;
  final String petAction;
  final CompanionMemoryCandidate memory;
  final CompanionSafetyResult safety;
  final CompanionNextStrategy nextStrategy;
  final CompanionVoiceFeatures voiceFeatures;
  final CompanionEmotionFusion fusion;

  /// Care Alert 人類可讀摘要（後端 companion 產生；給 Telegram / caregiver_web 顯示）。
  final String careAlertSummary;
  final bool needsSearch;
  final String searchTopic;
  final String knowledgeAnswer;
  final List<Map<String, dynamic>> sourceReferences;

  factory CompanionAnalysisResult.fromJson(Map<String, dynamic> json) {
    return CompanionAnalysisResult(
      turnId: json['turnId']?.toString() ?? '',
      emotion: json['emotion']?.toString() ?? 'neutral',
      emotionConfidence: _doubleValue(json['emotionConfidence'], 0.5),
      companionNeed: json['companionNeed']?.toString() ?? 'unknown',
      needConfidence: _doubleValue(json['needConfidence'], 0.5),
      replyStrategy: json['replyStrategy']?.toString() ?? 'normal_chat',
      implicitMeaning: json['implicitMeaning']?.toString() ?? '',
      petExpression: json['petExpression']?.toString() ?? 'idle',
      petAction: json['petAction']?.toString() ?? 'stay',
      memory: CompanionMemoryCandidate.fromJson(
        Map<String, dynamic>.from((json['memory'] as Map?) ?? const {}),
      ),
      safety: CompanionSafetyResult.fromJson(
        Map<String, dynamic>.from((json['safety'] as Map?) ?? const {}),
      ),
      nextStrategy: CompanionNextStrategy.fromJson(
        Map<String, dynamic>.from((json['nextStrategy'] as Map?) ?? const {}),
      ),
      voiceFeatures: CompanionVoiceFeatures.fromJson(
        Map<String, dynamic>.from((json['voiceFeatures'] as Map?) ?? const {}),
      ),
      fusion: CompanionEmotionFusion.fromJson(
        Map<String, dynamic>.from((json['fusion'] as Map?) ?? const {}),
      ),
      careAlertSummary: json['careAlertSummary']?.toString() ?? '',
      needsSearch: json['needsSearch'] == true,
      searchTopic: json['searchTopic']?.toString() ?? 'none',
      knowledgeAnswer: json['knowledgeAnswer']?.toString() ?? '',
      sourceReferences:
          ((json['sourceReferences'] as List<dynamic>?) ?? const [])
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(),
    );
  }

  Map<String, dynamic> toContextJson() {
    return {
      'emotion': emotion,
      'companionNeed': companionNeed,
      'replyStrategy': replyStrategy,
      'petExpression': petExpression,
      'petAction': petAction,
      'nextStrategy': {
        'mode': nextStrategy.mode,
        'instruction': nextStrategy.instruction,
      },
      'voiceFeatures': voiceFeatures.toJson(),
      'fusion': fusion.toJson(),
    };
  }

  static double _doubleValue(Object? value, double fallback) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }
}

class CompanionVoiceFeatures {
  const CompanionVoiceFeatures({
    this.volumeMean,
    this.volumeVariance,
    this.pauseDensity,
    this.estimatedSpeechRate,
    this.speechDuration,
    this.silenceDuration,
    this.confidence = 0,
  });

  final double? volumeMean;
  final double? volumeVariance;
  final double? pauseDensity;
  final double? estimatedSpeechRate;
  final double? speechDuration;
  final double? silenceDuration;
  final double confidence;

  factory CompanionVoiceFeatures.fromJson(Map<String, dynamic> json) {
    return CompanionVoiceFeatures(
      volumeMean: _nullableDouble(json['volumeMean']),
      volumeVariance: _nullableDouble(json['volumeVariance']),
      pauseDensity: _nullableDouble(json['pauseDensity']),
      estimatedSpeechRate: _nullableDouble(json['estimatedSpeechRate']),
      speechDuration: _nullableDouble(json['speechDuration']),
      silenceDuration: _nullableDouble(json['silenceDuration']),
      confidence: CompanionAnalysisResult._doubleValue(json['confidence'], 0),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'volumeMean': volumeMean,
      'volumeVariance': volumeVariance,
      'pauseDensity': pauseDensity,
      'estimatedSpeechRate': estimatedSpeechRate,
      'speechDuration': speechDuration,
      'silenceDuration': silenceDuration,
      'confidence': confidence,
    };
  }

  static double? _nullableDouble(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}

class CompanionEmotionFusion {
  const CompanionEmotionFusion({
    required this.textEmotion,
    required this.finalEmotion,
    required this.confidence,
    required this.reason,
  });

  final String textEmotion;
  final String finalEmotion;
  final double confidence;
  final String reason;

  factory CompanionEmotionFusion.fromJson(Map<String, dynamic> json) {
    return CompanionEmotionFusion(
      textEmotion: json['textEmotion']?.toString() ?? 'neutral',
      finalEmotion: json['finalEmotion']?.toString() ?? 'neutral',
      confidence: CompanionAnalysisResult._doubleValue(json['confidence'], 0.5),
      reason: json['reason']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'finalEmotion': finalEmotion,
      'textEmotion': textEmotion,
      'confidence': confidence,
      'reason': reason,
    };
  }
}

class CompanionMemoryCandidate {
  const CompanionMemoryCandidate({
    required this.shouldSave,
    required this.candidate,
    required this.type,
  });

  final bool shouldSave;
  final String candidate;
  final String type;

  factory CompanionMemoryCandidate.fromJson(Map<String, dynamic> json) {
    return CompanionMemoryCandidate(
      shouldSave: json['shouldSave'] == true,
      candidate: json['candidate']?.toString() ?? '',
      type: json['type']?.toString() ?? 'none',
    );
  }
}

class CompanionSafetyResult {
  const CompanionSafetyResult({
    required this.riskLevel,
    required this.needsHumanSupport,
  });

  final String riskLevel;
  final bool needsHumanSupport;

  factory CompanionSafetyResult.fromJson(Map<String, dynamic> json) {
    return CompanionSafetyResult(
      riskLevel: json['riskLevel']?.toString() ?? 'normal',
      needsHumanSupport: json['needsHumanSupport'] == true,
    );
  }
}

class CompanionNextStrategy {
  const CompanionNextStrategy({
    required this.mode,
    required this.instruction,
  });

  final String mode;
  final String instruction;

  factory CompanionNextStrategy.fromJson(Map<String, dynamic> json) {
    return CompanionNextStrategy(
      mode: json['mode']?.toString() ?? 'normal_chat',
      instruction: json['instruction']?.toString() ?? '',
    );
  }
}
