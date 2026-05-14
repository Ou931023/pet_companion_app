import 'package:flutter/material.dart';

class QuickActionPanel extends StatelessWidget {
  const QuickActionPanel({
    super.key,
    required this.onAction,
  });

  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    const actions = [
      '幫我簽到',
      '我喝水了',
      '我吃飯了',
      '我心情不好',
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: actions
          .map(
            (label) => ElevatedButton(
              onPressed: () => onAction(label),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Text(
                  label,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}
