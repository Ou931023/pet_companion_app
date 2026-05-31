import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pet_companion_app/controllers/auth_controller.dart';
import 'package:pet_companion_app/services/auth/auth_service.dart';
import 'package:pet_companion_app/services/auth/session_api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

AuthService _authServiceReturning(Map<String, dynamic> responseJson) {
  return AuthService(
    sessionApiService: SessionApiService(
      client: MockClient((request) async {
        return http.Response(jsonEncode(responseJson), 200);
      }),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('初始 restore（無持久化）→ unauthenticated', () async {
    final controller = AuthController(
      authService: _authServiceReturning(const {}),
    );

    expect(controller.status, AuthStatus.loading);
    await controller.restore();
    expect(controller.status, AuthStatus.unauthenticated);
    expect(controller.isAuthenticated, false);
  });

  test('有持久化 → restore 後 authenticated', () async {
    final service = _authServiceReturning({
      'success': true,
      'userId': 'user-123',
      'elderId': 'elder-456',
      'bindingStatus': 'bound',
      'isNewUser': false,
      'authMode': 'firebase',
    });
    // 先登入一次寫入持久化。
    await service.mockLogin();

    final controller = AuthController(authService: service);
    await controller.restore();

    expect(controller.status, AuthStatus.authenticated);
    expect(controller.currentUserId, 'user-123');
    expect(controller.currentElderId, 'elder-456');
  });

  test('loginAsDemoUser 成功 → authenticated 且 currentElderId 為後端 elderId',
      () async {
    final controller = AuthController(
      authService: _authServiceReturning({
        'success': true,
        'userId': 'user-123',
        'elderId': 'elder-456',
        'bindingStatus': 'pending',
        'isNewUser': true,
        'authMode': 'mock',
      }),
    );

    await controller.loginAsDemoUser(displayName: 'Demo');

    expect(controller.status, AuthStatus.authenticated);
    expect(controller.currentElderId, 'elder-456');
    expect(controller.currentUserId, 'user-123');
  });

  test('未登入時 currentElderId / currentUserId == default_user', () {
    final controller = AuthController(
      authService: _authServiceReturning(const {}),
    );

    expect(controller.currentElderId, 'default_user');
    expect(controller.currentUserId, 'default_user');
  });

  test('logout 後回到 unauthenticated 且 fallback default_user', () async {
    final controller = AuthController(
      authService: _authServiceReturning({
        'success': true,
        'userId': 'user-123',
        'elderId': 'elder-456',
        'bindingStatus': 'pending',
        'isNewUser': true,
        'authMode': 'mock',
      }),
    );

    await controller.loginAsDemoUser();
    expect(controller.isAuthenticated, true);

    await controller.logout();
    expect(controller.status, AuthStatus.unauthenticated);
    expect(controller.currentElderId, 'default_user');
  });
}
