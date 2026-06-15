import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/reminder.dart';
import 'check_in_reminder_schedule.dart';
import 'pet_concern_notification_policy.dart';

class NotificationService {
  NotificationService() : _plugin = FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  /// CR-0031：點到「每日簽到提醒」通知時要做的事（例如導回首頁）。
  /// 由 App 啟動處設定；沒設定就只會打開 App，不導頁。
  void Function()? onCheckInReminderTapped;

  /// CR-0087：點到「寵物關心提醒」通知時要做的事（導回首頁陪伴寵物）。
  void Function()? onPetConcernReminderTapped;

  Future<void> initialize() async {
    if (_initialized) return;
    // CR-0031：初始化失敗（例如平台外掛尚未就緒）不得讓 App crash。
    // 失敗時保持 _initialized = false，後續排程方法會安靜略過、下次再試。
    try {
      tz.initializeTimeZones();
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      await _plugin.initialize(
        settings: const InitializationSettings(android: android, iOS: ios),
        onDidReceiveNotificationResponse: _handleNotificationResponse,
      );
      // CR-0031：Android 13 以下需要先建好通知 channel，10:00 簽到提醒才會正常出現。
      await _ensureCheckInChannel();
      // CR-0087：寵物關心提醒走獨立 channel，與簽到提醒互不干擾。
      await _ensurePetConcernChannel();
      _initialized = true;
    } catch (_) {
      // 不對使用者顯示工程錯誤；通知無法初始化時，App 其他功能仍可正常使用。
    }
  }

  /// CR-0031：請求通知權限。權限被拒或發生例外時回傳 false，不對使用者顯示工程訊息。
  Future<bool> requestPermissions() async {
    try {
      await initialize();
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        final granted = await ios.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        return granted ?? false;
      }
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        final granted = await android.requestNotificationsPermission();
        return granted ?? false;
      }
    } catch (_) {
      // 權限流程失敗時保持安靜：不 crash、不顯示工程錯誤，回傳 false 即可。
      return false;
    }
    return false;
  }

  // ── CR-0031 每日簽到提醒 ──────────────────────────────────────────────

  /// 排程「下一次 10:00 簽到提醒」（id 固定 [CheckInReminderSchedule.notificationId]）。
  ///
  /// 現在早於今天 10:00 → 排今天 10:00；已過 10:00 → 排明天 10:00。
  /// 採做法 B：排「一則一次性」通知，不用 daily repeat，避免已簽到當天仍洗版。
  Future<void> scheduleDailyCheckInReminder({
    bool hasCheckedInToday = false,
  }) async {
    await initialize();
    if (!_initialized) return;
    final wallClock = CheckInReminderSchedule.nextReminderTime(
      now: DateTime.now(),
      hasCheckedInToday: hasCheckedInToday,
    );
    final scheduled = tz.TZDateTime(
      tz.local,
      wallClock.year,
      wallClock.month,
      wallClock.day,
      CheckInReminderSchedule.hour,
      CheckInReminderSchedule.minute,
    );
    // 先取消舊的，避免重複排程造成通知洗版。
    await cancelTodayCheckInReminder();
    await _plugin.zonedSchedule(
      id: CheckInReminderSchedule.notificationId,
      title: CheckInReminderSchedule.title,
      body: CheckInReminderSchedule.body,
      payload: CheckInReminderSchedule.payload,
      scheduledDate: scheduled,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _checkInChannelId,
          _checkInChannelName,
          channelDescription: '提醒你每天回來看看 AI 寵物、完成今日簽到',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  /// 取消今天的簽到提醒（id 10001）。用於：已簽到、或 App 啟動發現今天已簽到。
  Future<void> cancelTodayCheckInReminder() async {
    await initialize();
    if (!_initialized) return;
    await _plugin.cancel(id: CheckInReminderSchedule.notificationId);
  }

  /// 先取消舊的 10001，再排下一次 10:00 簽到提醒。
  Future<void> rescheduleNextCheckInReminder({
    bool hasCheckedInToday = false,
  }) async {
    await cancelTodayCheckInReminder();
    await scheduleDailyCheckInReminder(hasCheckedInToday: hasCheckedInToday);
  }

  /// CR-0031 最重要的方法：依「今天是否已簽到」同步簽到提醒。
  ///
  /// - 已簽到：取消今天通知，排下一次（通常是明天 10:00）。
  /// - 未簽到：早於 10:00 排今天 10:00；已過 10:00 排明天 10:00。
  ///
  /// 兩種情況都先取消舊的再排，避免 App 重開造成重複排程。
  Future<void> syncCheckInReminder({required bool hasCheckedInToday}) async {
    await initialize();
    await scheduleDailyCheckInReminder(hasCheckedInToday: hasCheckedInToday);
  }

  /// 取消所有通知（含簽到提醒）。
  Future<void> cancelAllNotifications() async {
    await initialize();
    if (!_initialized) return;
    await cancelAll();
  }

  // ── CR-0087 寵物關心提醒 ──────────────────────────────────────────────

  /// 排程一則「寵物關心提醒」（id 固定 [PetConcernNotificationPolicy.notificationId]）。
  ///
  /// 文案由純邏輯 [PetConcernNotificationPolicy] 決定；本方法只負責薄薄一層排程。
  /// 一律先取消舊的再排，避免重複跳。回到 App 時請呼叫 [cancelPetConcernReminder]。
  Future<void> schedulePetConcernReminder({
    required String title,
    required String body,
    required DateTime scheduledAt,
  }) async {
    await initialize();
    if (!_initialized) return;
    await cancelPetConcernReminder();
    final scheduled = tz.TZDateTime.from(scheduledAt, tz.local);
    await _plugin.zonedSchedule(
      id: PetConcernNotificationPolicy.notificationId,
      title: title,
      body: body,
      payload: PetConcernNotificationPolicy.payload,
      scheduledDate: scheduled,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          PetConcernNotificationPolicy.channelId,
          PetConcernNotificationPolicy.channelName,
          channelDescription: '寵物在你較少互動或狀態較低時，溫和地想你、提醒你回來陪牠',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  /// 取消待發的寵物關心提醒（回到 App / 已互動 / 關閉設定時呼叫）。
  Future<void> cancelPetConcernReminder() async {
    await initialize();
    if (!_initialized) return;
    await _plugin.cancel(id: PetConcernNotificationPolicy.notificationId);
  }

  void _handleNotificationResponse(NotificationResponse response) {
    if (response.payload == CheckInReminderSchedule.payload) {
      onCheckInReminderTapped?.call();
    } else if (response.payload == PetConcernNotificationPolicy.payload) {
      onPetConcernReminderTapped?.call();
    }
  }

  static const String _checkInChannelId = 'check_in_reminders';
  static const String _checkInChannelName = '每日簽到提醒';

  Future<void> _ensureCheckInChannel() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        _checkInChannelId,
        _checkInChannelName,
        description: '提醒你每天回來看看 AI 寵物、完成今日簽到',
        importance: Importance.high,
      ),
    );
  }

  Future<void> _ensurePetConcernChannel() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        PetConcernNotificationPolicy.channelId,
        PetConcernNotificationPolicy.channelName,
        description: '寵物在你較少互動或狀態較低時，溫和地想你、提醒你回來陪牠',
        importance: Importance.high,
      ),
    );
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
