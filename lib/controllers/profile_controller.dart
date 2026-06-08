import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/language_route.dart';
import '../models/user_profile.dart';
import '../services/local_storage_service.dart';
import '../services/speech_to_text_service.dart';

class ProfileController extends ChangeNotifier {
  ProfileController(this._storageService);

  final LocalStorageService _storageService;
  UserProfile _profile = UserProfile.initial();
  bool _isLoading = true;

  UserProfile get profile => _profile;
  bool get isLoading => _isLoading;
  bool get hasCompletedOnboarding => _profile.hasCompletedOnboarding;
  String get petName => _profile.petName;
  int get coins => _profile.userCoins;
  int get bond => _profile.petBond;
  int get fullness => _profile.petFullness;
  int get mood => _profile.petMood;
  String? get checkInDate => _profile.checkInDate;
  Map<String, bool> get taskState => _profile.taskCompletionState;
  bool get ttsEnabled => _profile.ttsEnabled;
  double get fontScale => _profile.fontScale;
  double get petVolume => _profile.petVolume;
  String get speechStyle => _profile.speechStyle;
  VoiceLanguageMode get voiceLanguageMode =>
      VoiceLanguageModeLabel.fromStorage(_profile.voiceLanguageMode);
  String get manualAsrStrategy => _profile.manualAsrStrategy;
  List<String> get contentPreferences =>
      List.unmodifiable(_profile.contentPreferences);
  String get sttProxyUrl => _profile.sttProxyUrl;
  SttMode get sttMode {
    // 正式版一律使用正式語音辨識，永不回 mock（即使儲存值為舊的 'mock'）。
    if (AppConfig.isProduction) return SttMode.openAiProxy;
    return _profile.sttMode == 'openAiProxy'
        ? SttMode.openAiProxy
        : SttMode.mock;
  }
  List<Map<String, String>> get familyContacts => List.unmodifiable(
        _profile.familyContacts.map((e) => Map<String, String>.from(e)),
      );

  Future<void> setFamilyContacts(List<Map<String, String>> contacts) async {
    _profile = _profile.copyWith(
      familyContacts: contacts
          .map((c) => {
                'alias': (c['alias'] ?? '').trim(),
                'phone': (c['phone'] ?? '').trim(),
                'email': (c['email'] ?? '').trim(),
              })
          .where((c) =>
              c['alias']!.isNotEmpty ||
              c['phone']!.isNotEmpty ||
              c['email']!.isNotEmpty)
          .toList(),
    );
    await _persist();
  }

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    _profile = await _storageService.loadProfile();
    final normalizedSttProxyUrl =
        AppConfig.normalizeSttProxyUrl(_profile.sttProxyUrl);
    if (normalizedSttProxyUrl != _profile.sttProxyUrl) {
      _profile = _profile.copyWith(sttProxyUrl: normalizedSttProxyUrl);
      await _persist();
    }
    debugPrint('[PET_NAME] current=${_profile.petName}');
    _isLoading = false;
    notifyListeners();
  }

  Future<void> completeOnboarding(String petName) async {
    final normalizedName = petName.trim();
    if (normalizedName.isEmpty) return;

    _profile = _profile.copyWith(
      hasCompletedOnboarding: true,
      petName: normalizedName,
    );
    await _persist();
  }

  Future<void> renamePet(
    String newName, {
    String source = 'settings',
  }) async {
    final normalizedName = newName.trim();
    if (normalizedName.isEmpty) return;

    _profile = _profile.copyWith(petName: normalizedName);
    debugPrint('[PET_NAME] updatedFrom=$source name=$normalizedName');
    debugPrint('[PET_NAME] current=${_profile.petName}');
    await _persist();
  }

  Future<void> setSttMode(SttMode mode) async {
    _profile = _profile.copyWith(
      sttMode: mode == SttMode.openAiProxy ? 'openAiProxy' : 'mock',
    );
    await _persist();
  }

  Future<void> setSttProxyUrl(String url) async {
    _profile = _profile.copyWith(
      sttProxyUrl: AppConfig.normalizeSttProxyUrl(url),
    );
    await _persist();
  }

  Future<void> setTtsEnabled(bool enabled) async {
    _profile = _profile.copyWith(ttsEnabled: enabled);
    await _persist();
  }

  Future<void> setFontScale(double value) async {
    _profile = _profile.copyWith(fontScale: value.clamp(0.9, 1.3));
    await _persist();
  }

  Future<void> setPetVolume(double value) async {
    _profile = _profile.copyWith(petVolume: value.clamp(0.0, 1.0));
    await _persist();
  }

  Future<void> setSpeechStyle(String style) async {
    final normalized = switch (style) {
      'bright' => 'bright',
      'calm' => 'calm',
      _ => 'gentle',
    };
    _profile = _profile.copyWith(speechStyle: normalized);
    await _persist();
  }

  Future<void> setVoiceLanguageMode(VoiceLanguageMode mode) async {
    _profile = _profile.copyWith(voiceLanguageMode: mode.storageValue);
    await _persist();
  }

  Future<void> setManualAsrStrategy(String strategyName) async {
    final normalized = strategyName.trim().isEmpty
        ? 'defaultOpenAiRealtime'
        : strategyName.trim();
    _profile = _profile.copyWith(manualAsrStrategy: normalized);
    await _persist();
  }

  Future<void> setContentPreference(String type, bool enabled) async {
    final next = [..._profile.contentPreferences];
    if (enabled && !next.contains(type)) {
      next.add(type);
    }
    if (!enabled) {
      next.remove(type);
    }
    _profile = _profile.copyWith(contentPreferences: next);
    await _persist();
  }

  Future<void> updateStats({
    int? coins,
    int? bond,
    int? fullness,
    int? mood,
    String? checkInDate,
    Map<String, bool>? taskCompletionState,
  }) async {
    _profile = _profile.copyWith(
      userCoins: coins,
      petBond: bond,
      petFullness: fullness,
      petMood: mood,
      checkInDate: checkInDate,
      taskCompletionState: taskCompletionState,
    );
    await _persist();
  }

  Future<void> resetOnboarding() async {
    _profile = _profile.copyWith(hasCompletedOnboarding: false);
    await _persist();
  }

  Future<void> clearAllData() async {
    await _storageService.clearAll();
    _profile = UserProfile.initial();
    notifyListeners();
  }

  Future<void> _persist() async {
    await _storageService.saveProfile(_profile);
    notifyListeners();
  }
}
