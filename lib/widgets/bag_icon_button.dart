import 'package:flutter/material.dart';

class BagIconButton extends StatelessWidget {
  const BagIconButton({
    super.key,
    required this.totalItems,
    required this.onTap,
  });

  final int totalItems;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          onPressed: onTap,
          icon: const Icon(Icons.backpack),
          tooltip: '背包',
        ),
        if (totalItems > 0)
          Positioned(
            right: 2,
            top: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$totalItems',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),
      ],
    );
  }
}
