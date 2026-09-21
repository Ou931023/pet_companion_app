import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/controllers/app_navigation_controller.dart';
import 'package:pet_companion_app/routes/app_routes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('預設導覽保留寵物商城分頁', () {
    final navigation = AppNavigationController();

    expect(navigation.visibleShellRoutes, AppRoute.shellRoutes);
    navigation.selectShellIndex(1);
    expect(navigation.currentShellRoute, AppRoute.shop);
  });

  test(
    '緊急關閉寵物商城時仍會正確重映射可見分頁',
    () {
      final navigation = AppNavigationController(showMarketplace: false);

      expect(navigation.visibleShellRoutes, const [
        AppRoute.home,
        AppRoute.history,
        AppRoute.settings,
      ]);

      navigation.selectShellIndex(1);
      expect(navigation.currentShellRoute, AppRoute.history);
      expect(navigation.currentShellIndex, 1);

      navigation.selectShellIndex(2);
      expect(navigation.currentShellRoute, AppRoute.settings);
      expect(navigation.currentShellIndex, 2);
    },
  );

  test('開啟寵物商城時保留四個既有分頁', () {
    final navigation = AppNavigationController(showMarketplace: true);

    expect(navigation.visibleShellRoutes, AppRoute.shellRoutes);
    navigation.selectShellIndex(1);
    expect(navigation.currentShellRoute, AppRoute.shop);
    navigation.selectShellIndex(3);
    expect(navigation.currentShellRoute, AppRoute.settings);
  });

  test('out-of-range visible index is ignored', () {
    final navigation = AppNavigationController(showMarketplace: false);

    navigation.selectShellIndex(3);
    expect(navigation.currentShellRoute, AppRoute.home);
  });

  test('商城被緊急關閉時不能切入隱藏路由', () {
    final navigation = AppNavigationController(showMarketplace: false);

    navigation.navigateTo(AppRoute.shop);
    expect(navigation.currentShellRoute, AppRoute.home);
  });
}
