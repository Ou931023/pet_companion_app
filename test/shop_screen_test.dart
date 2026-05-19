import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pet_companion_app/controllers/inventory_controller.dart';
import 'package:pet_companion_app/controllers/pet_stats_controller.dart';
import 'package:pet_companion_app/controllers/profile_controller.dart';
import 'package:pet_companion_app/controllers/wallet_controller.dart';
import 'package:pet_companion_app/screens/shop_screen.dart';
import 'package:pet_companion_app/services/inventory_storage_service.dart';
import 'package:pet_companion_app/services/local_storage_service.dart';
import 'package:pet_companion_app/services/pet_stats_storage_service.dart';
import 'package:pet_companion_app/services/shop_service.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  test('ShopService includes a broader set of pet care items', () {
    final items = const ShopService().allItems();

    expect(items.length, greaterThanOrEqualTo(12));
    expect(
        items.map((item) => item.name),
        containsAll([
          '鮭魚餐',
          '暖雞湯',
          '午睡小床',
          '梳毛刷',
          '洗澡浴巾',
        ]));
  });

  testWidgets('ShopScreen shows long-term care shop consent before opening',
      (tester) async {
    await binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => binding.setSurfaceSize(null));
    final harness = await _ShopHarness.create();
    addTearDown(harness.dispose);

    await tester.pumpWidget(_shopHost(harness));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('外部長照用品商城'), findsOneWidget);
    expect(find.text('寵物用品'), findsOneWidget);
    expect(find.text('鮭魚餐'), findsOneWidget);
    expect(find.text('梳毛刷'), findsOneWidget);

    await tester.tap(find.text('外部長照用品商城'));
    await tester.pumpAndSettle();

    expect(find.text('開啟外部長照商城？'), findsOneWidget);
    expect(find.text('同意並前往'), findsOneWidget);

    await tester.tap(find.text('先不要'));
    await tester.pumpAndSettle();
    expect(find.text('開啟外部長照商城？'), findsNothing);
  });
}

Widget _shopHost(_ShopHarness harness) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ProfileController>.value(
        value: harness.profileController,
      ),
      ChangeNotifierProvider<WalletController>.value(
        value: harness.walletController,
      ),
      ChangeNotifierProvider<PetStatsController>.value(
        value: harness.petStatsController,
      ),
      ChangeNotifierProvider<InventoryController>.value(
        value: harness.inventoryController,
      ),
      Provider<ShopService>.value(value: harness.shopService),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: ShopScreen(),
      ),
    ),
  );
}

class _ShopHarness {
  _ShopHarness({
    required this.profileController,
    required this.walletController,
    required this.petStatsController,
    required this.inventoryController,
    required this.shopService,
  });

  final ProfileController profileController;
  final WalletController walletController;
  final PetStatsController petStatsController;
  final InventoryController inventoryController;
  final ShopService shopService;
  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    inventoryController.dispose();
    petStatsController.dispose();
    walletController.dispose();
    profileController.dispose();
  }

  static Future<_ShopHarness> create() async {
    SharedPreferences.setMockInitialValues({});
    final profileController = ProfileController(LocalStorageService());
    await profileController.completeOnboarding('小伴');
    final walletController = WalletController(profileController);
    final petStatsController = PetStatsController(PetStatsStorageService());
    final inventoryController = InventoryController(InventoryStorageService());

    return _ShopHarness(
      profileController: profileController,
      walletController: walletController,
      petStatsController: petStatsController,
      inventoryController: inventoryController,
      shopService: const ShopService(),
    );
  }
}
