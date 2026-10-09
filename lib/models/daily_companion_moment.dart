enum DailyCompanionMomentStatus { completed, skipped }

/// One optional local activity, independent of care tasks and rewards.
class DailyCompanionMomentRecord {
  const DailyCompanionMomentRecord({required this.date, required this.status});
  final String date;
  final DailyCompanionMomentStatus status;

  static String localDate(DateTime now) =>
      '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';

  String encode() => '$date|${status.name}';

  static DailyCompanionMomentRecord? decode(String? raw) {
    if (raw == null) return null;
    final parts = raw.split('|');
    if (parts.length != 2 ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(parts[0])) {
      return null;
    }
    final day = DateTime.tryParse(parts[0]);
    if (day == null || localDate(day) != parts[0]) return null;
    for (final status in DailyCompanionMomentStatus.values) {
      if (status.name == parts[1]) {
        return DailyCompanionMomentRecord(date: parts[0], status: status);
      }
    }
    return null;
  }
}
