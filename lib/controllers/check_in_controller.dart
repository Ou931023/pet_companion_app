import 'package:flutter/material.dart';

import '../models/check_in_record.dart';
import '../models/daily_reward.dart';
import '../models/shop_item.dart';
import '../services/check_in_storage_service.dart';
import '../services/shop_service.dart';
import 'inventory_controller.dart';
import 'pet_stats_controller.dart';
import 'wallet_controller.dart';

/// 一次成功簽到實際領到的獎勵（給 UI 顯示用）。
class CheckInClaim {
  const CheckInClaim({required this.coins, this.gift});

  final int coins;
  final ShopItem? gift;
}

class CheckInController extends ChangeNotifier {
  CheckInController(
    this._storageService, {
    ShopService shopService = const ShopService(),
  }) : _shopService = shopService;

  final CheckInStorageService _storageService;
  final ShopService _shopService;
  CheckInRecord _record = CheckInRecord.initial();
  MonthlyRewardTable? _rewardTable;
  CheckInClaim? _lastClaim;
  bool _isLoading = true;

  bool get isLoading => _isLoading;
  Set<String> get checkInDates => _record.checkInDates;
  String get todayKey => DateTime.now().toIso8601String().split('T').first;
  bool get hasCheckedInToday => _record.lastCheckInDate == todayKey;

  /// 本月的固定獎勵表（日曆 UI 用來顯示每天的金幣 / 禮物）。
  MonthlyRewardTable? get rewardTable => _rewardTable;

  /// 上一次成功簽到領到的獎勵（給「簽到成功」提示用）。
  CheckInClaim? get lastClaim => _lastClaim;

  /// 指定日期的獎勵（無資料回 null）。
  DailyReward? rewardForDay(int day) => _rewardTable?.forDay(day);

  Future<void> load() async {
    _isLoading = true;
    // 換帳號時也是走 load()：清掉上一個帳號的獎勵表 / 領取結果，
    // 強制依「目前帳號的 namespace」重新讀取或產生（不會看到別人的獎勵）。
    _rewardTable = null;
    _lastClaim = null;
    notifyListeners();
    _record = await _storageService.load();
    await _resetDailyCheckInIfNeeded();
    await _ensureRewardTable();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> refreshForDateChange() async {
    await _resetDailyCheckInIfNeeded();
    await _ensureRewardTable();
    notifyListeners();
  }

  Future<bool> checkIn({
    required WalletController walletController,
    required PetStatsController petStatsController,
    required InventoryController inventoryController,
  }) async {
    if (hasCheckedInToday) return false;
    await _ensureRewardTable();
    final today = DateTime.now();
    final reward = _rewardTable?.forDay(today.day);
    final coins = reward?.coins ?? 10;

    final updatedDates = <String>{..._record.checkInDates, todayKey};
    _record = _record.copyWith(
      checkInDates: updatedDates,
      lastCheckInDate: todayKey,
    );
    await walletController.addCoins(coins);
    await petStatsController.applyCheckInReward();

    ShopItem? gift;
    if (reward != null && reward.hasGift && reward.giftItemId != null) {
      gift = _giftForId(reward.giftItemId!);
      if (gift != null) {
        await inventoryController.addFromShop(gift);
      }
    }

    _lastClaim = CheckInClaim(coins: coins, gift: gift);
    await _storageService.save(_record);
    notifyListeners();
    return true;
  }

  /// 可作為簽到禮物的商城商品（排除只在寵物昏迷時才用的道具，避免送出怪禮物）。
  List<ShopItem> _giftPool() =>
      _shopService.allItems().where((item) => !item.onlyWhenDead).toList();

  ShopItem? _giftForId(String id) {
    for (final item in _giftPool()) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// 確保本月獎勵表已就緒：先讀已存的，沒有才依「帳號 + 年月」產生並存回。
  /// 同一帳號同一月每天獎勵固定；跨月會換成新的一張表。
  Future<void> _ensureRewardTable() async {
    final now = DateTime.now();
    if (_rewardTable?.year == now.year && _rewardTable?.month == now.month) {
      return;
    }
    var table = await _storageService.loadRewardTable(now.year, now.month);
    if (table == null) {
      table = MonthlyRewardTable.generate(
        year: now.year,
        month: now.month,
        elderId: _storageService.userId,
        giftPool: _giftPool(),
      );
      await _storageService.saveRewardTable(table);
    }
    _rewardTable = table;
  }

  Future<void> _resetDailyCheckInIfNeeded() async {
    final last = _record.lastCheckInDate;
    if (last == null || last == todayKey) return;
    _record = _record.copyWith(clearLastCheckInDate: true);
    await _storageService.save(_record);
  }
}
