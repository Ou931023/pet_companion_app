import 'package:shared_preferences/shared_preferences.dart';

import '../models/pet_stats.dart';

class PetStatsStorageService {
  static const _keyIntimacy = 'petStats.intimacy';
  static const _keyFullness = 'petStats.fullness';
  static const _keyMoodValue = 'petStats.moodValue';
  static const _keyLastOpenedDate = 'petStats.lastOpenedDate';

  Future<PetStats> load() async {
    final prefs = await SharedPreferences.getInstance();
    final initial = PetStats.initial();
    return PetStats(
      intimacy: prefs.getInt(_keyIntimacy) ?? initial.intimacy,
      fullness: prefs.getInt(_keyFullness) ?? initial.fullness,
      moodValue: prefs.getInt(_keyMoodValue) ?? initial.moodValue,
      lastOpenedDate: prefs.getString(_keyLastOpenedDate),
    );
  }

  Future<void> save(PetStats stats) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyIntimacy, stats.intimacy);
    await prefs.setInt(_keyFullness, stats.fullness);
    await prefs.setInt(_keyMoodValue, stats.moodValue);
    if (stats.lastOpenedDate == null) {
      await prefs.remove(_keyLastOpenedDate);
    } else {
      await prefs.setString(_keyLastOpenedDate, stats.lastOpenedDate!);
    }
  }
}
