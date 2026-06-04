import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/cart_controller.dart';
import '../../models/cart_item.dart';
import '../../services/marketplace_service.dart';
import '../../widgets/marketplace/marketplace_ui.dart';
import '../../widgets/ui/empty_state.dart';
import 'order_success_screen.dart';

/// 購物車 + 結帳頁（CR-0032）。
///
/// 可調整數量、移除商品、看小計與總額，填寫收件人與配送備註後確認下單。
class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final cart = context.read<CartController>();
    if (cart.isEmpty || _submitting) return;
    setState(() => _submitting = true);

    final service = context.read<MarketplaceService>();
    final auth = context.read<AuthController>();
    final items = List<CartItem>.from(cart.items);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final order = await service.createOrder(
        userId: auth.currentUserId,
        elderName: _nameController.text.trim(),
        deliveryNote: _noteController.text.trim(),
        items: items,
      );
      if (!mounted) return;
      cart.clear();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => OrderSuccessScreen(order: order),
        ),
      );
    } on MarketplaceApiException catch (error) {
      if (!mounted) return;
      messenger.clearSnackBars();
      messenger.showSnackBar(SnackBar(content: Text(error.friendlyMessage)));
    } catch (_) {
      if (!mounted) return;
      messenger.clearSnackBars();
      messenger.showSnackBar(
        const SnackBar(content: Text('現在沒辦法送出訂單，待會再試一次好嗎？')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartController>();
    // 鍵盤是否開著：開著時把底部欄換成「完成」收鍵盤按鈕（長者友善）。
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      appBar: AppBar(title: const Text('購物車')),
      body: SafeArea(
        child: cart.isEmpty
            ? const EmptyState(
                icon: Icons.shopping_cart_outlined,
                message: '購物車還是空的。',
                hint: '回商城挑幾樣需要的用品吧。',
              )
            : GestureDetector(
                // 點空白處也能收鍵盤（多一個直覺的收鍵盤方式）。
                behavior: HitTestBehavior.opaque,
                onTap: () => FocusScope.of(context).unfocus(),
                child: ListView(
                  // 往下滑動也能收鍵盤。
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                  for (final item in cart.items) ...[
                    _CartItemTile(
                      key: ValueKey('cart-item-${item.product.id}'),
                      item: item,
                      onIncrease: () => cart.increment(item.product.id),
                      onDecrease: () => cart.decrement(item.product.id),
                      onRemove: () => cart.removeProduct(item.product.id),
                    ),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 8),
                  _ContactFields(
                    nameController: _nameController,
                    noteController: _noteController,
                  ),
                  ],
                ),
              ),
      ),
      bottomNavigationBar: cart.isEmpty
          ? null
          : (keyboardOpen
              ? _KeyboardDoneBar(
                  onDone: () => FocusScope.of(context).unfocus(),
                )
              : _CheckoutBar(
                  total: cart.totalAmount,
                  count: cart.totalCount,
                  submitting: _submitting,
                  onSubmit: _submit,
                )),
    );
  }
}

/// 鍵盤開啟時顯示在鍵盤上方的「完成」收鍵盤列（長者友善：大按鈕、清楚）。
class _KeyboardDoneBar extends StatelessWidget {
  const _KeyboardDoneBar({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 8,
      child: SizedBox(
        height: 52,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              onPressed: onDone,
              icon: const Icon(Icons.keyboard_hide),
              label: const Text(
                '完成',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartItemTile extends StatelessWidget {
  const _CartItemTile({
    super.key,
    required this.item,
    required this.onIncrease,
    required this.onDecrease,
    required this.onRemove,
  });

  final CartItem item;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final product = item.product;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MarketplaceProductImage(
            imageUrl: product.imageUrl,
            name: product.name,
            category: product.category,
            width: 72,
            height: 72,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '移除',
                      onPressed: onRemove,
                      icon: const Icon(Icons.delete_outline),
                      color: Colors.black45,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  formatNtDollars(product.price),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.redAccent,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _MiniStep(icon: Icons.remove, onTap: onDecrease),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Text(
                        '${item.quantity}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    _MiniStep(icon: Icons.add, onTap: onIncrease),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '小計 ${formatNtDollars(item.subtotal)}',
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.black.withValues(alpha: 0.6),
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
    );
  }
}

class _MiniStep extends StatelessWidget {
  const _MiniStep({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primary.withValues(alpha: 0.12),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, size: 20, color: scheme.primary),
        ),
      ),
    );
  }
}

class _ContactFields extends StatelessWidget {
  const _ContactFields({
    required this.nameController,
    required this.noteController,
  });

  final TextEditingController nameController;
  final TextEditingController noteController;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '聯絡資訊',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          '留下稱呼和備註，照護中心會方便和你聯絡、安排送貨。',
          style: TextStyle(
            fontSize: 14,
            color: Colors.black.withValues(alpha: 0.55),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: nameController,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: '收件人姓名（方便照護中心聯絡）',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: noteController,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: '配送備註（例如方便收貨的時間）',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
      ],
    );
  }
}

class _CheckoutBar extends StatelessWidget {
  const _CheckoutBar({
    required this.total,
    required this.count,
    required this.submitting,
    required this.onSubmit,
  });

  final int total;
  final int count;
  final bool submitting;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '共 $count 件',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.black.withValues(alpha: 0.55),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  formatNtDollars(total),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Colors.redAccent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 56,
            child: FilledButton.icon(
              onPressed: submitting ? null : onSubmit,
              icon: submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: const Text(
                '確認下單',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 22),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
