import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pet_companion_app/services/auth/auth_service.dart';
import 'package:pet_companion_app/services/auth/session_api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

SessionApiService _apiReturning(Map<String, dynamic> responseJson) {
  return SessionApiService(
    client: MockClient((request) async {
      return http.Response(jsonEncode(responseJson), 200);
    }),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('mockLogin 後 persist，restoreSession 取回同一 session', () async {
    final service = AuthService(
      sessionApiService: _apiReturning({
        'success': true,
        'userId': 'user-123',
        'elderId': 'elder-456',
        'role': 'elder',
        'bindingStatus': 'bound',
        'bindingDeadline': '2026-07-30T00:00:00.000Z',
        'isNewUser': false,
        'authMode': 'firebase',
      }),
    );

    final loggedIn = await service.mockLogin(displayName: 'Demo');
    expect(loggedIn.userId, 'user-123');
    expect(loggedIn.elderId, 'elder-456');

    final restored = await service.restoreSession();
    expect(restored, isNotNull);
    expect(restored!.userId, 'user-123');
    expect(restored.elderId, 'elder-456');
    expect(restored.authMode, 'firebase');
  });

  test('logout 後 restoreSession 回 null', () async {
    final service = AuthService(
      sessionApiService: _apiReturning({
        'success': true,
        'userId': 'user-123',
        'elderId': 'elder-456',
        'bindingStatus': 'pending',
        'isNewUser': true,
        'authMode': 'mock',
      }),
    );

    await service.mockLogin();
    expect(await service.restoreSession(), isNotNull);

    await service.logout();
    expect(await service.restoreSession(), isNull);
  });

  test('無持久化時 restoreSession 回 null', () async {
    final service = AuthService(sessionApiService: _apiReturning(const {}));
    expect(await service.restoreSession(), isNull);
  });
}
