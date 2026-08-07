import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pet_companion_app/controllers/auth_controller.dart';
import 'package:pet_companion_app/screens/register_screen.dart';
import 'package:pet_companion_app/services/auth/auth_service.dart';
import 'package:pet_companion_app/services/auth/firebase_auth_service.dart';

/// 覆寫 registerAccountOnly 的假 AuthService（註冊頁只做 Email 註冊）。
class _FakeAuthService extends AuthService {
  _FakeAuthService({this.registerError});

  final Object? registerError;

  @override
  Future<void> registerAccountOnly({
    required String email,
    required String password,
    String? displayName,
  }) async {
    if (registerError != null) throw registerError!;
    // 成功：不自動登入、不回 session。
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

  testWidgets('只做 Email 註冊：有欄位與建立帳號鈕，且不再有 Google/Apple 註冊鈕', (tester) async {
    useTallView(tester);
    final controller = AuthController(authService: _FakeAuthService());
    await _pumpRegister(tester, controller);

    expect(find.text('建立你的帳號，紀錄好好保存'), findsOneWidget);
    expect(find.text('建立帳號'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(3)); // email + 密碼 + 確認密碼
    // Google / Apple 註冊入口與未完成提示都不出現在註冊頁。
    expect(find.text('用 Google 註冊'), findsNothing);
    expect(find.text('用 Apple 註冊'), findsNothing);
    expect(find.textContaining('Google'), findsNothing);
    expect(find.textContaining('Apple'), findsNothing);
    expect(find.text('請使用常用的 Email，之後回來就能接著陪伴。'), findsOneWidget);
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

  testWidgets('Email 註冊成功 → 顯示「帳號建立成功」且不自動登入（CR-0006 Batch 4d）',
      (tester) async {
    useTallView(tester);
    final controller = AuthController(authService: _FakeAuthService());
    await _pumpRegister(tester, controller);

    await tester.enterText(find.byType(TextField).at(0), 'grandma@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'secret1');
    await tester.enterText(find.byType(TextField).at(2), 'secret1');
    await tester.tap(find.text('建立帳號'));
    await tester.pumpAndSettle();

    // 顯示成功提示對話框，且**不**自動登入。
    expect(find.text('帳號建立成功'), findsOneWidget);
    expect(find.text('請用剛剛的 Email 和密碼登入吧。'), findsOneWidget);
    expect(find.text('去登入'), findsOneWidget);
    expect(controller.status, isNot(AuthStatus.authenticated));
  });

  testWidgets('Email 已被使用 → 白話提醒、不自動登入', (tester) async {
    useTallView(tester);
    final controller = AuthController(
      authService: _FakeAuthService(
        registerError: const EmailAuthException('email-already-in-use'),
      ),
    );
    await _pumpRegister(tester, controller);

    await tester.enterText(find.byType(TextField).at(0), 'grandma@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'secret1');
    await tester.enterText(find.byType(TextField).at(2), 'secret1');
    await tester.tap(find.text('建立帳號'));
    await tester.pumpAndSettle();

    expect(find.text('這個 Email 已經註冊過了，直接登入就可以囉。'), findsOneWidget);
    expect(controller.status, isNot(AuthStatus.authenticated));
  });

  testWidgets('點「返回登入」會呼叫 onBackToLogin', (tester) async {
    useTallView(tester);
    final controller = AuthController(authService: _FakeAuthService());
    var backTapped = false;
    await _pumpRegister(tester, controller,
        onBackToLogin: () => backTapped = true);

    await tester.tap(find.text('返回登入'));
    await tester.pump();

    expect(backTapped, isTrue);
  });
}
