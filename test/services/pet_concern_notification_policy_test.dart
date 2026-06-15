import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/services/pet_concern_notification_policy.dart';

// CR-0087：寵物關心提醒「決策」純邏輯測試（無 plugin / 無 binding）。
// 涵蓋：各類型觸發、優先序、cooldown、多條件擇一、無資料不亂發、關閉不發。

void main() {
  final now = DateTime(2026, 6, 15, 20, 0); // 固定錨點，文案輪替可重現

  // 沒有任何 cooldown 紀錄（從未發過）。
  Map<PetConcernType, DateTime?> noCooldowns() => {
        for (final t in PetConcernType.values) t: null,
      };

  PetConcernDecision evalWith({
    bool enabled = true,
    int? mood = 60,
    int? satiety = 60,
    int? intimacy = 60,
    String? emotion,
    double? hoursSince = 1,
    bool interactedToday = true,
    Map<PetConcernType, DateTime?>? lastByType,
    DateTime? lastAny,
  }) {
    return PetConcernNotificationPolicy.evaluate(
      enabled: enabled,
      moodValue: mood,
      satiety: satiety,
      intimacy: intimacy,
      latestEmotionTag: emotion,
      hoursSinceLastInteraction: hoursSince,
      hasInteractedToday: interactedToday,
      now: now,
      lastSentByType: lastByType ?? noCooldowns(),
      lastAnySent: lastAny,
    );
  }

  test('狀態正常 → 不發任何關心提醒', () {
    final d = evalWith();
    expect(d.shouldNotify, isFalse);
    expect(d.type, isNull);
  });

  test('心情低落（mood < 30）→ low_mood_care，且文案非空、無工程字', () {
    final d = evalWith(mood: 20);
    expect(d.shouldNotify, isTrue);
    expect(d.type, PetConcernType.lowMood);
    expect(d.title.isNotEmpty, isTrue);
    expect(d.body.isNotEmpty, isTrue);
    expect(d.body.contains('mood'), isFalse);
    expect(d.body.contains('<'), isFalse);
  });

  test('情緒分析為 sad（mood 不低）也觸發 low_mood_care', () {
    final d = evalWith(mood: 60, emotion: 'sad');
    expect(d.type, PetConcernType.lowMood);
  });

  test('飽足度低（satiety < 30）→ low_satiety', () {
    final d = evalWith(satiety: 20);
    expect(d.type, PetConcernType.lowSatiety);
  });

  test('親密度低且今日未互動 → low_intimacy', () {
    final d = evalWith(intimacy: 20, interactedToday: false, hoursSince: 5);
    expect(d.type, PetConcernType.lowIntimacy);
  });

  test('親密度低但今日已互動 → 不觸發 low_intimacy（無其他條件 → 不發）', () {
    final d = evalWith(intimacy: 20, interactedToday: true);
    expect(d.shouldNotify, isFalse);
  });

  test('長時間未互動（>= 24h）→ inactive_interaction', () {
    final d = evalWith(hoursSince: 30, interactedToday: false);
    expect(d.type, PetConcernType.inactiveInteraction);
  });

  test('多條件同時成立 → 依優先序只選 low_mood', () {
    final d = evalWith(
      mood: 10,
      satiety: 10,
      intimacy: 10,
      interactedToday: false,
      hoursSince: 30,
    );
    expect(d.type, PetConcernType.lowMood);
  });

  test('該類型 cooldown 內 → 不重複發（lowMood 1h 前發過，cooldown 6h）', () {
    final d = evalWith(
      mood: 10,
      lastByType: {
        ...noCooldowns(),
        PetConcernType.lowMood: now.subtract(const Duration(hours: 1)),
      },
      lastAny: now.subtract(const Duration(hours: 3)), // 全體 cooldown 已過
    );
    expect(d.shouldNotify, isFalse);
  });

  test('cooldown 已過 → 可再發（lowMood 7h 前發過）', () {
    final d = evalWith(
      mood: 10,
      lastByType: {
        ...noCooldowns(),
        PetConcernType.lowMood: now.subtract(const Duration(hours: 7)),
      },
      lastAny: now.subtract(const Duration(hours: 7)),
    );
    expect(d.type, PetConcernType.lowMood);
  });

  test('全體 cooldown：2h 內已發過任何一則 → 一律不發', () {
    final d = evalWith(
      satiety: 10,
      lastAny: now.subtract(const Duration(minutes: 30)),
    );
    expect(d.shouldNotify, isFalse);
  });

  test('關閉寵物關心提醒（enabled=false）→ 不發', () {
    final d = evalWith(enabled: false, mood: 5, satiety: 5, intimacy: 5);
    expect(d.shouldNotify, isFalse);
  });

  test('無資料（全 null）→ 不崩潰、不亂發', () {
    final d = evalWith(
      mood: null,
      satiety: null,
      intimacy: null,
      emotion: null,
      hoursSince: null,
      interactedToday: false,
    );
    expect(d.shouldNotify, isFalse);
  });

  test('飽足度資料缺漏（satiety=null）→ 不因缺資料硬觸發 low_satiety', () {
    final d = evalWith(satiety: null, mood: 60, intimacy: 60);
    expect(d.shouldNotify, isFalse);
  });
}
