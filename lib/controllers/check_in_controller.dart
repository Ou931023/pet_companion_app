import 'package:flutter/material.dart';

import '../models/check_in_record.dart';
import '../services/check_in_storage_service.dart';
import 'pet_stats_controller.dart';
import 'wallet_controller.dart';

class CheckInController extends ChangeNotifier {
  CheckInController(this._storageService);

  final CheckInStorageService _storageService;
  CheckInRecord _record = CheckInRecord.initial();
  bool _isLoading = true;

  bool get isLoading => _isLoading;
  Set<String> get checkInDates => _record.checkInDates;
  String get todayKey => DateTime.now().toIso8601String().split('T').first;
  bool get hasCheckedInToday => _record.lastCheckInDate == todayKey;

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    _record = await _storageService.load();
    await _resetDailyCheckInIfNeeded();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> refreshForDateChange() async {
    await _resetDailyCheckInIfNeeded();
    notifyListeners();
  }

  Future<bool> checkIn({
    required WalletController walletController,
    required PetStatsController petStatsController,
  }) async {
    if (hasCheckedInToday) return false;
    final updatedDates = <String>{..._record.checkInDates, todayKey};
    _record = _record.copyWith(
      checkInDates: updatedDates,
      lastCheckInDate: todayKey,
    );
    await walletController.addCoins(10);
    await petStatsController.applyCheckInReward();
    await _storageService.save(_record);
    notifyListeners();
    return true;
  }

  Future<void> _resetDailyCheckInIfNeeded() async {
    final last = _record.lastCheckInDate;
    if (last == null || last == todayKey) return;
    _record = _record.copyWith(clearLastCheckInDate: true);
    await _storageService.save(_record);
  }
}
