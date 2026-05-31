import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../config/app_config.dart';
import '../../models/auth_session.dart';

/// 呼叫後端 `POST /api/auth/session` 建立 / 取回 session 的 HTTP 服務。
///
/// 設計原則（CR-0006 Batch 3a）：
/// - 只負責一次 HTTP 往返，不持有任何登入狀態。
/// - **任何失敗都不丟例外**：非 2xx、連線錯誤、JSON 解析失敗，
///   一律回 [AuthSession.mockFallback]，確保 Demo 不被後端問題擋住。
/// - HTTP client 可注入，方便用 `package:http/testing.dart` 的 MockClient 測試。
class SessionApiService {
  SessionApiService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 8);

  /// auth session 端點：`$backendBaseUrl/api/auth/session`。
  Uri get _sessionUri =>
      Uri.parse('${AppConfig.backendBaseUrl}/api/auth/session');

  Future<AuthSession> createSession({
    required String firebaseUid,
    required String idToken,
    String? email,
    String? displayName,
    required String provider,
    String? photoUrl,
  }) async {
    try {
      final response = await _client
          .post(
            _sessionUri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'firebaseUid': firebaseUid,
              'idToken': idToken,
              if (email != null) 'email': email,
              if (displayName != null) 'displayName': displayName,
              'provider': provider,
              if (photoUrl != null) 'photoUrl': photoUrl,
            }),
          )
          .timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          '[AUTH_SESSION] non-2xx response: ${response.statusCode}, '
          '改用 demo fallback session。',
        );
        return AuthSession.mockFallback();
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['success'] != true) {
        debugPrint('[AUTH_SESSION] backend 回應非成功格式，改用 demo fallback session。');
        return AuthSession.mockFallback();
      }
      return AuthSession.fromJson(decoded);
    } catch (error) {
      // 含 timeout / 連線錯誤 / JSON 解析失敗：吞掉，回 fallback。
      debugPrint('[AUTH_SESSION] createSession 失敗，改用 demo fallback session：$error');
      return AuthSession.mockFallback();
    }
  }
}
