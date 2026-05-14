import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/inventory_controller.dart';
import '../widgets/inventory_item_card.dart';

class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryController>();
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('背包',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('長按並拖曳道具到寵物身上即可使用', style: TextStyle(fontSize: 14)),
          const SizedBox(height: 10),
          if (inventory.items.isEmpty) const Text('背包目前是空的'),
          for (final item in inventory.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InventoryItemCard(item: item, draggable: true),
            ),
        ],
      ),
    );
  }
}
