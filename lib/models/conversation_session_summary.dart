class ConversationSessionSummary {
  const ConversationSessionSummary({
    required this.sessionId,
    required this.title,
    required this.updatedAt,
    required this.lastPreview,
    required this.emotionTag,
  });

  final String sessionId;
  final String title;
  final DateTime updatedAt;
  final String lastPreview;
  final String emotionTag;
}
