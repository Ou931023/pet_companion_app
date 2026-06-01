import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/reminder.dart';

class ReminderService {
  static const _key = 'careReminders';

  static const String defaultUserId = 'default_user';

  // CR-0012：提醒事項依帳號隔離。`default_user`（Demo / 未登入）沿用原本全域
  // key（不動既有 Demo 資料）；真帳號 elderId 加前綴 `u:<elderId>:`。
  String _userId = defaultUserId;

  void setUserId(String? userId) {
    _userId = (userId == null || userId.isEmpty) ? defaultUserId : userId;
  }

  String get userId => _userId;

  String _k(String key) => _userId == defaultUserId ? key : 'u:$_userId:$key';

  Future<List<Reminder>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k(_key));
    if (raw == null || raw.isEmpty) return [];
    final items = jsonDecode(raw) as List<dynamic>;
    return items
        .whereType<Map>()
        .map((item) => Reminder.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<void> save(List<Reminder> reminders) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _k(_key),
      jsonEncode(reminders.map((item) => item.toJson()).toList()),
    );
  }
}
