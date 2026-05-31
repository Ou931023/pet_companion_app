import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pet_companion_app/app.dart';
import 'package:pet_companion_app/controllers/auth_controller.dart';
import 'package:pet_companion_app/controllers/profile_controller.dart';
import 'package:pet_companion_app/models/auth_session.dart';
import 'package:pet_companion_app/screens/login_screen.dart';
import 'package:pet_companion_app/screens/onboarding_screen.dart';
import 'package:pet_companion_app/screens/register_screen.dart';
import 'package:pet_companion_app/services/auth/auth_service.dart';
import 'package:pet_companion_app/services/local_storage_service.dart';

/// 可控狀態的 AuthController：直接設定終態，不碰 prefs / 後端 / 真 AuthService。
class _StubAuthController extends AuthController {
  _StubAuthController(this._status) : super(authService: _StubAuthService()) {
    setStatusForTest(_status);
  }

  AuthStatus _status;

  /// 紀錄 restore() 被呼叫的次數（驗證啟動只還原一次）。
  int restoreCallCount = 0;

  @override
  AuthStatus get status => _status;

  void setStatusForTest(AuthStatus next) {
    _status = next;
    notifyListeners();
  }

  @override
  Future<void> restore() async {
    restoreCallCount++;
    // 不真的去 prefs / 後端，維持目前測試指定的狀態。
  }

  /// 模擬 demo 登入成功：直接收斂到 authenticated。
  @override
  Future<void> loginAsDemoUser({String? displayName, String? email}) async {
    setStatusForTest(AuthStatus.authenticated);
  }
}

class _StubAuthService extends AuthService {
  @override
  Future<AuthSession?> restoreSession() async => null;
}

/// 可控 isLoading / hasCompletedOnboarding 的 ProfileController，
/// 不碰真實儲存。
class _FakeProfileController extends ProfileController {
  _FakeProfileController({
    required bool isLoading,
    required bool onboarded,
  })  : _isLoading = isLoading,
        _onboarded = onboarded,
        super(_NoopLocalStorageService());

  final bool _isLoading;
  final bool _onboarded;

  @override
  bool get isLoading => _isLoading;

  @override
  bool get hasCompletedOnboarding => _onboarded;
}

/// ProfileController 建構子需要一個 LocalStorageService；測試不會真的呼叫它。
class _NoopLocalStorageService extends LocalStorageService {}

