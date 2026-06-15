import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pet_companion_app/config/app_config.dart';
import 'package:pet_companion_app/controllers/inventory_controller.dart';
import 'package:pet_companion_app/controllers/pet_stats_controller.dart';
import 'package:pet_companion_app/controllers/profile_controller.dart';
import 'package:pet_companion_app/controllers/wallet_controller.dart';
import 'package:pet_companion_app/onboarding/coach_mark_keys.dart';
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

  testWidgets('ShopScreen opens the built-in care marketplace entry',
      (tester) async {
    await binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => binding.setSurfaceSize(null));
    final harness = await _ShopHarness.create();
    addTearDown(harness.dispose);

    await tester.pumpWidget(_shopHost(harness));
    await tester.pump();

    expect(tester.takeException(), isNull);
    // CR-0056 A2：production 完全隱藏 marketplace 入口，故此導頁行為僅在 dev/test 驗證。
    if (AppConfig.isProduction) {
      expect(find.text('照護用品商城'), findsNothing);
      return;
    }
    // CR-0032：商城入口改成內建長照商城（不再是外部連結 / 同意離開 App 對話框）。
    expect(find.text('照護用品商城'), findsOneWidget);
    expect(find.text('寵物用品'), findsOneWidget);
    expect(find.text('小餅乾'), findsOneWidget);
    expect(find.text('飯糰'), findsOneWidget);

    await tester.tap(find.text('照護用品商城'));
    await tester.pumpAndSettle();

    // 進到內建商城頁（stub），不再彈出外部連結確認框。
    expect(find.text('MARKETPLACE_STUB'), findsOneWidget);
    expect(find.text('開啟外部長照商城？'), findsNothing);
  });

  testWidgets(
      'ShopScreen marketplace 入口依環境顯示（CR-0056 A2：production 隱藏 / dev 顯示）',
      (tester) async {
    await binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => binding.setSurfaceSize(null));
    final harness = await _ShopHarness.create();
    addTearDown(harness.dispose);

    await tester.pumpWidget(_shopHost(harness));
    await tester.pump();

    expect(tester.takeException(), isNull);
    if (AppConfig.isProduction) {
      // 正式版完全隱藏入口（能力/路由保留，但長者看不到死路頁）。
      expect(find.text('照護用品商城'), findsNothing);
    } else {
      expect(find.text('照護用品商城'), findsOneWidget);
    }
    // 寵物用品本體與環境無關，永遠顯示。
    expect(find.text('寵物用品'), findsOneWidget);
  });

  testWidgets('ShopScreen lays pet items out as one full-width row per item',
      (tester) async {
    await binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => binding.setSurfaceSize(null));
    final harness = await _ShopHarness.create();
    addTearDown(harness.dispose);

    await tester.pumpWidget(_shopHost(harness));
    await tester.pump();

    final firstCard = find.byKey(const ValueKey('shop-item-cookie'));
    final secondCard = find.byKey(const ValueKey('shop-item-rice_ball'));

    expect(firstCard, findsOneWidget);
    expect(secondCard, findsOneWidget);
    expect(tester.getTopLeft(firstCard).dx, tester.getTopLeft(secondCard).dx);
    expect(tester.getTopLeft(secondCard).dy, greaterThan(tester.getTopLeft(firstCard).dy));
    expect(tester.getSize(firstCard).width, greaterThan(320));
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
      Provider<CoachMarkKeys>(create: (_) => CoachMarkKeys()),
    ],
    child: MaterialApp(
      home: const Scaffold(
        body: ShopScreen(),
      ),
      // CR-0032：商城入口改成內建長照商城（pushNamed）；測試以 stub 驗證有導頁。
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const Scaffold(
          body: Center(child: Text('MARKETPLACE_STUB')),
        ),
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
