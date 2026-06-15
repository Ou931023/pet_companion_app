import 'package:flutter/material.dart';

import '../models/conversation_session_summary.dart';
import '../utils/conversation_history_display.dart';

class ConversationSessionTile extends StatelessWidget {
  const ConversationSessionTile({
    super.key,
    required this.summary,
    required this.onTap,
    this.onLongPress,
  });

  final ConversationSessionSummary summary;
  final VoidCallback onTap;

  /// 長按整則卡片（CR-0027）：用來刪除這一則對話紀錄。null 時不啟用長按。
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    // CR-0091：心情標籤改成長者友善描述；neutral / 不認得就不顯示（不外漏 emotionTag）。
    final mood = friendlyMoodLabel(summary.emotionTag);
    return Card(
      child: ListTile(
        onTap: onTap,
        onLongPress: onLongPress,
        title:
            Text(summary.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${_formatDate(summary.updatedAt)} ・ ${summary.lastPreview}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: mood == null ? null : Chip(label: Text(mood)),
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
