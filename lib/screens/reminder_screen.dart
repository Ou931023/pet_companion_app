import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/reminder_controller.dart';
import '../models/reminder.dart';

class ReminderScreen extends StatelessWidget {
  const ReminderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ReminderController>();
    return Scaffold(
      appBar: AppBar(title: const Text('日常提醒')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '日常提醒',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text('設定吃藥、喝水、運動或回診提醒，寵物會溫柔提醒你。'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => _showReminderForm(context),
            icon: const Icon(Icons.add),
            label: const Text('新增提醒'),
          ),
          const SizedBox(height: 12),
          if (controller.reminders.isEmpty)
            const Text('目前還沒有提醒')
          else
            for (final reminder in controller.reminders)
              Card(
                child: ListTile(
                  leading: IconButton(
                    tooltip: '修改提醒內容與時間',
                    onPressed: () =>
                        _showReminderForm(context, reminder: reminder),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  title: Text('${reminder.title} ${reminder.timeLabel}'),
                  subtitle: Text(
                    '${reminder.repeatLabel}${reminder.note.isEmpty ? '' : '・${reminder.note}'}',
                  ),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      Switch(
                        value: reminder.enabled,
                        onChanged: (value) =>
                            controller.setEnabled(reminder.id, value),
                      ),
                      IconButton(
                        tooltip: '刪除提醒',
                        onPressed: () => controller.remove(reminder.id),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                  onTap: () => _showReminderForm(context, reminder: reminder),
                ),
              ),
        ],
      ),
    );
  }

  Future<void> _showReminderForm(
    BuildContext context, {
    Reminder? reminder,
  }) async {
    final controller = context.read<ReminderController>();
    final titleController =
        TextEditingController(text: reminder?.title ?? '喝水');
    final noteController = TextEditingController(text: reminder?.note ?? '');
    var time =
        TimeOfDay(hour: reminder?.hour ?? 9, minute: reminder?.minute ?? 0);
    var repeatType = reminder?.repeatType ?? 'daily';
    var enabled = reminder?.enabled ?? true;
    var saving = false;
    String? error;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) => SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  reminder == null ? '新增提醒' : '修改提醒',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleController,
                  enabled: !saving,
                  decoration: const InputDecoration(
                    labelText: '提醒名稱',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: time,
                          );
                          if (context.mounted && picked != null) {
                            setSheetState(() => time = picked);
                          }
                        },
                  icon: const Icon(Icons.schedule),
                  label: Text(
                    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                  ),
                ),
                const SizedBox(height: 10),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'none', label: Text('一次')),
                    ButtonSegment(value: 'daily', label: Text('每天')),
                    ButtonSegment(value: 'weekly', label: Text('每週')),
                  ],
                  selected: {repeatType},
                  onSelectionChanged: saving
                      ? null
                      : (values) =>
                          setSheetState(() => repeatType = values.first),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: noteController,
                  enabled: !saving,
                  decoration: const InputDecoration(
                    labelText: '備註',
                    border: OutlineInputBorder(),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: enabled,
                  title: const Text('啟用提醒'),
                  onChanged: saving
                      ? null
                      : (value) => setSheetState(() => enabled = value),
                ),
                if (error != null)
                  Text(error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (titleController.text.trim().isEmpty) {
                            setSheetState(() => error = '請填寫提醒內容。');
                            return;
                          }
                          setSheetState(() {
                            saving = true;
                            error = null;
                          });
                          final next = Reminder(
                            id: reminder?.id ??
                                DateTime.now()
                                    .microsecondsSinceEpoch
                                    .toString(),
                            title: titleController.text.trim().isEmpty
                                ? '日常提醒'
                                : titleController.text.trim(),
                            hour: time.hour,
                            minute: time.minute,
                            repeatType: repeatType,
                            note: noteController.text.trim(),
                            enabled: enabled,
                          );
                          try {
                            await controller.addOrUpdate(next);
                            if (sheetContext.mounted) {
                              Navigator.pop(sheetContext);
                            }
                          } catch (_) {
                            if (sheetContext.mounted) {
                              setSheetState(() {
                                saving = false;
                                error = '提醒還沒設定好，請稍後再試一次。';
                              });
                            }
                          }
                        },
                  child: Text(saving ? '正在儲存' : '儲存提醒'),
                ),
              ],
            ),
          ),
        );
      },
    );
    titleController.dispose();
    noteController.dispose();
  }
}
