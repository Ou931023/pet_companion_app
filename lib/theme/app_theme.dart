import 'package:flutter/material.dart';

/// 全 App 共用的色彩語彙。
///
/// 保留紫藍色作為主色，但整體調得更溫暖、更柔和：主色改用偏紫的柔和紫藍，
/// 背景採用很淡的紫灰暖底（不全白），讓畫面看起來乾淨、療癒、有陪伴感。
class AppColors {
  const AppColors._();

  /// 主色：柔和紫藍（比原本的靛藍多一點暖紫感）。
  static const Color seed = Color(0xFF6D5DD3);

  /// 全域背景：很淡的紫灰暖底（避免全白的工程感）。
  static const Color background = Color(0xFFF5F3FB);

  /// 卡片 / 區塊表面色。
  static const Color surface = Colors.white;

  /// 溫暖點綴色（用於需要一點暖意的小裝飾）。
  static const Color warmAccent = Color(0xFFF4A8B0);

  /// 次要文字色（白話、柔和，不死黑）。
  static Color subtitle = Colors.black.withValues(alpha: 0.58);
}

/// App 的淺色主題組裝點。集中設定色票、背景與底部導覽列外觀，
/// 讓各畫面只要套用共用元件即可維持一致的視覺風格。
class AppTheme {
  const AppTheme._();

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.seed,
      brightness: Brightness.light,
    ).copyWith(
      surface: AppColors.surface,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
    );

    return base.copyWith(
      // 底部導覽列：白底、柔和陰影、選取膠囊收斂（不要太大太厚）。
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        elevation: 3,
        height: 66,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorColor: scheme.primary.withValues(alpha: 0.14),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? scheme.primary : Colors.black54,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 26,
            color: selected ? scheme.primary : Colors.black54,
          );
        }),
      ),
    );
  }
}
