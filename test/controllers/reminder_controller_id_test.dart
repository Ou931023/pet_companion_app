import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/controllers/reminder_controller.dart';
import 'package:pet_companion_app/models/reminder.dart';
import 'package:pet_companion_app/services/notification_service.dart';
import 'package:pet_companion_app/services/reminder_service.dart';

class _MemoryReminders extends ReminderService {
  List<Reminder> stored = [];
  @override
  Future<List<Reminder>> load() async => List.of(stored);
  @override
  Future<void> save(List<Reminder> reminders) async {
    stored = List.of(reminders);
  }
}

class _Notifications extends NotificationService {
  final scheduled = <Reminder>[];
  @override
  Future<void> scheduleReminder(Reminder reminder) async {
    scheduled.add(reminder);
  }

  @override
  Future<void> rescheduleAll(List<Reminder> reminders) async {}
}

const _voice = '\u63d0\u9192\u6211 20:00 \u559d\u6c34';

void main() {
  test('fixed clock keeps both voice reminders persisted and scheduled',
      () async {
    final storage = _MemoryReminders();
    final notifications = _Notifications();
    final controller = ReminderController(
      reminderService: storage,
      notificationService: notifications,
      now: () => DateTime(2035),
    );
    addTearDown(controller.dispose);
    final first = (await controller.createFromVoice(_voice))!;
    final second = (await controller.createFromVoice(_voice))!;
    expect(int.parse(second.id), greaterThan(int.parse(first.id)));
    expect(controller.reminders, hasLength(2));
    expect(storage.stored.map((r) => r.id), [first.id, second.id]);
    expect(notifications.scheduled.map((r) => r.id), [first.id, second.id]);
  });

  test('loaded ID collision and clock rollback preserve existing reminders',
      () async {
    var time = DateTime(2050);
    final loaded = Reminder(
      id: time.microsecondsSinceEpoch.toString(),
      title: 'Existing',
      hour: 8,
      minute: 0,
      repeatType: 'none',
      note: '',
      enabled: true,
    );
    final storage = _MemoryReminders()..stored = [loaded];
    final notifications = _Notifications();
    final controller = ReminderController(
      reminderService: storage,
      notificationService: notifications,
      now: () => time,
    );
    addTearDown(controller.dispose);
    await controller.load();
    final first = (await controller.createFromVoice(_voice))!;
    time = DateTime(2030);
    final second = (await controller.createFromVoice(_voice))!;
    expect(first.id, isNot(loaded.id));
    expect(int.parse(second.id), greaterThan(int.parse(first.id)));
    expect(storage.stored, hasLength(3));
    expect(storage.stored.first.title, 'Existing');
    expect(notifications.scheduled.map((r) => r.id), [first.id, second.id]);
  });

  test('explicit updates retain the existing ID and replace only that reminder',
      () async {
    const original = Reminder(
        id: 'legacy-id',
        title: 'Original',
        hour: 8,
        minute: 0,
        repeatType: 'none',
        note: '',
        enabled: true);
    final storage = _MemoryReminders()..stored = [original];
    final notifications = _Notifications();
    final controller = ReminderController(
      reminderService: storage,
      notificationService: notifications,
    );
    addTearDown(controller.dispose);
    await controller.load();
    await controller.addOrUpdate(original.copyWith(title: 'Updated'));
    expect(storage.stored.single.id, original.id);
    expect(storage.stored.single.title, 'Updated');
    expect(notifications.scheduled.single.id, original.id);
  });
}
