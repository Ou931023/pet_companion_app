import 'source_reference.dart';

class SearchResponse {
  const SearchResponse({
    required this.answer,
    required this.summary,
    required this.sources,
    required this.mode,
    required this.provider,
    required this.toolUsed,
    required this.confidence,
    required this.shouldShowSources,
  });

  final String answer;
  final String summary;
  final List<SourceReference> sources;
  final String mode;
  final String provider;
  final String toolUsed;
  final String confidence;
  final bool shouldShowSources;

  factory SearchResponse.fromJson(Map<String, dynamic> json) {
    final rawSources = json['sources'] as List<dynamic>? ?? [];
    return SearchResponse(
      answer: json['answer']?.toString() ?? '',
      summary: json['summary']?.toString() ?? '',
      sources: rawSources
          .whereType<Map>()
          .map((item) => SourceReference.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList(),
      mode: json['mode']?.toString() ?? 'general_web_search',
      provider: json['provider']?.toString() ?? 'mock_fallback',
      toolUsed: json['toolUsed']?.toString() ?? '',
      confidence: json['confidence']?.toString() ?? 'low',
      shouldShowSources: json['shouldShowSources'] == true,
    );
  }
}
