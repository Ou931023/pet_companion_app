import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/services/check_in_reminder_schedule.dart';

void main() {
  group('CheckInReminderSchedule.nextReminderTime', () {
    test('未簽到且現在早於 10:00 → 排今天 10:00', () {
      final now = DateTime(2026, 6, 4, 8, 30);
      final next = CheckInReminderSchedule.nextReminderTime(
        now: now,
        hasCheckedInToday: false,
      );
      expect(next, DateTime(2026, 6, 4, 10, 0));
    });

    test('未簽到且現在晚於 10:00 → 排明天 10:00', () {
      final now = DateTime(2026, 6, 4, 14, 5);
      final next = CheckInReminderSchedule.nextReminderTime(
        now: now,
        hasCheckedInToday: false,
      );
      expect(next, DateTime(2026, 6, 5, 10, 0));
    });

    test('未簽到且現在剛好 10:00 → 視為已過，排明天 10:00（不排在過去/當下）', () {
      final now = DateTime(2026, 6, 4, 10, 0);
      final next = CheckInReminderSchedule.nextReminderTime(
        now: now,
        hasCheckedInToday: false,
      );
      expect(next, DateTime(2026, 6, 5, 10, 0));
    });

    test('今天已簽到（早於 10:00）→ 一律排明天 10:00', () {
      final now = DateTime(2026, 6, 4, 7, 0);
      final next = CheckInReminderSchedule.nextReminderTime(
        now: now,
        hasCheckedInToday: true,
      );
      expect(next, DateTime(2026, 6, 5, 10, 0));
    });

    test('今天已簽到（晚於 10:00）→ 排明天 10:00', () {
      final now = DateTime(2026, 6, 4, 21, 0);
      final next = CheckInReminderSchedule.nextReminderTime(
        now: now,
        hasCheckedInToday: true,
      );
      expect(next, DateTime(2026, 6, 5, 10, 0));
    });

    test('跨月邊界：6/30 晚於 10:00 未簽到 → 排 7/1 10:00', () {
      final now = DateTime(2026, 6, 30, 23, 59);
      final next = CheckInReminderSchedule.nextReminderTime(
        now: now,
        hasCheckedInToday: false,
      );
      expect(next, DateTime(2026, 7, 1, 10, 0));
    });
  });

  group('CheckInReminderSchedule 固定常數', () {
    test('notification id 固定為 10001', () {
      expect(CheckInReminderSchedule.notificationId, 10001);
    });

    test('payload 固定為 check_in_reminder', () {
      expect(CheckInReminderSchedule.payload, 'check_in_reminder');
    });

    test('每日提醒時間為 10:00', () {
      expect(CheckInReminderSchedule.hour, 10);
      expect(CheckInReminderSchedule.minute, 0);
    });

    test('文案符合規格、且不含工程字眼', () {
      expect(CheckInReminderSchedule.title, '早安，今天也來看看你的 AI 寵物吧');
      expect(CheckInReminderSchedule.body, '記得完成今日簽到，領取陪伴獎勵！');
      const forbidden = [
        'API error',
        'exception',
        'null',
        'debug',
        'token',
        'stack trace',
        'failed',
      ];
      for (final word in forbidden) {
        expect(CheckInReminderSchedule.title.toLowerCase(),
            isNot(contains(word.toLowerCase())));
        expect(CheckInReminderSchedule.body.toLowerCase(),
            isNot(contains(word.toLowerCase())));
      }
    });
  });
}
