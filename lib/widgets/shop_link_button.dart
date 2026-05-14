import 'package:flutter/material.dart';

class ShopLinkButton extends StatelessWidget {
  const ShopLinkButton({
    super.key,
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.open_in_new),
        label: const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
            '前往長照商城',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
