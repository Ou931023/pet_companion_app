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
  _FakeFirebaseAuthService({
    this.result,
    this.googleResult,
    this.appleResult,
    this.error,
    this.deleteError,
    this.reauthError,
    this.authInfo,
  });

  final FirebaseSignInResult? result;
  final FirebaseSignInResult? googleResult;
  final FirebaseSignInResult? appleResult;
  final Object? error;
  final Object? deleteError;
  final Object? reauthError;

  /// 若設定，`currentUserAuthInfo()` 會回傳它（模擬有登入中的 Firebase user）。
  final ({String uid, String idToken})? authInfo;

  bool deleteCalled = false;
  bool reauthPasswordCalled = false;
  bool reauthGoogleCalled = false;
  bool reauthAppleCalled = false;
  bool revokeAppleCalled = false;
  String? revokedAppleAuthorizationCode;
  String? resetEmail;
  String? reauthPassword;
  final List<String> operations = <String>[];

  @override
  Future<void> deleteCurrentUser() async {
    deleteCalled = true;
    operations.add('deleteFirebaseUser');
    if (deleteError != null) throw deleteError!;
  }

  @override
  Future<({String uid, String idToken})?> currentUserAuthInfo() async =>
      authInfo;

  @override
  Future<void> reauthenticateWithPassword(String password) async {
    reauthPasswordCalled = true;
    reauthPassword = password;
    if (reauthError != null) throw reauthError!;
  }

  @override
  Future<void> reauthenticateWithGoogle() async {
    reauthGoogleCalled = true;
    if (reauthError != null) throw reauthError!;
  }

  @override
  Future<String?> reauthenticateWithApple() async {
    reauthAppleCalled = true;
    operations.add('reauthApple');
    if (reauthError != null) throw reauthError!;
    return 'apple-authorization-code';
  }

  @override
  Future<void> revokeAppleToken(String authorizationCode) async {
    revokeAppleCalled = true;
    operations.add('revokeAppleToken');
    revokedAppleAuthorizationCode = authorizationCode;
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    resetEmail = email;
    if (error != null) throw error!;
  }

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

  @override
  Future<FirebaseSignInResult> signInWithApple() async {
    if (error != null) throw error!;
    return appleResult!;
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

const _appleResult = FirebaseSignInResult(
  uid: 'fb-uid-a',
  idToken: 'fb-id-token-a',
  provider: 'apple',
  email: 'hidden@privaterelay.appleid.com',
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

  test('deleteAccount 成功 → 刪 Firebase 帳號並清本機 session', () async {
    final fakeFirebase = _FakeFirebaseAuthService(result: _firebaseResult);
    final service = AuthService(
      sessionApiService: _apiReturning({
        'success': true,
        'userId': 'user-123',
        'elderId': 'elder-456',
        'bindingStatus': 'bound',
        'isNewUser': false,
        'authMode': 'firebase',
      }),
      firebaseAuthService: fakeFirebase,
    );

    await service.signInWithEmail(email: 'a@b.c', password: 'secret1');
    expect(await service.restoreSession(), isNotNull);

    await service.deleteAccount();

    expect(fakeFirebase.deleteCalled, isTrue);
    expect(await service.restoreSession(), isNull);
  });

  test('deleteAccount Firebase 失敗 → 丟出且本機 session 保留（可重新登入後再刪）', () async {
    final fakeFirebase = _FakeFirebaseAuthService(
      result: _firebaseResult,
      deleteError: const EmailAuthException('requires-recent-login'),
    );
    final service = AuthService(
      sessionApiService: _apiReturning({
        'success': true,
        'userId': 'user-123',
        'elderId': 'elder-456',
        'bindingStatus': 'bound',
        'isNewUser': false,
        'authMode': 'firebase',
      }),
      firebaseAuthService: fakeFirebase,
    );

    await service.signInWithEmail(email: 'a@b.c', password: 'secret1');
    expect(await service.restoreSession(), isNotNull);

    await expectLater(
      service.deleteAccount(),
      throwsA(isA<EmailAuthException>()),
    );
    // 失敗時本機 session 仍在，不會被清掉。
    expect(await service.restoreSession(), isNotNull);
  });

  test('deleteAccount（Email）→ 用密碼重新驗證 + 呼叫後端刪資料 + 刪 Firebase + 清本機', () async {
    Uri? hitUri;
    Map<String, dynamic>? deleteBody;
    final fakeFirebase = _FakeFirebaseAuthService(
      result: _firebaseResult,
      authInfo: (uid: 'fb-uid-1', idToken: 'fresh-id-token'),
    );
    final service = AuthService(
      sessionApiService: SessionApiService(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/api/auth/delete')) {
            hitUri = request.url;
            deleteBody = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode({
                'success': true,
                'deleted': {
                  'user': 1,
                  'elder': 1,
                  'memories': 3,
                  'careAlerts': 1
                },
              }),
              200,
            );
          }
          // 其餘（建立 session）一律成功。
          return http.Response(
            jsonEncode({
              'success': true,
              'userId': 'user-123',
              'elderId': 'elder-456',
              'bindingStatus': 'bound',
              'isNewUser': false,
              'authMode': 'firebase',
            }),
            200,
          );
        }),
      ),
      firebaseAuthService: fakeFirebase,
    );

    await service.signInWithEmail(email: 'a@b.c', password: 'secret1');
    expect(await service.restoreSession(), isNotNull);

    await service.deleteAccount(password: 'mypassword', provider: 'email');

    // 1. 用密碼重新驗證（不會誤跑 Google 重新驗證）。
    expect(fakeFirebase.reauthPasswordCalled, isTrue);
    expect(fakeFirebase.reauthPassword, 'mypassword');
    expect(fakeFirebase.reauthGoogleCalled, isFalse);
    // 2. 後端刪除有被呼叫，且帶上 uid + 新 idToken。
    expect(hitUri, isNotNull);
    expect(deleteBody!['firebaseUid'], 'fb-uid-1');
    expect(deleteBody!['idToken'], 'fresh-id-token');
    // 3. Firebase 帳號被刪。
    expect(fakeFirebase.deleteCalled, isTrue);
    // 4. 本機 session 清掉。
    expect(await service.restoreSession(), isNull);
  });

  test('deleteAccount（Google）→ 重新跑 Google 驗證', () async {
    final fakeFirebase = _FakeFirebaseAuthService(
      googleResult: _googleResult,
      authInfo: (uid: 'fb-uid-g', idToken: 'g-token'),
    );
    final service = AuthService(
      sessionApiService: _apiReturning({'success': true}),
      firebaseAuthService: fakeFirebase,
    );
    await service.signInWithGoogle();

    await service.deleteAccount(provider: 'google');

    expect(fakeFirebase.reauthGoogleCalled, isTrue);
    expect(fakeFirebase.reauthPasswordCalled, isFalse);
    expect(fakeFirebase.deleteCalled, isTrue);
    expect(await service.restoreSession(), isNull);
  });

  test('deleteAccount 後端不可達 → 保留 Firebase 帳號與本機 session 供重試', () async {
    final fakeFirebase = _FakeFirebaseAuthService(
      result: _firebaseResult,
      authInfo: (uid: 'fb-uid-1', idToken: 'tok'),
    );
    final service = AuthService(
      // 後端刪除回 500 → 不得繼續刪 Firebase，保留登入供使用者重試。
      sessionApiService: SessionApiService(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/api/auth/delete')) {
            return http.Response('err', 500);
          }
          return http.Response(
            jsonEncode({
              'success': true,
              'userId': 'u',
              'elderId': 'e',
              'bindingStatus': 'bound',
              'isNewUser': false,
              'authMode': 'firebase',
            }),
            200,
          );
        }),
      ),
      firebaseAuthService: fakeFirebase,
    );
    await service.signInWithEmail(email: 'a@b.c', password: 'secret1');

    await expectLater(
      service.deleteAccount(password: 'pw', provider: 'email'),
      throwsA(
        isA<SessionApiException>().having(
          (error) => error.code,
          'code',
          'account_delete_failed',
        ),
      ),
    );

    expect(fakeFirebase.deleteCalled, isFalse);
    expect(await service.restoreSession(), isNotNull);
  });

  test('deleteAccount 重新驗證失敗（密碼錯）→ 丟出、不清本機 session、不刪 Firebase', () async {
    final fakeFirebase = _FakeFirebaseAuthService(
      result: _firebaseResult,
      authInfo: (uid: 'fb-uid-1', idToken: 'tok'),
      reauthError: const EmailAuthException('wrong-password'),
    );
    final service = AuthService(
      sessionApiService: _apiReturning({
        'success': true,
        'userId': 'user-123',
        'elderId': 'elder-456',
        'bindingStatus': 'bound',
        'isNewUser': false,
        'authMode': 'firebase',
      }),
      firebaseAuthService: fakeFirebase,
    );
    await service.signInWithEmail(email: 'a@b.c', password: 'secret1');

    await expectLater(
      service.deleteAccount(password: 'wrong', provider: 'email'),
      throwsA(isA<EmailAuthException>()),
    );
    // 重新驗證就失敗 → 不會走到刪除 Firebase，本機 session 也保留可重試。
    expect(fakeFirebase.deleteCalled, isFalse);
    expect(await service.restoreSession(), isNotNull);
  });

  test('無持久化時 restoreSession 回 null', () async {
    final service = AuthService(sessionApiService: _apiReturning(const {}));
    expect(await service.restoreSession(), isNull);
  });

  test('signInWithEmail 成功 → 帶 idToken 與 provider=email 呼叫後端並回 session',
      () async {
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

    final session = await service.signInWithEmail(
        email: 'grandma@example.com', password: 'secret1');

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
        isA<EmailAuthException>()
            .having((e) => e.code, 'code', 'wrong-password'),
      ),
    );
  });

  // CR-0037（重新規格化）：原本此測試斷言「後端 500 → 用 Firebase uid 捏造一個
  // authenticated session（authMode=mock、elderId=fb-uid）」。正式版不可在後端
  // 未驗證下捏造登入，改為「正式帳號後端失敗 → 丟 SessionApiException 且不持久化」。
  test('Firebase 成功但後端 5xx → 丟 SessionApiException(server)、不捏造 session、不持久化',
      () async {
    final service = AuthService(
      sessionApiService: SessionApiService(
        client: MockClient((request) async => http.Response('err', 500)),
      ),
      firebaseAuthService: _FakeFirebaseAuthService(result: _firebaseResult),
    );

    await expectLater(
      service.signInWithEmail(
          email: 'grandma@example.com', password: 'secret1'),
      throwsA(
        isA<SessionApiException>().having((e) => e.code, 'code', 'server'),
      ),
    );
    // 沒有捏造的 session 被持久化。
    expect(await service.restoreSession(), isNull);
  });

  test('Firebase 成功但後端 401 → 丟 SessionApiException(invalid_token)、不持久化',
      () async {
    final service = AuthService(
      sessionApiService: SessionApiService(
        client: MockClient(
          (request) async => http.Response('invalid_id_token', 401),
        ),
      ),
      firebaseAuthService: _FakeFirebaseAuthService(result: _firebaseResult),
    );

    await expectLater(
      service.signInWithEmail(
          email: 'grandma@example.com', password: 'secret1'),
      throwsA(
        isA<SessionApiException>()
            .having((e) => e.code, 'code', 'invalid_token'),
      ),
    );
    expect(await service.restoreSession(), isNull);
  });

  test('Firebase 成功但後端連線錯誤 → 丟 SessionApiException(network)、不持久化', () async {
    final service = AuthService(
      sessionApiService: SessionApiService(
        client: MockClient((request) async {
          throw const _FakeSocketException();
        }),
      ),
      firebaseAuthService: _FakeFirebaseAuthService(result: _firebaseResult),
    );

    await expectLater(
      service.signInWithEmail(
          email: 'grandma@example.com', password: 'secret1'),
      throwsA(
        isA<SessionApiException>().having((e) => e.code, 'code', 'network'),
      ),
    );
    expect(await service.restoreSession(), isNull);
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
      firebaseAuthService:
          _FakeFirebaseAuthService(googleResult: _googleResult),
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
        isA<GoogleAuthException>()
            .having((e) => e.isCanceled, 'isCanceled', true),
      ),
    );
  });

  test('signInWithApple 成功 → provider=apple 呼叫既有後端 session', () async {
    Map<String, dynamic>? sentBody;
    final service = AuthService(
      sessionApiService: SessionApiService(
        client: MockClient((request) async {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'success': true,
              'userId': 'user-a-1',
              'elderId': 'elder-a-1',
              'bindingStatus': 'bound',
              'isNewUser': true,
              'authMode': 'firebase',
            }),
            200,
          );
        }),
      ),
      firebaseAuthService: _FakeFirebaseAuthService(appleResult: _appleResult),
    );

    final session = await service.signInWithApple();

    expect(session.elderId, 'elder-a-1');
    expect(session.provider, 'apple');
    expect(sentBody!['idToken'], 'fb-id-token-a');
    expect(sentBody!['provider'], 'apple');
  });

  test('sendPasswordResetEmail 交由 Firebase 且不建立 session', () async {
    final firebase = _FakeFirebaseAuthService();
    final service = AuthService(
      sessionApiService: _apiReturning(const {}),
      firebaseAuthService: firebase,
    );

    await service.sendPasswordResetEmail('grandma@example.com');

    expect(firebase.resetEmail, 'grandma@example.com');
    expect(await service.restoreSession(), isNull);
  });

  test('deleteAccount（Apple）先重新驗證，再刪 Firebase 帳號', () async {
    final firebase = _FakeFirebaseAuthService();
    final service = AuthService(
      sessionApiService: _apiReturning(const {}),
      firebaseAuthService: firebase,
    );

    await service.deleteAccount(provider: 'apple');

    expect(firebase.reauthAppleCalled, isTrue);
    expect(firebase.revokeAppleCalled, isTrue);
    expect(firebase.revokedAppleAuthorizationCode, 'apple-authorization-code');
    expect(firebase.deleteCalled, isTrue);
    expect(
      firebase.operations,
      ['reauthApple', 'revokeAppleToken', 'deleteFirebaseUser'],
    );
  });

  test('Apple 驗證成功但後端失敗時不撤銷 token，也不刪 Firebase 帳號', () async {
    final firebase = _FakeFirebaseAuthService(
      authInfo: (uid: 'fb-uid-a', idToken: 'fb-id-token-a'),
    );
    final service = AuthService(
      sessionApiService: SessionApiService(
        client: MockClient((_) async => http.Response('{}', 500)),
      ),
      firebaseAuthService: firebase,
    );

    await expectLater(
      service.deleteAccount(provider: 'apple'),
      throwsA(isA<SessionApiException>()),
    );

    expect(firebase.reauthAppleCalled, isTrue);
    expect(firebase.revokeAppleCalled, isFalse);
    expect(firebase.deleteCalled, isFalse);
  });

  test('Apple 成功但後端 session 失敗時不建立或持久化 session', () async {
    final service = AuthService(
      sessionApiService: SessionApiService(
        client: MockClient((_) async => http.Response('{}', 500)),
      ),
      firebaseAuthService: _FakeFirebaseAuthService(appleResult: _appleResult),
    );

    await expectLater(
      service.signInWithApple(),
      throwsA(isA<SessionApiException>()),
    );
    expect(await service.restoreSession(), isNull);
  });

  test('registerAccountOnly 成功 → 不建後端 session、不持久化（不自動登入）', () async {
    final service = AuthService(
      sessionApiService: _apiReturning({
        'success': true,
        'userId': 'u',
        'elderId': 'e',
        'bindingStatus': 'pending',
        'isNewUser': true,
        'authMode': 'firebase',
      }),
      firebaseAuthService: _FakeFirebaseAuthService(result: _firebaseResult),
    );

    await service.registerAccountOnly(
      email: 'grandma@example.com',
      password: 'secret1',
    );

    // 沒有持久化任何 session → 還原為 null（代表沒被自動登入）。
    expect(await service.restoreSession(), isNull);
  });

  test('registerAccountOnly 失敗（email 已使用）→ 丟 EmailAuthException', () async {
    final service = AuthService(
      sessionApiService: _apiReturning(const {}),
      firebaseAuthService: _FakeFirebaseAuthService(
        error: const EmailAuthException('email-already-in-use'),
      ),
    );

    await expectLater(
      service.registerAccountOnly(
        email: 'grandma@example.com',
        password: 'secret1',
      ),
      throwsA(
        isA<EmailAuthException>()
            .having((e) => e.code, 'code', 'email-already-in-use'),
      ),
    );
  });

  // CR-0037（重新規格化）：原本此測試斷言「Google 成功但後端失敗 → mockFallback
  // （用 Firebase uid 捏造 authenticated session）」。正式版改為丟例外、不捏造。
  test('Google 成功但後端失敗 → 丟 SessionApiException(server)、不持久化', () async {
    final service = AuthService(
      sessionApiService: SessionApiService(
        client: MockClient((request) async => http.Response('err', 500)),
      ),
      firebaseAuthService:
          _FakeFirebaseAuthService(googleResult: _googleResult),
    );

    await expectLater(
      service.signInWithGoogle(),
      throwsA(
        isA<SessionApiException>().having((e) => e.code, 'code', 'server'),
      ),
    );
    expect(await service.restoreSession(), isNull);
  });
}

class _FakeSocketException implements Exception {
  const _FakeSocketException();
  @override
  String toString() => 'Connection refused';
}
