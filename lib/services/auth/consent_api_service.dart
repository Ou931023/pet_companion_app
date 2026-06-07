import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../config/app_config.dart';

/// 把一次「知情同意」事件 best-effort 補送後端稽核表的 HTTP 服務。
///
/// 對應 `PROJECT_ARCHITECTURE.md` §10.4 的 `POST /api/consent`。
///
/// 設計同 [SessionApiService.deleteAccount]：**永遠不丟例外**。成功回 `true`，
/// 任何失敗（離線 / 5xx / timeout / 解析失敗 / 未登入）回 `false`——讓「同意」
/// 不被後端連線問題擋住。本機 `consent.acceptedVersion` 仍是 App 內判斷是否需
/// 重新同意的唯一來源；後端只是稽核軌跡。
///
/// HTTP client 可注入，方便用 `package:http/testing.dart` 的 MockClient 測試，
/// 不需實打網路。
class ConsentApiService {
  ConsentApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 8);

  /// 同意稽核端點：`$backendBaseUrl/api/consent`。
  Uri get _consentUri => Uri.parse('${AppConfig.backendBaseUrl}/api/consent');

  /// 補送一次同意事件。回 `true` 代表後端確認寫入；任何失敗回 `false`（不丟例外）。
  ///
  /// 身份識別（[firebaseUid] / [idToken] / [userId] / [elderId]）能取到什麼帶什麼；
  /// 都沒有時後端契約仍允許寫入一列（user_id / elder_id 為 null 的稽核軌跡）。
  ///
  /// **PII 紅線**：刻意不帶 ip / userAgent——那是後端自行從 request 擷取的，
  /// request body 不接受。
  Future<bool> submitConsent({
    required String consentType,
    required String consentVersion,
    String action = 'granted',
    String? source,
    String? firebaseUid,
    String? idToken,
    String? userId,
    String? elderId,
    String? appVersion,
    String? platform,
    String? agreedAt,
  }) async {
    try {
      final response = await _client
          .post(
            _consentUri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'consentType': consentType,
              'consentVersion': consentVersion,
              'action': action,
              if (source != null) 'source': source,
              if (firebaseUid != null) 'firebaseUid': firebaseUid,
              if (idToken != null) 'idToken': idToken,
              if (userId != null) 'userId': userId,
              if (elderId != null) 'elderId': elderId,
              if (appVersion != null) 'appVersion': appVersion,
              if (platform != null) 'platform': platform,
              if (agreedAt != null) 'agreedAt': agreedAt,
            }),
          )
          .timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('[CONSENT_SYNC] 後端回非 2xx：${response.statusCode}（已忽略，本機同意不受影響）');
        return false;
      }
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> && decoded['success'] == true;
    } catch (error) {
      debugPrint('[CONSENT_SYNC] 補送後端失敗（已忽略，本機同意不受影響）：$error');
      return false;
    }
  }
}
