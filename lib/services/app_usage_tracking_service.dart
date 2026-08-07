import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../utils/app_log.dart';
import 'care_alert_notification_service.dart';

/// First-party usage tracking for admin analytics.
///
/// Tracking must never block elder-facing companionship. Missing auth, network
/// errors, timeouts, or backend failures return false and keep the app flow
/// moving.
class AppUsageTrackingService {
  AppUsageTrackingService({
    http.Client? client,
    AuthTokenProvider? authTokenProvider,
  })  : _client = client ?? http.Client(),
        _authTokenProvider = authTokenProvider;

  final http.Client _client;
  final AuthTokenProvider? _authTokenProvider;

  Future<bool> track(
    String eventType, {
    String? sessionId,
    int? durationMs,
    Map<String, Object?> metadata = const {},
  }) async {
    try {
      String? token;
      try {
        token = await _authTokenProvider?.call();
      } catch (_) {
        token = null;
      }
      if (token == null || token.isEmpty) {
        AppLog.debug('[APP_USAGE] no auth token, skip event.');
        return false;
      }

      final response = await _client
          .post(
            Uri.parse(AppConfig.appUsageEventsUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'eventType': eventType,
              if (sessionId != null && sessionId.trim().isNotEmpty)
                'sessionId': sessionId.trim(),
              if (durationMs != null) 'durationMs': durationMs,
              if (metadata.isNotEmpty) 'metadata': _safeMetadata(metadata),
            }),
          )
          .timeout(const Duration(seconds: 4));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        AppLog.debug('[APP_USAGE] non-2xx response: ${response.statusCode}');
        return false;
      }
      return true;
    } catch (error) {
      AppLog.error('[APP_USAGE] track failed', error);
      return false;
    }
  }

  Map<String, Object> _safeMetadata(Map<String, Object?> input) {
    final out = <String, Object>{};
    for (final entry in input.entries) {
      final value = entry.value;
      if (value == null) continue;
      if (value is String) {
        out[entry.key] = String.fromCharCodes(value.runes.take(120));
      } else if (value is num || value is bool) {
        out[entry.key] = value;
      }
    }
    return out;
  }
}
