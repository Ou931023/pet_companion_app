import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/controllers/check_in_controller.dart';
import 'package:pet_companion_app/controllers/inventory_controller.dart';
import 'package:pet_companion_app/controllers/pet_stats_controller.dart';
import 'package:pet_companion_app/controllers/profile_controller.dart';
import 'package:pet_companion_app/controllers/wallet_controller.dart';
import 'package:pet_companion_app/models/daily_reward.dart';
import 'package:pet_companion_app/services/check_in_storage_service.dart';
import 'package:pet_companion_app/services/inventory_storage_service.dart';
import 'package:pet_companion_app/services/local_storage_service.dart';
import 'package:pet_companion_app/services/pet_stats_storage_service.dart';
import 'package:pet_companion_app/services/shop_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Harness {
  _Harness()
      : storage = CheckInStorageService(),
        inventory = InventoryController(InventoryStorageService()),
        petStats = PetStatsController(PetStatsStorageService()) {
    final profile = ProfileController(LocalStorageService());
    wallet = WalletController(profile);
    controller = CheckInController(storage, shopService: const ShopService());
  }

  final CheckInStorageService storage;
  final InventoryController inventory;
  final PetStatsController petStats;
  late final WalletController wallet;
  late final CheckInController controller;

  Future<bool> claim() => controller.checkIn(
        walletController: wallet,
        petStatsController: petStats,
        inventoryController: inventory,
      );
}

/// 預存一張「今天」為指定獎勵的當月表，讓簽到行為可被精準驗證
/// （checkIn 用真實的今天日期）。
Future<void> _seedToday(
  CheckInStorageService storage, {
  required int coins,
  required bool hasGift,
  String? giftItemId,
}) async {
  final now = DateTime.now();
  await storage.saveRewardTable(MonthlyRewardTable(
    year: now.year,
    month: now.month,
    rewards: {
      now.day: DailyReward(
        day: now.day,
        coins: coins,
        hasGift: hasGift,
        giftItemId: giftItemId,
      ),
    },
  ));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('簽到發放當日金幣並記錄已簽到，重複簽到回 false', () async {
    final h = _Harness();
    await _seedToday(h.storage, coins: 18, hasGift: false);
    await h.controller.load();

    final before = h.wallet.coins;
    final ok = await h.claim();

    expect(ok, isTrue);
    expect(h.wallet.coins, before + 18);
    expect(h.controller.hasCheckedInToday, isTrue);
    expect(h.controller.lastClaim?.coins, 18);
    expect(h.controller.lastClaim?.gift, isNull);

    // 同一天再簽到 → 擋下。
    expect(await h.claim(), isFalse);
  });

  test('禮物日簽到：發金幣並把指定商品放進背包', () async {
    final h = _Harness();
    await _seedToday(h.storage, coins: 33, hasGift: true, giftItemId: 'cookie');
    await h.controller.load();

    final before = h.wallet.coins;
    final ok = await h.claim();

    expect(ok, isTrue);
    expect(h.wallet.coins, before + 33);
    expect(h.inventory.items.any((i) => i.itemId == 'cookie'), isTrue);
    expect(h.controller.lastClaim?.gift?.id, 'cookie');
  });

  test('rewardForDay 反映當月表', () async {
    final h = _Harness();
    final now = DateTime.now();
    await _seedToday(h.storage, coins: 27, hasGift: true, giftItemId: 'juice');
    await h.controller.load();

    expect(h.controller.rewardForDay(now.day)?.coins, 27);
    expect(h.controller.rewardForDay(now.day)?.hasGift, isTrue);
  });

  test('沒有預存表時會自動產生並持久化，重載結果一致', () async {
    final now = DateTime.now();
    final h1 = _Harness();
    await h1.controller.load(); // 產生並存回
    final firstCoins = h1.controller.rewardForDay(now.day)?.coins;
    expect(firstCoins, isNotNull);

    // 另一個 controller 共用同一帳號 namespace → 讀到同一張表。
    final h2 = _Harness();
    await h2.controller.load();
    expect(h2.controller.rewardForDay(now.day)?.coins, firstCoins);
  });

  test('每月 reward 表依 elderId 隔離：A 的表不會被 B 讀到', () async {
    final storage = CheckInStorageService();
    final now = DateTime.now();

    storage.setUserId('elder-A');
    await storage.saveRewardTable(MonthlyRewardTable(
      year: now.year,
      month: now.month,
      rewards: {1: const DailyReward(day: 1, coins: 99, hasGift: false)},
    ));

    storage.setUserId('elder-B');
    expect(await storage.loadRewardTable(now.year, now.month), isNull);

    storage.setUserId('elder-A');
    final table = await storage.loadRewardTable(now.year, now.month);
    expect(table?.forDay(1)?.coins, 99);

    // Demo / 未登入（default_user）也是獨立。
    storage.setUserId('default_user');
    expect(await storage.loadRewardTable(now.year, now.month), isNull);
  });
}
