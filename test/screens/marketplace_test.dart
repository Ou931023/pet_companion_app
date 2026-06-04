import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:pet_companion_app/controllers/cart_controller.dart';
import 'package:pet_companion_app/controllers/marketplace_controller.dart';
import 'package:pet_companion_app/models/cart_item.dart';
import 'package:pet_companion_app/models/marketplace_product.dart';
import 'package:pet_companion_app/screens/marketplace/cart_screen.dart';
import 'package:pet_companion_app/screens/marketplace/marketplace_screen.dart';
import 'package:pet_companion_app/services/marketplace_service.dart';

MarketplaceProduct _product({
  String id = 'p1',
  String centerId = 'c1',
  String name = '防滑沐浴椅',
  String category = '照護用品',
  int price = 1800,
  int stock = 12,
}) {
  return MarketplaceProduct(
    id: id,
    centerId: centerId,
    centerName: '安心長照中心',
    name: name,
    description: '洗澡時穩穩坐著，防滑安全。',
    category: category,
    price: price,
    stock: stock,
    imageUrl: '',
    status: 'active',
    commissionRate: 0.1,
  );
}

class _FakeMarketplaceService extends MarketplaceService {
  _FakeMarketplaceService(this._products);
  final List<MarketplaceProduct> _products;

  @override
  Future<List<MarketplaceProduct>> listProducts({String category = ''}) async {
    if (category.trim().isEmpty) return _products;
    return _products.where((p) => p.category == category).toList();
  }
}

void main() {
  group('CartController', () {
    test('加入同商品會累加數量並計算總額', () {
      final cart = CartController();
      final product = _product(price: 1800, stock: 12);
      expect(cart.addProduct(product), isTrue);
      expect(cart.addProduct(product, quantity: 2), isTrue);
      expect(cart.totalCount, 3);
      expect(cart.lineCount, 1);
      expect(cart.totalAmount, 5400);
    });

    test('一次只能買同一間照護中心的商品', () {
      final cart = CartController();
      expect(cart.addProduct(_product(id: 'a', centerId: 'c1')), isTrue);
      // 不同中心 → 拒絕。
      expect(cart.addProduct(_product(id: 'b', centerId: 'c2')), isFalse);
      expect(cart.lineCount, 1);
    });

    test('數量不會超過庫存，調到 0 會移除', () {
      final cart = CartController();
      final product = _product(id: 'a', stock: 2);
      cart.addProduct(product);
      cart.setQuantity('a', 99);
      expect(cart.quantityOf('a'), 2); // clamp 到庫存
      cart.setQuantity('a', 0);
      expect(cart.isEmpty, isTrue);
    });

    test('缺貨商品無法加入', () {
      final cart = CartController();
      expect(cart.addProduct(_product(stock: 0)), isFalse);
      expect(cart.isEmpty, isTrue);
    });
  });

  group('MarketplaceService.createOrder', () {
    test('送出 productId/quantity，解析後端訂單回應', () async {
      late Map<String, dynamic> sentBody;
      final client = MockClient((request) async {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'ok': true,
            'order': {
              'id': 'o1',
              'user_id': 'u1',
              'elder_name': '陳奶奶',
              'center_id': 'c1',
              'center_name': '安心長照中心',
              'items': [
                {
                  'product_id': 'p1',
                  'product_name': '防滑沐浴椅',
                  'quantity': 2,
                  'unit_price': 1800,
                  'subtotal': 3600,
                },
              ],
              'total_amount': 3600,
              'commission_rate': 0.1,
              'commission_amount': 360,
              'center_revenue': 3240,
              'status': 'pending',
              'delivery_note': '白天在家',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = MarketplaceService(client: client);
      final order = await service.createOrder(
        userId: 'u1',
        elderName: '陳奶奶',
        deliveryNote: '白天在家',
        items: [CartItem(product: _product(), quantity: 2)],
      );
      expect(order.id, 'o1');
      expect(order.totalAmount, 3600);
      expect(order.commissionAmount, 360);
      expect(order.centerRevenue, 3240);
      expect(order.items.single.quantity, 2);
      // 只送 productId / quantity（不送價格，由後端重算）。
      final items = sentBody['items'] as List<dynamic>;
      expect(items.single['productId'], 'p1');
      expect(items.single['quantity'], 2);
    });

    test('庫存不足回白話訊息', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'ok': false, 'error': 'insufficient_stock'}),
          400,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = MarketplaceService(client: client);
      await expectLater(
        service.createOrder(
          userId: 'u1',
          elderName: '',
          deliveryNote: '',
          items: [CartItem(product: _product(), quantity: 5)],
        ),
        throwsA(
          isA<MarketplaceApiException>().having(
            (e) => e.friendlyMessage,
            'friendlyMessage',
            contains('庫存不夠'),
          ),
        ),
      );
    });
  });

  testWidgets('MarketplaceScreen 載入商品並可加入購物車（更新數量徽章）',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final service = _FakeMarketplaceService([_product()]);
    final controller = MarketplaceController(service);
    final cart = CartController();
    addTearDown(controller.dispose);
    addTearDown(cart.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MarketplaceController>.value(value: controller),
          ChangeNotifierProvider<CartController>.value(value: cart),
        ],
        child: const MaterialApp(home: MarketplaceScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // 品名會同時出現在「色卡 placeholder」與「卡片標題」，所以用 findsWidgets。
    expect(find.text('防滑沐浴椅'), findsWidgets);
    expect(find.text('挑選需要的用品，我們會協助通知照護中心處理訂單。'),
        findsOneWidget);

    await tester.tap(find.text('加入'));
    await tester.pump();

    expect(cart.totalCount, 1);
    // 購物車徽章顯示數量。
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('購物車鍵盤開啟時，底部改顯示「完成」收鍵盤按鈕', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final cart = CartController();
    cart.addProduct(_product());
    addTearDown(cart.dispose);

    Widget host(double keyboardInset) => MultiProvider(
          providers: [
            ChangeNotifierProvider<CartController>.value(value: cart),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => MediaQuery(
                // 沿用測試畫面尺寸，只覆寫鍵盤高度。
                data: MediaQuery.of(context).copyWith(
                  viewInsets: EdgeInsets.only(bottom: keyboardInset),
                ),
                child: const CartScreen(),
              ),
            ),
          ),
        );

    // 鍵盤關閉：顯示「確認下單」，不顯示「完成」。
    await tester.pumpWidget(host(0));
    await tester.pump();
    expect(find.text('確認下單'), findsOneWidget);
    expect(find.text('完成'), findsNothing);

    // 鍵盤開啟：底部改成「完成」收鍵盤列。
    await tester.pumpWidget(host(300));
    await tester.pump();
    expect(find.text('完成'), findsOneWidget);
    expect(find.text('確認下單'), findsNothing);
  });
}
