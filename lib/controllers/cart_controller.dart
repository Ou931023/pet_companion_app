import 'package:flutter/foundation.dart';

import '../models/cart_item.dart';
import '../models/marketplace_product.dart';

/// 購物車狀態（CR-0032）。
///
/// MVP 階段把購物車存在 App 狀態中（記憶體），下單成功後清空。
/// 規則：一次只買同一間照護中心的商品（避免拆單），加入不同中心商品時先提示。
class CartController extends ChangeNotifier {
  final List<CartItem> _items = [];

  List<CartItem> get items => List.unmodifiable(_items);

  bool get isEmpty => _items.isEmpty;

  /// 購物車內商品總件數（含數量）。
  int get totalCount =>
      _items.fold(0, (sum, item) => sum + item.quantity);

  /// 不重複的品項數。
  int get lineCount => _items.length;

  /// 總金額。
  int get totalAmount =>
      _items.fold(0, (sum, item) => sum + item.subtotal);

  /// 目前購物車綁定的照護中心 id（空車時為 null）。
  String? get centerId => _items.isEmpty ? null : _items.first.product.centerId;

  /// 指定商品目前在購物車中的數量（不在則 0）。
  int quantityOf(String productId) {
    for (final item in _items) {
      if (item.product.id == productId) return item.quantity;
    }
    return 0;
  }

  /// 加入商品。
  ///
  /// 回傳是否成功；當購物車已有「其他照護中心」商品時回 false（畫面據此提示）。
  /// 數量不會超過庫存。
  bool addProduct(MarketplaceProduct product, {int quantity = 1}) {
    if (quantity <= 0 || !product.inStock) return false;
    if (_items.isNotEmpty && _items.first.product.centerId != product.centerId) {
      return false;
    }
    final index = _items.indexWhere((item) => item.product.id == product.id);
    if (index >= 0) {
      final next = (_items[index].quantity + quantity).clamp(1, product.stock);
      _items[index] = _items[index].copyWith(quantity: next);
    } else {
      final next = quantity.clamp(1, product.stock);
      _items.add(CartItem(product: product, quantity: next));
    }
    notifyListeners();
    return true;
  }

  /// 設定某商品數量；<=0 視為移除。數量不超過庫存。
  void setQuantity(String productId, int quantity) {
    final index = _items.indexWhere((item) => item.product.id == productId);
    if (index < 0) return;
    if (quantity <= 0) {
      _items.removeAt(index);
    } else {
      final capped = quantity.clamp(1, _items[index].product.stock);
      _items[index] = _items[index].copyWith(quantity: capped);
    }
    notifyListeners();
  }

  void increment(String productId) =>
      setQuantity(productId, quantityOf(productId) + 1);

  void decrement(String productId) =>
      setQuantity(productId, quantityOf(productId) - 1);

  void removeProduct(String productId) {
    _items.removeWhere((item) => item.product.id == productId);
    notifyListeners();
  }

  void clear() {
    if (_items.isEmpty) return;
    _items.clear();
    notifyListeners();
  }
}
