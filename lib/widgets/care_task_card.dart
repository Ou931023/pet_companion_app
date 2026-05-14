import 'package:flutter/material.dart';

import '../models/care_task.dart';

class CareTaskCard extends StatelessWidget {
  const CareTaskCard({
    super.key,
    required this.task,
    required this.onComplete,
  });

  final CareTask task;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(
          task.title,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '獎勵 ${task.rewardCoins} 金幣 / 親密度 +${task.rewardBond}',
          style: const TextStyle(fontSize: 16),
        ),
        trailing: ElevatedButton(
          onPressed: task.completed ? null : onComplete,
          child: Text(task.completed ? '已完成' : '完成'),
        ),
      ),
    );
  }
}
