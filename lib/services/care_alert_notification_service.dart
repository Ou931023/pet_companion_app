import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/care_alert.dart';
import '../utils/app_log.dart';

/// 取得呼叫後端所需的身分權杖（Bearer token）。
///
/// - 正式（Firebase）帳號 → 回傳「新的」Firebase idToken。
/// - Demo / mock 帳號（僅非 production）→ 回傳 `mock-id-token-<uid>`。
/// - 取不到時回 `null`（呼叫端會選擇不送出通知，不偽造）。
typedef AuthTokenProvider = Future<String?> Function();

/// 將 CareAlert 以 fire-and-forget 方式送到自家後端的 Telegram 通知端點。
///
/// 設計原則：
/// - 只呼叫自己的後端 `POST /api/care-alerts/notify`，
///   Telegram token 與 chat id 完全留在後端，Flutter 不持有、也不知道。
/// - CR-0045 B3：後端 `/notify` 已要求 caller 帶 `Authorization: Bearer <idToken>`，
///   server 由 token 權威推導 elderId，**前端不送 elderId**。token 由建構期注入的
///   [authTokenProvider] 取得（firebase→新 idToken、mock→mock-id-token-<uid>）。
/// - notify 內部完全 try/catch：取不到 token、非 200（含 401/403）、後端回
///   success:false、或網路錯誤都不會 throw，只記錄簡短 debug log（**絕不印出
///   完整 token**），不影響 Realtime 與本機 CareAlert。
class CareAlertNotificationService {
  CareAlertNotificationService({
    http.Client? client,
    AuthTokenProvider? authTokenProvider,
  })  : _client = client ?? http.Client(),
        _authTokenProvider = authTokenProvider;

  final http.Client _client;
  final AuthTokenProvider? _authTokenProvider;

  Future<void> notify({
    required String sttProxyUrl,
    required CareAlert alert,
  }) async {
    try {
      // 先取得身分權杖。取不到（未登入 / production 無法產生 / 取得失敗）就
      // 不送出通知——避免必然收到 401，也不偽造身分。整段失敗只吞、不 throw。
      String? token;
      try {
        token = await _authTokenProvider?.call();
      } catch (_) {
        token = null;
      }
      if (token == null || token.isEmpty) {
        AppLog.debug('[CARE_ALERT_NOTIFY] 沒有可用的身分權杖，略過通知。');
        return;
      }

      final apiBase = Uri.parse(AppConfig.apiBaseUrlForSttProxy(sttProxyUrl));
      final basePath = apiBase.path.endsWith('/')
          ? apiBase.path.substring(0, apiBase.path.length - 1)
          : apiBase.path;
      final uri = apiBase.replace(
        path: '$basePath/care-alerts/notify',
        query: null,
        fragment: null,
      );
      final response = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'riskLevel': alert.riskLevel.name,
              'riskLevelLabel': alert.riskLevel.label,
              'category': alert.category.name,
              'categoryLabel': alert.category.label,
              'triggerSummary': alert.triggerSummary,
              'transcriptSnippet': alert.transcriptSnippet,
              'createdAt': alert.createdAt.toIso8601String(),
              'source': alert.source,
            }),
          )
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) {
        AppLog.debug('[CARE_ALERT_NOTIFY] non-200 response: ${response.statusCode}');
        return;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['success'] != true) {
        AppLog.debug('[CARE_ALERT_NOTIFY] backend reported failure.');
      }
    } catch (error) {
      // 含 timeout 與網路錯誤：吞掉，不影響語音陪伴與本機 CareAlert。
      AppLog.error('[CARE_ALERT_NOTIFY] notify failed', error);
    }
  }
}
