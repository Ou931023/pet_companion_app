/// CR-0087：寵物關心提醒的純邏輯（決策 + 固定常數 + 文案）。
///
/// 這是「通知長者本人」的本地陪伴提醒，**不是 Care Alert、不是 Telegram、不是後端通知**。
/// 把「現在該不該發、發哪一種、用哪一句」這段純計算抽出來，不依賴
/// flutter_local_notifications / timezone，可在純 Dart 測試直接驗證決策。
///
/// 與每日簽到提醒（[CheckInReminderSchedule]，id 10001）完全分開：本類用 id 10002、
/// 自己的 channel，互不干擾。
library;

/// 寵物關心提醒的類型（同時也是優先順序：愈前面愈優先）。
enum PetConcernType { lowMood, lowSatiety, inactiveInteraction, lowIntimacy }

extension PetConcernTypeX on PetConcernType {
  /// 存進 cooldown 紀錄用的穩定字串。
  String get key => switch (this) {
        PetConcernType.lowMood => 'low_mood_care',
        PetConcernType.lowSatiety => 'low_satiety',
        PetConcernType.inactiveInteraction => 'inactive_interaction',
        PetConcernType.lowIntimacy => 'low_intimacy',
      };
}

/// 一次決策的結果。[shouldNotify] 為 false 時其餘欄位無意義。
class PetConcernDecision {
  const PetConcernDecision._({
    required this.shouldNotify,
    this.type,
    this.title = '',
    this.body = '',
  });

  const PetConcernDecision.none() : this._(shouldNotify: false);

  final bool shouldNotify;
  final PetConcernType? type;
  final String title;
  final String body;
}

class PetConcernNotificationPolicy {
  const PetConcernNotificationPolicy._();

  // ── 固定常數（通知排程層共用）──────────────────────────────
  /// 寵物關心提醒固定 id（與簽到提醒 10001 區隔）。
  static const int notificationId = 10002;
  static const String payload = 'pet_concern_reminder';
  static const String channelId = 'pet_concern_reminders';
  static const String channelName = '寵物關心提醒';

  /// 判定離開 App 後多久才真的跳出關心提醒（太早跳會打擾；回到 App 會先取消）。
  static const Duration scheduleDelay = Duration(hours: 2);

  // ── 觸發門檻 ──────────────────────────────────────────────
  static const int moodThreshold = 30;
  static const int satietyThreshold = 30;
  static const int intimacyThreshold = 30;
  static const double inactiveHoursThreshold = 24;

  /// 低落情緒線索（未達 Care Alert 高風險，僅作溫和陪伴提醒）。
  static const Set<String> lowEmotions = {'sad', 'anxious', 'lonely', 'tired'};

  // ── 各類型 cooldown（避免打擾）────────────────────────────
  static const Duration lowMoodCooldown = Duration(hours: 6);
  static const Duration lowSatietyCooldown = Duration(hours: 4);
  static const Duration lowIntimacyCooldown = Duration(hours: 24);
  static const Duration inactiveCooldown = Duration(hours: 24);

  /// 全體寵物關心提醒：每 2 小時最多一則。
  static const Duration overallCooldown = Duration(hours: 2);

  static Duration cooldownFor(PetConcernType type) => switch (type) {
        PetConcernType.lowMood => lowMoodCooldown,
        PetConcernType.lowSatiety => lowSatietyCooldown,
        PetConcernType.inactiveInteraction => inactiveCooldown,
        PetConcernType.lowIntimacy => lowIntimacyCooldown,
      };

  // ── 文案（繁中、溫暖、長者友善；不得出現工程字）──────────────
  static const Map<PetConcernType, String> _titles = {
    PetConcernType.lowMood: '小夥伴有點擔心你',
    PetConcernType.lowSatiety: '寵物肚子餓了',
    PetConcernType.inactiveInteraction: '今天還沒看到你',
    PetConcernType.lowIntimacy: '寵物有點想你',
  };

