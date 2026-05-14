import 'package:flutter/material.dart';

class CoinBadge extends StatefulWidget {
  const CoinBadge({
    super.key,
    required this.coins,
  });

  final int coins;

  @override
  State<CoinBadge> createState() => _CoinBadgeState();
}

class _CoinBadgeState extends State<CoinBadge> {
  int _delta = 0;
  int _pulse = 0;

  @override
  void didUpdateWidget(covariant CoinBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    final delta = widget.coins - oldWidget.coins;
    if (delta > 0) {
      setState(() {
        _delta = delta;
        _pulse++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.amber.shade100,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.monetization_on, size: 18, color: Colors.orange),
              const SizedBox(width: 4),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(scale: animation, child: child),
                  );
                },
                child: Text(
                  '金幣 ${widget.coins}',
                  key: ValueKey<int>(widget.coins),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        if (_delta > 0)
          Positioned(
            top: -20,
            right: 8,
            child: _CoinDelta(
              key: ValueKey<int>(_pulse),
              value: _delta,
            ),
          ),
      ],
    );
  }
}

class _CoinDelta extends StatelessWidget {
  const _CoinDelta({
    super.key,
    required this.value,
  });

  final int value;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 950),
      curve: Curves.easeOutCubic,
      builder: (context, progress, child) {
        return Opacity(
          opacity: 1 - progress,
          child: Transform.translate(
            offset: Offset(0, -18 * progress),
            child: child,
          ),
        );
      },
      child: Text(
        '+$value',
        style: TextStyle(
          color: Colors.orange.shade700,
          fontSize: 14,
          fontWeight: FontWeight.w900,
          shadows: [
            Shadow(
              color: Colors.white.withValues(alpha: 0.9),
              blurRadius: 5,
            ),
          ],
        ),
      ),
    );
  }
}
