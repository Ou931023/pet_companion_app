import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/agent_tool_controller.dart';
import '../controllers/profile_controller.dart';
import '../widgets/agent/agent_tool_card.dart';
import '../widgets/agent/agent_tool_result_card.dart';

class AgentToolDemoScreen extends StatelessWidget {
  const AgentToolDemoScreen({super.key});

  static const _samples = [
    '幫我播放放鬆音樂',
    '幫我打給女兒',
    '幫我寄 email 給家人說我今天有點累',
    '提醒我晚上八點吃藥',
    '幫我查今天的防詐騙新聞',
    '帶我去商城',
    '記住我喜歡聽台語老歌',
  ];

  @override
  Widget build(BuildContext context) {
    final agent = context.watch<AgentToolController>();
    final profile = context.watch<ProfileController>();
    return Scaffold(
      appBar: AppBar(title: const Text('AI Agent 工具測試')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '測試 Agent Router 判斷工具意圖，再由 Flutter 執行手機原生工具。',
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.62),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          for (final sample in _samples) ...[
            FilledButton.tonal(
              onPressed: agent.isRouting
                  ? null
                  : () => agent.routeFromUserText(
                        sample,
                        sessionId: 'agent_demo',
                        turnId:
                            'agent_demo_${DateTime.now().microsecondsSinceEpoch}',
                        petName: profile.petName,
                        emotion: 'neutral',
                        languageHint: 'zh-TW',
                      ),
              child: Text(sample),
            ),
            const SizedBox(height: 8),
          ],
          if (agent.isRouting) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
          if (agent.pendingIntent != null) ...[
            const SizedBox(height: 12),
            AgentToolCard(
              intent: agent.pendingIntent!,
              isExecuting: agent.isExecuting,
              onConfirm: agent.confirmAndExecute,
              onCancel: agent.cancelIntent,
            ),
          ],
          if (agent.executionResult != null) ...[
            const SizedBox(height: 12),
            AgentToolResultCard(
              result: agent.executionResult!,
              onDismiss: agent.clear,
            ),
          ],
          if (agent.errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              agent.errorMessage!,
              style: const TextStyle(color: Colors.red),
            ),
          ],
        ],
      ),
    );
  }
}
