import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/auth_controller.dart';
import '../widgets/auth/auth_visuals.dart';

/// 註冊頁（CR-0006 Batch 3b UI / Batch 4b 接上 Email 註冊）。
///
/// 長者友善：大字、大按鈕、溫暖語氣。**註冊頁只做 Email 註冊**；Google / Apple
/// 綁定統一放在最前面的登入頁，這裡不重複（CR-0009 後續調整）。Email 註冊成功
/// 後不自動登入，會提示「請用 Email 登入」並返回登入頁。
///
/// 視覺重設計：沿用登入頁的暖色背景，表單收進白色圓角卡片，輸入框高度統一、
/// 圓角柔和；「建立帳號」主按鈕固定在安全區上方。登入 / 註冊邏輯一字未動。
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, this.onBackToLogin});

  /// 點「返回登入」時通知外層切回登入頁。
  final VoidCallback? onBackToLogin;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  bool _isSubmitting = false;

  bool get _isBusy => _isSubmitting;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (_isBusy) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (email.isEmpty) {
      _showFriendlyMessage('請先填一下 Email 喔。');
      return;
    }
    if (password.isEmpty) {
      _showFriendlyMessage('請設定一個密碼喔。');
      return;
    }
    if (password.length < 6) {
      _showFriendlyMessage('密碼長一點會比較安全，至少 6 個字喔。');
      return;
    }
    if (password != confirm) {
      _showFriendlyMessage('兩次輸入的密碼不一樣，再確認一下好嗎？');
      return;
    }

    FocusScope.of(context).unfocus();
    final authController = context.read<AuthController>();
    setState(() => _isSubmitting = true);

    // CR-0006 Batch 4d：註冊**不自動登入**。成功回 null、失敗回白話訊息。
    final error =
        await authController.registerAccount(email: email, password: password);

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (error == null) {
      await _showRegisteredDialog();
      if (!mounted) return;
      // 回登入頁，讓使用者用剛建立的 Email / 密碼登入（不自動進 App）。
      Navigator.of(context).maybePop();
    } else {
      _showFriendlyMessage(error);
    }
  }

  /// 註冊成功提示：「帳號建立成功，請用 Email 登入。」
  Future<void> _showRegisteredDialog() {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            '帳號建立成功',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          content: const Text(
            '請用剛剛的 Email 和密碼登入吧。',
            style: TextStyle(fontSize: 18, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                '去登入',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showFriendlyMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 18)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AuthGradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      const Text(
                        '建立你的帳號，紀錄好好保存',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '綁定一個常用的帳號，下次回來陪伴的點滴都還在。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          height: 1.5,
                          color: Colors.black.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 24),
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
                              label: '密碼（至少 6 個字）',
                              icon: Icons.lock_outline,
                              obscure: true,
                              enabled: !_isBusy,
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: 14),
                            AuthTextField(
                              controller: _confirmController,
                              label: '再輸入一次密碼',
                              icon: Icons.lock_outline,
                              obscure: true,
                              enabled: !_isBusy,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _handleRegister(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '想用 Google 或 Apple？回上一頁就能綁定。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.4,
                          color: Colors.black.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _buildBottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  /// 固定在安全區上方的底部操作列：主按鈕「建立帳號」+ 次要「返回登入」。
  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildRegisterButton(),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: _isBusy ? null : widget.onBackToLogin,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text(
                '返回登入',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegisterButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isBusy ? null : _handleRegister,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: _isSubmitting
            ? const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Colors.white,
                ),
              )
            : const Text(
                '建立帳號',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
      ),
    );
  }
}
