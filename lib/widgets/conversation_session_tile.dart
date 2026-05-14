import 'package:flutter/material.dart';

import '../models/conversation_session_summary.dart';

class ConversationSessionTile extends StatelessWidget {
  const ConversationSessionTile({
    super.key,
    required this.summary,
    required this.onTap,
  });

  final ConversationSessionSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        title:
            Text(summary.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${_formatDate(summary.updatedAt)} ・ ${summary.lastPreview}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Chip(label: Text(summary.emotionTag)),
      ),
    );
  }

  String _formatDate(DateTime time) {
    final now = DateTime.now();
    final d0 = DateTime(now.year, now.month, now.day);
    final d1 = DateTime(time.year, time.month, time.day);
    final diff = d0.difference(d1).inDays;
    if (diff == 0) return '今天';
    if (diff == 1) return '昨天';
    return '${time.month.toString().padLeft(2, '0')}/${time.day.toString().padLeft(2, '0')}';
  }
}
