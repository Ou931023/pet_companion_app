import 'package:flutter/material.dart';

import '../models/reminder.dart';
import '../services/notification_service.dart';
import '../services/reminder_service.dart';

class ReminderController extends ChangeNotifier {
  ReminderController({
    required ReminderService reminderService,
    required NotificationService notificationService,
  })  : _reminderService = reminderService,
        _notificationService = notificationService;

  final ReminderService _reminderService;
  final NotificationService _notificationService;

  List<Reminder> _reminders = [];
  bool _isLoading = true;

  List<Reminder> get reminders => List.unmodifiable(_reminders);
  bool get isLoading => _isLoading;

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    _reminders = await _reminderService.load();
    _isLoading = false;
    notifyListeners();
    await _notificationService.rescheduleAll(_reminders);
  }

  Future<void> addOrUpdate(Reminder reminder) async {
    final index = _reminders.indexWhere((item) => item.id == reminder.id);
    if (index == -1) {
      _reminders = [..._reminders, reminder];
    } else {
      _reminders = [..._reminders]..[index] = reminder;
    }
    await _persistAndSchedule(reminder);
  }

  Future<void> remove(String id) async {
    _reminders = _reminders.where((item) => item.id != id).toList();
    await _reminderService.save(_reminders);
    await _notificationService.cancelReminder(id);
    notifyListeners();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final reminder = _reminders.firstWhere((item) => item.id == id);
    await addOrUpdate(reminder.copyWith(enabled: enabled));
  }

  Future<Reminder?> createFromVoice(String text) async {
    final parsed = _parseVoiceReminder(text);
    if (parsed == null) return null;
    await addOrUpdate(parsed);
    return parsed;
  }

  bool isCreateReminderCommand(String text) {
    return text.contains('提醒我') || text.contains('記得提醒');
  }

  bool isListReminderCommand(String text) {
    return text.contains('有哪些提醒') ||
        text.contains('提醒清單') ||
        text.contains('我的提醒');
  }

  String listSummary() {
    if (_reminders.isEmpty) return '目前還沒有提醒，你可以跟我說，提醒我晚上八點吃藥。';
    final enabled = _reminders.where((item) => item.enabled).toList();
    if (enabled.isEmpty) return '目前提醒都暫停了，需要時可以再打開。';
    return '目前有 ${enabled.length} 個提醒：${enabled.map((item) => '${item.repeatLabel}${item.timeLabel}${item.title}').join('、')}。';
  }

  Reminder? _parseVoiceReminder(String text) {
    final time = _parseTime(text);
    if (time == null) return null;
    final title = _parseTitle(text);
    final repeatType = text.contains('每天')
        ? 'daily'
        : text.contains('每週') || text.contains('每个禮拜')
            ? 'weekly'
            : 'none';
    return Reminder(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      hour: time.hour,
      minute: time.minute,
      repeatType: repeatType,
      note: _noteFor(title),
      enabled: true,
    );
  }

  TimeOfDay? _parseTime(String text) {
    final digitMatch = RegExp(r'([0-2]?\d)[:：點点時时]([0-5]\d)?').firstMatch(text);
    if (digitMatch != null) {
      var hour = int.tryParse(digitMatch.group(1) ?? '') ?? 9;
      final minute = int.tryParse(digitMatch.group(2) ?? '') ?? 0;
      if (text.contains('晚上') || text.contains('下午')) {
        if (hour < 12) hour += 12;
      }
      return TimeOfDay(hour: hour.clamp(0, 23), minute: minute.clamp(0, 59));
    }
    final zh = <String, int>{
      '一': 1,
      '二': 2,
      '兩': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
      '十': 10,
    };
    for (final entry in zh.entries) {
      if (text.contains('${entry.key}點') || text.contains('${entry.key}時')) {
        var hour = entry.value;
        if (text.contains('晚上') || text.contains('下午')) {
          if (hour < 12) hour += 12;
        }
        return TimeOfDay(hour: hour, minute: 0);
      }
    }
    return null;
  }

  String _parseTitle(String text) {
    if (text.contains('吃藥')) return '吃藥';
    if (text.contains('喝水')) return '喝水';
    if (text.contains('運動')) return '運動';
    if (text.contains('睡覺') || text.contains('休息')) return '睡覺';
    if (text.contains('回診')) return '回診';
    if (text.contains('血壓')) return '量血壓';
    if (text.contains('血糖')) return '量血糖';
    if (text.contains('散步')) return '散步';
    return '日常提醒';
  }

  String _noteFor(String title) {
    if (title.contains('藥')) return '記得按照醫師說的方式吃喔。';
    if (title.contains('水')) return '我陪你一起照顧身體。';
    return '';
  }

  Future<void> _persistAndSchedule(Reminder reminder) async {
    await _reminderService.save(_reminders);
    await _notificationService.scheduleReminder(reminder);
    notifyListeners();
  }
}
