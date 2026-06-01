import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/inventory_item.dart';

class InventoryStorageService {
  static const _keyInventory = 'inventory.items';

  static const String defaultUserId = 'default_user';

  // CR-0012：背包道具依帳號隔離。`default_user`（Demo / 未登入）沿用原本全域
  // key（不動既有 Demo 資料）；真帳號 elderId 加前綴 `u:<elderId>:`。
  String _userId = defaultUserId;

  void setUserId(String? userId) {
    _userId = (userId == null || userId.isEmpty) ? defaultUserId : userId;
  }

  String get userId => _userId;

  String _k(String key) => _userId == defaultUserId ? key : 'u:$_userId:$key';

  Future<List<InventoryItem>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k(_keyInventory));
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((e) => InventoryItem.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.quantity > 0)
        .toList();
  }

  Future<void> save(List<InventoryItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(items.map((e) => e.toJson()).toList());
    await prefs.setString(_k(_keyInventory), encoded);
  }
}
