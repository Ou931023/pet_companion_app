import 'dart:async';

import 'package:flutter/material.dart';

import '../models/pet_skin.dart';
import '../models/pet_state.dart';
import '../models/pet_status.dart';
import '../services/local_storage_service.dart';

class PetController extends ChangeNotifier {
  /// [storageService] 可省略：UI / 單元測試不需要持久化時用 `PetController()` 即可，
  /// 外觀會維持預設狗狗。實際 App 會注入 storage 以記住每個帳號各自的外觀。
  PetController({LocalStorageService? storageService})
      : _storageService = storageService;

  final LocalStorageService? _storageService;

  PetState _state = const PetState(
    mode: PetMode.rest,
    message: '準備好開始今天的陪伴了嗎？',
  );
  Timer? _idleTimer;
  String _mood = 'neutral';
  String _expression = 'normal';
  String _action = 'idle';
  PetSkin _currentSkin = PetSkin.dog;
  Set<PetSkin> _ownedSkins = {PetSkin.dog};

  PetState get state => _state;
  PetMode get mode => _state.mode;
  String get message => _state.message;
  String get mood => _mood;
  String get expression => _expression;
  String get action => _action;

  /// 目前寵物外觀，預設狗狗。
  PetSkin get currentSkin => _currentSkin;

  /// 已擁有 / 已解鎖的外觀（狗狗永遠在內）。未擁有的需購買 / 解鎖才能套用。
  Set<PetSkin> get ownedSkins => Set.unmodifiable(_ownedSkins);

  bool isOwned(PetSkin skin) => _ownedSkins.contains(skin);

  /// 載入目前帳號（elderId）保存的外觀與已擁有清單；
  /// 沒有 storage 或沒存過 → 狗狗、且只擁有狗狗。
  /// 防呆：若存到的目前外觀不在已擁有清單內，退回狗狗。
  Future<void> loadSkin() async {
    final storage = _storageService;
    if (storage == null) return;
    final owned = await storage.loadOwnedPetSkins();
    final skin = await storage.loadPetSkin();
    _ownedSkins = {PetSkin.dog, ...owned};
    final resolved = _ownedSkins.contains(skin) ? skin : PetSkin.dog;
    if (resolved == _currentSkin && _ownedSkins.length == 1) return;
    _currentSkin = resolved;
    notifyListeners();
  }

  /// 立即套用外觀（長者點一下就生效）。**只有已擁有的外觀**才能套用；
  /// 未擁有時回傳 false、不做任何事（未擁有要走 [purchaseAndApplySkin]）。
  Future<bool> changeSkin(PetSkin skin) async {
    if (!isOwned(skin)) return false;
    if (skin == _currentSkin) return true;
    _currentSkin = skin;
    notifyListeners();
    await saveSkin();
    return true;
  }

  /// 新手導覽「選夥伴」：免費把選到的外觀設成起始夥伴（解鎖 + 套用），不扣點。
  Future<void> selectStarterSkin(PetSkin skin) async {
    await _unlock(skin);
    await changeSkin(skin);
  }

  /// 購買並套用未擁有的外觀：用注入的 [spendCoins] 扣點（沿用既有 wallet）。
  /// - 已擁有 → 直接套用（[SkinPurchaseResult.applied]）。
  /// - 點數足夠 → 扣點、解鎖、套用（[SkinPurchaseResult.purchasedAndApplied]）。
  /// - 點數不足 → 不扣點、不解鎖（[SkinPurchaseResult.insufficientCoins]）。
  ///
  /// 「購買前確認」由 UI 在呼叫此方法前處理（避免直接扣點）。
  Future<SkinPurchaseResult> purchaseAndApplySkin(
    PetSkin skin, {
    required Future<bool> Function(int cost) spendCoins,
  }) async {
    if (isOwned(skin)) {
      await changeSkin(skin);
      return SkinPurchaseResult.applied;
    }
    final paid = await spendCoins(skin.unlockCost);
    if (!paid) return SkinPurchaseResult.insufficientCoins;
    await _unlock(skin);
    await changeSkin(skin);
    return SkinPurchaseResult.purchasedAndApplied;
  }

  Future<void> _unlock(PetSkin skin) async {
    if (_ownedSkins.contains(skin)) return;
    _ownedSkins = {..._ownedSkins, skin};
    notifyListeners();
    await _storageService?.saveOwnedPetSkins(_ownedSkins);
  }

  /// 把目前外觀寫回目前帳號的本機資料。
  Future<void> saveSkin() async {
    await _storageService?.savePetSkin(_currentSkin);
  }

  void setMessage(String message) {
    _state = _state.copyWith(message: message);
    _startIdleTimer();
    notifyListeners();
  }

  void setMode(PetMode mode, {bool isSpeaking = false}) {
    _state = _state.copyWith(mode: mode, isSpeaking: isSpeaking);
    _startIdleTimer();
    _logPetState();
    notifyListeners();
  }

  void setModeAndMessage(PetMode mode, String message,
      {bool isSpeaking = false}) {
    _state =
        _state.copyWith(mode: mode, message: message, isSpeaking: isSpeaking);
    _startIdleTimer();
    _logPetState();
    notifyListeners();
  }

  void updateEmotionState({
    required String mood,
    required String expression,
    required String action,
    required PetMode mode,
  }) {
    _mood = mood;
    _expression = expression;
    _action = action;
    _state = _state.copyWith(mode: mode);
    _startIdleTimer();
    _logPetState();
    notifyListeners();
  }

  Future<void> enterInitialRestThenListen() async {
    setMode(PetMode.rest);
    await Future<void>.delayed(const Duration(seconds: 1));
    setMode(PetMode.listening);
  }

  void _startIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(seconds: 8), () {
      if (_state.mode != PetMode.talking) {
        _state = _state.copyWith(mode: PetMode.rest);
        notifyListeners();
      }
    });
  }

  void _logPetState() {
    debugPrint(
        '[PET_CONTROLLER] mood=$_mood expression=$_expression action=$_action mode=${_state.mode.name}');
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }
}

/// [PetController.purchaseAndApplySkin] 的結果，供 UI 顯示對應的長者友善訊息。
enum SkinPurchaseResult {
  /// 已擁有，直接套用。
  applied,

  /// 點數足夠 → 已扣點、解鎖並套用。
  purchasedAndApplied,

  /// 點數不足 → 沒有扣點、沒有解鎖。
  insufficientCoins,
}
