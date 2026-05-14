class Reminder {
  const Reminder({
    required this.id,
    required this.title,
    required this.hour,
    required this.minute,
    required this.repeatType,
    required this.note,
    required this.enabled,
  });

  final String id;
  final String title;
  final int hour;
  final int minute;
  final String repeatType;
  final String note;
  final bool enabled;

  String get timeLabel =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  String get repeatLabel {
    return switch (repeatType) {
      'daily' => '每天',
      'weekly' => '每週',
      _ => '一次',
    };
  }

  Reminder copyWith({
    String? title,
    int? hour,
    int? minute,
    String? repeatType,
    String? note,
    bool? enabled,
  }) {
    return Reminder(
      id: id,
      title: title ?? this.title,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      repeatType: repeatType ?? this.repeatType,
      note: note ?? this.note,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'hour': hour,
      'minute': minute,
      'repeatType': repeatType,
      'note': note,
      'enabled': enabled,
    };
  }

  factory Reminder.fromJson(Map<String, dynamic> json) {
    return Reminder(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '提醒',
      hour: json['hour'] as int? ?? 9,
      minute: json['minute'] as int? ?? 0,
      repeatType: json['repeatType'] as String? ?? 'none',
      note: json['note'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}
