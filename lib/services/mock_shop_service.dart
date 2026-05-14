import '../models/shop_product.dart';

class MockShopService {
  final List<ShopProduct> _products = const [
    ShopProduct(
      id: 'p1',
      name: '狗狗餅乾',
      price: 30,
      category: '寵物互動商品',
      description: '香脆口感，互動獎勵小點心。',
    ),
    ShopProduct(
      id: 'p2',
      name: '營養補充飲',
      price: 45,
      category: '營養補充',
      description: '每日營養補充，適合長者。',
    ),
    ShopProduct(
      id: 'p3',
      name: '防滑墊',
      price: 60,
      category: '安全輔具',
      description: '提升居家行走安全。',
    ),
    ShopProduct(
      id: 'p4',
      name: '血壓機',
      price: 120,
      category: '健康監測',
      description: '居家量測血壓。',
    ),
    ShopProduct(
      id: 'p5',
      name: '看護墊',
      price: 50,
      category: '日常照護',
      description: '日常照護防漏耗材。',
    ),
    ShopProduct(
      id: 'p6',
      name: '寵物玩具',
      price: 35,
      category: '寵物互動商品',
      description: '互動陪伴玩具。',
    ),
  ];

  List<ShopProduct> get products => List.unmodifiable(_products);

  ShopProduct? findByText(String text) {
    for (final product in _products) {
      if (text.contains(product.name)) {
        return product;
      }
    }
    return null;
  }
}
