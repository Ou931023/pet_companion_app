import 'package:shared_preferences/shared_preferences.dart';

import '../models/pet_stats.dart';

class PetStatsStorageService {
  static const _keyIntimacy = 'petStats.intimacy';
  static const _keyFullness = 'petStats.fullness';
  static const _keyMoodValue = 'petStats.moodValue';
  static const _keyLastOpenedDate = 'petStats.lastOpenedDate';

  static const String defaultUserId = 'default_user';

  // CR-0009：寵物狀態依帳號隔離。`default_user`（Demo / 未登入）沿用原本全域
  // key（不動既有資料）；真帳號 elderId 加前綴 `u:<elderId>:`。
  String _userId = defaultUserId;

  void setUserId(String? userId) {
    _userId = (userId == null || userId.isEmpty) ? defaultUserId : userId;
  }

  String get userId => _userId;

  String _k(String key) => _userId == defaultUserId ? key : 'u:$_userId:$key';

  Future<PetStats> load() async {
    final prefs = await SharedPreferences.getInstance();
    final initial = PetStats.initial();
    return PetStats(
      intimacy: prefs.getInt(_k(_keyIntimacy)) ?? initial.intimacy,
      fullness: prefs.getInt(_k(_keyFullness)) ?? initial.fullness,
      moodValue: prefs.getInt(_k(_keyMoodValue)) ?? initial.moodValue,
      lastOpenedDate: prefs.getString(_k(_keyLastOpenedDate)),
    );
  }

  Future<void> save(PetStats stats) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_k(_keyIntimacy), stats.intimacy);
    await prefs.setInt(_k(_keyFullness), stats.fullness);
    await prefs.setInt(_k(_keyMoodValue), stats.moodValue);
    if (stats.lastOpenedDate == null) {
      await prefs.remove(_k(_keyLastOpenedDate));
    } else {
      await prefs.setString(_k(_keyLastOpenedDate), stats.lastOpenedDate!);
    }
  }
}
