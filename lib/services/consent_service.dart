import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth/consent_api_service.dart';

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

/// 補送後端稽核時可帶上的身份識別（能取到什麼帶什麼，全部可為 null）。
///
/// 知情同意 gate 位於登入 gate 之前，多數情況下使用者**尚未登入**，此時四個欄位
/// 都會是 null——後端契約（§10.4）允許在 user_id / elder_id 為 null 時仍寫入一列
/// 稽核軌跡，故仍會補送。
class ConsentIdentity {
  const ConsentIdentity({
    this.firebaseUid,
    this.idToken,
    this.userId,
    this.elderId,
  });

  final String? firebaseUid;
  final String? idToken;
  final String? userId;
  final String? elderId;
}

/// 知情同意狀態的本機持久化服務。
///
/// 目前只存本機（shared_preferences）。後端 `consent_records` 持久化是另一個批次，
/// 屆時可在 [recordConsent] 之後再補上送後端的步驟（方法已集中於此，方便擴充）。
///
/// 風格沿用 [LocalStorageService]：以 shared_preferences 為單一儲存來源。
class ConsentService {
  ConsentService({
    SharedPreferences? preferences,
    ConsentApiService? consentApi,
  })  : _injected = preferences,
        _consentApi = consentApi ?? ConsentApiService();

  static const String _keyVersion = 'consent.acceptedVersion';
  static const String _keyGrantedAt = 'consent.grantedAt';

  /// 測試可注入一個 in-memory 的 SharedPreferences（用 setMockInitialValues），
  /// 正式執行時為 null，會走 [SharedPreferences.getInstance]。
  final SharedPreferences? _injected;

  /// 同意事件 best-effort 補送後端的 HTTP 服務（永遠不丟例外）。可注入做測試。
  final ConsentApiService _consentApi;

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
  /// 寫入本機（shared_preferences）成功後，會**非阻塞、best-effort** 地把同意事件
  /// 補送後端稽核（§10.4 `POST /api/consent`）。補送在背景進行，**不會 await**、
  /// 也**永不丟例外**——離線 / 5xx / timeout / 未登入都只靜默記錄，不影響回傳的
  /// [ConsentRecord]，本機 `acceptedVersion` 仍是 App 內唯一判斷來源。
  ///
  /// [identity]：登入後（如設定頁重新檢視同意）可帶當前身份；同意 gate 在登入 gate
  /// 之前，多數情況為 null，後端仍會寫一列無身份的稽核軌跡。
  Future<ConsentRecord> recordConsent(
    String version, {
    ConsentIdentity? identity,
  }) async {
    final prefs = await _prefs;
    final grantedAt = DateTime.now().toIso8601String();
    await prefs.setString(_keyVersion, version);
    await prefs.setString(_keyGrantedAt, grantedAt);
    // 本機寫入成功後，背景補送後端稽核（不 await，失敗不影響本機已同意狀態）。
    _syncConsentToBackend(version: version, grantedAt: grantedAt, identity: identity);
    return ConsentRecord(version: version, grantedAt: grantedAt);
  }

  /// 背景 best-effort 補送同意事件到後端稽核 API。
  ///
  /// 刻意以 [unawaited] fire-and-forget；[ConsentApiService.submitConsent] 內部已
  /// 攔截所有例外並回 false，故這裡不會有未處理的 async error。
  void _syncConsentToBackend({
    required String version,
    required String grantedAt,
    ConsentIdentity? identity,
  }) {
    unawaited(
      _consentApi.submitConsent(
        // 目前單一同意 gate 對應隱私權＋服務條款，先固定 privacy_terms。
        consentType: 'privacy_terms',
        consentVersion: version,
        action: 'granted',
        source: 'elder_app',
        agreedAt: grantedAt,
        platform: _platformName(),
        firebaseUid: identity?.firebaseUid,
        idToken: identity?.idToken,
        userId: identity?.userId,
        elderId: identity?.elderId,
      ),
    );
  }

  /// 稽核用的平台標記；非行動平台時回 null（欄位可選）。
  String? _platformName() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.android:
        return 'android';
      default:
        return null;
    }
  }

  /// 清除本機同意紀錄（例如使用者在設定裡選擇「重新檢視同意」）。
  Future<void> clearConsent() async {
    final prefs = await _prefs;
    await prefs.remove(_keyVersion);
    await prefs.remove(_keyGrantedAt);
  }
}
