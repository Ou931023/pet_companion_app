/// CR-0031 每日簽到提醒的純邏輯（時間計算 + 固定常數）。
///
/// 做法 B：每天「預先排程」一則 10:00 的本機通知，已簽到就取消今天那一則。
/// 把「下一次 10:00 是今天還是明天」這段純計算抽出來，方便單元測試，
/// 不依賴 flutter_local_notifications / timezone，可在純 Dart 測試直接驗證。
class CheckInReminderSchedule {
  const CheckInReminderSchedule._();

  /// 固定的通知 id（規格要求 10001，全 App 只用這一個簽到提醒 id）。
  static const int notificationId = 10001;

  /// 點擊通知時可辨識來源的 payload。
  static const String payload = 'check_in_reminder';

  /// 每日提醒時間：當地時間 10:00。
  static const int hour = 10;
  static const int minute = 0;

  /// 通知文案（繁體中文、溫暖、長者友善）。
  static const String title = '早安，今天也來看看你的 AI 寵物吧';
  static const String body = '記得完成今日簽到，領取陪伴獎勵！';

  /// 計算「下一次 10:00 簽到通知」的日期時間（以手機當地時間語意表示）。
  ///
  /// 規則：
  /// - 今天已簽到（[hasCheckedInToday] == true）：一律排明天 10:00
  ///   （今天不需要再提醒，避免提醒已完成的事）。
  /// - 今天未簽到：
  ///   - 現在早於今天 10:00 → 排今天 10:00。
  ///   - 現在已過今天 10:00 → 排明天 10:00（不排在過去的時間）。
  static DateTime nextReminderTime({
    required DateTime now,
    required bool hasCheckedInToday,
  }) {
    final tenToday = DateTime(now.year, now.month, now.day, hour, minute);
    if (hasCheckedInToday) {
      return tenToday.add(const Duration(days: 1));
    }
    if (now.isBefore(tenToday)) {
      return tenToday;
    }
    return tenToday.add(const Duration(days: 1));
  }
}
