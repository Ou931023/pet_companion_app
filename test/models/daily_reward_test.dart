import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/models/daily_reward.dart';
import 'package:pet_companion_app/models/shop_item.dart';

const _pool = [
  ShopItem(id: 'cookie', name: '小餅乾', emoji: '🍪', category: '食物', price: 20),
  ShopItem(id: 'juice', name: '果汁', emoji: '🧃', category: '飲料', price: 30),
];

void main() {
  group('MonthlyRewardTable.generate', () {
    test('同帳號同月份每天獎勵固定（可重現）', () {
      final a = MonthlyRewardTable.generate(
          year: 2026, month: 6, elderId: 'elder-A', giftPool: _pool);
      final b = MonthlyRewardTable.generate(
          year: 2026, month: 6, elderId: 'elder-A', giftPool: _pool);

      for (var day = 1; day <= 30; day++) {
        expect(a.forDay(day)!.coins, b.forDay(day)!.coins,
            reason: 'day $day coins 應固定');
        expect(a.forDay(day)!.hasGift, b.forDay(day)!.hasGift);
        expect(a.forDay(day)!.giftItemId, b.forDay(day)!.giftItemId);
      }
    });

    test('每 4 天為禮物日（4,8,12,…），並指定固定商品', () {
      final table = MonthlyRewardTable.generate(
          year: 2026, month: 6, elderId: 'elder-A', giftPool: _pool);
      for (final day in [4, 8, 12, 16, 20, 24, 28]) {
        expect(table.forDay(day)!.hasGift, isTrue, reason: 'day $day 應為禮物日');
        expect(table.forDay(day)!.giftItemId, isNotNull);
        expect(['cookie', 'juice'], contains(table.forDay(day)!.giftItemId));
      }
      // 非 4 的倍數不是禮物日。
      for (final day in [1, 2, 3, 5, 7, 9, 15]) {
        expect(table.forDay(day)!.hasGift, isFalse);
        expect(table.forDay(day)!.giftItemId, isNull);
      }
    });

    test('每週一 25–40 金幣，一般日 10–25 金幣', () {
      final table = MonthlyRewardTable.generate(
          year: 2026, month: 6, elderId: 'elder-A', giftPool: _pool);
      final daysInMonth = DateTime(2026, 7, 0).day;
      for (var day = 1; day <= daysInMonth; day++) {
        final coins = table.forDay(day)!.coins;
        final isMonday = DateTime(2026, 6, day).weekday == DateTime.monday;
        if (isMonday) {
          expect(coins, inInclusiveRange(25, 40), reason: '週一 day $day');
        } else {
          expect(coins, inInclusiveRange(10, 25), reason: '一般日 day $day');
        }
      }
    });

    test('禮物池為空時仍標記禮物日，但 giftItemId 為 null', () {
      final table = MonthlyRewardTable.generate(
          year: 2026, month: 6, elderId: 'elder-A', giftPool: const []);
      expect(table.forDay(8)!.hasGift, isTrue);
      expect(table.forDay(8)!.giftItemId, isNull);
    });

    test('toJson / fromJson 來回一致', () {
      final table = MonthlyRewardTable.generate(
          year: 2026, month: 6, elderId: 'elder-A', giftPool: _pool);
      final restored = MonthlyRewardTable.fromJson(table.toJson());
      expect(restored.year, 2026);
      expect(restored.month, 6);
      for (var day = 1; day <= 30; day++) {
        expect(restored.forDay(day)!.coins, table.forDay(day)!.coins);
        expect(restored.forDay(day)!.hasGift, table.forDay(day)!.hasGift);
        expect(restored.forDay(day)!.giftItemId, table.forDay(day)!.giftItemId);
      }
    });
  });
}
