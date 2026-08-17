import 'package:flutter/material.dart';

import '../models/daily_care_task.dart';

/// 長者端「今日任務」卡片。大字、大按鈕、狀態清楚（長者友善）。
class DailyCareTaskCard extends StatelessWidget {
  const DailyCareTaskCard({
    super.key,
    required this.task,
    required this.isSubmitting,
    required this.onComplete,
    this.isHighlighted = false,
  });

  final DailyCareTask task;
  final bool isSubmitting;
  final VoidCallback onComplete;
  final bool isHighlighted;

  IconData get _typeIcon {
    switch (task.type) {
      case DailyCareTaskType.medication:
        return Icons.medication_outlined;
      case DailyCareTaskType.hydration:
        return Icons.local_drink_outlined;
      case DailyCareTaskType.exercise:
        return Icons.directions_walk_outlined;
    }
  }

  Color _statusColor(BuildContext context) {
    switch (task.status) {
      case DailyCareTaskStatus.completed:
        return const Color(0xFF15803D); // 綠
      case DailyCareTaskStatus.needsReview:
      case DailyCareTaskStatus.submitted:
        return const Color(0xFFB45309); // 琥珀
      case DailyCareTaskStatus.rejected:
        return const Color(0xFFB91C1C); // 紅
      case DailyCareTaskStatus.missed:
        return const Color(0xFF6B7280); // 灰
      case DailyCareTaskStatus.pending:
        return const Color(0xFF1D4ED8); // 藍
    }
  }

  bool get _isDone => task.status == DailyCareTaskStatus.completed;

  String get _actionLabel {
    switch (task.status) {
      case DailyCareTaskStatus.needsReview:
      case DailyCareTaskStatus.rejected:
        return '重新拍照';
      default:
        return '拍照完成';
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: isHighlighted
            ? const BorderSide(color: Color(0xFF2563EB), width: 3)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: statusColor.withValues(alpha: 0.12),
                  child: Icon(_typeIcon, size: 30, color: statusColor),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title.isEmpty ? task.typeLabel : task.title,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        task.scheduledTime.isEmpty
                            ? task.typeLabel
                            : '${task.typeLabel}・預定 ${task.scheduledTime}',
                        style: const TextStyle(
                            fontSize: 16, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                _StatusChip(label: task.statusLabel, color: statusColor),
                _buildAction(context),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAction(BuildContext context) {
    if (isSubmitting) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          SizedBox(width: 8),
          Text('確認中…', style: TextStyle(fontSize: 16)),
        ],
      );
    }
    if (_isDone) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, color: Color(0xFF15803D), size: 26),
          SizedBox(width: 6),
          Text(
            '完成',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF15803D),
            ),
          ),
        ],
      );
    }
    if (!task.proofRequired) {
      return const SizedBox.shrink();
    }
    return FilledButton.icon(
      onPressed: onComplete,
      icon: const Icon(Icons.photo_camera, size: 22),
      label: Text(_actionLabel, style: const TextStyle(fontSize: 18)),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
