import 'package:flutter/material.dart';

import '../widgets/auth/auth_provider_button.dart';

/// 註冊頁（CR-0006 Batch 3b）。
///
/// 長者友善：大字、大按鈕、溫暖語氣。三種綁定選項（Google / Apple / Email）
/// 本批只保留 UI，點擊顯示「即將推出」白話提示，不接真 SDK。透過 callback
/// 對外溝通，**不自行導航**。
class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key, this.onBackToLogin});

  /// 點「返回登入」時通知外層切回登入頁。
  final VoidCallback? onBackToLogin;

  void _showComingSoon(BuildContext context, String provider) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '$provider 綁定即將推出，現在可以先回去用「快速開始」進去陪伴。',
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
                      const SizedBox(height: 16),
                      const Text(
                        '建立你的帳號，紀錄好好保存',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '綁定一個常用的帳號，下次回來陪伴的點滴都還在。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          height: 1.4,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 36),
                      AuthProviderButton(
                        icon: Icons.g_mobiledata,
                        label: '用 Google 註冊',
                        onPressed: () => _showComingSoon(context, 'Google'),
                      ),
                      const SizedBox(height: 16),
                      AuthProviderButton(
                        icon: Icons.apple,
                        label: '用 Apple 註冊',
                        onPressed: () => _showComingSoon(context, 'Apple'),
                      ),
                      const SizedBox(height: 16),
                      AuthProviderButton(
                        icon: Icons.email_outlined,
                        label: '用 Email 註冊',
                        onPressed: () => _showComingSoon(context, 'Email'),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: onBackToLogin,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text(
                            '返回登入',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
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
}
