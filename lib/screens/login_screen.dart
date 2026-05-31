import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/auth_controller.dart';
import '../widgets/auth/auth_provider_button.dart';

/// 登入頁（CR-0006 Batch 3b）。
///
/// 長者友善：大字、大按鈕、溫暖語氣。透過 callback 對外溝通，**不自行導航**
/// 到 MainShell（auth gate 接線是 Batch 3c）。第三方綁定（Google / Apple /
/// Email）本批只保留 UI，點擊顯示「即將推出」白話提示，不接真 SDK。
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.onSignedIn, this.onRegister});

  /// 登入成功（state=authenticated）後通知外層。
  final VoidCallback? onSignedIn;

  /// 點「還沒有帳號？註冊」時通知外層切到註冊頁。
  final VoidCallback? onRegister;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
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

  Future<void> _handleQuickStart() async {
    if (_isBusy) return;
    final authController = context.read<AuthController>();
    setState(() => _isSigningIn = true);

    await authController.loginAsDemoUser();

    if (!mounted) return;
    setState(() => _isSigningIn = false);

    if (authController.status == AuthStatus.authenticated) {
      widget.onSignedIn?.call();
    } else {
      _showFriendlyMessage('現在連線不太順，待會再試一次好嗎？');
    }
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
    setState(() => _isEmailSubmitting = true);

    await authController.signInWithEmail(email: email, password: password);

    if (!mounted) return;
    setState(() => _isEmailSubmitting = false);

    if (authController.status == AuthStatus.authenticated) {
      widget.onSignedIn?.call();
    } else {
      _showFriendlyMessage(
        authController.errorMessage ?? '現在連線不太順，待會再試一次好嗎？',
      );
    }
  }

  Future<void> _handleGoogleSignIn() async {
    if (_isBusy) return;
    final authController = context.read<AuthController>();
    setState(() => _isGoogleSubmitting = true);

    await authController.signInWithGoogle();

    if (!mounted) return;
    setState(() => _isGoogleSubmitting = false);

    if (authController.status == AuthStatus.authenticated) {
      widget.onSignedIn?.call();
    } else if (authController.errorMessage != null) {
      // 使用者取消時 errorMessage 為 null → 不打擾；其他失敗才顯示白話。
      _showFriendlyMessage(authController.errorMessage!);
    }
  }

  void _showComingSoon(String provider) {
    _showFriendlyMessage('$provider 綁定即將推出，現在先用「先進去陪伴」進去吧。');
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
                        '點一下就能開始，和你的陪伴寵物說說話。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          height: 1.4,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const Spacer(),
                      _buildPrimaryButton(context),
                      const SizedBox(height: 24),
                      _buildDivider('或用 Email 登入'),
                      const SizedBox(height: 20),
                      _buildEmailField(),
                      const SizedBox(height: 14),
                      _buildPasswordField(),
                      const SizedBox(height: 16),
                      _buildEmailSignInButton(),
                      const SizedBox(height: 24),
                      _buildDivider('或綁定其他帳號'),
                      const SizedBox(height: 20),
                      AuthProviderButton(
                        icon: Icons.g_mobiledata,
                        label: '用 Google 綁定',
                        onPressed: () => _handleGoogleSignIn(),
                      ),
                      const SizedBox(height: 14),
                      AuthProviderButton(
                        icon: Icons.apple,
                        label: '用 Apple 綁定',
                        onPressed: () => _showComingSoon('Apple'),
                      ),
                      const SizedBox(height: 28),
                      _buildRegisterLink(context),
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
            '註冊',
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
