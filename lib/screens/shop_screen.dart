import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/inventory_controller.dart';
import '../controllers/pet_stats_controller.dart';
import '../controllers/wallet_controller.dart';
import '../services/shop_service.dart';
import '../widgets/coin_badge.dart';
import '../widgets/shop_item_card.dart';

class ShopScreen extends StatelessWidget {
  const ShopScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletController>();
    final petStats = context.watch<PetStatsController>();
    final inventory = context.watch<InventoryController>();
    final items = context.read<ShopService>().allItems();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('寵物商城',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
            ),
            CoinBadge(coins: wallet.coins),
          ],
        ),
        const SizedBox(height: 12),
        for (final item in items)
          ShopItemCard(
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
      ],
    );
  }
}
