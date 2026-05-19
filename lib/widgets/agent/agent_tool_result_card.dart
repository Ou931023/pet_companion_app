import 'package:flutter/material.dart';

import '../../models/agent_tool_execution_result.dart';

class AgentToolResultCard extends StatelessWidget {
  const AgentToolResultCard({
    super.key,
    required this.result,
    this.onDismiss,
  });

  final AgentToolExecutionResult result;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final color = result.success ? Colors.green.shade700 : Colors.red.shade700;
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.20)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(
              result.success ? Icons.check_circle : Icons.error_outline,
              color: color,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                result.message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (onDismiss != null)
              IconButton(
                onPressed: onDismiss,
                icon: const Icon(Icons.close),
                tooltip: '關閉',
              ),
          ],
        ),
      ),
    );
  }
}
