/// 長照商城商品（CR-0032）。
///
/// 後端 JSON 採 snake_case（與 DB 欄位 / caregiver_web 一致），這裡轉成 Dart 欄位。
class MarketplaceProduct {
  const MarketplaceProduct({
    required this.id,
    required this.centerId,
    required this.centerName,
    required this.name,
    required this.description,
    required this.category,
    required this.price,
    required this.stock,
    required this.imageUrl,
    required this.status,
    required this.commissionRate,
  });

  final String id;
  final String centerId;
  final String centerName;
  final String name;
  final String description;
  final String category;
  final int price;
  final int stock;
  final String imageUrl;
  final String status;
  final double commissionRate;

  bool get isActive => status == 'active';
  bool get inStock => stock > 0;

  factory MarketplaceProduct.fromJson(Map<String, dynamic> json) {
    return MarketplaceProduct(
      id: (json['id'] ?? '').toString(),
      centerId: (json['center_id'] ?? '').toString(),
      centerName: (json['center_name'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      category: (json['category'] ?? '').toString(),
      price: _toInt(json['price']),
      stock: _toInt(json['stock']),
      imageUrl: (json['image_url'] ?? '').toString(),
      status: (json['status'] ?? 'active').toString(),
      commissionRate: _toDouble(json['commission_rate']),
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
