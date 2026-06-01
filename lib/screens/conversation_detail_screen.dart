import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/conversation_controller.dart';
import '../models/conversation_turn.dart';

class ConversationDetailScreen extends StatelessWidget {
  const ConversationDetailScreen({
    super.key,
    required this.sessionId,
    required this.title,
  });

  final String sessionId;
  final String title;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ConversationController>();
    final turns = controller.turnsForSession(sessionId);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: turns.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  '這段對話的紀錄都刪完了。',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.black.withValues(alpha: 0.55),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: turns.length,
              itemBuilder: (context, index) {
                final t = turns[index];
                // 長按單筆紀錄 → 確認後才刪除（避免誤觸直接刪掉）。
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onLongPress: () => _confirmDeleteTurn(context, controller, t),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (t.userText.trim().isNotEmpty)
                          Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(t.userText),
                            ),
                          ),
                        if (t.petReply.trim().isNotEmpty)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(top: 6),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(t.petReply),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '情緒：${t.emotionTag}｜寵物心情：${t.petMood}',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  /// 長按後的刪除確認：點「刪除」才真的移除這一筆對話紀錄；不影響長期記憶。
  Future<void> _confirmDeleteTurn(
    BuildContext context,
    ConversationController controller,
    ConversationTurn turn,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            '要刪除這筆紀錄嗎？',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          content: const Text(
            '刪掉後這筆聊天紀錄就看不到了，但不會影響寵物記得你的事。',
            style: TextStyle(fontSize: 16, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消', style: TextStyle(fontSize: 18)),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text(
                '刪除',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFC2410C),
                ),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) return;
    final ok = await controller.deleteConversationTurn(turn);
    if (!context.mounted || ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('沒辦法刪除這筆，請再試一次。')),
    );
  }
}
