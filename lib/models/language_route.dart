enum VoiceLanguageMode {
  defaultOpenAiRealtime,
  taigiRealtime,
  taigiPreferred,
  manualOverride,
}

enum TranscriptLanguageHint {
  zh,
  taigi,
  mixed,
  unknown,
}

enum ReplyLanguage {
  zhTw,
  taigi,
  mixedZhTaigi,
}

extension VoiceLanguageModeLabel on VoiceLanguageMode {
  String get storageValue {
    return switch (this) {
      VoiceLanguageMode.taigiRealtime => 'taigiRealtime',
      VoiceLanguageMode.taigiPreferred => 'taigiPreferred',
      VoiceLanguageMode.manualOverride => 'manualOverride',
      VoiceLanguageMode.defaultOpenAiRealtime => 'defaultOpenAiRealtime',
    };
  }

  static VoiceLanguageMode fromStorage(String value) {
    return switch (value) {
      'taigiRealtime' => VoiceLanguageMode.taigiRealtime,
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

extension ReplyLanguageLabel on ReplyLanguage {
  String get value {
    return switch (this) {
      ReplyLanguage.zhTw => 'zh-TW',
      ReplyLanguage.taigi => 'taigi',
      ReplyLanguage.mixedZhTaigi => 'mixed-zh-taigi',
    };
  }

  static ReplyLanguage fromValue(String value) {
    return switch (value.trim()) {
      'taigi' => ReplyLanguage.taigi,
      'mixed-zh-taigi' => ReplyLanguage.mixedZhTaigi,
      _ => ReplyLanguage.zhTw,
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
    this.replyLanguage = ReplyLanguage.zhTw,
  });

  final String strategyName;
  final TranscriptLanguageHint languageHint;
  final String routeReason;
  final bool isFallback;
  final String transcript;
  final ReplyLanguage replyLanguage;
}
