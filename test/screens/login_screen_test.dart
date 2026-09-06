import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pet_companion_app/controllers/app_navigation_controller.dart';
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
    this.appleError,
    this.passwordResetError,
  });

  final bool shouldFail;

  /// 若有提供，mockLogin 會等到外部 complete 才回（測 loading 狀態）。
  final Completer<void>? completer;

  /// Email 登入要丟的錯（測白話錯誤）。
  final Object? emailError;

  /// Google 登入要丟的錯（測取消 / 白話錯誤）。
  final Object? googleError;

  /// Apple 登入要丟的錯（測取消 / 白話錯誤）。
  final Object? appleError;

  /// 密碼重設要丟的錯（測 controller 回傳的白話訊息）。
  final Object? passwordResetError;

  int passwordResetCalls = 0;
  String? lastPasswordResetEmail;

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

  @override
  Future<AuthSession> signInWithApple() async {
    if (appleError != null) throw appleError!;
    return AuthSession.mockFallback();
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    passwordResetCalls += 1;
    lastPasswordResetEmail = email;
    if (passwordResetError != null) throw passwordResetError!;
  }
}

Future<void> _pumpLogin(
  WidgetTester tester,
  AuthController controller, {
  VoidCallback? onSignedIn,
  VoidCallback? onRegister,
  // 預設帶出 Demo 備援按鈕，方便沿用既有 Demo 測試；正式模式另有專門測試。
  bool showDemoLogin = true,
  bool showSocialSignIn = true,
  double textScale = 1,
  TargetPlatform platform = TargetPlatform.iOS,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: platform),
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthController>.value(value: controller),
          ChangeNotifierProvider<AppNavigationController>(
            create: (_) => AppNavigationController(),
          ),
        ],
        child: LoginScreen(
          onSignedIn: onSignedIn,
          onRegister: onRegister,
          showDemoLogin: showDemoLogin,
          showSocialSignIn: showSocialSignIn,
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

  testWidgets('顯示主視覺標題、Demo 備援按鈕與可展開的 Email 登入區', (tester) async {
    useTallView(tester);
    final controller = AuthController(authService: _FakeAuthService());
    await _pumpLogin(tester, controller);

    expect(find.text('你的陪伴夥伴正在等你'), findsOneWidget);
    expect(find.text('先進去陪伴'), findsOneWidget); // Demo 仍保留且明顯
    expect(find.text('Email 登入'), findsOneWidget);
    // 預設收合：尚未點開「Email 登入」時不顯示輸入框（畫面先呈現寵物與登入選項）。
    expect(find.byType(TextField), findsNothing);

    // 點「Email 登入」展開 Email / 密碼欄位與「登入」按鈕。
    await tester.tap(find.text('Email 登入'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('登入'), findsOneWidget);
    expect(find.text('忘記密碼？'), findsOneWidget);
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

    await tester.tap(find.text('Email 登入'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'grandma@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'secret1');
    await tester.tap(find.text('登入'));
    await tester.pumpAndSettle();

    expect(controller.status, AuthStatus.authenticated);
    expect(signedIn, isTrue);
  });

  testWidgets('Email 欄位空白 → 白話提醒，不送出', (tester) async {
    useTallView(tester);
    final controller = AuthController(authService: _FakeAuthService());
    await _pumpLogin(tester, controller);

    await tester.tap(find.text('Email 登入'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('登入'));
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

    await tester.tap(find.text('Email 登入'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'grandma@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'bad');
    await tester.tap(find.text('登入'));
    await tester.pumpAndSettle();

    expect(controller.status, AuthStatus.error);
    // 錯誤改由 build() 內白話橫幅顯示（不靠 snackbar）。
    expect(find.text('Email 或密碼不太對，請再確認一次。'), findsOneWidget);
    expect(find.textContaining('wrong-password'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets('Apple 正式登入成功 → authenticated 並呼叫 onSignedIn', (tester) async {
    useTallView(tester);
    final controller = AuthController(authService: _FakeAuthService());
    var signedIn = false;
    await _pumpLogin(tester, controller, onSignedIn: () => signedIn = true);

    expect(find.text('Apple 登入'), findsOneWidget);

    await tester.tap(find.text('Apple 登入'));
    await tester.pumpAndSettle();

    expect(controller.status, AuthStatus.authenticated);
    expect(signedIn, isTrue);
    expect(find.textContaining('準備中'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets('Apple 登入被取消 → 留在登入頁且不顯示錯誤', (tester) async {
    useTallView(tester);
    final controller = AuthController(
      authService: _FakeAuthService(
        appleError: const AppleAuthException('canceled'),
      ),
    );
    await _pumpLogin(tester, controller);

    await tester.tap(find.text('Apple 登入'));
    await tester.pumpAndSettle();

    expect(controller.status, AuthStatus.unauthenticated);
    expect(controller.errorMessage, isNull);
    expect(find.textContaining('canceled'), findsNothing);
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });

  testWidgets('Google 按鈕成功登入 → authenticated 並呼叫 onSignedIn', (tester) async {
    useTallView(tester);
    final controller = AuthController(authService: _FakeAuthService());
    var signedIn = false;
    await _pumpLogin(tester, controller, onSignedIn: () => signedIn = true);

    await tester.tap(find.text('Google 登入'));
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

    await tester.tap(find.text('Google 登入'));
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

    await tester.tap(find.text('Google 登入'));
    await tester.pumpAndSettle();

    expect(controller.status, AuthStatus.error);
    expect(
      find.text('Google 登入暫時還不能用，可以改用 Email 登入喔。'),
      findsOneWidget,
    );
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets('點「開始陪伴生活」會呼叫 onRegister', (tester) async {
    useTallView(tester);
    final controller = AuthController(authService: _FakeAuthService());
    var registerTapped = false;
    await _pumpLogin(tester, controller,
        onRegister: () => registerTapped = true);

    await tester.tap(find.text('開始陪伴生活'));
    await tester.pump();

    expect(registerTapped, isTrue);
  });

  testWidgets('正式模式：顯示 Google、Apple、Email，且不顯示 Demo', (tester) async {
    useTallView(tester);
    final controller = AuthController(authService: _FakeAuthService());
    await _pumpLogin(
      tester,
      controller,
      showDemoLogin: false,
      showSocialSignIn: true,
    );

    // 正式登入入口完整可見。
    expect(find.text('Google 登入'), findsOneWidget);
    expect(find.text('Apple 登入'), findsOneWidget);
    expect(find.text('Email 登入'), findsOneWidget);
    expect(find.text('開始陪伴生活'), findsOneWidget);

    // 不出現測試感字樣 / Demo 按鈕 / Apple placeholder。
    expect(find.text('先進去陪伴'), findsNothing);
    expect(find.textContaining('Apple 登入準備中'), findsNothing);
    expect(find.textContaining('Demo'), findsNothing);
    expect(find.textContaining('demo'), findsNothing);
    expect(find.textContaining('測試'), findsNothing);
    expect(find.textContaining('快速開始'), findsNothing);
  });

  testWidgets('Android 正式模式只顯示 Google，不顯示 Apple 入口', (tester) async {
    useTallView(tester);
    final controller = AuthController(authService: _FakeAuthService());

    await _pumpLogin(
      tester,
      controller,
      showDemoLogin: false,
      showSocialSignIn: true,
      platform: TargetPlatform.android,
    );

    expect(find.text('Google 登入'), findsOneWidget);
    expect(find.text('Apple 登入'), findsNothing);
    expect(find.text('Email 登入'), findsOneWidget);
  });

  testWidgets('忘記密碼：Email 空白或格式錯誤時不送出並顯示白話提醒', (tester) async {
    useTallView(tester);
    final service = _FakeAuthService();
    final controller = AuthController(authService: service);
    await _pumpLogin(tester, controller);
    await tester.tap(find.text('Email 登入'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('忘記密碼？'));
    await tester.pump();
    expect(find.text('請先填入要重設密碼的 Email 喔。'), findsOneWidget);
    expect(service.passwordResetCalls, 0);

    await tester.enterText(find.byType(TextField).first, '不是 Email');
    await tester.tap(find.text('忘記密碼？'));
    await tester.pump();
    expect(find.text('Email 的格式好像不太對，再檢查一下喔。'), findsOneWidget);
    expect(service.passwordResetCalls, 0);
  });

  testWidgets('忘記密碼：有效 Email 會呼叫 controller 並顯示已寄信訊息', (tester) async {
    useTallView(tester);
    final service = _FakeAuthService();
    final controller = AuthController(authService: service);
    await _pumpLogin(tester, controller);
    await tester.tap(find.text('Email 登入'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      ' grandma@example.com ',
    );

    await tester.tap(find.text('忘記密碼？'));
    await tester.pumpAndSettle();

    expect(service.passwordResetCalls, 1);
    expect(service.lastPasswordResetEmail, 'grandma@example.com');
    expect(find.text('重設密碼的信已寄出，請到 Email 信箱收信喔。'), findsOneWidget);
  });

  testWidgets('忘記密碼：寄送失敗顯示 controller 回傳的白話訊息', (tester) async {
    useTallView(tester);
    final service = _FakeAuthService(
      passwordResetError: const EmailAuthException('network-request-failed'),
    );
    final controller = AuthController(authService: service);
    await _pumpLogin(tester, controller);
    await tester.tap(find.text('Email 登入'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      'grandma@example.com',
    );

    await tester.tap(find.text('忘記密碼？'));
    await tester.pumpAndSettle();

    expect(find.text('現在網路好像不太穩，待會再試一次好嗎？'), findsOneWidget);
    expect(find.textContaining('network-request-failed'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets('小螢幕 1.3 倍文字可捲動且不 overflow', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    final controller = AuthController(authService: _FakeAuthService());

    await _pumpLogin(
      tester,
      controller,
      showDemoLogin: false,
      showSocialSignIn: true,
      textScale: 1.3,
    );
    await tester.pumpAndSettle();

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('開發模式（showDemoLogin=true）：仍保留 Demo 備援按鈕', (tester) async {
    useTallView(tester);
    final controller = AuthController(authService: _FakeAuthService());
    await _pumpLogin(tester, controller, showDemoLogin: true);

    expect(find.text('先進去陪伴'), findsOneWidget);
  });

  testWidgets('登入前可看到隱私權政策與服務條款入口', (tester) async {
    useTallView(tester);
    final controller = AuthController(authService: _FakeAuthService());
    await _pumpLogin(tester, controller);

    expect(find.text('登入即代表你已閱讀並同意'), findsOneWidget);
    expect(find.text('隱私權政策'), findsOneWidget);
    expect(find.text('服務條款'), findsOneWidget);
  });

  testWidgets('點「隱私權政策」會在 App 內開啟並顯示政策內容', (tester) async {
    useTallView(tester);
    final controller = AuthController(authService: _FakeAuthService());
    await _pumpLogin(tester, controller);

    await tester.tap(find.text('隱私權政策'));
    await tester.pumpAndSettle();

    // 進入 App 內可捲動閱讀的政策畫面，顯示政策段落（不依賴外部網址）。
    expect(find.text('我們珍惜你的信任'), findsOneWidget);
    expect(find.textContaining('TODO'), findsNothing);
  });

  testWidgets('點「服務條款」會在 App 內開啟並顯示條款內容', (tester) async {
    useTallView(tester);
    final controller = AuthController(authService: _FakeAuthService());
    await _pumpLogin(tester, controller);

    await tester.tap(find.text('服務條款'));
    await tester.pumpAndSettle();

    expect(find.text('關於這個服務'), findsOneWidget);
    expect(find.textContaining('TODO'), findsNothing);
  });
}
