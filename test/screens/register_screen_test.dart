import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pet_companion_app/controllers/auth_controller.dart';
import 'package:pet_companion_app/models/auth_session.dart';
import 'package:pet_companion_app/screens/register_screen.dart';
import 'package:pet_companion_app/services/auth/auth_service.dart';
import 'package:pet_companion_app/services/auth/firebase_auth_service.dart';

/// 覆寫 registerWithEmail / signInWithGoogle 的假 AuthService。
class _FakeAuthService extends AuthService {
  _FakeAuthService({this.googleError});

  final Object? googleError;

  @override
  Future<AuthSession> registerWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    return AuthSession.mockFallback();
  }

  @override
  Future<AuthSession> signInWithGoogle() async {
    if (googleError != null) throw googleError!;
    return AuthSession.mockFallback();
  }
}

Future<void> _pumpRegister(
  WidgetTester tester,
  AuthController controller, {
  VoidCallback? onBackToLogin,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ChangeNotifierProvider<AuthController>.value(
        value: controller,
        child: RegisterScreen(onBackToLogin: onBackToLogin),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 放大測試視窗，避免長者友善大字大按鈕在預設小視窗下被裁掉。
  void useTallView(WidgetTester tester) {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
  }

  testWidgets('顯示標題、Email 註冊欄位與建立帳號按鈕；Google/Apple 仍保留', (tester) async {
    useTallView(tester);
    final controller = AuthController(authService: _FakeAuthService());
    await _pumpRegister(tester, controller);

    expect(find.text('建立你的帳號，紀錄好好保存'), findsOneWidget);
    expect(find.text('建立帳號'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(3)); // email + 密碼 + 確認密碼
    expect(find.text('用 Google 註冊'), findsOneWidget);
    expect(find.text('用 Apple 註冊'), findsOneWidget);
  });

  testWidgets('兩次密碼不一致 → 白話提醒，不送出', (tester) async {
    useTallView(tester);
    final controller = AuthController(authService: _FakeAuthService());
    await _pumpRegister(tester, controller);

    await tester.enterText(find.byType(TextField).at(0), 'grandma@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'secret1');
    await tester.enterText(find.byType(TextField).at(2), 'secret2');
    await tester.tap(find.text('建立帳號'));
    await tester.pumpAndSettle();

    expect(find.text('兩次輸入的密碼不一樣，再確認一下好嗎？'), findsOneWidget);
    expect(controller.status, isNot(AuthStatus.authenticated));
  });

  testWidgets('密碼太短 → 白話提醒', (tester) async {
    useTallView(tester);
    final controller = AuthController(authService: _FakeAuthService());
    await _pumpRegister(tester, controller);

    await tester.enterText(find.byType(TextField).at(0), 'grandma@example.com');
    await tester.enterText(find.byType(TextField).at(1), '123');
    await tester.enterText(find.byType(TextField).at(2), '123');
    await tester.tap(find.text('建立帳號'));
    await tester.pumpAndSettle();

    expect(find.text('密碼長一點會比較安全，至少 6 個字喔。'), findsOneWidget);
  });

  testWidgets('Email 註冊成功 → controller 轉 authenticated', (tester) async {
    useTallView(tester);
    final controller = AuthController(authService: _FakeAuthService());
    await _pumpRegister(tester, controller);

    await tester.enterText(find.byType(TextField).at(0), 'grandma@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'secret1');
    await tester.enterText(find.byType(TextField).at(2), 'secret1');
    await tester.tap(find.text('建立帳號'));
    await tester.pumpAndSettle();

    expect(controller.status, AuthStatus.authenticated);
  });

  testWidgets('Apple 註冊按鈕仍顯示「即將推出」，不 crash', (tester) async {
    useTallView(tester);
    final controller = AuthController(authService: _FakeAuthService());
    await _pumpRegister(tester, controller);

    await tester.tap(find.text('用 Apple 註冊'));
    await tester.pump();

    expect(find.textContaining('即將推出'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets('Google 註冊成功 → controller 轉 authenticated', (tester) async {
    useTallView(tester);
    final controller = AuthController(authService: _FakeAuthService());
    await _pumpRegister(tester, controller);

    await tester.tap(find.text('用 Google 註冊'));
    await tester.pumpAndSettle();

    expect(controller.status, AuthStatus.authenticated);
  });

  testWidgets('Google 註冊被取消 → 不 crash、不顯示嚇人錯誤', (tester) async {
    useTallView(tester);
    final controller = AuthController(
      authService: _FakeAuthService(
        googleError: const GoogleAuthException('canceled'),
      ),
    );
    await _pumpRegister(tester, controller);

    await tester.tap(find.text('用 Google 註冊'));
    await tester.pumpAndSettle();

    expect(controller.status, isNot(AuthStatus.authenticated));
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets('點「返回登入」會呼叫 onBackToLogin', (tester) async {
    useTallView(tester);
    final controller = AuthController(authService: _FakeAuthService());
    var backTapped = false;
    await _pumpRegister(tester, controller, onBackToLogin: () => backTapped = true);

    await tester.tap(find.text('返回登入'));
    await tester.pump();

    expect(backTapped, isTrue);
  });
}
