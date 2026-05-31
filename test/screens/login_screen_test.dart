import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pet_companion_app/controllers/auth_controller.dart';
import 'package:pet_companion_app/models/auth_session.dart';
import 'package:pet_companion_app/screens/login_screen.dart';
import 'package:pet_companion_app/services/auth/auth_service.dart';
import 'package:pet_companion_app/services/auth/firebase_auth_service.dart';

/// 可控制成功 / 失敗 / 卡住的假 AuthService，避免測試碰真後端或 prefs。
class _FakeAuthService extends AuthService {
  _FakeAuthService({
    this.shouldFail = false,
    this.completer,
    this.emailError,
    this.googleError,
  });

  final bool shouldFail;

  /// 若有提供，mockLogin 會等到外部 complete 才回（測 loading 狀態）。
  final Completer<void>? completer;

  /// Email 登入要丟的錯（測白話錯誤）。
  final Object? emailError;

  /// Google 登入要丟的錯（測取消 / 白話錯誤）。
  final Object? googleError;

  @override
  Future<AuthSession> mockLogin({String? displayName, String? email}) async {
    if (completer != null) {
      await completer!.future;
    }
    if (shouldFail) {
      throw StateError('forced failure for test');
    }
    return AuthSession.mockFallback();
  }

  @override
  Future<AuthSession> signInWithEmail({
    required String email,
    required String password,
  }) async {
    if (emailError != null) throw emailError!;
    return AuthSession.mockFallback();
  }

  @override
  Future<AuthSession> signInWithGoogle() async {
    if (googleError != null) throw googleError!;
    return AuthSession.mockFallback();
  }
}

