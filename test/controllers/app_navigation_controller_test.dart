import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/controllers/app_navigation_controller.dart';
import 'package:pet_companion_app/routes/app_routes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'production navigation hides shop and maps visible indices correctly',
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

  test('development navigation keeps the four existing shell routes', () {
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

  test('hidden shop route cannot become the production shell route', () {
    final navigation = AppNavigationController(showMarketplace: false);

    navigation.navigateTo(AppRoute.shop);
    expect(navigation.currentShellRoute, AppRoute.home);
  });
}
