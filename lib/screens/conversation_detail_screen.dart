import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/conversation_controller.dart';
import '../models/conversation_turn.dart';
import '../utils/conversation_history_display.dart';

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
          : Column(
              children: [
                // 操作提示：讓長者知道可以一句一句刪、也可以整段刪。
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    '長按一則訊息可只刪那一句；長按下面的灰色小字可刪整段。',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: Colors.black.withValues(alpha: 0.55),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: turns.length,
                    itemBuilder: (context, index) {
                      return _buildTurn(context, controller, turns[index]);
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildTurn(
    BuildContext context,
    ConversationController controller,
    ConversationTurn t,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (t.userText.trim().isNotEmpty)
            // 長按使用者這一則 → 只刪你說的這句。
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPress: () =>
                  _confirmDeleteMessage(context, controller, t, deleteUser: true),
              child: Align(
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
            ),
          if (t.petReply.trim().isNotEmpty)
            // 長按寵物這一則 → 只刪寵物回的這句。
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPress: () => _confirmDeleteMessage(context, controller, t,
                  deleteUser: false),
              child: Align(
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
            ),
          // 長按下面這行 → 刪整段（這則和它的回覆一起）。
          // CR-0091：不再外漏 emotionTag / petMood 原值；只用長者友善的心情描述，
          // neutral / 不認得時就只留刪除提示。
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: () => _confirmDeleteTurn(context, controller, t),
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Builder(
                builder: (_) {
                  final mood = friendlyMoodLabel(t.emotionTag);
                  final text = mood == null
                      ? '長按這行可刪整段'
                      : '那天$mood　·　長按這行可刪整段';
                  return Text(
                    text,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 長按單一泡泡後的刪除確認：只刪「這一則」（你說的那句 / 寵物回的那句）。
  /// 若刪掉後整段都空了，整段會一起消失。不影響長期記憶。
  Future<void> _confirmDeleteMessage(
    BuildContext context,
    ConversationController controller,
    ConversationTurn turn, {
    required bool deleteUser,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            '要刪掉這一句嗎？',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          content: Text(
            deleteUser
                ? '只會刪掉你說的這一句，寵物的回覆會留著。'
                : '只會刪掉寵物說的這一句，你說的話會留著。',
            style: const TextStyle(fontSize: 16, height: 1.4),
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
    final ok =
        await controller.deleteConversationMessage(turn, deleteUser: deleteUser);
    if (!context.mounted || ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('沒辦法刪除這一句，請再試一次。')),
    );
  }

  /// 長按情緒列後的刪除確認：刪「整段」（這則和它的回覆一起移除）；不影響長期記憶。
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
            '要刪除整段對話嗎？',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          content: const Text(
            '會把你這句和寵物的回覆一起刪掉，但不會影響寵物記得你的事。',
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
      const SnackBar(content: Text('沒辦法刪除這段，請再試一次。')),
    );
  }
}
