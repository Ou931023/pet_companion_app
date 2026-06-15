import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/conversation_turn.dart';
import '../models/pet_skin.dart';
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
  static const _keyFamilyContacts = 'familyContactsList';
  static const _keyConversationHistory = 'conversationHistory';
  static const _keyConversationTitles = 'conversationTitles';
  static const _keyPetSkin = 'petSkin';
  static const _keyOwnedPetSkins = 'ownedPetSkins';
  static const _keyHomeCoachMarkDone = 'homeCoachMarkDone';
  // CR-0087：寵物關心提醒設定 + cooldown 紀錄（避免太頻繁打擾）。
  static const _keyConcernRemindersEnabled = 'concernRemindersEnabled';
  static const _keyConcernNotifyTimestamps = 'concernNotifyTimestamps';

  static const String defaultUserId = 'default_user';

  // CR-0009：依帳號隔離本機資料。`default_user`（Demo / 未登入）沿用原本的
  // 全域 key（**不動到既有資料與 Demo 寵物**）；真 Firebase 帳號的 elderId
  // 會加前綴 `u:<elderId>:`，讓每個帳號各自獨立。
  String _userId = defaultUserId;

  void setUserId(String? userId) {
    _userId = (userId == null || userId.isEmpty) ? defaultUserId : userId;
  }

  String get userId => _userId;

  String _k(String key) => _userId == defaultUserId ? key : 'u:$_userId:$key';

  Future<UserProfile> loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final initial = UserProfile.initial();
    final taskJson = prefs.getString(_k(_keyTaskCompletionState));
    final taskMap = taskJson == null
        ? initial.taskCompletionState
        : Map<String, bool>.from(jsonDecode(taskJson) as Map);

    return UserProfile(
      hasCompletedOnboarding: prefs.getBool(_k(_keyHasCompletedOnboarding)) ??
          initial.hasCompletedOnboarding,
      petName: prefs.getString(_k(_keyPetName)) ?? initial.petName,
      userCoins: prefs.getInt(_k(_keyUserCoins)) ?? initial.userCoins,
      petBond: prefs.getInt(_k(_keyPetBond)) ?? initial.petBond,
      petFullness: prefs.getInt(_k(_keyPetFullness)) ?? initial.petFullness,
      petMood: prefs.getInt(_k(_keyPetMood)) ?? initial.petMood,
      checkInDate: prefs.getString(_k(_keyCheckInDate)),
      taskCompletionState: taskMap,
      sttMode: prefs.getString(_k(_keySttMode)) ?? initial.sttMode,
      sttProxyUrl: prefs.getString(_k(_keySttProxyUrl)) ?? initial.sttProxyUrl,
      ttsEnabled: prefs.getBool(_k(_keyTtsEnabled)) ?? initial.ttsEnabled,
      fontScale: prefs.getDouble(_k(_keyFontScale)) ?? initial.fontScale,
      petVolume: prefs.getDouble(_k(_keyPetVolume)) ?? initial.petVolume,
      speechStyle: prefs.getString(_k(_keySpeechStyle)) ?? initial.speechStyle,
      contentPreferences: prefs.getStringList(_k(_keyContentPreferences)) ??
          initial.contentPreferences,
      voiceLanguageMode: prefs.getString(_k(_keyVoiceLanguageMode)) ??
          initial.voiceLanguageMode,
      manualAsrStrategy: prefs.getString(_k(_keyManualAsrStrategy)) ??
          initial.manualAsrStrategy,
      familyContacts: _loadFamilyContacts(prefs),
      concernRemindersEnabled: prefs.getBool(_k(_keyConcernRemindersEnabled)) ??
          initial.concernRemindersEnabled,
    );
  }

  /// CR-0087：讀取寵物關心提醒的 cooldown 紀錄（{類型/`_any` → ISO 時間字串}）。
  /// 無紀錄 / 解析失敗 → 空 map（視為從未發過，不會誤擋）。
  Future<Map<String, String>> loadConcernNotifyTimestamps() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k(_keyConcernNotifyTimestamps));
    if (raw == null || raw.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  /// CR-0087：保存寵物關心提醒的 cooldown 紀錄。
  Future<void> saveConcernNotifyTimestamps(Map<String, String> timestamps) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _k(_keyConcernNotifyTimestamps),
      jsonEncode(timestamps),
    );
  }

  List<Map<String, String>> _loadFamilyContacts(SharedPreferences prefs) {
    final raw = prefs.getString(_k(_keyFamilyContacts));
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => Map<String, String>.from(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveProfile(UserProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      _k(_keyHasCompletedOnboarding),
      profile.hasCompletedOnboarding,
    );
    await prefs.setString(_k(_keyPetName), profile.petName);
    await prefs.setInt(_k(_keyUserCoins), profile.userCoins);
    await prefs.setInt(_k(_keyPetBond), profile.petBond);
    await prefs.setInt(_k(_keyPetFullness), profile.petFullness);
    await prefs.setInt(_k(_keyPetMood), profile.petMood);
    if (profile.checkInDate == null) {
      await prefs.remove(_k(_keyCheckInDate));
    } else {
      await prefs.setString(_k(_keyCheckInDate), profile.checkInDate!);
    }
    await prefs.setString(
      _k(_keyTaskCompletionState),
      jsonEncode(profile.taskCompletionState),
    );
    await prefs.setString(_k(_keySttMode), profile.sttMode);
    await prefs.setString(_k(_keySttProxyUrl), profile.sttProxyUrl);
    await prefs.setBool(_k(_keyTtsEnabled), profile.ttsEnabled);
    await prefs.setBool(
      _k(_keyConcernRemindersEnabled),
      profile.concernRemindersEnabled,
    );
    await prefs.setDouble(_k(_keyFontScale), profile.fontScale);
    await prefs.setDouble(_k(_keyPetVolume), profile.petVolume);
    await prefs.setString(_k(_keySpeechStyle), profile.speechStyle);
    await prefs.setString(_k(_keyVoiceLanguageMode), profile.voiceLanguageMode);
    await prefs.setString(_k(_keyManualAsrStrategy), profile.manualAsrStrategy);
    await prefs.setStringList(
      _k(_keyContentPreferences),
      profile.contentPreferences,
    );
    await prefs.setString(
      _k(_keyFamilyContacts),
      jsonEncode(profile.familyContacts),
    );
  }

  Future<List<ConversationTurn>> loadConversationHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k(_keyConversationHistory));
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
      _k(_keyConversationHistory),
      jsonEncode(cappedTurns.map((turn) => turn.toJson()).toList()),
    );
  }

  /// 載入目前帳號快取的對話標題（sessionId → title，CR-0027）。
  Future<Map<String, String>> loadConversationTitles() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_k(_keyConversationTitles));
    if (raw == null || raw.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((key, value) => MapEntry(key, value.toString()));
    } catch (_) {
      return {};
    }
  }

  /// 保存目前帳號快取的對話標題（依 [_k] 各帳號互不影響）。
  Future<void> saveConversationTitles(Map<String, String> titles) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_k(_keyConversationTitles), jsonEncode(titles));
  }

  /// 載入目前帳號的寵物外觀。沒存過或認不得一律回預設狗狗。
  /// 走 [_k] → `default_user`（Demo）用全域 key，正式帳號各自加 `u:<elderId>:` 前綴。
  Future<PetSkin> loadPetSkin() async {
    final prefs = await SharedPreferences.getInstance();
    return PetSkinX.fromStorageId(prefs.getString(_k(_keyPetSkin)));
  }

  /// 保存目前帳號的寵物外觀（依 [_k] 各帳號互不影響）。
  Future<void> savePetSkin(PetSkin skin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_k(_keyPetSkin), skin.storageId);
  }

  /// 載入目前帳號「已擁有 / 已解鎖」的外觀集合。沒存過 → 只有預設狗狗。
  /// 狗狗一律視為已擁有（保底），避免任何資料異常造成沒有可用外觀。
  Future<Set<PetSkin>> loadOwnedPetSkins() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_k(_keyOwnedPetSkins)) ?? const [];
    final owned = <PetSkin>{PetSkin.dog};
    for (final id in ids) {
      owned.add(PetSkinX.fromStorageId(id));
    }
    return owned;
  }

  /// 保存已擁有的外觀集合（依 [_k] 各帳號互不影響）。狗狗一律保底寫入。
  Future<void> saveOwnedPetSkins(Set<PetSkin> skins) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = {PetSkin.dog, ...skins}.map((s) => s.storageId).toList();
    await prefs.setStringList(_k(_keyOwnedPetSkins), ids);
  }

  /// 首頁新手導覽（Coach Mark）是否已看過。依 [_k] 各帳號獨立，
  /// Demo（default_user）用全域 key；看過後下次開 App 不再自動跳出。
  Future<bool> loadHomeCoachMarkDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_k(_keyHomeCoachMarkDone)) ?? false;
  }

  Future<void> saveHomeCoachMarkDone(bool done) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_k(_keyHomeCoachMarkDone), done);
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
