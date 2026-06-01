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

  PetState get state => _state;
  PetMode get mode => _state.mode;
  String get message => _state.message;
  String get mood => _mood;
  String get expression => _expression;
  String get action => _action;

  /// 目前寵物外觀，預設狗狗。
  PetSkin get currentSkin => _currentSkin;

  /// 載入目前帳號（elderId）保存的外觀；沒有 storage 或沒存過就維持狗狗。
  Future<void> loadSkin() async {
    final storage = _storageService;
    if (storage == null) return;
    final skin = await storage.loadPetSkin();
    if (skin == _currentSkin) return;
    _currentSkin = skin;
    notifyListeners();
  }

  /// 立即切換外觀並保存（長者點一下就生效）。
  Future<void> changeSkin(PetSkin skin) async {
    if (skin == _currentSkin) return;
    _currentSkin = skin;
    notifyListeners();
    await saveSkin();
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
