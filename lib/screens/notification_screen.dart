import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/reminder_controller.dart';
import '../controllers/task_controller.dart';
import '../routes/app_routes.dart';

class NotificationScreen extends StatelessWidget {
  const NotificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tasks = context.watch<TaskController>().tasks;
    final reminders = context.watch<ReminderController>().reminders;
    final unfinished = tasks.where((task) => !task.completed).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('通知中心')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            '通知中心',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () =>
                Navigator.of(context).pushNamed(AppRoute.reminders),
            icon: const Icon(Icons.alarm),
            label: const Text('管理日常提醒'),
          ),
          const SizedBox(height: 12),
          if (reminders.where((item) => item.enabled).isNotEmpty) ...[
            const Text(
              '已啟用提醒',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            for (final reminder in reminders.where((item) => item.enabled))
              ListTile(
                leading: const Icon(Icons.alarm_on),
                title: Text('${reminder.title} ${reminder.timeLabel}'),
                subtitle: Text(reminder.repeatLabel),
              ),
            const Divider(),
          ],
          if (unfinished.isEmpty)
            const Text(
              '今天的提醒都完成了，辛苦了。',
              style: TextStyle(fontSize: 20),
            )
          else
            for (final task in unfinished)
              ListTile(
                leading: const Icon(Icons.notifications_active),
                title: Text(task.title),
                subtitle: const Text('還沒完成，記得慢慢來就好。'),
              ),
        ],
      ),
    );
  }
}
