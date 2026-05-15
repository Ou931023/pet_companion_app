import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/conversation_turn.dart';
import '../models/user_profile.dart';

class LocalStorageService {
  static const _keyHasCompletedOnboarding = 'hasCompletedOnboarding';
  static const _keyPetName = 'petName';
  static const _keyUserCoins = 'userCoins';
  static const _keyPetBond = 'petBond';
  static const _keyPetFullness = 'petFullness';
  static const _keyPetMood = 'petMood';
  static const _keyCheckInDate = 'checkInDate';
  static const _keyTaskCompletionState = 'taskCompletionState';
  static const _keySttMode = 'sttMode';
  static const _keySttProxyUrl = 'sttProxyUrl';
  static const _keyTtsEnabled = 'ttsEnabled';
  static const _keyFontScale = 'fontScale';
  static const _keyPetVolume = 'petVolume';
  static const _keySpeechStyle = 'speechStyle';
  static const _keyContentPreferences = 'contentPreferences';
  static const _keyVoiceLanguageMode = 'voiceLanguageMode';
  static const _keyManualAsrStrategy = 'manualAsrStrategy';
  static const _keyConversationHistory = 'conversationHistory';

  Future<UserProfile> loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final initial = UserProfile.initial();
    final taskJson = prefs.getString(_keyTaskCompletionState);
    final taskMap = taskJson == null
        ? initial.taskCompletionState
        : Map<String, bool>.from(jsonDecode(taskJson) as Map);

    return UserProfile(
      hasCompletedOnboarding: prefs.getBool(_keyHasCompletedOnboarding) ??
          initial.hasCompletedOnboarding,
      petName: prefs.getString(_keyPetName) ?? initial.petName,
      userCoins: prefs.getInt(_keyUserCoins) ?? initial.userCoins,
      petBond: prefs.getInt(_keyPetBond) ?? initial.petBond,
      petFullness: prefs.getInt(_keyPetFullness) ?? initial.petFullness,
      petMood: prefs.getInt(_keyPetMood) ?? initial.petMood,
      checkInDate: prefs.getString(_keyCheckInDate),
      taskCompletionState: taskMap,
      sttMode: prefs.getString(_keySttMode) ?? initial.sttMode,
      sttProxyUrl: prefs.getString(_keySttProxyUrl) ?? initial.sttProxyUrl,
      ttsEnabled: prefs.getBool(_keyTtsEnabled) ?? initial.ttsEnabled,
      fontScale: prefs.getDouble(_keyFontScale) ?? initial.fontScale,
      petVolume: prefs.getDouble(_keyPetVolume) ?? initial.petVolume,
      speechStyle: prefs.getString(_keySpeechStyle) ?? initial.speechStyle,
      contentPreferences: prefs.getStringList(_keyContentPreferences) ??
          initial.contentPreferences,
      voiceLanguageMode:
          prefs.getString(_keyVoiceLanguageMode) ?? initial.voiceLanguageMode,
      manualAsrStrategy:
          prefs.getString(_keyManualAsrStrategy) ?? initial.manualAsrStrategy,
    );
  }

  Future<void> saveProfile(UserProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      _keyHasCompletedOnboarding,
      profile.hasCompletedOnboarding,
    );
    await prefs.setString(_keyPetName, profile.petName);
    await prefs.setInt(_keyUserCoins, profile.userCoins);
    await prefs.setInt(_keyPetBond, profile.petBond);
    await prefs.setInt(_keyPetFullness, profile.petFullness);
    await prefs.setInt(_keyPetMood, profile.petMood);
    if (profile.checkInDate == null) {
      await prefs.remove(_keyCheckInDate);
    } else {
      await prefs.setString(_keyCheckInDate, profile.checkInDate!);
    }
    await prefs.setString(
      _keyTaskCompletionState,
      jsonEncode(profile.taskCompletionState),
    );
    await prefs.setString(_keySttMode, profile.sttMode);
    await prefs.setString(_keySttProxyUrl, profile.sttProxyUrl);
    await prefs.setBool(_keyTtsEnabled, profile.ttsEnabled);
    await prefs.setDouble(_keyFontScale, profile.fontScale);
    await prefs.setDouble(_keyPetVolume, profile.petVolume);
    await prefs.setString(_keySpeechStyle, profile.speechStyle);
    await prefs.setString(_keyVoiceLanguageMode, profile.voiceLanguageMode);
    await prefs.setString(_keyManualAsrStrategy, profile.manualAsrStrategy);
    await prefs.setStringList(
      _keyContentPreferences,
      profile.contentPreferences,
    );
  }

  Future<List<ConversationTurn>> loadConversationHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyConversationHistory);
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map>()
          .map((item) => ConversationTurn.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveConversationHistory(List<ConversationTurn> turns) async {
    final prefs = await SharedPreferences.getInstance();
    final cappedTurns =
        turns.length > 120 ? turns.sublist(turns.length - 120) : turns;
    await prefs.setString(
      _keyConversationHistory,
      jsonEncode(cappedTurns.map((turn) => turn.toJson()).toList()),
    );
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