  static const Map<PetConcernType, List<String>> _bodies = {
    PetConcernType.lowMood: [
      '小夥伴有點擔心你，想陪你說說話。',
      '聽起來你今天有點累，寵物想陪你一下。',
      '如果你願意，可以回來和寵物聊聊。',
    ],
    PetConcernType.lowSatiety: [
      '你的寵物肚子有點餓了，回來看看牠吧！',
      '小夥伴想吃點東西，也想看看你。',
      '寵物在等你回來照顧牠。',
    ],
    PetConcernType.inactiveInteraction: [
      '今天還沒看到你，寵物有點想你了。',
      '要不要打開 App，和寵物說幾句話？',
      '小夥伴在等你回來。',
    ],
    PetConcernType.lowIntimacy: [
      '你的寵物好像有點想你了，來陪牠聊聊天吧。',
      '今天還沒和寵物說說話，要不要回來看看牠？',
      '小夥伴在等你，想和你聊幾句。',
    ],
  };

  static String titleFor(PetConcernType type) => _titles[type] ?? '寵物想你了';

  /// 依日期挑一句（同一天固定、不同天輪替），保持可測且不重複洗版。
  static String bodyFor(PetConcernType type, DateTime now) {
    final list = _bodies[type] ?? const ['寵物想你了，回來看看牠吧。'];
    final index = now.day % list.length;
    return list[index];
  }

  /// 決定現在該不該發、發哪一種寵物關心提醒。
  ///
  /// 設計原則：
  /// - 關閉（[enabled] == false）→ 一律不發。
  /// - 全體 cooldown：距上次任何關心提醒不足 [overallCooldown] → 不發。
  /// - 依優先順序（lowMood → lowSatiety → inactive → lowIntimacy）取第一個
  ///   「條件成立且該類型 cooldown 已過」者。
  /// - 資料缺漏（null）→ 該類型不觸發（不捏造狀態硬發）。
  ///
  /// 參數：
  /// - [moodValue] / [satiety] / [intimacy]：寵物數值 0..100，未知傳 null。
  /// - [latestEmotionTag]：最近一次情緒分析標籤（happy/sad/...），未知傳 null。
  /// - [hoursSinceLastInteraction]：距最近一次互動的小時數，未知傳 null。
  /// - [hasInteractedToday]：今天是否已與寵物互動（low_intimacy 需「今日未互動」）。
  /// - [lastSentByType] / [lastAnySent]：cooldown 紀錄（上次各類型 / 任何一則的時間）。
  static PetConcernDecision evaluate({
    required bool enabled,
    required int? moodValue,
    required int? satiety,
    required int? intimacy,
    required String? latestEmotionTag,
    required double? hoursSinceLastInteraction,
    required bool hasInteractedToday,
    required DateTime now,
    required Map<PetConcernType, DateTime?> lastSentByType,
    required DateTime? lastAnySent,
  }) {
    if (!enabled) return const PetConcernDecision.none();

    // 全體 cooldown：2 小時內已發過任何一則 → 先不打擾。
    if (lastAnySent != null && now.difference(lastAnySent) < overallCooldown) {
      return const PetConcernDecision.none();
    }

    for (final type in PetConcernType.values) {
      if (!_triggerHolds(
        type,
        moodValue: moodValue,
        satiety: satiety,
        intimacy: intimacy,
        latestEmotionTag: latestEmotionTag,
        hoursSinceLastInteraction: hoursSinceLastInteraction,
        hasInteractedToday: hasInteractedToday,
      )) {
        continue;
      }
      final last = lastSentByType[type];
      if (last != null && now.difference(last) < cooldownFor(type)) {
        continue; // 該類型仍在 cooldown 內
      }
      return PetConcernDecision._(
        shouldNotify: true,
        type: type,
        title: titleFor(type),
        body: bodyFor(type, now),
      );
    }
    return const PetConcernDecision.none();
  }

  static bool _triggerHolds(
    PetConcernType type, {
    required int? moodValue,
    required int? satiety,
    required int? intimacy,
    required String? latestEmotionTag,
    required double? hoursSinceLastInteraction,
    required bool hasInteractedToday,
  }) {
    switch (type) {
      case PetConcernType.lowMood:
        final byValue = moodValue != null && moodValue < moodThreshold;
        final byEmotion =
            latestEmotionTag != null && lowEmotions.contains(latestEmotionTag);
        return byValue || byEmotion;
      case PetConcernType.lowSatiety:
        return satiety != null && satiety < satietyThreshold;
      case PetConcernType.inactiveInteraction:
        return hoursSinceLastInteraction != null &&
            hoursSinceLastInteraction >= inactiveHoursThreshold;
      case PetConcernType.lowIntimacy:
        return intimacy != null &&
            intimacy < intimacyThreshold &&
            !hasInteractedToday;
    }
  }
}
