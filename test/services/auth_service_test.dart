import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pet_companion_app/services/auth/auth_service.dart';
import 'package:pet_companion_app/services/auth/firebase_auth_service.dart';
import 'package:pet_companion_app/services/auth/session_api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

SessionApiService _apiReturning(Map<String, dynamic> responseJson) {
  return SessionApiService(
    client: MockClient((request) async {
      return http.Response(jsonEncode(responseJson), 200);
    }),
  );
}

/// 假的 Firebase 層：覆寫 Email 方法，回傳 canned 結果或丟錯，**不碰真 Firebase**。
class _FakeFirebaseAuthService extends FirebaseAuthService {
  _FakeFirebaseAuthService({this.result, this.googleResult, this.error});

  final FirebaseSignInResult? result;
  final FirebaseSignInResult? googleResult;
  final Object? error;

  @override
  Future<FirebaseSignInResult> signInWithEmail({
    required String email,
    required String password,
  }) async {
    if (error != null) throw error!;
    return result!;
  }

  @override
  Future<FirebaseSignInResult> registerWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    if (error != null) throw error!;
    return result!;
  }

  @override
  Future<FirebaseSignInResult> signInWithGoogle() async {
    if (error != null) throw error!;
    return googleResult!;
  }
}

const _firebaseResult = FirebaseSignInResult(
  uid: 'fb-uid-1',
  idToken: 'fb-id-token-1',
  provider: 'email',
  email: 'grandma@example.com',
  displayName: '陳奶奶',
);

const _googleResult = FirebaseSignInResult(
  uid: 'fb-uid-g',
  idToken: 'fb-id-token-g',
  provider: 'google',
  email: 'grandma@gmail.com',
  displayName: '陳奶奶',
);

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

  test('signInWithEmail 成功 → 帶 idToken 與 provider=email 呼叫後端並回 session', () async {
    Map<String, dynamic>? sentBody;
    final service = AuthService(
      sessionApiService: SessionApiService(
        client: MockClient((request) async {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'success': true,
              'userId': 'user-email-1',
              'elderId': 'elder-email-1',
              'bindingStatus': 'bound',
              'isNewUser': false,
              'authMode': 'firebase',
            }),
            200,
          );
        }),
      ),
      firebaseAuthService: _FakeFirebaseAuthService(result: _firebaseResult),
    );

    final session =
        await service.signInWithEmail(email: 'grandma@example.com', password: 'secret1');

    expect(session.userId, 'user-email-1');
    expect(session.elderId, 'elder-email-1');
    expect(session.authMode, 'firebase');
    expect(sentBody!['idToken'], 'fb-id-token-1');
    expect(sentBody!['firebaseUid'], 'fb-uid-1');
    expect(sentBody!['provider'], 'email');
    // 持久化也成功，可被還原。
    expect(await service.restoreSession(), isNotNull);
  });

  test('registerWithEmail 成功 → 回 session 且持久化', () async {
    final service = AuthService(
      sessionApiService: _apiReturning({
        'success': true,
        'userId': 'user-reg-1',
        'elderId': 'elder-reg-1',
        'bindingStatus': 'pending',
        'isNewUser': true,
        'authMode': 'firebase',
      }),
      firebaseAuthService: _FakeFirebaseAuthService(result: _firebaseResult),
    );

    final session = await service.registerWithEmail(
      email: 'grandma@example.com',
      password: 'secret1',
    );

    expect(session.userId, 'user-reg-1');
    expect(session.isNewUser, true);
    expect(await service.restoreSession(), isNotNull);
  });

  test('Firebase 驗證失敗 → EmailAuthException 往上傳（不被吞、不 crash）', () async {
    final service = AuthService(
      sessionApiService: _apiReturning(const {}),
      firebaseAuthService: _FakeFirebaseAuthService(
        error: const EmailAuthException('wrong-password'),
      ),
    );

    await expectLater(
      service.signInWithEmail(email: 'grandma@example.com', password: 'bad'),
      throwsA(
        isA<EmailAuthException>().having((e) => e.code, 'code', 'wrong-password'),
      ),
    );
  });

  test('Firebase 成功但後端 session 失敗 → 回 mockFallback、不 crash', () async {
    final service = AuthService(
      // 後端 500 → createSession 內部回 mockFallback。
      sessionApiService: SessionApiService(
        client: MockClient((request) async => http.Response('err', 500)),
      ),
      firebaseAuthService: _FakeFirebaseAuthService(result: _firebaseResult),
    );

    final session =
        await service.signInWithEmail(email: 'grandma@example.com', password: 'secret1');

    expect(session.authMode, 'mock');
    expect(session.userId, 'default_user');
  });

  test('signInWithGoogle 成功 → 帶 idToken 與 provider=google 呼叫後端並回 session',
      () async {
    Map<String, dynamic>? sentBody;
    final service = AuthService(
      sessionApiService: SessionApiService(
        client: MockClient((request) async {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'success': true,
              'userId': 'user-g-1',
              'elderId': 'elder-g-1',
              'bindingStatus': 'bound',
              'isNewUser': false,
              'authMode': 'firebase',
            }),
            200,
          );
        }),
      ),
      firebaseAuthService: _FakeFirebaseAuthService(googleResult: _googleResult),
    );

    final session = await service.signInWithGoogle();

    expect(session.elderId, 'elder-g-1');
    expect(session.authMode, 'firebase');
    expect(sentBody!['idToken'], 'fb-id-token-g');
    expect(sentBody!['provider'], 'google');
    expect(await service.restoreSession(), isNotNull);
  });

  test('Google 取消 → GoogleAuthException(canceled) 往上傳（不被吞）', () async {
    final service = AuthService(
      sessionApiService: _apiReturning(const {}),
      firebaseAuthService: _FakeFirebaseAuthService(
        error: const GoogleAuthException('canceled'),
      ),
    );

    await expectLater(
      service.signInWithGoogle(),
      throwsA(
        isA<GoogleAuthException>().having((e) => e.isCanceled, 'isCanceled', true),
      ),
    );
  });

  test('Google 成功但後端失敗 → mockFallback、不 crash', () async {
    final service = AuthService(
      sessionApiService: SessionApiService(
        client: MockClient((request) async => http.Response('err', 500)),
      ),
      firebaseAuthService: _FakeFirebaseAuthService(googleResult: _googleResult),
    );

    final session = await service.signInWithGoogle();

    expect(session.authMode, 'mock');
    expect(session.userId, 'default_user');
  });
}
