import 'package:shared_preferences/shared_preferences.dart';

/// 一筆「使用者已同意的條款紀錄」。
class ConsentRecord {
  const ConsentRecord({
    required this.version,
    required this.grantedAt,
  });

  /// 使用者當時同意的條款版本號（對應 [LegalConfig.consentVersion]）。
  final String version;

  /// 同意的時間（ISO 8601 字串）。
  final String grantedAt;
}

/// 知情同意狀態的本機持久化服務。
///
/// 目前只存本機（shared_preferences）。後端 `consent_records` 持久化是另一個批次，
/// 屆時可在 [recordConsent] 之後再補上送後端的步驟（方法已集中於此，方便擴充）。
///
/// 風格沿用 [LocalStorageService]：以 shared_preferences 為單一儲存來源。
class ConsentService {
  ConsentService({SharedPreferences? preferences}) : _injected = preferences;

  static const String _keyVersion = 'consent.acceptedVersion';
  static const String _keyGrantedAt = 'consent.grantedAt';

  /// 測試可注入一個 in-memory 的 SharedPreferences（用 setMockInitialValues），
  /// 正式執行時為 null，會走 [SharedPreferences.getInstance]。
  final SharedPreferences? _injected;

  Future<SharedPreferences> get _prefs async =>
      _injected ?? await SharedPreferences.getInstance();

  /// 讀取目前已同意的條款紀錄；從未同意過則回 `null`。
  Future<ConsentRecord?> loadConsent() async {
    final prefs = await _prefs;
    final version = prefs.getString(_keyVersion);
    final grantedAt = prefs.getString(_keyGrantedAt);
    if (version == null || version.isEmpty) return null;
    return ConsentRecord(
      version: version,
      grantedAt: grantedAt ?? '',
    );
  }

  /// 判斷「目前要求的版本」是否已被同意。
  /// 版本不同（條款更新）或從未同意都回 `false`，需要重新請使用者同意。
  Future<bool> hasConsentedTo(String requiredVersion) async {
    final record = await loadConsent();
    return record != null && record.version == requiredVersion;
  }

  /// 記錄使用者同意了某個版本（寫入版本號 + 同意時間）。
  ///
  /// 回傳寫入的 [ConsentRecord]。日後要把同意事件補送後端時，
  /// 可在這個方法內或呼叫端接續呼叫對應 API（介面已預留集中於此）。
  Future<ConsentRecord> recordConsent(String version) async {
    final prefs = await _prefs;
    final grantedAt = DateTime.now().toIso8601String();
    await prefs.setString(_keyVersion, version);
    await prefs.setString(_keyGrantedAt, grantedAt);
    // TODO(批次 1.2)：在此把同意事件送往後端 consent_records，失敗不可影響本機已同意狀態。
    return ConsentRecord(version: version, grantedAt: grantedAt);
  }

  /// 清除本機同意紀錄（例如使用者在設定裡選擇「重新檢視同意」）。
  Future<void> clearConsent() async {
    final prefs = await _prefs;
    await prefs.remove(_keyVersion);
    await prefs.remove(_keyGrantedAt);
  }
}
