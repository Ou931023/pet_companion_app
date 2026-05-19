import 'package:flutter/material.dart';

import '../../models/agent_tool_intent.dart';
import 'agent_confirmation_sheet.dart';

class AgentToolCard extends StatelessWidget {
  const AgentToolCard({
    super.key,
    required this.intent,
    required this.isExecuting,
    required this.onConfirm,
    required this.onCancel,
  });

  final AgentToolIntent intent;
  final bool isExecuting;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: _riskColor(intent).withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, color: _riskColor(intent)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    intent.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _RiskBadge(intent: intent),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              intent.userFacingMessage,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (intent.arguments.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _argumentSummary(intent.arguments),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.58),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: isExecuting ? null : onCancel,
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed:
                        isExecuting ? null : () => _confirm(context, intent),
                    child: Text(
                      intent.requiresConfirmation ? '確認' : '立即執行',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirm(BuildContext context, AgentToolIntent intent) async {
    if (!intent.requiresConfirmation) {
      onConfirm();
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => AgentConfirmationSheet(
        intent: intent,
        onConfirm: () {
          Navigator.of(sheetContext).pop();
          onConfirm();
        },
        onCancel: () {
          Navigator.of(sheetContext).pop();
          onCancel();
        },
      ),
    );
  }

  Color _riskColor(AgentToolIntent intent) {
    return switch (intent.riskLevel) {
      AgentToolRiskLevel.high => Colors.red.shade700,
      AgentToolRiskLevel.medium => Colors.orange.shade800,
      AgentToolRiskLevel.low => Colors.green.shade700,
    };
  }

  String _argumentSummary(Map<String, dynamic> arguments) {
    return arguments.entries
        .where((entry) => entry.value.toString().trim().isNotEmpty)
        .map((entry) => '${entry.key}: ${entry.value}')
        .join('  /  ');
  }
}

class _RiskBadge extends StatelessWidget {
  const _RiskBadge({required this.intent});

  final AgentToolIntent intent;

  @override
  Widget build(BuildContext context) {
    final label = switch (intent.riskLevel) {
      AgentToolRiskLevel.high => '高',
      AgentToolRiskLevel.medium => '中',
      AgentToolRiskLevel.low => '低',
    };
    final color = switch (intent.riskLevel) {
      AgentToolRiskLevel.high => Colors.red.shade700,
      AgentToolRiskLevel.medium => Colors.orange.shade800,
      AgentToolRiskLevel.low => Colors.green.shade700,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          '$label風險',
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
