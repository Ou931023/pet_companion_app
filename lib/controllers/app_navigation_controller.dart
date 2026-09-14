import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../routes/app_routes.dart';

class AppNavigationController extends ChangeNotifier {
  AppNavigationController({bool? showMarketplace})
      : _showMarketplace = showMarketplace ?? AppConfig.marketplaceVisible;

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final bool _showMarketplace;

  String _currentShellRoute = AppRoute.home;

  String get currentShellRoute => _currentShellRoute;
  List<String> get visibleShellRoutes => _showMarketplace
      ? AppRoute.shellRoutes
      : const [AppRoute.home, AppRoute.history, AppRoute.settings];

  int get currentShellIndex => visibleShellRoutes.indexOf(_currentShellRoute);

  bool canNavigateTo(String route) {
    return !AppRoute.shellRoutes.contains(route) ||
        visibleShellRoutes.contains(route);
  }

  void selectShellIndex(int index) {
    final routes = visibleShellRoutes;
    if (index < 0 || index >= routes.length) return;
    navigateTo(routes[index]);
  }

  void navigateTo(String route, {Object? arguments}) {
    if (AppRoute.shellRoutes.contains(route)) {
      if (!canNavigateTo(route)) return;
      navigatorKey.currentState?.popUntil((route) => route.isFirst);
      if (_currentShellRoute != route) {
        _currentShellRoute = route;
        notifyListeners();
      }
      return;
    }

    navigatorKey.currentState?.pushNamed(route, arguments: arguments);
  }
}
