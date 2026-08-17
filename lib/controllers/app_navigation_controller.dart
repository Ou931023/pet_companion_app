import 'package:flutter/material.dart';

import '../routes/app_routes.dart';

class AppNavigationController extends ChangeNotifier {
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  String _currentShellRoute = AppRoute.home;

  String get currentShellRoute => _currentShellRoute;
  int get currentShellIndex => AppRoute.shellRoutes.indexOf(_currentShellRoute);

  void selectShellIndex(int index) {
    if (index < 0 || index >= AppRoute.shellRoutes.length) return;
    navigateTo(AppRoute.shellRoutes[index]);
  }

  void navigateTo(String route, {Object? arguments}) {
    if (AppRoute.shellRoutes.contains(route)) {
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
