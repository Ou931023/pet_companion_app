class TaigiAsrResult {
  const TaigiAsrResult({
    required this.success,
    required this.transcript,
    required this.language,
    required this.confidence,
    required this.source,
    required this.durationMs,
    this.message = '',
  });

  final bool success;
  final String transcript;
  final String language;
  final double confidence;
  final String source;
  final int durationMs;
  final String message;

  factory TaigiAsrResult.fromJson(Map<String, dynamic> json) {
    return TaigiAsrResult(
      success: true,
      transcript: json['transcript']?.toString().trim() ?? '',
      language: json['language']?.toString() ?? 'taigi',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      source: json['source']?.toString() ?? 'taigi-asr',
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
    );
  }

  factory TaigiAsrResult.unavailable() {
    return const TaigiAsrResult(
      success: false,
      transcript: '',
      language: 'taigi',
      confidence: 0,
      source: 'taigi-asr',
      durationMs: 0,
      message: '目前台語語音辨識暫時無法使用，請稍後再試。',
    );
  }

  factory TaigiAsrResult.empty() {
    return const TaigiAsrResult(
      success: false,
      transcript: '',
      language: 'taigi',
      confidence: 0,
      source: 'taigi-asr',
      durationMs: 0,
      message: '我這次沒有聽清楚，可以再說一次嗎？',
    );
  }
}
