import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/cart_controller.dart';
import '../../models/marketplace_product.dart';
import '../../widgets/marketplace/marketplace_ui.dart';
import 'cart_screen.dart';

/// 商品詳情頁（CR-0032）：圖片、名稱、價格、分類、庫存、說明 + 數量選擇 + 加入購物車。
class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({super.key, required this.product});

  final MarketplaceProduct product;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  int _quantity = 1;

  MarketplaceProduct get _product => widget.product;

  void _changeQuantity(int delta) {
    setState(() {
      _quantity = (_quantity + delta).clamp(1, _product.stock <= 0 ? 1 : _product.stock);
    });
  }

  void _addToCart() {
    final cart = context.read<CartController>();
    final ok = cart.addProduct(_product, quantity: _quantity);
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('一次只能訂同一間照護中心的商品，請先結帳或清空購物車。'),
        ),
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text('已加入購物車：${_product.name}'),
        action: SnackBarAction(
          label: '去結帳',
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const CartScreen()),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final soldOut = !_product.inStock;
    return Scaffold(
      appBar: AppBar(title: const Text('商品詳情')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            MarketplaceProductImage(
              imageUrl: _product.imageUrl,
              name: _product.name,
              category: _product.category,
              height: 220,
              width: double.infinity,
              borderRadius: 22,
            ),
            const SizedBox(height: 18),
            Text(
              _product.name,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                StockBadge(stock: _product.stock),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${_product.category}・${_product.centerName}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black.withValues(alpha: 0.55),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              formatNtDollars(_product.price),
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: Colors.redAccent,
              ),
            ),
            const SizedBox(height: 18),
            if (_product.description.trim().isNotEmpty) ...[
              const Text(
                '商品說明',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                _product.description,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  color: Colors.black.withValues(alpha: 0.72),
                ),
              ),
              const SizedBox(height: 20),
            ],
            if (!soldOut) ...[
              const Text(
                '數量',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              _QuantityStepper(
                quantity: _quantity,
                onDecrease: _quantity > 1 ? () => _changeQuantity(-1) : null,
                onIncrease:
                    _quantity < _product.stock ? () => _changeQuantity(1) : null,
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: SizedBox(
          height: 56,
          child: FilledButton.icon(
            onPressed: soldOut ? null : _addToCart,
            icon: const Icon(Icons.add_shopping_cart),
            label: Text(
              soldOut ? '已售完' : '加入購物車',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({
    required this.quantity,
    required this.onDecrease,
    required this.onIncrease,
  });

  final int quantity;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StepButton(icon: Icons.remove, onTap: onDecrease),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            '$quantity',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
        ),
        _StepButton(icon: Icons.add, onTap: onIncrease),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    return Material(
      color: enabled
          ? scheme.primary.withValues(alpha: 0.12)
          : Colors.black.withValues(alpha: 0.05),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(
            icon,
            color: enabled ? scheme.primary : Colors.black26,
          ),
        ),
      ),
    );
  }
}
