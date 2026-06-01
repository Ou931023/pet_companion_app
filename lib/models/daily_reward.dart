import 'dart:math';

import 'shop_item.dart';

/// 單一日期的簽到獎勵。
///
/// - [coins]：當天可領的金幣（一般日 10–25、每週一 25–40）。
/// - [hasGift]：是否為「禮物日」（每 4 天一次：4、8、12…）。
/// - [giftItemId]：禮物日預先決定好的商城商品 id（固定不變，領取時才真正放進背包）。
class DailyReward {
  const DailyReward({
    required this.day,
    required this.coins,
    required this.hasGift,
    this.giftItemId,
  });

  final int day;
  final int coins;
  final bool hasGift;
  final String? giftItemId;

  Map<String, dynamic> toJson() => {
        'day': day,
        'coins': coins,
        'hasGift': hasGift,
        if (giftItemId != null) 'giftItemId': giftItemId,
      };

  factory DailyReward.fromJson(Map<String, dynamic> json) {
    return DailyReward(
      day: (json['day'] as num).toInt(),
      coins: (json['coins'] as num).toInt(),
      hasGift: json['hasGift'] == true,
      giftItemId: json['giftItemId'] as String?,
    );
  }
}

/// 一整個月的簽到獎勵表。
///
/// 同一帳號、同一月份每天的獎勵必須「固定」——重開頁面不會重新隨機。
/// 透過 [generate] 以「帳號 + 年月」推導出穩定亂數種子，確保即使資料被清掉、
/// 重新產生也會得到一模一樣的結果；產生後也會被儲存（依 elderId 隔離）。
class MonthlyRewardTable {
  const MonthlyRewardTable({
    required this.year,
    required this.month,
    required this.rewards,
  });

  final int year;
  final int month;
  final Map<int, DailyReward> rewards;

  DailyReward? forDay(int day) => rewards[day];

  /// 是否為禮物日（每 4 天一次）。
  static bool isGiftDay(int day) => day % 4 == 0;

  /// 是否為每週第一天（以週一為準）。
  static bool isWeekStart(int year, int month, int day) =>
      DateTime(year, month, day).weekday == DateTime.monday;

  /// 依「帳號 + 年月」產生固定的整月獎勵表。
  ///
  /// [giftPool] 為可作為禮物的商城商品（呼叫端會先濾掉不適合的，例如只在寵物
  /// 昏迷時用的道具）。若 [giftPool] 為空，禮物日仍標記 hasGift 但 giftItemId 為 null。
  factory MonthlyRewardTable.generate({
    required int year,
    required int month,
    required String elderId,
    required List<ShopItem> giftPool,
  }) {
    final rng = Random(_stableSeed('$elderId|$year|$month'));
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final rewards = <int, DailyReward>{};
    for (var day = 1; day <= daysInMonth; day++) {
      final weekStart = isWeekStart(year, month, day);
      // 每週一 25–40，一般日 10–25。
      final coins =
          weekStart ? 25 + rng.nextInt(16) : 10 + rng.nextInt(16);
      final gift = isGiftDay(day);
      String? giftItemId;
      if (gift && giftPool.isNotEmpty) {
        giftItemId = giftPool[rng.nextInt(giftPool.length)].id;
      }
      rewards[day] = DailyReward(
        day: day,
        coins: coins,
        hasGift: gift,
        giftItemId: giftItemId,
      );
    }
    return MonthlyRewardTable(year: year, month: month, rewards: rewards);
  }

  Map<String, dynamic> toJson() => {
        'year': year,
        'month': month,
        'rewards':
            rewards.map((day, reward) => MapEntry('$day', reward.toJson())),
      };

  factory MonthlyRewardTable.fromJson(Map<String, dynamic> json) {
    final rawRewards = (json['rewards'] as Map?) ?? const {};
    final rewards = <int, DailyReward>{};
    rawRewards.forEach((key, value) {
      final day = int.tryParse(key.toString());
      if (day == null || value is! Map) return;
      rewards[day] =
          DailyReward.fromJson(Map<String, dynamic>.from(value));
    });
    return MonthlyRewardTable(
      year: (json['year'] as num).toInt(),
      month: (json['month'] as num).toInt(),
      rewards: rewards,
    );
  }
}

/// 穩定的 32-bit FNV-1a 雜湊：同樣的字串永遠得到同樣的種子（不依賴 Dart
/// 內建 hashCode 在不同執行間可能不同的特性），確保獎勵可重現。
int _stableSeed(String input) {
  var hash = 0x811c9dc5;
  for (final unit in input.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}
