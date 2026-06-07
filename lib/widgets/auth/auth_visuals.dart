import 'package:flutter/material.dart';

import '../../utils/asset_paths.dart';

/// 登入 / 註冊 / 首次設定流程共用的暖色品牌視覺元件。
///
/// 目標：讓三個入口畫面有一致、溫暖、柔和的第一印象，而不是冷冰冰的表單。
/// 這裡只負責「外觀」，不含任何登入 / 註冊 / 寵物邏輯。

/// 共用暖色漸層背景：上方暖奶油、下方柔紫，營造療癒的陪伴氛圍。
class AuthGradientBackground extends StatelessWidget {
  const AuthGradientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFF4EC), // 暖奶油
            Color(0xFFF6F1FB), // 柔紫
          ],
        ),
      ),
      child: child,
    );
  }
}

/// 登入頁主視覺：把寵物放大成「主角」，外圈加一圈柔和光暈，
/// 而不是縮成像 icon 的小圖。
class AuthPetHero extends StatelessWidget {
  const AuthPetHero({
    super.key,
    this.imagePath = AssetPaths.defaultRestImage,
    this.size = 220,
  });

  final String imagePath;
  final double size;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 柔和光暈：讓寵物像被溫暖的光包著。
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  primary.withValues(alpha: 0.16),
                  primary.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(size * 0.10),
            child: Image.asset(
              imagePath,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Icon(
                Icons.pets,
                size: size * 0.4,
                color: primary.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 共用白色圓角卡片：用於註冊 / 設定流程的表單區，讓輸入區從暖色背景上浮起。
class AuthCard extends StatelessWidget {
  const AuthCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// 共用輸入框：高度統一、圓角柔和、底色淡，視覺比系統預設表單更柔。
class AuthTextField extends StatelessWidget {
  const AuthTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.icon,
    this.obscure = false,
    this.enabled = true,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData? icon;
  final bool obscure;
  final bool enabled;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return TextField(
      controller: controller,
      enabled: enabled,
      obscureText: obscure,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      autocorrect: false,
      style: const TextStyle(fontSize: 20),
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(fontSize: 18),
        hintStyle: TextStyle(
          fontSize: 18,
          color: Colors.black.withValues(alpha: 0.35),
        ),
        prefixIcon: icon == null ? null : Icon(icon, size: 26),
        filled: true,
        fillColor: const Color(0xFFF7F5FB),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: primary, width: 1.8),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}
