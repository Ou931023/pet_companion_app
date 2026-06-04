import 'package:flutter/material.dart';

/// 千分位金額顯示，如「NT$ 2,500」（CR-0032）。
String formatNtDollars(int amount) {
  final digits = amount.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return 'NT\$ ${amount < 0 ? '-' : ''}$buffer';
}

/// 分類 → 底色 + 圖示。用來畫「沒有真實照片時」的乾淨色卡 placeholder。
class _CategoryStyle {
  const _CategoryStyle(this.color, this.icon);
  final Color color;
  final IconData icon;
}

const Map<String, _CategoryStyle> _kCategoryStyles = {
  '照護用品': _CategoryStyle(Color(0xFF4C8BF5), Icons.health_and_safety),
  '復健輔具': _CategoryStyle(Color(0xFF22A06B), Icons.accessible),
  '營養補充': _CategoryStyle(Color(0xFFF59E0B), Icons.local_drink),
  '清潔衛生': _CategoryStyle(Color(0xFF14B8A6), Icons.sanitizer),
  '日常生活': _CategoryStyle(Color(0xFF8B5CF6), Icons.home_rounded),
  '其他': _CategoryStyle(Color(0xFFEF4444), Icons.medical_services),
};

/// 商品圖片。
///
/// - 有真實照片 URL（[imageUrl]）→ 顯示網路圖；載入失敗時退回色卡 placeholder。
/// - 沒有照片 → 由 App 自己畫「分類色卡 + 圖示 + 中文品名」placeholder。
///   （不依賴外部圖床、中文一定正常顯示、絕不破圖。）
class MarketplaceProductImage extends StatelessWidget {
  const MarketplaceProductImage({
    super.key,
    required this.imageUrl,
    this.name = '',
    this.category = '',
    this.height,
    this.width,
    this.borderRadius = 16,
  });

  final String imageUrl;
  final String name;
  final String category;
  final double? height;
  final double? width;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final placeholder = _CategoryPlaceholder(
      name: name,
      category: category,
      height: height,
      width: width,
    );

    final child = (imageUrl.trim().isEmpty)
        ? placeholder
        : Image.network(
            imageUrl,
            height: height,
            width: width,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => placeholder,
            loadingBuilder: (context, widget, progress) {
              if (progress == null) return widget;
              return Container(
                height: height,
                width: width,
                color: Colors.black.withValues(alpha: 0.04),
                alignment: Alignment.center,
                child: const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              );
            },
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: child,
    );
  }
}

/// 沒有真實照片時，App 自己畫的「分類色卡 + 圖示 + 品名」。
class _CategoryPlaceholder extends StatelessWidget {
  const _CategoryPlaceholder({
    required this.name,
    required this.category,
    required this.height,
    required this.width,
  });

  final String name;
  final String category;
  final double? height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final style = _kCategoryStyles[category] ??
        const _CategoryStyle(Color(0xFF4C8BF5), Icons.shopping_bag);

    return LayoutBuilder(
      builder: (context, constraints) {
        // 取得實際可用大小（width/height 可能為 null 或 infinity）。
        final w = width ?? (constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 96.0);
        final h = height ?? (constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 96.0);
        final shortest = w < h ? w : h;
        final iconSize = (shortest * 0.34).clamp(22.0, 64.0);
        final showName = name.trim().isNotEmpty && h >= 70;
        final nameSize = (shortest * 0.11).clamp(11.0, 18.0);

        return Container(
          height: height,
          width: width,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                style.color,
                Color.alphaBlend(Colors.black.withValues(alpha: 0.16), style.color),
              ],
            ),
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                style.icon,
                size: iconSize.toDouble(),
                color: Colors.white.withValues(alpha: 0.95),
              ),
              if (showName) ...[
                SizedBox(height: shortest * 0.06),
                Text(
                  name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: nameSize.toDouble(),
                    height: 1.2,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// 庫存狀態小標籤（有貨 / 庫存不多 / 缺貨）。
class StockBadge extends StatelessWidget {
  const StockBadge({super.key, required this.stock});

  final int stock;

  @override
  Widget build(BuildContext context) {
    late final Color color;
    late final String label;
    if (stock <= 0) {
      color = Colors.grey;
      label = '已售完';
    } else if (stock <= 3) {
      color = Colors.orange.shade700;
      label = '庫存不多';
    } else {
      color = Colors.green.shade700;
      label = '有現貨';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      ),
    );
  }
}
