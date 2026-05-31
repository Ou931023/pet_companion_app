import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pet_companion_app/controllers/auth_controller.dart';
import 'package:pet_companion_app/models/auth_session.dart';
import 'package:pet_companion_app/services/auth/auth_service.dart';
import 'package:pet_companion_app/services/auth/firebase_auth_service.dart';
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

/// 覆寫 Email / Google 方法的假 AuthService，回 canned session 或丟錯，
/// **不碰真 Firebase**。
class _StubEmailAuthService extends AuthService {
  _StubEmailAuthService({
    this.session,
    this.error,
    this.googleError,
    this.registerError,
  });

  final AuthSession? session;
  final Object? error;
  final Object? googleError;
  final Object? registerError;

  @override
  Future<void> registerAccountOnly({
    required String email,
    required String password,
    String? displayName,
  }) async {
    if (registerError != null) throw registerError!;
  }

  @override
  Future<AuthSession> signInWithEmail({
    required String email,
    required String password,
  }) async {
    if (error != null) throw error!;
    return session!;
  }

  @override
  Future<AuthSession> registerWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    if (error != null) throw error!;
    return session!;
  }

  @override
  Future<AuthSession> signInWithGoogle() async {
    if (googleError != null) throw googleError!;
    return session!;
  }
}

const _firebaseSession = AuthSession(
  userId: 'user-email-1',
  elderId: 'elder-email-1',
  bindingStatus: 'bound',
  authMode: 'firebase',
  provider: 'email', // CR-0009：正式帳號（依登入方式判斷）→ 用 session.elderId
  isNewUser: false,
);

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
    // 先以 demo（mockLogin）登入一次寫入持久化。
    await service.mockLogin();

    final controller = AuthController(authService: service);
    await controller.restore();

    expect(controller.status, AuthStatus.authenticated);
    // CR-0009：mockLogin 是 demo 登入（provider='mock'）→ 還原後仍是 default_user。
    expect(controller.currentUserId, 'default_user');
    expect(controller.currentElderId, 'default_user');
  });

  test('loginAsDemoUser 成功（mock session）→ authenticated 但 elderId 仍 default_user',
      () async {
    // CR-0006 Batch 3d：mock/demo session 一律回 default_user，保護既有 seed 記憶。
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
    expect(controller.currentElderId, 'default_user');
    expect(controller.currentUserId, 'default_user');
  });

  test('正式帳號 session（provider=google）→ 即使 authMode=mock 也用後端真實 id',
      () async {
    // CR-0009：隔離依「登入方式」判斷，不靠 authMode。直接持久化一個正式帳號
    // session（provider=google，authMode 故意設 mock）模擬還原。
    final service = _authServiceReturning(const {});
    await service.persist(const AuthSession(
      userId: 'user-789',
      elderId: 'elder-789',
      bindingStatus: 'bound',
      authMode: 'mock',
      provider: 'google',
      isNewUser: false,
    ));

    final controller = AuthController(authService: service);
    await controller.restore();

    expect(controller.status, AuthStatus.authenticated);
    expect(controller.currentElderId, 'elder-789');
    expect(controller.currentUserId, 'user-789');
  });

  test('未知 authMode → fallback default_user', () async {
    final service = _authServiceReturning({
      'success': true,
      'userId': 'user-xyz',
      'elderId': 'elder-xyz',
      'bindingStatus': 'pending',
      'isNewUser': true,
      'authMode': 'something-else',
    });
    await service.mockLogin();

    final controller = AuthController(authService: service);
    await controller.restore();

    expect(controller.status, AuthStatus.authenticated);
    expect(controller.currentElderId, 'default_user');
    expect(controller.currentUserId, 'default_user');
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

  group('Email 登入 / 註冊（CR-0006 Batch 4b）', () {
    test('signInWithEmail 成功 → authenticated，firebase session 用真實 elderId', () async {
      final controller = AuthController(
        authService: _StubEmailAuthService(session: _firebaseSession),
      );

      await controller.signInWithEmail(
        email: 'grandma@example.com',
        password: 'secret1',
      );

      expect(controller.status, AuthStatus.authenticated);
      expect(controller.currentElderId, 'elder-email-1');
      expect(controller.errorMessage, isNull);
    });

    test('registerWithEmail 成功 → authenticated', () async {
      final controller = AuthController(
        authService: _StubEmailAuthService(session: _firebaseSession),
      );

      await controller.registerWithEmail(
        email: 'grandma@example.com',
        password: 'secret1',
      );

      expect(controller.status, AuthStatus.authenticated);
      expect(controller.currentElderId, 'elder-email-1');
    });

    test('帳號密碼錯誤 → error 狀態且訊息白話、不露 Firebase code', () async {
      final controller = AuthController(
        authService: _StubEmailAuthService(
          error: const EmailAuthException('wrong-password'),
        ),
      );

      await controller.signInWithEmail(
        email: 'grandma@example.com',
        password: 'bad',
      );

      expect(controller.status, AuthStatus.error);
      expect(controller.errorMessage, 'Email 或密碼不太對，請再確認一次。');
      expect(controller.errorMessage, isNot(contains('wrong-password')));
      expect(controller.errorMessage, isNot(contains('Exception')));
    });

    test('Email 已被註冊 → 白話提示直接登入', () async {
      final controller = AuthController(
        authService: _StubEmailAuthService(
          error: const EmailAuthException('email-already-in-use'),
        ),
      );

      await controller.registerWithEmail(
        email: 'grandma@example.com',
        password: 'secret1',
      );

      expect(controller.status, AuthStatus.error);
      expect(controller.errorMessage, '這個 Email 已經註冊過了，直接登入就可以囉。');
    });

    test('非預期錯誤也轉白話，不讓 App 卡死', () async {
      final controller = AuthController(
        authService: _StubEmailAuthService(error: StateError('boom')),
      );

      await controller.signInWithEmail(
        email: 'grandma@example.com',
        password: 'secret1',
      );

      expect(controller.status, AuthStatus.error);
      expect(controller.errorMessage, '現在連線不太順，待會再試一次好嗎？');
    });
  });

  group('Email 註冊不自動登入（CR-0006 Batch 4d）', () {
    test('registerAccount 成功 → 回 null 且 status 不變、未登入', () async {
      final controller = AuthController(authService: _StubEmailAuthService());
      await controller.restore(); // → unauthenticated
      final before = controller.status;

      final result = await controller.registerAccount(
        email: 'grandma@example.com',
        password: 'secret1',
      );

      expect(result, isNull); // 成功
      expect(controller.status, before); // 狀態未變
      expect(controller.isAuthenticated, false); // 不自動登入
    });

    test('registerAccount 失敗（email 已使用）→ 回白話訊息、未登入', () async {
      final controller = AuthController(
        authService: _StubEmailAuthService(
          registerError: const EmailAuthException('email-already-in-use'),
        ),
      );

      final result = await controller.registerAccount(
        email: 'grandma@example.com',
        password: 'secret1',
      );

      expect(result, '這個 Email 已經註冊過了，直接登入就可以囉。');
      expect(controller.isAuthenticated, false);
    });
  });

  group('Google 登入（CR-0006 Batch 4c）', () {
    test('成功 → authenticated，firebase session 用真實 elderId', () async {
      final controller = AuthController(
        authService: _StubEmailAuthService(session: _firebaseSession),
      );

      await controller.signInWithGoogle();

      expect(controller.status, AuthStatus.authenticated);
      expect(controller.currentElderId, 'elder-email-1');
      expect(controller.errorMessage, isNull);
    });

    test('使用者取消 → 柔性中止：unauthenticated 且無錯誤訊息（不死路）', () async {
      final controller = AuthController(
        authService: _StubEmailAuthService(
          googleError: const GoogleAuthException('canceled'),
        ),
      );

      await controller.signInWithGoogle();

      expect(controller.status, AuthStatus.unauthenticated);
      expect(controller.errorMessage, isNull);
    });

    test('設定不足等錯誤 → error 且白話、不露 code', () async {
      final controller = AuthController(
        authService: _StubEmailAuthService(
          googleError: const GoogleAuthException('config'),
        ),
      );

      await controller.signInWithGoogle();

      expect(controller.status, AuthStatus.error);
      expect(
        controller.errorMessage,
        'Google 登入暫時還不能用，可以改用 Email 登入喔。',
      );
      expect(controller.errorMessage, isNot(contains('config')));
      expect(controller.errorMessage, isNot(contains('Exception')));
    });

    test('非預期錯誤也轉白話，不讓 App 卡死', () async {
      final controller = AuthController(
        authService: _StubEmailAuthService(googleError: StateError('boom')),
      );

      await controller.signInWithGoogle();

      expect(controller.status, AuthStatus.error);
      expect(controller.errorMessage, '現在連線不太順，待會再試一次好嗎？');
    });
  });
}
