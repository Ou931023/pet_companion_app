import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/care_alert.dart';

/// 長照提醒的本機儲存服務。
///
/// 以 SharedPreferences 持久化一份 care alert 清單，寫法沿用 ReminderService。
class CareAlertStorageService {
  static const _key = 'careAlerts';

  static const String defaultUserId = 'default_user';

  // CR-0012：本機 Care Alert 快取依帳號隔離。`default_user`（Demo / 未登入）沿用
  // 原本全域 key（不動既有 Demo 資料）；真帳號 elderId 加前綴 `u:<elderId>:`。
  String _userId = defaultUserId;

  void setUserId(String? userId) {
    _userId = (userId == null || userId.isEmpty) ? defaultUserId : userId;
  }

  String get userId => _userId;

  String _k(String key) => _userId == defaultUserId ? key : 'u:$_userId:$key';

  Future<List<CareAlert>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k(_key));
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
      _k(_key),
      jsonEncode(alerts.map((item) => item.toJson()).toList()),
    );
  }
}
