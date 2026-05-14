import 'package:flutter/material.dart';

import '../models/shop_item.dart';

class ShopItemCard extends StatelessWidget {
  const ShopItemCard({
    super.key,
    required this.item,
    required this.canBuy,
    required this.onBuy,
  });

  final ShopItem item;
  final bool canBuy;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final effects = <String>[
      if (item.fullnessDelta > 0) '飽足 +${item.fullnessDelta}',
      if (item.moodDelta > 0) '心情 +${item.moodDelta}',
      if (item.intimacyDelta > 0) '親密 +${item.intimacyDelta}',
      if (item.isRevive) '復活',
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Text(item.emoji, style: const TextStyle(fontSize: 34)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text('${item.price} 金幣',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  if (effects.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      effects.join('・'),
                      style:
                          const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ],
              ),
            ),
            FilledButton(
              onPressed: canBuy ? onBuy : null,
              child: const Text('購買'),
            ),
          ],
        ),
      ),
    );
  }
}
