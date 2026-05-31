import 'package:flutter/material.dart';

/// 登入 / 註冊頁共用的大顆綁定按鈕（Google / Apple / Email）。
///
/// CR-0006 Batch 3b：純 UI，不接任何第三方 SDK。點擊行為交由 [onPressed]，
/// 由畫面顯示「即將推出」白話提示。長者友善：大字、大留白、清楚圖示。
class AuthProviderButton extends StatelessWidget {
  const AuthProviderButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 18),
          side: BorderSide(color: Colors.grey.shade300, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          foregroundColor: const Color(0xFF333333),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
