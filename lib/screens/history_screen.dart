import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/conversation_controller.dart';
import '../routes/app_routes.dart';
import '../widgets/conversation_session_tile.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sessions = context.watch<ConversationController>().sessionSummaries;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('對話紀錄',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        if (sessions.isEmpty) const Text('目前尚無對話紀錄'),
        for (final s in sessions)
          ConversationSessionTile(
            summary: s,
            onTap: () {
              Navigator.of(context).pushNamed(
                AppRoute.conversationDetail,
                arguments: ConversationDetailArgs(
                  sessionId: s.sessionId,
                  title: s.title,
                ),
              );
            },
          ),
      ],
    );
  }
}
