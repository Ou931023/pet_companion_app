import 'marketplace_product.dart';

/// 購物車中的一筆商品（商品 + 數量），CR-0032。
class CartItem {
  const CartItem({required this.product, required this.quantity});

  final MarketplaceProduct product;
  final int quantity;

  /// 小計 = 單價 × 數量。
  int get subtotal => product.price * quantity;

  CartItem copyWith({int? quantity}) =>
      CartItem(product: product, quantity: quantity ?? this.quantity);
}
