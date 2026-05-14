import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/conversation_controller.dart';
import '../controllers/task_controller.dart';
import '../widgets/care_task_card.dart';

class TaskScreen extends StatelessWidget {
  const TaskScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final taskController = context.watch<TaskController>();
    final conversationController = context.read<ConversationController>();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          '長照生活任務',
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        ...taskController.tasks.map(
          (task) => CareTaskCard(
            task: task,
            onComplete: () async {
              final command = switch (task.id) {
                'dailyCheckIn' => '幫我簽到',
                'drinkWater' => '我喝水了',
                'eatMeal' => '我吃飯了',
                'restReminder' => '我休息了',
                _ => '我完成任務',
              };
              await conversationController.quickAction(command);
            },
          ),
        ),
      ],
    );
  }
}
