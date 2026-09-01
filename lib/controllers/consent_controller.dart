import 'package:flutter/foundation.dart';

import '../config/legal_config.dart';
import '../services/consent_service.dart';
import '../utils/app_log.dart';

/// 知情同意流程的狀態。
enum ConsentStatus {
  /// 啟動時讀取本機同意紀錄中。
  loading,

  /// 尚未同意目前版本（首次使用或條款已更新）→ 顯示同意流程。
  needsConsent,

  /// 已同意目前版本 → 可進入登入 / 主流程。
  granted,
}

/// 管理「使用者是否已同意當前版本條款」的 Controller。
///
/// 純前端狀態層：透過 [ConsentService] 讀寫本機紀錄。設計上把「同意事件」集中在
/// [grantConsent]，未來要補送後端時只需擴充這裡與 service，不必改 UI。
class ConsentController extends ChangeNotifier {
  ConsentController({
    ConsentService? consentService,
    String requiredVersion = LegalConfig.consentVersion,
  })  : _service = consentService ?? ConsentService(),
        _requiredVersion = requiredVersion;

  final ConsentService _service;
  final String _requiredVersion;

  ConsentStatus _status = ConsentStatus.loading;
  ConsentRecord? _record;

  ConsentStatus get status => _status;

  /// 目前 App 要求的條款版本（UI 可顯示 / 測試可斷言）。
  String get requiredVersion => _requiredVersion;

  /// 目前已同意的紀錄（含版本與時間），未同意則為 null。
  ConsentRecord? get record => _record;

  /// 是否已同意當前版本。
  bool get hasConsented => _status == ConsentStatus.granted;

  /// 啟動時載入本機同意狀態，決定要不要先擋同意流程。
  Future<void> load() async {
    _setStatus(ConsentStatus.loading);
    try {
      final record = await _service.loadConsent();
      _record = record;
      final granted = record != null && record.version == _requiredVersion;
      _setStatus(granted ? ConsentStatus.granted : ConsentStatus.needsConsent);
    } catch (error) {
      // 讀取失敗時保守處理：要求重新同意（不可因為讀取失敗就放行蒐集資料）。
      AppLog.error('[CONSENT] load 失敗，改為要求重新同意', error);
      _record = null;
      _setStatus(ConsentStatus.needsConsent);
    }
  }

  /// 使用者明確按下「我同意」時呼叫：記錄版本與時間，狀態切為已同意。
  Future<void> grantConsent() async {
    final record = await _service.recordConsent(_requiredVersion);
    _record = record;
    _setStatus(ConsentStatus.granted);
  }

  /// 重新檢視同意：清除本機紀錄並回到「需要同意」狀態（設定頁可用）。
  Future<void> resetConsent() async {
    await _service.clearConsent();
    _record = null;
    _setStatus(ConsentStatus.needsConsent);
  }

  void _setStatus(ConsentStatus next) {
    _status = next;
    notifyListeners();
  }
}
