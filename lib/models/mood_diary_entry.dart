class MoodDiaryEntry {
  const MoodDiaryEntry({
    required this.id,
    required this.mood,
    required this.content,
    required this.createdAt,
    required this.sharedWithCaregiver,
  });

  static const moods = {
    'happy': '開心',
    'okay': '平靜',
    'low': '低落',
    'worried': '擔心',
  };

  final String id;
  final String mood;
  final String content;
  final DateTime createdAt;
  final bool sharedWithCaregiver;

  factory MoodDiaryEntry.fromJson(Map<String, dynamic> json) {
    return MoodDiaryEntry(
      id: json['id'] as String,
      mood: json['mood'] as String,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      sharedWithCaregiver: json['sharedWithCaregiver'] == true,
    );
  }
}
