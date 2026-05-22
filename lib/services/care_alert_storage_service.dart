import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/care_alert.dart';

/// 長照提醒的本機儲存服務。
///
/// 以 SharedPreferences 持久化一份 care alert 清單，寫法沿用 ReminderService。
class CareAlertStorageService {
  static const _key = 'careAlerts';

  Future<List<CareAlert>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final items = jsonDecode(raw) as List<dynamic>;
    return items
        .whereType<Map>()
        .map((item) => CareAlert.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<void> save(List<CareAlert> alerts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(alerts.map((item) => item.toJson()).toList()),
    );
  }
}
