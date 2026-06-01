import 'package:shared_preferences/shared_preferences.dart';

import '../models/check_in_record.dart';

class CheckInStorageService {
  static const _keyCheckInDates = 'checkin.dates';
  static const _keyLastCheckInDate = 'checkin.lastDate';

  static const String defaultUserId = 'default_user';

  // CR-0012：簽到紀錄依帳號隔離。`default_user`（Demo / 未登入）沿用原本全域
  // key（不動既有 Demo 資料）；真帳號 elderId 加前綴 `u:<elderId>:`，與
  // CR-0009 LocalStorageService 機制一致。
  String _userId = defaultUserId;

  void setUserId(String? userId) {
    _userId = (userId == null || userId.isEmpty) ? defaultUserId : userId;
  }

  String get userId => _userId;

  String _k(String key) => _userId == defaultUserId ? key : 'u:$_userId:$key';

  Future<CheckInRecord> load() async {
    final prefs = await SharedPreferences.getInstance();
    final dates = prefs.getStringList(_k(_keyCheckInDates)) ?? const <String>[];
    return CheckInRecord(
      checkInDates: dates.toSet(),
      lastCheckInDate: prefs.getString(_k(_keyLastCheckInDate)),
    );
  }

  Future<void> save(CheckInRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _k(_keyCheckInDates), record.checkInDates.toList()..sort());
    if (record.lastCheckInDate == null) {
      await prefs.remove(_k(_keyLastCheckInDate));
    } else {
      await prefs.setString(_k(_keyLastCheckInDate), record.lastCheckInDate!);
    }
  }
}
