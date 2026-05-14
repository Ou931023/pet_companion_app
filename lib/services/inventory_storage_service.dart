import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/inventory_item.dart';

class InventoryStorageService {
  static const _keyInventory = 'inventory.items';

  Future<List<InventoryItem>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyInventory);
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
    await prefs.setString(_keyInventory, encoded);
  }
}
