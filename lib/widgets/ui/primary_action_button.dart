import 'package:flutter/material.dart';

/// 全 App 的主要行動按鈕（CTA）。
///
/// 設計成「一眼就知道是主功能」：大尺寸、圓潤、主色漸層、icon + 白話文字。
/// 主要用在首頁的語音對話按鈕，也可重用在其他需要醒目主操作的地方。
/// [onPressed] 為 null 時自動轉為柔和的停用樣式。
class PrimaryActionButton extends StatelessWidget {
  const PrimaryActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.height = 74,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final double height;

  /// 是否處於「進行中」狀態（例如正在聆聽 / 說話），會帶一圈柔光強調。
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    final radius = BorderRadius.circular(height / 2);

    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: enabled
          ? [
              Color.lerp(scheme.primary, Colors.white, 0.12)!,
              scheme.primary,
            ]
          : [
              Colors.grey.shade300,
              Colors.grey.shade400,
            ],
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: gradient,
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color:
                        scheme.primary.withValues(alpha: active ? 0.42 : 0.3),
                    blurRadius: active ? 24 : 16,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onPressed,
            borderRadius: radius,
            child: SizedBox(
              height: height,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 32, color: Colors.white),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
