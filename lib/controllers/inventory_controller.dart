import 'package:flutter/material.dart';

import '../models/inventory_item.dart';
import '../models/shop_item.dart';
import '../services/inventory_storage_service.dart';

class InventoryController extends ChangeNotifier {
  InventoryController(this._storageService);

  final InventoryStorageService _storageService;
  List<InventoryItem> _items = const [];
  bool _isLoading = true;

  List<InventoryItem> get items => List.unmodifiable(_items);
  bool get isLoading => _isLoading;
  int get totalQuantity => _items.fold(0, (sum, item) => sum + item.quantity);

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    _items = await _storageService.load();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> addFromShop(ShopItem item) async {
    final index = _items.indexWhere((e) => e.itemId == item.id);
    if (index == -1) {
      _items = [
        ..._items,
        InventoryItem(
          itemId: item.id,
          name: item.name,
          emoji: item.emoji,
          quantity: 1,
          category: item.category,
          intimacyDelta: item.intimacyDelta,
          fullnessDelta: item.fullnessDelta,
          moodDelta: item.moodDelta,
          isReviveItem: item.isRevive,
        ),
      ];
    } else {
      final old = _items[index];
      _items = [..._items]..[index] = old.copyWith(quantity: old.quantity + 1);
    }
    await _persist();
  }

  Future<bool> consume(String itemId) async {
    final index = _items.indexWhere((e) => e.itemId == itemId);
    if (index == -1) return false;
    final item = _items[index];
    final next = item.quantity - 1;
    if (next <= 0) {
      _items = [..._items]..removeAt(index);
    } else {
      _items = [..._items]..[index] = item.copyWith(quantity: next);
    }
    await _persist();
    return true;
  }

  InventoryItem? findById(String id) {
    for (final item in _items) {
      if (item.itemId == id) return item;
    }
    return null;
  }

  Future<void> _persist() async {
    await _storageService.save(_items);
    notifyListeners();
  }
}
