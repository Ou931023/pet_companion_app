import 'dart:async';

import 'package:flutter/material.dart';

import '../models/pet_state.dart';
import '../models/pet_status.dart';

class PetController extends ChangeNotifier {
  PetState _state = const PetState(
    mode: PetMode.rest,
    message: '準備好開始今天的陪伴了嗎？',
  );
  Timer? _idleTimer;
  String _mood = 'neutral';
  String _expression = 'normal';
  String _action = 'idle';

  PetState get state => _state;
  PetMode get mode => _state.mode;
  String get message => _state.message;
  String get mood => _mood;
  String get expression => _expression;
  String get action => _action;

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
