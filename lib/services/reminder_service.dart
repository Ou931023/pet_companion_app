import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/reminder.dart';

class ReminderService {
  static const _key = 'careReminders';

  Future<List<Reminder>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
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
      _key,
      jsonEncode(reminders.map((item) => item.toJson()).toList()),
    );
  }
}
