import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../controllers/app_navigation_controller.dart';
import '../controllers/auth_controller.dart';
import '../routes/app_routes.dart';
import '../widgets/auth/auth_provider_button.dart';
import '../widgets/auth/auth_visuals.dart';
import 'legal_document_screen.dart';

/// 登入頁。
///
/// 正式展示主視覺：先看到放大的陪伴寵物與溫暖文案，再呈現登入選項
/// （Google / Apple / 用 Email 登入）。Email / 密碼欄位預設收合，點「用 Email 登入」
/// 才展開，避免一開始就太像工具表單。Demo 快速登入預設隱藏，由
/// `AppConfig.showDemoLoginButton`（或建構參數 [showDemoLogin]）控制，開發時可開啟。
///
/// 本次只調整 UI / UX 與文案；Google / Apple / Email 登入邏輯一字未動。
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.onSignedIn,
    this.onRegister,
    this.showDemoLogin,
  });

  /// 登入成功（state=authenticated）後通知外層。
  final VoidCallback? onSignedIn;

  /// 點「還沒有帳號？開始陪伴生活」時通知外層切到註冊頁。
  final VoidCallback? onRegister;

  /// 是否顯示 Demo 快速登入（備援）。null → 沿用 [AppConfig.showDemoLoginButton]。
  final bool? showDemoLogin;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool get _showDemoLogin =>
      widget.showDemoLogin ?? AppConfig.demoLoginVisible;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSigningIn = false;
  bool _isEmailSubmitting = false;
  bool _isGoogleSubmitting = false;

  /// Email / 密碼欄位是否已展開（點「用 Email 登入」後才出現）。
  bool _emailExpanded = false;

  bool get _isBusy => _isSigningIn || _isEmailSubmitting || _isGoogleSubmitting;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 登入成功後 MainShell 要落在首頁，而不是上次停留的分頁（route 是單例、
  /// 跨登入保留）。所以登入前先把 shell route 重置成首頁。
  void _resetShellToHome() {
    context.read<AppNavigationController>().navigateTo(AppRoute.home);
  }

  /// 點「用 Email 登入」：展開欄位，並把畫面捲到底讓欄位看得到。
  void _expandEmail() {
    if (_emailExpanded) return;
    setState(() => _emailExpanded = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _handleQuickStart() async {
    if (_isBusy) return;
    final authController = context.read<AuthController>();
    _resetShellToHome();
    setState(() => _isSigningIn = true);

    await authController.loginAsDemoUser();

    if (!mounted) return;
    setState(() => _isSigningIn = false);

    if (authController.status == AuthStatus.authenticated) {
      widget.onSignedIn?.call();
    }
    // 失敗時由 build() 的白話錯誤橫幅顯示（讀 authController.errorMessage），
    // 不另跳 snackbar，避免重複。
  }

  Future<void> _handleEmailSignIn() async {
    if (_isBusy) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty) {
      _showFriendlyMessage('請先填一下 Email 喔。');
      return;
    }
    if (password.isEmpty) {
      _showFriendlyMessage('請輸入密碼喔。');
      return;
    }

    FocusScope.of(context).unfocus();
    final authController = context.read<AuthController>();
    _resetShellToHome();
    setState(() => _isEmailSubmitting = true);

    await authController.signInWithEmail(email: email, password: password);

    if (!mounted) return;
    setState(() => _isEmailSubmitting = false);

    if (authController.status == AuthStatus.authenticated) {
      widget.onSignedIn?.call();
    }
    // 失敗時不在這裡跳 snackbar：登入過程 auth gate 會把本頁換成 loading 再換
    // 回來，這個 callback 多半已在「不再 mounted」的舊頁面上。錯誤改由 build()
    // 內的白話錯誤橫幅顯示（讀 authController.errorMessage），保證一定看得到。
  }

  Future<void> _handleGoogleSignIn() async {
    if (_isBusy) return;
    final authController = context.read<AuthController>();
    _resetShellToHome();
    setState(() => _isGoogleSubmitting = true);

    await authController.signInWithGoogle();

    if (!mounted) return;
    setState(() => _isGoogleSubmitting = false);

    if (authController.status == AuthStatus.authenticated) {
      widget.onSignedIn?.call();
    }
    // 取消（errorMessage 為 null）不打擾；其他失敗由 build() 的錯誤橫幅顯示。
  }

  /// Apple 登入尚未接上：點到時給白話提示，不 crash（按鈕僅作展示）。
  void _handleApplePending() {
    _showFriendlyMessage('Apple 登入準備中，敬請期待。');
  }

  void _showFriendlyMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontSize: 18),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 監聽 auth 狀態：登入失敗時用白話橫幅顯示錯誤（讀 errorMessage），
    // 不依賴 snackbar（會被 auth gate 換頁吃掉）。
    final auth = context.watch<AuthController>();
    final errorMessage =
        auth.status == AuthStatus.error ? auth.errorMessage : null;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AuthGradientBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const pagePadding = EdgeInsets.fromLTRB(24, 24, 24, 28);
              final minContentHeight =
                  (constraints.maxHeight - pagePadding.vertical)
                      .clamp(0.0, double.infinity);

              return SingleChildScrollView(
                controller: _scrollController,
                padding: pagePadding,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: minContentHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 8),
                        const Center(child: AuthPetHero(size: 220)),
                        const SizedBox(height: 20),
                        const Text(
                          '你的陪伴夥伴正在等你',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '登入後，牠會陪你說話、記得你的日常，也關心你的心情。',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            height: 1.5,
                            color: Colors.black.withValues(alpha: 0.6),
                          ),
                        ),
                        const Spacer(),
                        AuthProviderButton(
                          icon: Icons.g_mobiledata,
                          label: '用 Google 登入',
                          iconColor: const Color(0xFF4285F4),
                          onPressed: () => _handleGoogleSignIn(),
                        ),
                        const SizedBox(height: 14),
                        AuthProviderButton(
                          icon: Icons.apple,
                          label: '用 Apple 登入',
                          onPressed: _handleApplePending,
                        ),
                        const SizedBox(height: 14),
                        _buildEmailSection(),
                        if (errorMessage != null) ...[
                          const SizedBox(height: 16),
                          _buildErrorBanner(errorMessage),
                        ],
                        const SizedBox(height: 22),
                        _buildRegisterLink(context),
                        if (_showDemoLogin) ...[
                          const SizedBox(height: 18),
                          _buildDemoButton(context),
                        ],
                        const SizedBox(height: 16),
                        _buildLegalLinks(context),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Email 登入區：收合時是一顆「用 Email 登入」按鈕；點開後柔順展開
  /// Email / 密碼欄位與「登入」按鈕。
  Widget _buildEmailSection() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: _emailExpanded ? _buildEmailForm() : _buildEmailExpander(),
    );
  }

  Widget _buildEmailExpander() {
    return AuthProviderButton(
      icon: Icons.email_outlined,
      label: '用 Email 登入',
      trailing: Icon(
        Icons.keyboard_arrow_down_rounded,
        size: 26,
        color: Colors.black.withValues(alpha: 0.45),
      ),
      onPressed: _expandEmail,
    );
  }

  Widget _buildEmailForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AuthCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AuthTextField(
                controller: _emailController,
                label: 'Email',
                icon: Icons.email_outlined,
                enabled: !_isBusy,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),
              AuthTextField(
                controller: _passwordController,
                label: '密碼',
                icon: Icons.lock_outline,
                obscure: true,
                enabled: !_isBusy,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _handleEmailSignIn(),
              ),
              const SizedBox(height: 16),
              _buildEmailSignInButton(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmailSignInButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isBusy ? null : _handleEmailSignIn,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _isEmailSubmitting
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Colors.white,
                ),
              )
            : const Text(
                '登入',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
      ),
    );
  }

  Widget _buildDemoButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: TextButton(
        onPressed: _isSigningIn ? null : _handleQuickStart,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        child: _isSigningIn
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  SizedBox(width: 14),
                  Text(
                    '正在帶你進去…',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ],
              )
            : const Text(
                '先進去陪伴',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF5C2C0), width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFC2410C), size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 18,
                height: 1.4,
                color: Color(0xFFB91C1C),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegisterLink(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '還沒有帳號？',
          style: TextStyle(
            fontSize: 18,
            color: Colors.black.withValues(alpha: 0.6),
          ),
        ),
        TextButton(
          onPressed: widget.onRegister,
          child: const Text(
            '開始陪伴生活',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  /// 登入前可閱讀的法遵入口：在 App 內直接捲動閱讀隱私權政策與服務條款，
  /// 不依賴外部網址（URL 仍是佔位時也能安心點開）。
  Widget _buildLegalLinks(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          '登入即代表你已閱讀並同意',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            height: 1.4,
            color: Colors.black.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: () => _openPrivacyPolicy(context),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text(
                '隱私權政策',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              '與',
              style: TextStyle(
                fontSize: 16,
                color: Colors.black.withValues(alpha: 0.55),
              ),
            ),
            TextButton(
              onPressed: () => _openTermsOfService(context),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text(
                '服務條款',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _openPrivacyPolicy(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LegalDocumentScreen.privacyPolicy(),
      ),
    );
  }

  void _openTermsOfService(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LegalDocumentScreen.termsOfService(),
      ),
    );
  }
}
