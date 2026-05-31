import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pet_companion_app/services/auth/session_api_service.dart';

void main() {
  test('200 正確 JSON → 解析出 userId/elderId/authMode/isNewUser', () async {
    http.Request? captured;
    final service = SessionApiService(
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'success': true,
            'userId': 'user-123',
            'elderId': 'elder-456',
            'role': 'elder',
            'bindingStatus': 'bound',
            'bindingDeadline': '2026-07-30T00:00:00.000Z',
            'isNewUser': true,
            'authMode': 'firebase',
          }),
          200,
        );
      }),
    );

    final session = await service.createSession(
      firebaseUid: 'uid-1',
      idToken: 'token-1',
      email: 'a@b.com',
      displayName: 'Demo',
      provider: 'mock',
    );

    expect(captured, isNotNull);
    expect(captured!.method, 'POST');
    expect(captured!.url.path, '/api/auth/session');
    final body = jsonDecode(captured!.body) as Map<String, dynamic>;
    expect(body['firebaseUid'], 'uid-1');
    expect(body['idToken'], 'token-1');
    expect(body['provider'], 'mock');

    expect(session.userId, 'user-123');
    expect(session.elderId, 'elder-456');
    expect(session.authMode, 'firebase');
    expect(session.isNewUser, true);
  });

  test('500 → fallback mock session（不丟例外）', () async {
    final service = SessionApiService(
      client: MockClient((request) async {
        return http.Response('boom', 500);
      }),
    );

    final session = await service.createSession(
      firebaseUid: 'uid-1',
      idToken: 'token-1',
      provider: 'mock',
    );

    expect(session.authMode, 'mock');
    expect(session.elderId, 'default_user');
    expect(session.userId, 'default_user');
  });

  test('連線例外 → fallback mock session（不丟例外）', () async {
    final service = SessionApiService(
      client: MockClient((request) async {
        throw const _FakeSocketException();
      }),
    );

    final session = await service.createSession(
      firebaseUid: 'uid-1',
      idToken: 'token-1',
      provider: 'mock',
    );

    expect(session.authMode, 'mock');
    expect(session.elderId, 'default_user');
  });

  test('JSON 解析失敗 → fallback mock session', () async {
    final service = SessionApiService(
      client: MockClient((request) async {
        return http.Response('not-json', 200);
      }),
    );

    final session = await service.createSession(
      firebaseUid: 'uid-1',
      idToken: 'token-1',
      provider: 'mock',
    );

    expect(session.authMode, 'mock');
    expect(session.elderId, 'default_user');
  });
}

class _FakeSocketException implements Exception {
  const _FakeSocketException();
  @override
  String toString() => 'Connection refused';
}
