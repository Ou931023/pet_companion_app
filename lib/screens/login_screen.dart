import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../controllers/app_navigation_controller.dart';
import '../controllers/auth_controller.dart';
import '../routes/app_routes.dart';
import '../widgets/auth/auth_provider_button.dart';

/// 登入頁。
///
/// 長者友善：大字、大按鈕、溫暖語氣。正式展示主視覺為 **Google 登入 / Email
/// 登入 / 建立帳號**；Demo 快速登入預設隱藏（正式截圖不露測試感按鈕），由
/// `AppConfig.showDemoLoginButton`（或建構參數 [showDemoLogin]）控制，開發時可開啟。
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.onSignedIn,
    this.onRegister,
    this.showDemoLogin,
  });

  /// 登入成功（state=authenticated）後通知外層。
  final VoidCallback? onSignedIn;

  /// 點「還沒有帳號？建立帳號」時通知外層切到註冊頁。
  final VoidCallback? onRegister;

  /// 是否顯示 Demo 快速登入（備援）。null → 沿用 [AppConfig.showDemoLoginButton]。
  final bool? showDemoLogin;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool get _showDemoLogin =>
      widget.showDemoLogin ?? AppConfig.showDemoLoginButton;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isSigningIn = false;
  bool _isEmailSubmitting = false;
  bool _isGoogleSubmitting = false;

  bool get _isBusy => _isSigningIn || _isEmailSubmitting || _isGoogleSubmitting;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// 登入成功後 MainShell 要落在首頁，而不是上次停留的分頁（route 是單例、
  /// 跨登入保留）。所以登入前先把 shell route 重置成首頁。
  void _resetShellToHome() {
    context.read<AppNavigationController>().navigateTo(AppRoute.home);
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
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            const pagePadding = EdgeInsets.fromLTRB(24, 24, 24, 24);
            final minContentHeight =
                (constraints.maxHeight - pagePadding.vertical)
                    .clamp(0.0, double.infinity);

            return SingleChildScrollView(
              padding: pagePadding,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: minContentHeight),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 12),
                      Center(
                        child: Image.asset(
                          'assets/pets/rest/dog_rest_01.png',
                          width: 180,
                          height: 180,
                          errorBuilder: (_, __, ___) => Container(
                            width: 180,
                            height: 180,
                            alignment: Alignment.center,
                            color: Colors.grey.shade200,
                            child: const Icon(
                              Icons.pets,
                              size: 80,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        '歡迎回來，陪伴一直都在',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '用你的帳號登入，繼續陪伴的點滴。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          height: 1.4,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const Spacer(),
                      AuthProviderButton(
                        icon: Icons.g_mobiledata,
                        label: '用 Google 登入',
                        onPressed: () => _handleGoogleSignIn(),
                      ),
                      const SizedBox(height: 14),
                      AuthProviderButton(
                        icon: Icons.apple,
                        label: '用 Apple 登入',
                        onPressed: _handleApplePending,
                      ),
                      const SizedBox(height: 24),
                      _buildDivider('或用 Email 登入'),
                      const SizedBox(height: 20),
                      _buildEmailField(),
                      const SizedBox(height: 14),
                      _buildPasswordField(),
                      const SizedBox(height: 16),
                      _buildEmailSignInButton(),
                      if (errorMessage != null) ...[
                        const SizedBox(height: 16),
                        _buildErrorBanner(errorMessage),
                      ],
                      const SizedBox(height: 24),
                      _buildRegisterLink(context),
                      if (_showDemoLogin) ...[
                        const SizedBox(height: 24),
                        _buildPrimaryButton(context),
                      ],
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPrimaryButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isSigningIn ? null : _handleQuickStart,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _isSigningIn
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 16),
                  Text(
                    '正在帶你進去…',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              )
            : const Text(
                '先進去陪伴',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
      ),
    );
  }

  Widget _buildDivider(String label) {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.grey.shade300, thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade600,
            ),
          ),
        ),
        Expanded(child: Divider(color: Colors.grey.shade300, thickness: 1)),
      ],
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

  Widget _buildEmailField() {
    return TextField(
      controller: _emailController,
      enabled: !_isBusy,
      keyboardType: TextInputType.emailAddress,
      autocorrect: false,
      style: const TextStyle(fontSize: 20),
      decoration: InputDecoration(
        labelText: 'Email',
        labelStyle: const TextStyle(fontSize: 18),
        prefixIcon: const Icon(Icons.email_outlined, size: 26),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }

  Widget _buildPasswordField() {
    return TextField(
      controller: _passwordController,
      enabled: !_isBusy,
      obscureText: true,
      style: const TextStyle(fontSize: 20),
      onSubmitted: (_) => _handleEmailSignIn(),
      decoration: InputDecoration(
        labelText: '密碼',
        labelStyle: const TextStyle(fontSize: 18),
        prefixIcon: const Icon(Icons.lock_outline, size: 26),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }

  Widget _buildEmailSignInButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: _isBusy ? null : _handleEmailSignIn,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          side: BorderSide(color: Colors.grey.shade400, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: _isEmailSubmitting
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 3),
              )
            : const Text(
                '用 Email 登入',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
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
            fontSize: 20,
            color: Colors.grey.shade700,
          ),
        ),
        TextButton(
          onPressed: widget.onRegister,
          child: const Text(
            '建立帳號',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
