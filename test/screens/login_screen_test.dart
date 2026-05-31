import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pet_companion_app/controllers/auth_controller.dart';
import 'package:pet_companion_app/models/auth_session.dart';
import 'package:pet_companion_app/screens/login_screen.dart';
import 'package:pet_companion_app/services/auth/auth_service.dart';

/// 可控制成功 / 失敗 / 卡住的假 AuthService，避免測試碰真後端或 prefs。
class _FakeAuthService extends AuthService {
  _FakeAuthService({this.shouldFail = false, this.completer});

  final bool shouldFail;

  /// 若有提供，mockLogin 會等到外部 complete 才回（測 loading 狀態）。
  final Completer<void>? completer;

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

  testWidgets('顯示溫暖標題、副標與主要登入按鈕', (tester) async {
    useTallView(tester);
    final controller = AuthController(authService: _FakeAuthService());
    await _pumpLogin(tester, controller);

    expect(find.text('歡迎回來，陪伴一直都在'), findsOneWidget);
    expect(find.text('點一下就能開始，和你的陪伴寵物說說話。'), findsOneWidget);
    expect(find.text('先進去陪伴'), findsOneWidget);
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
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // 不可出現工程 / debug 字樣
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('error'), findsNothing);
    expect(find.textContaining('demo'), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('登入失敗顯示白話錯誤訊息，不露技術細節', (tester) async {
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

  testWidgets('Google / Apple / Email 按鈕點擊不 crash 並顯示「即將推出」', (tester) async {
    useTallView(tester);
    final controller = AuthController(authService: _FakeAuthService());
    await _pumpLogin(tester, controller);

    for (final label in ['用 Google 綁定', '用 Apple 綁定', '用 Email 綁定']) {
      await tester.tap(find.text(label));
      await tester.pump();
      expect(find.textContaining('即將推出'), findsOneWidget);
      // 清掉 snackbar 再測下一個
      await tester.pumpAndSettle(const Duration(seconds: 4));
    }
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
