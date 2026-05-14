class MemoryItem {
  const MemoryItem({
    required this.id,
    required this.summary,
    required this.memoryType,
    required this.emotion,
    required this.importance,
    required this.similarity,
    required this.createdAt,
  });

  final String id;
  final String summary;
  final String memoryType;
  final String emotion;
  final double importance;
  final double similarity;
  final DateTime createdAt;

  factory MemoryItem.fromJson(Map<String, dynamic> json) {
    return MemoryItem(
      id: (json["id"] ?? "").toString(),
      summary: (json["summary"] ?? "").toString(),
      memoryType: (json["memoryType"] ?? "").toString(),
      emotion: (json["emotion"] ?? "").toString(),
      importance: (json["importance"] as num?)?.toDouble() ?? 0,
      similarity: (json["similarity"] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.tryParse((json["createdAt"] ?? "").toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
