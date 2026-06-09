import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../controllers/inventory_controller.dart';
import '../controllers/pet_stats_controller.dart';
import '../controllers/wallet_controller.dart';
import '../routes/app_routes.dart';
import '../services/shop_service.dart';
import '../widgets/coin_badge.dart';
import '../widgets/shop_item_card.dart';
import '../widgets/ui/section_card.dart';

class ShopScreen extends StatelessWidget {
  const ShopScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletController>();
    final petStats = context.watch<PetStatsController>();
    final inventory = context.watch<InventoryController>();
    final items = context.read<ShopService>().allItems();

    return SafeArea(
      bottom: false,
      child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        _ShopHeader(coins: wallet.coins),
        const SizedBox(height: 16),
        // CR-0056（A2）：marketplace 入口正式版完全隱藏（能力/路由保留）。
        if (AppConfig.marketplaceVisible) ...[
          _LongTermCareShopCard(
            onTap: () => Navigator.of(context).pushNamed(AppRoute.marketplace),
          ),
          const SizedBox(height: 22),
        ],
        Text(
          '寵物用品',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          '餵牠吃點東西、陪牠玩，親密和心情都會變好。',
          style: TextStyle(
            color: Colors.black.withValues(alpha: 0.55),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        for (final item in items) ...[
          ShopItemCard(
            key: ValueKey('shop-item-${item.id}'),
            item: item,
            canBuy: wallet.coins >= item.price &&
                (!item.onlyWhenDead || petStats.isDead),
            onBuy: () async {
              final ok = await wallet.spendCoins(item.price);
              if (!ok || !context.mounted) return;
              await inventory.addFromShop(item);

              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('已放入背包：${item.name}')),
              );
            },
          ),
          const SizedBox(height: 10),
        ],
      ],
      ),
    );
  }

}

class _ShopHeader extends StatelessWidget {
  const _ShopHeader({required this.coins});

  final int coins;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '寵物商城',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                '挑些吃的、玩的和照護用品，讓寵物過得更舒服。',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.58),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        CoinBadge(coins: coins),
      ],
    );
  }
}

class _LongTermCareShopCard extends StatelessWidget {
  const _LongTermCareShopCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SectionCard(
      onTap: onTap,
      color: scheme.primary.withValues(alpha: 0.06),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.storefront,
              color: scheme.primary,
              size: 30,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '照護用品商城',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '挑選需要的用品，我們會協助通知照護中心處理訂單。',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.black.withValues(alpha: 0.62),
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right, color: scheme.primary),
        ],
      ),
    );
  }
}
