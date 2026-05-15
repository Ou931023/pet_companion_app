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
    };
  }

  static double _doubleValue(Object? value, double fallback) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
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
