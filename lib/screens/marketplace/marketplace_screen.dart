import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/cart_controller.dart';
import '../../controllers/marketplace_controller.dart';
import '../../models/marketplace_product.dart';
import '../../widgets/marketplace/marketplace_ui.dart';
import '../../widgets/ui/empty_state.dart';
import 'cart_screen.dart';
import 'product_detail_screen.dart';

/// 長者端內建長照商城（CR-0032）。
///
/// 取代原本只連外部維康網站的做法：在 App 內顯示平台上架的照護 / 復健 / 生活
/// 輔助商品，可加入購物車並下單。文案口語、白話，錯誤訊息不工程化。
class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<MarketplaceController>().loadProducts();
    });
  }

  void _openCart() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const CartScreen()),
    );
  }

  void _openDetail(MarketplaceProduct product) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProductDetailScreen(product: product),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MarketplaceController>();
    final cart = context.watch<CartController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('照護用品商城'),
        actions: [
          _CartButton(count: cart.totalCount, onTap: _openCart),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => controller.loadProducts(),
          child: _buildBody(context, controller),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, MarketplaceController controller) {
    if (controller.isLoading && controller.products.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (controller.errorMessage != null && controller.products.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          EmptyState(
            icon: Icons.wifi_off_rounded,
            message: controller.errorMessage!,
            hint: '往下拉可以重新整理。',
          ),
          const SizedBox(height: 16),
          Center(
            child: FilledButton.icon(
              onPressed: () => controller.loadProducts(),
              icon: const Icon(Icons.refresh),
              label: const Text('重新整理'),
            ),
          ),
        ],
      );
    }

    final categories = controller.availableCategories;
    final products = controller.products;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text(
          '挑選需要的用品，我們會協助通知照護中心處理訂單。',
          style: TextStyle(
            fontSize: 16,
            height: 1.4,
            color: Colors.black.withValues(alpha: 0.6),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 14),
        if (categories.isNotEmpty)
          _CategoryFilter(
            categories: categories,
            selected: controller.category,
            onSelected: controller.selectCategory,
          ),
        if (categories.isNotEmpty) const SizedBox(height: 12),
        if (products.isEmpty)
          const EmptyState(
            icon: Icons.inventory_2_outlined,
            message: '這個分類目前還沒有商品。',
            hint: '換個分類看看，或往下拉重新整理。',
          )
        else
          for (final product in products) ...[
            _ProductCard(
              key: ValueKey('market-product-${product.id}'),
              product: product,
              onTap: () => _openDetail(product),
              onAdd: () => _addToCart(context, product),
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }

  void _addToCart(BuildContext context, MarketplaceProduct product) {
    final cart = context.read<CartController>();
    final ok = cart.addProduct(product);
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    if (ok) {
      messenger.showSnackBar(
        SnackBar(content: Text('已加入購物車：${product.name}')),
      );
    } else if (!product.inStock) {
      messenger.showSnackBar(
        const SnackBar(content: Text('這個商品剛好售完了，先看看其他用品吧。')),
      );
    } else {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('一次只能訂同一間照護中心的商品，請先結帳或清空購物車。'),
        ),
      );
    }
  }
}

class _CartButton extends StatelessWidget {
  const _CartButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            tooltip: '購物車',
            iconSize: 28,
            onPressed: onTap,
            icon: const Icon(Icons.shopping_cart_outlined),
          ),
          if (count > 0)
            Positioned(
              right: 2,
              top: 2,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: const BoxDecoration(
                  color: Colors.redAccent,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                alignment: Alignment.center,
                child: Text(
                  '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CategoryFilter extends StatelessWidget {
  const _CategoryFilter({
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  final List<String> categories;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final all = ['', ...categories];
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: all.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final value = all[index];
          final label = value.isEmpty ? '全部' : value;
          final isSelected = value == selected;
          return ChoiceChip(
            label: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            selected: isSelected,
            onSelected: (_) => onSelected(value),
          );
        },
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    super.key,
    required this.product,
    required this.onTap,
    required this.onAdd,
  });

  final MarketplaceProduct product;
  final VoidCallback onTap;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final soldOut = !product.inStock;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
            color: Colors.white,
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MarketplaceProductImage(
                imageUrl: product.imageUrl,
                name: product.name,
                category: product.category,
                width: 96,
                height: 96,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${product.category}・${product.centerName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.black.withValues(alpha: 0.5),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        StockBadge(stock: product.stock),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            formatNtDollars(product.price),
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              color: Colors.redAccent,
                            ),
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: soldOut ? null : onAdd,
                          icon: const Icon(Icons.add_shopping_cart, size: 18),
                          label: const Text('加入'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
