import 'dart:async';

import 'package:flutter/material.dart';

import '../models/pet_skin.dart';
import '../models/pet_state.dart';
import '../models/pet_status.dart';
import '../models/pet_visual_profile.dart';
import '../services/local_storage_service.dart';
import '../utils/app_log.dart';
import '../utils/asset_paths.dart';
import '../utils/pet_state_selector.dart';

class PetController extends ChangeNotifier {
  /// [storageService] 可省略：UI / 單元測試不需要持久化時用 `PetController()` 即可，
  /// 外觀會維持預設狗狗。實際 App 會注入 storage 以記住每個帳號各自的外觀。
  ///
  /// [freeAllSkins] 為 true 時所有外觀一律視為已擁有，長者點一下就能換、不需解鎖。
  /// 預設 false → 維持商店 / 金幣解鎖流程。Demo 期間 App 端會傳 true（見 app.dart）。
  PetController(
      {LocalStorageService? storageService, bool freeAllSkins = false})
      : _storageService = storageService,
        _freeAllSkins = freeAllSkins,
        _ownedSkins = freeAllSkins ? {...PetSkin.values} : {PetSkin.dog};

  final LocalStorageService? _storageService;

  /// true → 所有外觀免費、預設擁有（Demo 用，見建構子 [freeAllSkins]）。
  final bool _freeAllSkins;

  PetState _state = const PetState(
    mode: PetMode.rest,
    message: '準備好開始今天的陪伴了嗎？',
  );
  Timer? _idleTimer;
  // CR-0088：互動結束後短暫顯示的情緒狀態（happy / caring / sad…）。到期自動清除。
  PetMode? _transientMode;
  Timer? _transientTimer;
  String _mood = 'neutral';
  String _expression = 'normal';
  String _action = 'idle';
  PetSkin _currentSkin = PetSkin.dog;
  PetVisualStyle _currentVisualStyle = PetVisualStyle.cute;
  final PetGrowthStage _currentGrowthStage = PetGrowthStage.adult;
  Set<PetSkin> _ownedSkins;

  PetState get state => _state;
  PetMode get mode => _state.mode;
  String get message => _state.message;
  String get mood => _mood;
  String get expression => _expression;
  String get action => _action;

  /// 目前寵物外觀，預設狗狗。
  PetSkin get currentSkin => _currentSkin;

  /// 目前寵物視覺風格，預設 Q版。只有已支援的 pet/style 會被保存與套用。
  PetVisualStyle get currentVisualStyle => _currentVisualStyle;

  /// 目前成長階段。CR-0100C 先維持成年，後續 CR-0100E 再接成長資料。
  PetGrowthStage get currentGrowthStage => _currentGrowthStage;

  /// 目前寵物素材能力，用於 UI 呈現與 data tracking。
  PetVisualProfile get currentVisualProfile {
    final base = AssetPaths.visualProfile(_currentSkin);
    return PetVisualProfile(
      skin: _currentSkin,
      visualStyle: _currentVisualStyle,
      growthStage: _currentGrowthStage,
      talkFrameCount: base.talkFrameCount,
      restFrameCount: base.restFrameCount,
      stateSuffixes: base.stateSuffixes,
    );
  }

  /// 已擁有 / 已解鎖的外觀（狗狗永遠在內）。未擁有的需購買 / 解鎖才能套用。
  Set<PetSkin> get ownedSkins => Set.unmodifiable(_ownedSkins);

  bool isOwned(PetSkin skin) => _freeAllSkins || _ownedSkins.contains(skin);

  /// CR-0088：目前的短暫情緒狀態（無則 null）。首頁狀態選擇器會優先顯示它。
  PetMode? get transientMode => _transientMode;

  /// CR-0088：互動（對話 / 任務 / 提醒）結束後，短暫顯示一個情緒狀態，到期自動退場。
  /// 擴充既有 idle 機制：idle timer 仍負責 mode→rest 衰減，這裡只額外持有一個
  /// 「會自己消失」的情緒狀態，供首頁選擇器在非收音 / 非播放時顯示。
  void showTransientState(
    PetMode mode, {
    Duration duration = PetStateSelector.transientDuration,
  }) {
    _transientTimer?.cancel();
    _transientMode = mode;
    notifyListeners();
    _transientTimer = Timer(duration, () {
      _transientMode = null;
      notifyListeners();
    });
  }

  /// 載入目前帳號（elderId）保存的外觀與已擁有清單；
  /// 沒有 storage 或沒存過 → 狗狗、且只擁有狗狗。
  /// 防呆：若存到的目前外觀不在已擁有清單內，退回狗狗。
  Future<void> loadSkin() async {
    final storage = _storageService;
    if (storage == null) return;
    final owned = await storage.loadOwnedPetSkins();
    final skin = await storage.loadPetSkin();
    final visualStyle = await storage.loadPetVisualStyle();
    _ownedSkins = {
      PetSkin.dog,
      ...owned,
      if (_freeAllSkins) ...PetSkin.values,
    };
    final resolved = _ownedSkins.contains(skin) ? skin : PetSkin.dog;
    final resolvedStyle = AssetPaths.supportsVisualStyle(
      resolved,
      visualStyle,
      growthStage: _currentGrowthStage,
    )
        ? visualStyle
        : PetVisualStyle.cute;
    if (resolved == _currentSkin &&
        resolvedStyle == _currentVisualStyle &&
        _ownedSkins.length == 1) {
      return;
    }
    _currentSkin = resolved;
    _currentVisualStyle = resolvedStyle;
    notifyListeners();
  }

  /// 立即套用外觀（長者點一下就生效）。**只有已擁有的外觀**才能套用；
  /// 未擁有時回傳 false、不做任何事（未擁有要走 [purchaseAndApplySkin]）。
  Future<bool> changeSkin(PetSkin skin) async {
    if (!isOwned(skin)) return false;
    final nextStyle = AssetPaths.supportsVisualStyle(
      skin,
      _currentVisualStyle,
      growthStage: _currentGrowthStage,
    )
        ? _currentVisualStyle
        : PetVisualStyle.cute;
    if (skin == _currentSkin && nextStyle == _currentVisualStyle) return true;
    _currentSkin = skin;
    _currentVisualStyle = nextStyle;
    notifyListeners();
    await saveSkin();
    return true;
  }

  /// 切換 Q版 / 真實版偏好。尚未支援的組合不套用，避免正式 UI 出現破圖。
  Future<bool> changeVisualStyle(PetVisualStyle visualStyle) async {
    if (!AssetPaths.supportsVisualStyle(
      _currentSkin,
      visualStyle,
      growthStage: _currentGrowthStage,
    )) {
      return false;
    }
    if (visualStyle == _currentVisualStyle) return true;
    _currentVisualStyle = visualStyle;
    notifyListeners();
    await _storageService?.savePetVisualStyle(_currentVisualStyle);
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
    await _storageService?.savePetVisualStyle(_currentVisualStyle);
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
    AppLog.debug(
      '[PET_CONTROLLER] mood=$_mood expression=$_expression action=$_action mode=${_state.mode.name}',
    );
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _transientTimer?.cancel();
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
