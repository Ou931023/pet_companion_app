import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config/app_config.dart';
import '../../models/auth_session.dart';
import '../../utils/app_log.dart';

/// 後端建立 session 失敗時、針對**正式帳號（email/google/apple）**丟出的
/// typed 例外。
///
/// CR-0037：正式帳號不可在後端失敗時被捏造成「已登入」。失敗會丟此例外，
/// 由上層（`AuthController`）轉成長者看得懂的白話訊息並提供重試。
///
/// [code] 為可分類的錯誤類別，**不含任何後端原文或工程細節**：
/// - `network`：連線不到後端 / timeout（裝置網路問題）。
/// - `server`：後端回非 2xx（5xx 等）或回應格式不正確。
/// - `invalid_token`：後端回 401（登入憑證已失效，需重新登入）。
class SessionApiException implements Exception {
  const SessionApiException(this.code);

  /// 'network' | 'server' | 'invalid_token'。
  final String code;

  @override
  String toString() => 'SessionApiException(code: $code)';
}

/// 呼叫後端 `POST /api/auth/session` 建立 / 取回 session 的 HTTP 服務。
///
/// 設計原則（CR-0006 Batch 3a，CR-0037 修正）：
/// - 只負責一次 HTTP 往返，不持有任何登入狀態。
/// - **provider-aware 失敗處理**：
///   - `provider == 'mock'`（Demo）：任何失敗一律回 [AuthSession.mockFallback]，
///     確保 Demo 不被後端問題擋住（行為與 CR-0006 相同）。
///   - 正式帳號（email/google/apple）：後端 non-2xx / timeout / 解析失敗時，
///     **不再捏造 authenticated session**，改丟 [SessionApiException]
///     （帶可分類 code），由上層轉白話錯誤＋重試。
/// - HTTP client 可注入，方便用 `package:http/testing.dart` 的 MockClient 測試。
class SessionApiService {
  SessionApiService({
    http.Client? client,
    this.requestTimeout = defaultRequestTimeout,
    this.retryTimeout = defaultRetryTimeout,
    this.retryDelay = defaultRetryDelay,
  }) : _client = client ?? http.Client();

  final http.Client _client;

  /// Render free instances may need more than 50 seconds to wake from idle.
  /// Keep authentication pending long enough for that first production request
  /// instead of misreporting a healthy cold start as a network failure.
  static const Duration defaultRequestTimeout = Duration(seconds: 60);
  static const Duration defaultRetryTimeout = Duration(seconds: 20);
  static const Duration defaultRetryDelay = Duration(milliseconds: 500);

  /// Injectable so timeout behavior stays fast and deterministic in tests.
  final Duration requestTimeout;
  final Duration retryTimeout;
  final Duration retryDelay;

  /// auth session 端點：`$backendBaseUrl/api/auth/session`。
  Uri get _sessionUri =>
      Uri.parse('${AppConfig.backendBaseUrl}/api/auth/session');

  /// 刪除帳號端點：`$backendBaseUrl/api/auth/delete`。
  Uri get _deleteUri =>
      Uri.parse('${AppConfig.backendBaseUrl}/api/auth/delete');

  Future<AuthSession> createSession({
    required String firebaseUid,
    required String idToken,
    String? email,
    String? displayName,
    required String provider,
    String? photoUrl,
  }) async {
    // Demo 路徑（provider == 'mock'）保留原本「任何失敗都回 fallback」行為；
    // 正式帳號路徑改丟 typed 例外，不捏造 session。
    final isDemo = provider == 'mock';
    try {
      final requestBody = jsonEncode({
        'firebaseUid': firebaseUid,
        'idToken': idToken,
        if (email != null) 'email': email,
        if (displayName != null) 'displayName': displayName,
        'provider': provider,
        if (photoUrl != null) 'photoUrl': photoUrl,
      });
      final response = await _postSessionWithColdStartRetry(
        requestBody: requestBody,
        provider: provider,
        allowRetry: !isDemo,
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (isDemo) {
          AppLog.debug(
            '[AUTH_SESSION] non-2xx response: ${response.statusCode}, '
            '改用 demo fallback session。',
          );
          return AuthSession.mockFallback();
        }
        // 正式帳號：401 視為登入憑證失效（需重新登入），其餘非 2xx 視為 server。
        AppLog.debug(
            '[AUTH_SESSION] non-2xx response: ${response.statusCode}（正式帳號，丟例外）。');
        throw SessionApiException(
          response.statusCode == 401 ? 'invalid_token' : 'server',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['success'] != true) {
        if (isDemo) {
          AppLog.debug(
              '[AUTH_SESSION] backend 回應非成功格式，改用 demo fallback session。');
          return AuthSession.mockFallback();
        }
        AppLog.debug('[AUTH_SESSION] backend 回應非成功格式（正式帳號，丟例外）。');
        throw const SessionApiException('server');
      }
      return AuthSession.fromJson(decoded);
    } on SessionApiException {
      rethrow;
    } on FormatException {
      // JSON 解析失敗：後端回了非預期內容。
      if (isDemo) {
        AppLog.debug('[AUTH_SESSION] 解析失敗，改用 demo fallback session。');
        return AuthSession.mockFallback();
      }
      throw const SessionApiException('server');
    } catch (error) {
      // timeout / 連線錯誤等。
      if (isDemo) {
        AppLog.error(
            '[AUTH_SESSION] createSession 失敗，改用 demo fallback session', error);
        return AuthSession.mockFallback();
      }
      throw const SessionApiException('network');
    }
  }

  Future<http.Response> _postSessionWithColdStartRetry({
    required String requestBody,
    required String provider,
    required bool allowRetry,
  }) async {
    AppLog.debug('[AUTH_SESSION] stage=request attempt=1 provider=$provider');
    try {
      return await _postSession(requestBody, requestTimeout);
    } catch (error) {
      if (!allowRetry) rethrow;
      AppLog.error('[AUTH_SESSION] stage=retry_after_transport_error', error);
      await Future<void>.delayed(retryDelay);
      AppLog.debug('[AUTH_SESSION] stage=request attempt=2 provider=$provider');
      return _postSession(requestBody, retryTimeout);
    }
  }

  Future<http.Response> _postSession(String requestBody, Duration timeout) {
    return _client
        .post(
          _sessionUri,
          headers: {'Content-Type': 'application/json'},
          body: requestBody,
        )
        .timeout(timeout);
  }

  /// 呼叫後端 `POST /api/auth/delete`，移除該帳號在後端的所有資料
  /// （使用者 / 長者 / 長期記憶 / Care Alert）。
  ///
  /// 設計同 [createSession]：**不丟例外**。成功回 `true`，任何失敗
  /// （非 2xx、連線錯誤、解析失敗）回 `false`。上層必須在 `false` 時保留
  /// Firebase 帳號與登入狀態，避免後端留下使用者無法再自行刪除的資料。
  Future<bool> deleteAccount({
    required String firebaseUid,
    required String idToken,
  }) async {
    try {
      final response = await _client
          .post(
            _deleteUri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'firebaseUid': firebaseUid,
              'idToken': idToken,
            }),
          )
          .timeout(requestTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        AppLog.debug('[AUTH_DELETE] 後端刪除回非 2xx：${response.statusCode}（已忽略）');
        return false;
      }
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> && decoded['success'] == true;
    } catch (error) {
      AppLog.error('[AUTH_DELETE] 後端刪除失敗（保留帳號與本機資料）', error);
      return false;
    }
  }
}
