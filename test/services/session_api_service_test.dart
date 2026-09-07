import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pet_companion_app/services/auth/session_api_service.dart';

void main() {
  test('正式 session timeout 可涵蓋 Render free cold start', () {
    final service = SessionApiService();

    expect(service.requestTimeout, const Duration(seconds: 60));
    expect(service.retryTimeout, const Duration(seconds: 20));
  });

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

  group('CR-0037 正式帳號 provider-aware：失敗丟 SessionApiException、不捏造', () {
    test('正式帳號（email）500 → 丟 SessionApiException(server)', () async {
      final service = SessionApiService(
        client: MockClient((request) async => http.Response('boom', 500)),
      );

      await expectLater(
        service.createSession(
          firebaseUid: 'uid-1',
          idToken: 'token-1',
          provider: 'email',
        ),
        throwsA(
          isA<SessionApiException>().having((e) => e.code, 'code', 'server'),
        ),
      );
    });

    test('正式帳號（google）401 → 丟 SessionApiException(invalid_token)', () async {
      final service = SessionApiService(
        client: MockClient(
          (request) async => http.Response('invalid_id_token', 401),
        ),
      );

      await expectLater(
        service.createSession(
          firebaseUid: 'uid-1',
          idToken: 'token-1',
          provider: 'google',
        ),
        throwsA(
          isA<SessionApiException>()
              .having((e) => e.code, 'code', 'invalid_token'),
        ),
      );
    });

    test('正式帳號 連線例外 → 丟 SessionApiException(network)', () async {
      final service = SessionApiService(
        client: MockClient((request) async {
          throw const _FakeSocketException();
        }),
      );

      await expectLater(
        service.createSession(
          firebaseUid: 'uid-1',
          idToken: 'token-1',
          provider: 'email',
        ),
        throwsA(
          isA<SessionApiException>().having((e) => e.code, 'code', 'network'),
        ),
      );
    });

    test('正式帳號超過設定 timeout → 丟 SessionApiException(network)', () async {
      final service = SessionApiService(
        requestTimeout: const Duration(milliseconds: 5),
        retryTimeout: const Duration(milliseconds: 5),
        retryDelay: Duration.zero,
        client: MockClient((request) async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return http.Response('{}', 200);
        }),
      );

      await expectLater(
        service.createSession(
          firebaseUid: 'uid-1',
          idToken: 'token-1',
          provider: 'google',
        ),
        throwsA(
          isA<SessionApiException>().having((e) => e.code, 'code', 'network'),
        ),
      );
    });

    test('正式帳號第一次 transport 失敗會自動重試且可成功', () async {
      var attempts = 0;
      final service = SessionApiService(
        retryDelay: Duration.zero,
        client: MockClient((request) async {
          attempts += 1;
          if (attempts == 1) throw const _FakeSocketException();
          return http.Response(
            jsonEncode({
              'success': true,
              'userId': 'user-123',
              'elderId': 'elder-456',
              'role': 'elder',
              'authMode': 'firebase',
            }),
            200,
          );
        }),
      );

      final session = await service.createSession(
        firebaseUid: 'uid-1',
        idToken: 'token-1',
        provider: 'google',
      );

      expect(attempts, 2);
      expect(session.userId, 'user-123');
      expect(session.elderId, 'elder-456');
    });

    test('正式帳號 JSON 解析失敗 → 丟 SessionApiException(server)', () async {
      final service = SessionApiService(
        client: MockClient((request) async => http.Response('not-json', 200)),
      );

      await expectLater(
        service.createSession(
          firebaseUid: 'uid-1',
          idToken: 'token-1',
          provider: 'email',
        ),
        throwsA(
          isA<SessionApiException>().having((e) => e.code, 'code', 'server'),
        ),
      );
    });

    test('正式帳號 回應 success != true → 丟 SessionApiException(server)', () async {
      final service = SessionApiService(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({'success': false, 'error': 'auth_session_failed'}),
            200,
          ),
        ),
      );

      await expectLater(
        service.createSession(
          firebaseUid: 'uid-1',
          idToken: 'token-1',
          provider: 'email',
        ),
        throwsA(
          isA<SessionApiException>().having((e) => e.code, 'code', 'server'),
        ),
      );
    });

    test('Demo（mock）路徑 500 仍回 fallback（不受 CR-0037 影響）', () async {
      final service = SessionApiService(
        client: MockClient((request) async => http.Response('boom', 500)),
      );

      final session = await service.createSession(
        firebaseUid: 'uid-1',
        idToken: 'token-1',
        provider: 'mock',
      );

      expect(session.authMode, 'mock');
      expect(session.elderId, 'default_user');
    });
  });
}

class _FakeSocketException implements Exception {
  const _FakeSocketException();
  @override
  String toString() => 'Connection refused';
}
