class EmotionResult {
  const EmotionResult({
    required this.emotion,
    required this.confidence,
    required this.reason,
    required this.source,
  });

  final String emotion;
  final double confidence;
  final String reason;
  final String source;

  static const neutral = EmotionResult(
    emotion: 'neutral',
    confidence: 0.4,
    reason: '沒有明確情緒詞',
    source: 'text',
  );
}
