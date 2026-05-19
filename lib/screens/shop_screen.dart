import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controllers/inventory_controller.dart';
import '../controllers/pet_stats_controller.dart';
import '../controllers/wallet_controller.dart';
import '../services/shop_service.dart';
import '../widgets/coin_badge.dart';
import '../widgets/shop_item_card.dart';

class ShopScreen extends StatelessWidget {
  const ShopScreen({super.key});

  static final Uri _longTermCareShopUrl = Uri.parse(
    'https://www.wellcare.com.tw/',
  );

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletController>();
    final petStats = context.watch<PetStatsController>();
    final inventory = context.watch<InventoryController>();
    final items = context.read<ShopService>().allItems();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ShopHeader(coins: wallet.coins),
        const SizedBox(height: 14),
        _LongTermCareShopCard(
          onTap: () => _confirmOpenLongTermCareShop(context),
        ),
        const SizedBox(height: 18),
        Text(
          '寵物用品',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 720 ? 3 : 2;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: columns == 2 ? 0.72 : 0.86,
              ),
              itemBuilder: (context, index) {
                final item = items[index];
                return ShopItemCard(
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
                );
              },
            );
          },
        ),
      ],
    );
  }

  Future<void> _confirmOpenLongTermCareShop(BuildContext context) async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('開啟外部長照商城？'),
        content: const Text(
          '接下來會離開 App，並透過外部網路開啟長照用品商城。請確認你同意連接外部網站後再繼續。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('先不要'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.open_in_new),
            label: const Text('同意並前往'),
          ),
        ],
      ),
    );
    if (agreed != true || !context.mounted) return;

    final opened = await launchUrl(
      _longTermCareShopUrl,
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('目前無法開啟外部長照商城，請稍後再試。')),
      );
    }
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
    return Material(
      color: Colors.indigo.shade50,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.health_and_safety,
                  color: Colors.indigo.shade700,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '外部長照用品商城',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '查看照護用品、醫療耗材與生活輔具。開啟前會先徵求同意。',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.black.withValues(alpha: 0.62),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: Colors.indigo.shade700),
            ],
          ),
        ),
      ),
    );
  }
}
