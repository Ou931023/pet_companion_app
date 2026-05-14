import 'package:flutter/material.dart';

class HomeDateCheckinCard extends StatelessWidget {
  const HomeDateCheckinCard({
    super.key,
    required this.hasCheckedInToday,
    required this.onOpenCalendarTap,
  });

  final bool hasCheckedInToday;
  final VoidCallback onOpenCalendarTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          onPressed: onOpenCalendarTap,
          icon: const Icon(Icons.calendar_month),
          tooltip: '簽到月曆',
        ),
        if (!hasCheckedInToday)
          Positioned(
            right: 4,
            top: 4,
            child: Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }
}
