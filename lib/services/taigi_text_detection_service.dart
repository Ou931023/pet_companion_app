class TaigiTextDetectionResult {
  const TaigiTextDetectionResult({
    required this.isLikelyTaigi,
    required this.confidence,
    required this.matchedKeywords,
    required this.languageHint,
    required this.reason,
  });

  final bool isLikelyTaigi;
  final double confidence;
  final List<String> matchedKeywords;
  final String languageHint;
  final String reason;

  Map<String, dynamic> toJson() {
    return {
      'isLikelyTaigi': isLikelyTaigi,
      'confidence': confidence,
      'matchedKeywords': matchedKeywords,
      'languageHint': languageHint,
      'reason': reason,
    };
  }
}

class TaigiTextDetectionService {
  const TaigiTextDetectionService();

  static const _strongKeywords = [
    '今仔日',
    '食飽未',
    '袂',
    '毋',
    '佮',
    '阮',
    '恁',
    '予',
    '攏',
    '啥物',
    '𠢕',
    '歹勢',
    '拍謝',
    '有影',
    '毋免',
    '走袂開',
    '心情無好',
    '睏袂去',
    '睏袂好',
    '逐家',
    '無聊',
  ];

  static const _contextualKeywords = [
    '無好',
    '欲',
    '足',
    '較',
    '甘',
    '阿公',
    '阿嬤',
    '厝內',
  ];

  TaigiTextDetectionResult detect(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), '').trim();
    if (normalized.isEmpty) {
      return const TaigiTextDetectionResult(
        isLikelyTaigi: false,
        confidence: 0,
        matchedKeywords: [],
        languageHint: 'zh',
        reason: 'empty_text',
      );
    }

    final matched = <String>[
      for (final keyword in _strongKeywords)
        if (normalized.contains(keyword)) keyword,
      for (final keyword in _contextualKeywords)
        if (normalized.contains(keyword)) keyword,
    ];
    final uniqueMatches = matched.toSet().toList(growable: false);
    final strongCount =
        _strongKeywords.where((keyword) => normalized.contains(keyword)).length;
    final contextualCount = _contextualKeywords
        .where((keyword) => normalized.contains(keyword))
        .length;
    final hasCjk = RegExp(r'[\u4e00-\u9fff]').hasMatch(normalized);
    final likely = strongCount > 0 || contextualCount >= 2;
    final confidence = likely
        ? (0.55 + strongCount * 0.22 + contextualCount * 0.10).clamp(0.0, 0.95)
        : (contextualCount == 1 ? 0.34 : 0.08);
    final reason = !likely
        ? 'no_taigi_keywords'
        : hasCjk && uniqueMatches.length >= 2
            ? 'matched_taigi_mixed_zh_keywords'
            : 'matched_taigi_keywords';

    return TaigiTextDetectionResult(
      isLikelyTaigi: likely,
      confidence: confidence.toDouble(),
      matchedKeywords: uniqueMatches,
      languageHint: likely ? 'taigi' : 'zh',
      reason: reason,
    );
  }
}
