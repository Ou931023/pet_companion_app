import 'package:shared_preferences/shared_preferences.dart';

import '../models/check_in_record.dart';

class CheckInStorageService {
  static const _keyCheckInDates = 'checkin.dates';
  static const _keyLastCheckInDate = 'checkin.lastDate';

  Future<CheckInRecord> load() async {
    final prefs = await SharedPreferences.getInstance();
    final dates = prefs.getStringList(_keyCheckInDates) ?? const <String>[];
    return CheckInRecord(
      checkInDates: dates.toSet(),
      lastCheckInDate: prefs.getString(_keyLastCheckInDate),
    );
  }

  Future<void> save(CheckInRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _keyCheckInDates, record.checkInDates.toList()..sort());
    if (record.lastCheckInDate == null) {
      await prefs.remove(_keyLastCheckInDate);
    } else {
      await prefs.setString(_keyLastCheckInDate, record.lastCheckInDate!);
    }
  }
}
