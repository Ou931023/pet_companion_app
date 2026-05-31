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
  bool _isSigningIn = false;

  Future<void> _handleQuickStart() async {
    if (_isSigningIn) return;
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

  void _showComingSoon(String provider) {
    _showFriendlyMessage('$provider 綁定即將推出，現在先用「快速開始」進去陪伴吧。');
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
                      _buildDivider(),
                      const SizedBox(height: 24),
                      AuthProviderButton(
                        icon: Icons.g_mobiledata,
                        label: '用 Google 綁定',
                        onPressed: () => _showComingSoon('Google'),
                      ),
                      const SizedBox(height: 14),
                      AuthProviderButton(
                        icon: Icons.apple,
                        label: '用 Apple 綁定',
                        onPressed: () => _showComingSoon('Apple'),
                      ),
                      const SizedBox(height: 14),
                      AuthProviderButton(
                        icon: Icons.email_outlined,
                        label: '用 Email 綁定',
                        onPressed: () => _showComingSoon('Email'),
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

  Widget _buildDivider() {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.grey.shade300, thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            '或綁定帳號保存紀錄',
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
