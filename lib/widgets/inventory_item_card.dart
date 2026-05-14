import 'package:flutter/material.dart';

import '../models/inventory_item.dart';

class InventoryItemCard extends StatelessWidget {
  const InventoryItemCard({
    super.key,
    required this.item,
    this.draggable = false,
    this.onDragStarted,
    this.onDragEnded,
  });

  final InventoryItem item;
  final bool draggable;
  final VoidCallback? onDragStarted;
  final VoidCallback? onDragEnded;

  @override
  Widget build(BuildContext context) {
    final child = Semantics(
      label: '${item.name}，剩下 ${item.quantity} 個',
      child: Container(
        width: 72,
        height: 72,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black12),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Center(
              child: Text(item.emoji, style: const TextStyle(fontSize: 38)),
            ),
            Positioned(
              right: -4,
              bottom: -4,
              child: Container(
                height: 26,
                constraints: const BoxConstraints(minWidth: 26),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF333333),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Text(
                  'x${item.quantity}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (!draggable) return child;
    return Draggable<InventoryItem>(
      data: item,
      onDragStarted: onDragStarted,
      onDragCompleted: onDragEnded,
      onDraggableCanceled: (_, __) => onDragEnded?.call(),
      onDragEnd: (_) => onDragEnded?.call(),
      rootOverlay: true,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          width: 86,
          height: 86,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.green, width: 3),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 16,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Text(item.emoji, style: const TextStyle(fontSize: 46)),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: child),
      child: child,
    );
  }
}
