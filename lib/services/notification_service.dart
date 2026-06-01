import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/reminder.dart';

class NotificationService {
  NotificationService() : _plugin = FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    tz.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
    );
    _initialized = true;
  }

  Future<void> scheduleReminder(Reminder reminder) async {
    await initialize();
    await cancelReminder(reminder.id);
    if (!reminder.enabled) return;

    await _plugin.zonedSchedule(
      id: _notificationId(reminder.id),
      title: reminder.title,
      body: _bodyFor(reminder),
      scheduledDate: _nextTime(reminder),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'care_reminders',
          '日常提醒',
          channelDescription: 'AI 寵物陪伴的日常健康提醒',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: reminder.repeatType == 'daily'
          ? DateTimeComponents.time
          : reminder.repeatType == 'weekly'
              ? DateTimeComponents.dayOfWeekAndTime
              : null,
    );
  }

  Future<void> cancelReminder(String id) async {
    await _plugin.cancel(id: _notificationId(id));
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  /// 重新排程「目前這份清單」的提醒。
  ///
  /// CR-0012：先 [cancelAll] 清掉所有已排程通知，再排目前帳號的提醒。
  /// 這樣切換帳號 / 登出回 Demo 時，上一個帳號排進系統的提醒不會繼續在
  /// 別的帳號身上響起（資料層已依 elderId 隔離，這裡補上 OS 排程層的隔離）。
  Future<void> rescheduleAll(List<Reminder> reminders) async {
    await initialize();
    await cancelAll();
    for (final reminder in reminders) {
      await scheduleReminder(reminder);
    }
  }

  tz.TZDateTime _nextTime(Reminder reminder) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      reminder.hour,
      reminder.minute,
    );
    while (scheduled.isBefore(now)) {
      scheduled = reminder.repeatType == 'weekly'
          ? scheduled.add(const Duration(days: 7))
          : scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  String _bodyFor(Reminder reminder) {
    final title = reminder.title;
    if (title.contains('藥')) return '吃藥時間到囉，記得按照醫師說的方式吃喔。';
    if (title.contains('水')) return '該喝水囉，我陪你一起照顧身體。';
    if (title.contains('運動') || title.contains('散步')) {
      return '我們一起動一動吧，散步一下對身體很好。';
    }
    if (title.contains('睡')) return '時間不早了，準備休息囉。';
    return reminder.note.isEmpty ? '提醒時間到囉，我陪你慢慢完成。' : reminder.note;
  }

  int _notificationId(String id) {
    return id.hashCode & 0x7fffffff;
  }
}
