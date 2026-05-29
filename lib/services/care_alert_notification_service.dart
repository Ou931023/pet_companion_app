import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/care_alert.dart';

/// 將 CareAlert 以 fire-and-forget 方式送到自家後端的 Telegram 通知端點。
///
/// 設計原則：
/// - 只呼叫自己的後端 `POST /api/care-alerts/notify`，
///   Telegram token 與 chat id 完全留在後端，Flutter 不持有、也不知道。
/// - notify 內部完全 try/catch：非 200、後端回 success:false、或網路錯誤
///   都不會 throw，只記錄簡短 debug log，不影響 Realtime 與本機 CareAlert。
class CareAlertNotificationService {
  CareAlertNotificationService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  Future<void> notify({
    required String sttProxyUrl,
    required CareAlert alert,
  }) async {
    try {
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
            headers: {'Content-Type': 'application/json'},
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
        debugPrint('[CARE_ALERT_NOTIFY] non-200 response: ${response.statusCode}');
        return;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['success'] != true) {
        debugPrint('[CARE_ALERT_NOTIFY] backend reported failure: ${decoded['error']}');
      }
    } catch (error) {
      // 含 timeout 與網路錯誤：吞掉，不影響語音陪伴與本機 CareAlert。
      debugPrint('[CARE_ALERT_NOTIFY] notify failed: $error');
    }
  }
}
