import 'source_reference.dart';

class ConversationTurn {
  const ConversationTurn({
    required this.timestamp,
    required this.userText,
    required this.petReply,
    required this.toolName,
    this.turnId = '',
    this.sessionId = '',
    this.emotionTag = 'neutral',
    this.petMood = 'neutral',
    this.toolUsed = '',
    this.searchMode = '',
    this.searchProvider = '',
    this.sources = const [],
    this.memoryExtracted = false,
    this.memorySaved = false,
    this.savedMemoryIds = const [],
    this.memoryExtractionReason,
    this.memoryUsed = false,
    this.usedMemoryIds = const [],
    this.memoryContextSummary,
    this.memoryProvider,
  });

  final DateTime timestamp;
  final String userText;
  final String petReply;
  final String toolName;
  final String turnId;
  final String sessionId;
  final String emotionTag;
  final String petMood;
  final String toolUsed;
  final String searchMode;
  final String searchProvider;
  final List<SourceReference> sources;
  final bool memoryExtracted;
  final bool memorySaved;
  final List<dynamic> savedMemoryIds;
  final String? memoryExtractionReason;
  final bool memoryUsed;
  final List<dynamic> usedMemoryIds;
  final String? memoryContextSummary;
  final String? memoryProvider;

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'userText': userText,
      'petReply': petReply,
      'toolName': toolName,
      'toolUsed': toolUsed.isEmpty ? toolName : toolUsed,
      'turnId': turnId,
      'sessionId': sessionId,
      'emotionTag': emotionTag,
      'petMood': petMood,
      'mode': searchMode,
      'provider': searchProvider,
      'sources': sources.map((source) => source.toJson()).toList(),
      'memoryExtracted': memoryExtracted,
      'memorySaved': memorySaved,
      'savedMemoryIds': savedMemoryIds,
      'memoryExtractionReason': memoryExtractionReason,
      'memoryUsed': memoryUsed,
      'usedMemoryIds': usedMemoryIds,
      'memoryContextSummary': memoryContextSummary,
      'memoryProvider': memoryProvider,
    };
  }

  factory ConversationTurn.fromJson(Map<String, dynamic> json) {
    final timestampText = json['timestamp']?.toString() ?? '';
    final rawSources = json['sources'] as List<dynamic>? ?? [];
    return ConversationTurn(
      timestamp: DateTime.tryParse(timestampText) ?? DateTime.now(),
      userText: json['userText']?.toString() ?? '',
      petReply:
          json['petReply']?.toString() ?? json['agentReply']?.toString() ?? '',
      toolName: json['toolName']?.toString() ??
          json['toolUsed']?.toString() ??
          'chat',
      turnId: json['turnId']?.toString() ?? '',
      sessionId: json['sessionId']?.toString() ?? '',
      emotionTag: json['emotionTag']?.toString() ??
          json['emotion']?.toString() ??
          'neutral',
      petMood: json['petMood']?.toString() ?? 'neutral',
      toolUsed: json['toolUsed']?.toString() ?? '',
      searchMode: json['mode']?.toString() ?? '',
      searchProvider: json['provider']?.toString() ?? '',
      sources: rawSources
          .whereType<Map>()
          .map((source) => SourceReference.fromJson(
                Map<String, dynamic>.from(source),
              ))
          .toList(),
      memoryExtracted: json['memoryExtracted'] == true,
      memorySaved: json['memorySaved'] == true,
      savedMemoryIds: json['savedMemoryIds'] as List<dynamic>? ?? const [],
      memoryExtractionReason: json['memoryExtractionReason']?.toString(),
      memoryUsed: json['memoryUsed'] == true,
      usedMemoryIds: json['usedMemoryIds'] as List<dynamic>? ?? const [],
      memoryContextSummary: json['memoryContextSummary']?.toString(),
      memoryProvider: json['memoryProvider']?.toString(),
    );
  }
}