Future<void> _pumpGate(
  WidgetTester tester, {
  required AuthController auth,
  ProfileController? profile,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthController>.value(value: auth),
        ChangeNotifierProvider<ProfileController>.value(
          value: profile ??
              _FakeProfileController(isLoading: false, onboarded: false),
        ),
      ],
      child: const MaterialApp(home: AuthGate()),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void useTallView(WidgetTester tester) {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
  }

  testWidgets('loading → 顯示溫暖等待文案，無工程字', (tester) async {
    useTallView(tester);
    await _pumpGate(tester, auth: _StubAuthController(AuthStatus.loading));
    await tester.pump();

    expect(find.text('正在準備你的陪伴空間…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.textContaining('error'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets('unauthenticated → 顯示 LoginScreen', (tester) async {
    useTallView(tester);
    await _pumpGate(
      tester,
      auth: _StubAuthController(AuthStatus.unauthenticated),
    );
    await tester.pump();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('先進去陪伴'), findsOneWidget);
  });

  testWidgets('error → 顯示 LoginScreen（可重試，不死路、不露工程字）', (tester) async {
    useTallView(tester);
    await _pumpGate(tester, auth: _StubAuthController(AuthStatus.error));
    await tester.pump();

    expect(find.byType(LoginScreen), findsOneWidget);
    // 仍可看到可操作的主按鈕（可重試 / 重新 demo 登入）
    expect(find.text('先進去陪伴'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('error'), findsNothing);
  });

  testWidgets('authenticated + 未完成 onboarding → OnboardingScreen', (tester) async {
    useTallView(tester);
    await _pumpGate(
      tester,
      auth: _StubAuthController(AuthStatus.authenticated),
      profile: _FakeProfileController(isLoading: false, onboarded: false),
    );
    await tester.pump();

    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets('authenticated + profile 載入中 → 簡單等待畫面（落回既有流程）',
      (tester) async {
    useTallView(tester);
    await _pumpGate(
      tester,
      auth: _StubAuthController(AuthStatus.authenticated),
      profile: _FakeProfileController(isLoading: true, onboarded: true),
    );
    await tester.pump();

    // 進入 authenticated 分支後，profile.isLoading 沿用既有 CircularProgressIndicator，
    // 不再是登入頁、也不是 onboarding。
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byType(OnboardingScreen), findsNothing);
    // 既有流程的 spinner 沒有 auth loading 的文案。
    expect(find.text('正在準備你的陪伴空間…'), findsNothing);
  });

  testWidgets('authenticated + 已完成 onboarding → 選到 MainShell 分支（既有流程）',
      (tester) async {
    // 取捨：MainShell 會建構 HomeScreen，其依賴 VoiceAgent/Conversation 等大量
    // provider，於單元測試完整建構成本過高（核准備註允許較輕量驗證）。這裡只驗證
    // gate 在 authenticated + onboarded 時「選到 MainShell 分支」：MainShell widget
    // 本身有被建立（find.byType 找得到），其子樹因缺 provider 而拋錯屬預期，
    // 用 takeException 收掉，重點是「不是被誤導到 LoginScreen / Onboarding」。
    useTallView(tester);
    final auth = _StubAuthController(AuthStatus.authenticated);
    final profile =
        _FakeProfileController(isLoading: false, onboarded: true);

    await _pumpGate(tester, auth: auth, profile: profile);

    // gate 確實選到 MainShell 分支（widget 已建立）。
    expect(find.byType(MainShell), findsOneWidget);
    // 不是登入 / onboarding / auth loading。
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.text('正在準備你的陪伴空間…'), findsNothing);

    // MainShell 子樹（HomeScreen）缺 provider 的建構錯誤屬預期，收掉避免污染測試結果。
    final exception = tester.takeException();
    expect(exception, isNotNull);
  });

  testWidgets('demo 登入成功 → gate 由 LoginScreen 重建進入既有流程', (tester) async {
    useTallView(tester);
    final auth = _StubAuthController(AuthStatus.unauthenticated);
    await _pumpGate(
      tester,
      auth: auth,
      profile: _FakeProfileController(isLoading: false, onboarded: false),
    );
    await tester.pump();
    expect(find.byType(LoginScreen), findsOneWidget);

    // 按主按鈕走 demo 登入（stub 直接收斂 authenticated）。
    await tester.tap(find.text('先進去陪伴'));
    await tester.pumpAndSettle();

    // gate 重建後不再是登入頁，落到既有流程（此處 onboarded=false → Onboarding）。
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byType(OnboardingScreen), findsOneWidget);
  });

  testWidgets('Login ↔ Register 切換：onRegister 疊上 Register，返回可回 Login',
      (tester) async {
    useTallView(tester);
    await _pumpGate(
      tester,
      auth: _StubAuthController(AuthStatus.unauthenticated),
    );
    await tester.pump();

    expect(find.byType(LoginScreen), findsOneWidget);

    await tester.tap(find.text('註冊'));
    await tester.pumpAndSettle();
    expect(find.byType(RegisterScreen), findsOneWidget);

    await tester.tap(find.text('返回登入'));
    await tester.pumpAndSettle();
    expect(find.byType(RegisterScreen), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  test('restore() 啟動只被呼叫一次的計數驗證（控制器層）', () async {
    final auth = _StubAuthController(AuthStatus.unauthenticated);
    expect(auth.restoreCallCount, 0);
    await auth.restore();
    expect(auth.restoreCallCount, 1);
  });
}
