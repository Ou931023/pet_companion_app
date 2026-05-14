import 'package:flutter/material.dart';

import '../models/pet_stats.dart';
import '../services/pet_stats_storage_service.dart';

class PetStatsController extends ChangeNotifier {
  PetStatsController(this._storageService);

  final PetStatsStorageService _storageService;
  PetStats _stats = PetStats.initial();
  bool _isLoading = true;

  PetStats get stats => _stats;
  bool get isLoading => _isLoading;
  int get intimacy => _stats.intimacy;
  int get fullness => _stats.fullness;
  int get moodValue => _stats.moodValue;
  PetLifeState get lifeState => _stats.lifeState;
  bool get isDead => lifeState == PetLifeState.dead;

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    _stats = await _storageService.load();
    await _applyDailyDecayIfNeeded();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> applyCheckInReward() async {
    await _applyDelta(intimacyDelta: 5, moodDelta: 3);
  }

  Future<void> markRealtimeConversationCompleted() async {
    if (isDead) return;
    await _applyDelta(intimacyDelta: 2, moodDelta: 2);
  }

  Future<void> applyConversationEmotion(String emotion) async {
    if (isDead) return;
    final moodDelta = switch (emotion) {
      'happy' => 4,
      'sad' => -2,
      'lonely' => -1,
      'anxious' => -1,
      'tired' => -1,
      'angry' => -2,
      _ => 1,
    };
    await _applyDelta(intimacyDelta: 1, moodDelta: moodDelta);
  }

  Future<void> markPuzzleCompleted() async {
    if (isDead) return;
    await _applyDelta(intimacyDelta: 2, moodDelta: 5);
  }

  Future<void> applyShopEffects({
    int intimacyDelta = 0,
    int fullnessDelta = 0,
    int moodDelta = 0,
  }) async {
    await _applyDelta(
      intimacyDelta: intimacyDelta,
      fullnessDelta: fullnessDelta,
      moodDelta: moodDelta,
    );
  }

  Future<void> revive() async {
    _stats = _stats.copyWith(intimacy: 30, fullness: 40, moodValue: 40);
    await _persist();
  }

  Future<void> _applyDailyDecayIfNeeded() async {
    final today = _todayKey();
    final last = _stats.lastOpenedDate;
    if (last == today) return;

    if (last != null) {
      final todayDate = DateTime.tryParse(today);
      final lastDate = DateTime.tryParse(last);
      if (todayDate != null && lastDate != null) {
        final days = todayDate.difference(lastDate).inDays;
        if (days >= 1) {
          _stats = _stats.copyWith(
            intimacy: _clamp(_stats.intimacy - 5),
            fullness: _clamp(_stats.fullness - 8),
            moodValue: _clamp(_stats.moodValue - 5),
          );
        }
      }
    }
    _stats = _stats.copyWith(lastOpenedDate: today);
    await _persist();
  }

  Future<void> _applyDelta({
    int intimacyDelta = 0,
    int fullnessDelta = 0,
    int moodDelta = 0,
  }) async {
    _stats = _stats.copyWith(
      intimacy: _clamp(_stats.intimacy + intimacyDelta),
      fullness: _clamp(_stats.fullness + fullnessDelta),
      moodValue: _clamp(_stats.moodValue + moodDelta),
    );
    await _persist();
  }

  Future<void> _persist() async {
    await _storageService.save(_stats);
    notifyListeners();
  }

  int _clamp(int value) => value.clamp(0, 100);

  String _todayKey() => DateTime.now().toIso8601String().split('T').first;
}