Future<void> _pumpLogin(
  WidgetTester tester,
  AuthController controller, {
  VoidCallback? onSignedIn,
  VoidCallback? onRegister,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ChangeNotifierProvider<AuthController>.value(
        value: controller,
        child: LoginScreen(
          onSignedIn: onSignedIn,
          onRegister: onRegister,
        ),
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

  testWidgets('顯示溫暖標題、Demo 主按鈕與 Email 登入區', (tester) async {
    useTallView(tester);
    final controller = AuthController(authService: _FakeAuthService());
    await _pumpLogin(tester, controller);

    expect(find.text('歡迎回來，陪伴一直都在'), findsOneWidget);
    expect(find.text('先進去陪伴'), findsOneWidget); // Demo 仍保留且明顯
    expect(find.text('用 Email 登入'), findsOneWidget);
    // Email / 密碼 兩個輸入框
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('點主按鈕成功登入會轉為 authenticated 並呼叫 onSignedIn', (tester) async {
    useTallView(tester);
    final controller = AuthController(authService: _FakeAuthService());
    var signedIn = false;
    await _pumpLogin(tester, controller, onSignedIn: () => signedIn = true);

    await tester.tap(find.text('先進去陪伴'));
    await tester.pumpAndSettle();

    expect(controller.status, AuthStatus.authenticated);
    expect(signedIn, isTrue);
  });

  testWidgets('登入進行中顯示白話 loading，且不出現工程字', (tester) async {
    useTallView(tester);
    final gate = Completer<void>();
    final controller = AuthController(
      authService: _FakeAuthService(completer: gate),
    );
    await _pumpLogin(tester, controller);

    await tester.tap(find.text('先進去陪伴'));
    await tester.pump();

    expect(find.text('正在帶你進去…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('error'), findsNothing);
    expect(find.textContaining('demo'), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('Demo 登入失敗顯示白話錯誤訊息，不露技術細節', (tester) async {
    useTallView(tester);
    final controller = AuthController(
      authService: _FakeAuthService(shouldFail: true),
    );
    await _pumpLogin(tester, controller);

    await tester.tap(find.text('先進去陪伴'));
    await tester.pumpAndSettle();

    expect(controller.status, AuthStatus.error);
    expect(find.text('現在連線不太順，待會再試一次好嗎？'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('StateError'), findsNothing);
  });

  testWidgets('Email 登入成功 → authenticated 並呼叫 onSignedIn', (tester) async {
    useTallView(tester);
    final controller = AuthController(authService: _FakeAuthService());
    var signedIn = false;
    await _pumpLogin(tester, controller, onSignedIn: () => signedIn = true);

    await tester.enterText(find.byType(TextField).at(0), 'grandma@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'secret1');
    await tester.tap(find.text('用 Email 登入'));
    await tester.pumpAndSettle();

    expect(controller.status, AuthStatus.authenticated);
    expect(signedIn, isTrue);
  });

  testWidgets('Email 欄位空白 → 白話提醒，不送出', (tester) async {
    useTallView(tester);
    final controller = AuthController(authService: _FakeAuthService());
    await _pumpLogin(tester, controller);

    await tester.tap(find.text('用 Email 登入'));
    await tester.pumpAndSettle();

    expect(find.text('請先填一下 Email 喔。'), findsOneWidget);
    expect(controller.status, isNot(AuthStatus.authenticated));
  });

  testWidgets('Email 登入失敗顯示白話錯誤，不露 Firebase code', (tester) async {
    useTallView(tester);
    final controller = AuthController(
      authService: _FakeAuthService(
        emailError: const EmailAuthException('wrong-password'),
      ),
    );
    await _pumpLogin(tester, controller);

    await tester.enterText(find.byType(TextField).at(0), 'grandma@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'bad');
    await tester.tap(find.text('用 Email 登入'));
    await tester.pumpAndSettle();

    expect(controller.status, AuthStatus.error);
    expect(find.text('帳號或密碼不太對，再試一次好嗎？'), findsOneWidget);
    expect(find.textContaining('wrong-password'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets('Apple 按鈕仍顯示「即將推出」，不 crash', (tester) async {
    useTallView(tester);
    final controller = AuthController(authService: _FakeAuthService());
    await _pumpLogin(tester, controller);

    await tester.tap(find.text('用 Apple 綁定'));
    await tester.pump();
    expect(find.textContaining('即將推出'), findsOneWidget);
  });

  testWidgets('Google 按鈕成功登入 → authenticated 並呼叫 onSignedIn', (tester) async {
    useTallView(tester);
    final controller = AuthController(authService: _FakeAuthService());
    var signedIn = false;
    await _pumpLogin(tester, controller, onSignedIn: () => signedIn = true);

    await tester.tap(find.text('用 Google 綁定'));
    await tester.pumpAndSettle();

    expect(controller.status, AuthStatus.authenticated);
    expect(signedIn, isTrue);
  });

  testWidgets('Google 登入被取消 → 不 crash、不顯示嚇人錯誤', (tester) async {
    useTallView(tester);
    final controller = AuthController(
      authService: _FakeAuthService(
        googleError: const GoogleAuthException('canceled'),
      ),
    );
    await _pumpLogin(tester, controller);

    await tester.tap(find.text('用 Google 綁定'));
    await tester.pumpAndSettle();

    expect(controller.status, isNot(AuthStatus.authenticated));
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('canceled'), findsNothing);
  });

  testWidgets('Google 設定不足 → 白話錯誤，不露技術細節', (tester) async {
    useTallView(tester);
    final controller = AuthController(
      authService: _FakeAuthService(
        googleError: const GoogleAuthException('config'),
      ),
    );
    await _pumpLogin(tester, controller);

    await tester.tap(find.text('用 Google 綁定'));
    await tester.pumpAndSettle();

    expect(controller.status, AuthStatus.error);
    expect(
      find.text('Google 登入暫時還不能用，可以先用 Email 或「先進去陪伴」喔。'),
      findsOneWidget,
    );
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets('點「註冊」會呼叫 onRegister', (tester) async {
    useTallView(tester);
    final controller = AuthController(authService: _FakeAuthService());
    var registerTapped = false;
    await _pumpLogin(tester, controller, onRegister: () => registerTapped = true);

    await tester.tap(find.text('註冊'));
    await tester.pump();

    expect(registerTapped, isTrue);
  });
}
