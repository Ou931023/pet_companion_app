import 'package:flutter/material.dart';

class PetStatusPanel extends StatelessWidget {
  const PetStatusPanel({
    super.key,
    required this.intimacy,
    required this.fullness,
    required this.moodValue,
    required this.isDead,
  });

  final int intimacy;
  final int fullness;
  final int moodValue;
  final bool isDead;

  @override
  Widget build(BuildContext context) {
    Widget item({
      required IconData icon,
      required String label,
      required int value,
      required Color color,
    }) {
      return Expanded(
        child: _StatItem(
          icon: icon,
          label: label,
          value: value,
          color: color,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDead ? Colors.grey.shade300 : Colors.green.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDead ? Colors.grey.shade400 : Colors.green.shade100,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isDead ? Icons.bedtime : Icons.favorite,
                size: 18,
                color: isDead ? Colors.grey.shade700 : Colors.green.shade700,
              ),
              const SizedBox(width: 6),
              Text(
                isDead ? '沉睡中' : '陪伴中',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              item(
                icon: Icons.favorite,
                label: '親密',
                value: intimacy,
                color: Colors.pink.shade400,
              ),
              const SizedBox(width: 8),
              item(
                icon: Icons.restaurant,
                label: '飽足',
                value: fullness,
                color: Colors.orange.shade500,
              ),
              const SizedBox(width: 8),
              item(
                icon: Icons.mood,
                label: '心情',
                value: moodValue,
                color: Colors.green.shade600,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatefulWidget {
  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final int value;
  final Color color;

  @override
  State<_StatItem> createState() => _StatItemState();
}

class _StatItemState extends State<_StatItem> {
  int _delta = 0;
  int _pulse = 0;

  @override
  void didUpdateWidget(covariant _StatItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    final delta = widget.value - oldWidget.value;
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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.black12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(widget.icon, size: 16, color: widget.color),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(scale: animation, child: child),
                      );
                    },
                    child: Text(
                      '${widget.value}',
                      key: ValueKey<int>(widget.value),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: widget.value.clamp(0, 100) / 100,
                  minHeight: 5,
                  backgroundColor: Colors.black.withValues(alpha: 0.08),
                  valueColor: AlwaysStoppedAnimation<Color>(widget.color),
                ),
              ),
            ],
          ),
        ),
        if (_delta > 0)
          Positioned(
            top: -18,
            right: 4,
            child: _FloatingDelta(
              key: ValueKey<int>(_pulse),
              value: _delta,
              color: widget.color,
            ),
          ),
      ],
    );
  }
}

class _FloatingDelta extends StatelessWidget {
  const _FloatingDelta({
    super.key,
    required this.value,
    required this.color,
  });

  final int value;
  final Color color;

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
          color: color,
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
