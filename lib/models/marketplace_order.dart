// 長照商城訂單與訂單明細（CR-0032）。後端 JSON 為 snake_case。

class MarketplaceOrderItem {
  const MarketplaceOrderItem({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.subtotal,
  });

  final String productId;
  final String productName;
  final int quantity;
  final int unitPrice;
  final int subtotal;

  factory MarketplaceOrderItem.fromJson(Map<String, dynamic> json) {
    return MarketplaceOrderItem(
      productId: (json['product_id'] ?? '').toString(),
      productName: (json['product_name'] ?? '').toString(),
      quantity: _toInt(json['quantity']),
      unitPrice: _toInt(json['unit_price']),
      subtotal: _toInt(json['subtotal']),
    );
  }

  static int _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class MarketplaceOrder {
  const MarketplaceOrder({
    required this.id,
    required this.userId,
    required this.elderName,
    required this.centerId,
    required this.centerName,
    required this.items,
    required this.totalAmount,
    required this.commissionRate,
    required this.commissionAmount,
    required this.centerRevenue,
    required this.status,
    required this.deliveryNote,
  });

  final String id;
  final String userId;
  final String elderName;
  final String centerId;
  final String centerName;
  final List<MarketplaceOrderItem> items;
  final int totalAmount;
  final double commissionRate;
  final int commissionAmount;
  final int centerRevenue;
  final String status;
  final String deliveryNote;

  static const Map<String, String> statusLabels = {
    'pending': '待處理',
    'confirmed': '已確認',
    'shipping': '配送中',
    'completed': '已完成',
    'cancelled': '已取消',
  };

  String get statusLabel => statusLabels[status] ?? status;

  factory MarketplaceOrder.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final items = (rawItems is List ? rawItems : const [])
        .whereType<Map<String, dynamic>>()
        .map(MarketplaceOrderItem.fromJson)
        .toList();
    return MarketplaceOrder(
      id: (json['id'] ?? '').toString(),
      userId: (json['user_id'] ?? '').toString(),
      elderName: (json['elder_name'] ?? '').toString(),
      centerId: (json['center_id'] ?? '').toString(),
      centerName: (json['center_name'] ?? '').toString(),
      items: items,
      totalAmount: _toInt(json['total_amount']),
      commissionRate: _toDouble(json['commission_rate']),
      commissionAmount: _toInt(json['commission_amount']),
      centerRevenue: _toInt(json['center_revenue']),
      status: (json['status'] ?? 'pending').toString(),
      deliveryNote: (json['delivery_note'] ?? '').toString(),
    );
  }

  static int _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
