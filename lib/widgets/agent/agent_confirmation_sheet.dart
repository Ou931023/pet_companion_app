import 'package:flutter/material.dart';

import '../../models/agent_tool_intent.dart';

class AgentConfirmationSheet extends StatelessWidget {
  const AgentConfirmationSheet({
    super.key,
    required this.intent,
    required this.onConfirm,
    required this.onCancel,
  });

  final AgentToolIntent intent;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              intent.displayName,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              _riskText(intent),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (intent.toolName == 'open_phone_dialer') ...[
              const SizedBox(height: 8),
              const Text('電話只會開啟撥號畫面，不會自動撥出。'),
            ],
            if (intent.toolName == 'create_email_draft') ...[
              const SizedBox(height: 8),
              const Text('Email 只會建立草稿，不會自動寄出。'),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onCancel,
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: onConfirm,
                    child: const Text('確認執行'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _riskText(AgentToolIntent intent) {
    return switch (intent.riskLevel) {
      AgentToolRiskLevel.high => '高風險工具，執行前需要你確認。',
      AgentToolRiskLevel.medium => '中風險工具，執行前需要你確認。',
      AgentToolRiskLevel.low => '低風險工具。',
    };
  }
}
