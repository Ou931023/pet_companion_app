import 'package:flutter/material.dart';

class MemoryCard extends StatelessWidget {
  const MemoryCard({
    super.key,
    required this.memory,
    required this.onForget,
    this.isForgetting = false,
  });

  final Map<String, dynamic> memory;
  final VoidCallback onForget;
  final bool isForgetting;

  @override
  Widget build(BuildContext context) {
    final summary = _text(memory['memorySummary'] ?? memory['memory_summary']);
    final type =
        _memoryTypeLabel(_text(memory['memoryType'] ?? memory['memory_type']));
    final importance = _text(memory['importance']);
    final createdAt =
        _formatDate(_text(memory['createdAt'] ?? memory['created_at']));
    final useCount = _text(memory['useCount'] ?? memory['use_count']);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              summary.isEmpty ? '未命名記憶' : summary,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(icon: Icons.label_outline, label: type),
                if (importance.isNotEmpty)
                  _InfoChip(icon: Icons.star_border, label: '重要性 $importance'),
                if (createdAt.isNotEmpty)
                  _InfoChip(icon: Icons.event_note, label: createdAt),
                if (useCount.isNotEmpty)
                  _InfoChip(icon: Icons.repeat, label: '使用 $useCount 次'),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: isForgetting ? null : onForget,
                icon: isForgetting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline),
                label: const Text('忘記這筆'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _text(Object? value) => value?.toString().trim() ?? '';

  String _formatDate(String value) {
    final date = DateTime.tryParse(value);
    if (date == null) return '';
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  }

  String _memoryTypeLabel(String value) {
    return switch (value) {
      'preference' => '偏好',
      'routine' => '生活習慣',
      'emotion' => '情緒狀態',
      'reminder' => '提醒事項',
      'care_need' => '照護需求',
      'story_preference' => '故事偏好',
      'health_lifestyle' => '健康生活',
      'other' => '其他',
      _ => value.isEmpty ? '記憶' : value,
    };
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.indigo.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.indigo),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
