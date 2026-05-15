enum VoiceLanguageMode {
  defaultOpenAiRealtime,
  taigiPreferred,
  manualOverride,
}

enum TranscriptLanguageHint {
  zh,
  taigi,
  mixed,
  unknown,
}

extension VoiceLanguageModeLabel on VoiceLanguageMode {
  String get storageValue {
    return switch (this) {
      VoiceLanguageMode.taigiPreferred => 'taigiPreferred',
      VoiceLanguageMode.manualOverride => 'manualOverride',
      VoiceLanguageMode.defaultOpenAiRealtime => 'defaultOpenAiRealtime',
    };
  }

  static VoiceLanguageMode fromStorage(String value) {
    return switch (value) {
      'taigiPreferred' => VoiceLanguageMode.taigiPreferred,
      'manualOverride' => VoiceLanguageMode.manualOverride,
      _ => VoiceLanguageMode.defaultOpenAiRealtime,
    };
  }
}

extension TranscriptLanguageHintLabel on TranscriptLanguageHint {
  String get value {
    return switch (this) {
      TranscriptLanguageHint.zh => 'zh',
      TranscriptLanguageHint.taigi => 'taigi',
      TranscriptLanguageHint.mixed => 'mixed',
      TranscriptLanguageHint.unknown => 'unknown',
    };
  }
}

class LanguageRouteResult {
  const LanguageRouteResult({
    required this.strategyName,
    required this.languageHint,
    required this.routeReason,
    required this.isFallback,
    required this.transcript,
  });

  final String strategyName;
  final TranscriptLanguageHint languageHint;
  final String routeReason;
  final bool isFallback;
  final String transcript;
}
