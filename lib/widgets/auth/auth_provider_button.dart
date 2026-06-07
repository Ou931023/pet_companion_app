import 'package:flutter/material.dart';

/// 登入 / 註冊頁共用的大顆綁定按鈕（Google / Apple / Email）。
///
/// CR-0006 Batch 3b：純 UI，不接任何第三方 SDK。點擊行為交由 [onPressed]。
/// 長者友善：大字、大留白、清楚圖示、按鈕高度一致。
///
/// 視覺重設計：白底柔邊、柔和陰影，icon 與文字置中，讓三顆按鈕排在一起時
/// 乾淨一致，而不是粗糙地全部攤開。
class AuthProviderButton extends StatelessWidget {
  const AuthProviderButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.iconColor,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  /// 圖示顏色（例如 Google 用品牌色點綴）。null → 沿用文字色。
  final Color? iconColor;

  /// 尾端附加元件（例如展開箭頭）。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onPressed,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.black.withValues(alpha: 0.08),
                width: 1.4,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.035),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 28,
                  color: iconColor ?? const Color(0xFF333333),
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF333333),
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
