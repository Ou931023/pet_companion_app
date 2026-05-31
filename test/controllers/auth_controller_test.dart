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
  _StubEmailAuthService({this.session, this.error, this.googleError});

  final AuthSession? session;
  final Object? error;
  final Object? googleError;

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
    // 先登入一次寫入持久化。
    await service.mockLogin();

    final controller = AuthController(authService: service);
    await controller.restore();

    expect(controller.status, AuthStatus.authenticated);
    expect(controller.currentUserId, 'user-123');
    expect(controller.currentElderId, 'elder-456');
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

  test('firebase session → currentElderId / currentUserId 使用後端真實 id', () async {
    final service = _authServiceReturning({
      'success': true,
      'userId': 'user-789',
      'elderId': 'elder-789',
      'bindingStatus': 'bound',
      'isNewUser': false,
      'authMode': 'firebase',
    });
    await service.mockLogin();

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
      expect(controller.errorMessage, '帳號或密碼不太對，再試一次好嗎？');
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
        'Google 登入暫時還不能用，可以先用 Email 或「先進去陪伴」喔。',
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
