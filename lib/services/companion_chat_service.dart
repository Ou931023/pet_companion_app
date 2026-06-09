import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../utils/app_log.dart';
import 'care_alert_notification_service.dart' show AuthTokenProvider;

/// 呼叫後端 `POST /api/companion/chat` 取得 AI 寵物的文字回覆。
///
/// 設計原則（CR-0049 B2 / CR-0051 C）：
/// - 金鑰留在後端：Flutter 不持有、也不傳 OpenAI key。本服務只呼叫自家後端。
/// - 身分驗證：CR-0051 B 後端已 HARD-require 住民 Firebase idToken。token 由
///   建構期注入的 [authTokenProvider] 取得（與 CareAlertNotificationService 同源：
///   firebase→新 idToken / mock→mock-id-token-<uid> / production demo→null）。
///   有 token 才帶 `Authorization: Bearer <token>`；provider 取不到 token（如
///   production demo）會必然 401，故直接 throw [CompanionChatException] 白話提示，
///   **不送出註定失敗的請求、不偽造成功**。
/// - 失敗一律 throw [CompanionChatException]，**絕不吞錯、絕不回 fake / 罐頭、
///   絕不回空字串**。呼叫端（_chat）負責把例外轉成長者友善的白話提示，且不 fallback mock。
/// - log 只走 [AppLog]（release 為 no-op），且不輸出完整 reply 內容、不印出 token。
class CompanionChatService {
  CompanionChatService({
    http.Client? client,
    AuthTokenProvider? authTokenProvider,
  })  : _client = client ?? http.Client(),
        _authTokenProvider = authTokenProvider;

  final http.Client _client;
  final AuthTokenProvider? _authTokenProvider;

  /// 後端等待逾時。超過即視為失敗並 throw [CompanionChatException]。
  static const Duration _timeout = Duration(seconds: 10);

  /// 送出使用者文字，回傳 AI 寵物的回覆字串。
  ///
  /// - [userText]：使用者輸入（必填，後端會擋空字串）。
  /// - [petName] / [memoryContextSummary] / [languageHint] / [replyLanguage]：
  ///   可選的陪伴脈絡；空值不會送出對應欄位。
  ///
  /// 成功條件：HTTP 200 且 `success == true` 且 `reply` 非空白字串。
  /// 其餘情形（非 200、`success != true`、reply 空、JSON 解析錯誤、網路錯誤、
  /// timeout）一律 throw [CompanionChatException]。
  Future<String> reply({
    required String userText,
    String petName = '',
    String memoryContextSummary = '',
    String? languageHint,
    String? replyLanguage,
  }) async {
    final uri = _buildUri();

    final payload = <String, dynamic>{'userText': userText};
    if (petName.isNotEmpty) {
      payload['petName'] = petName;
    }
    if (memoryContextSummary.isNotEmpty) {
      payload['memoryContextSummary'] = memoryContextSummary;
    }
    if (languageHint != null && languageHint.isNotEmpty) {
      payload['languageHint'] = languageHint;
    }
    if (replyLanguage != null && replyLanguage.isNotEmpty) {
      payload['replyLanguage'] = replyLanguage;
    }

    final headers = <String, String>{'Content-Type': 'application/json'};

    // CR-0051 C：後端已 HARD-require 住民 idToken。若有注入 provider 卻取不到
    // token（如 production demo），請求必然 401 → 直接 throw 白話例外，不送出
    // 註定失敗的請求、也不偽造成功。未注入 provider（部分測試情境）則維持原行為，
    // 不帶 Authorization header。
    final provider = _authTokenProvider;
    if (provider != null) {
      String? token;
      try {
        token = await provider();
      } catch (_) {
        token = null;
      }
      if (token == null || token.isEmpty) {
        AppLog.debug('[COMPANION_CHAT] 沒有可用的身分權杖，無法陪聊。');
        throw const CompanionChatException(
          code: 'no_auth',
          message: '寵物現在有點累，等一下再陪你聊好嗎？',
        );
      }
      headers['Authorization'] = 'Bearer $token';
    }

    http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(_timeout);
    } catch (error) {
      // 含 timeout 與網路錯誤：不吞、轉成可辨識的例外向上拋。
      AppLog.error('[COMPANION_CHAT] request failed', error);
      throw const CompanionChatException(
        code: 'network_error',
        message: '連線不太穩，請稍後再試一次。',
      );
    }

    if (response.statusCode != 200) {
      AppLog.debug('[COMPANION_CHAT] non-200 response: ${response.statusCode}');
      throw CompanionChatException(
        code: 'http_${response.statusCode}',
        message: '寵物現在有點累，等一下再陪你聊好嗎？',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      AppLog.error('[COMPANION_CHAT] invalid JSON body', error);
      throw const CompanionChatException(
        code: 'invalid_response',
        message: '寵物現在有點累，等一下再陪你聊好嗎？',
      );
    }

    if (decoded is! Map || decoded['success'] != true) {
      final code =
          decoded is Map && decoded['error'] is String ? decoded['error'] as String : 'unknown';
      AppLog.debug('[COMPANION_CHAT] backend reported failure: $code');
      throw CompanionChatException(
        code: code,
        message: '寵物現在有點累，等一下再陪你聊好嗎？',
      );
    }

    // CR-0051 C：成功 body 現為 {success:true, reply, careAlert?:{...}}。我們只取
    // reply；careAlert 及任何未知欄位一律忽略（多餘的 key 不影響解析），且**不**在
    // 長者畫面呈現任何「已建立風險警示 / 已通知照護人員」等監控感字樣（架構裁示 7）。
    final reply = decoded['reply'];
    if (reply is! String || reply.trim().isEmpty) {
      AppLog.debug('[COMPANION_CHAT] empty reply in successful response');
      throw const CompanionChatException(
        code: 'empty_reply',
        message: '寵物現在有點累，等一下再陪你聊好嗎？',
      );
    }

    return reply;
  }

  /// 以 [AppConfig.apiBaseUrl] 為基底組出 `/api/companion/chat`。
  Uri _buildUri() {
    final base = Uri.parse(AppConfig.apiBaseUrl);
    final basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    return base.replace(
      path: '$basePath/api/companion/chat',
      query: null,
      fragment: null,
    );
  }
}

/// 呼叫 companion chat 後端失敗時拋出的例外。
///
/// 只攜帶可辨識的 [code] 與長者友善的 [message]，**不含 token / 金鑰 /
/// 完整對話內容等敏感資訊**，可安全用於 log 與向上拋。
class CompanionChatException implements Exception {
  const CompanionChatException({required this.code, required this.message});

  /// 機器可辨識的錯誤碼（如 `network_error`、`http_503`、`empty_reply`、
  /// 後端回傳的 `invalid_input` / `openai_unavailable` 等）。
  final String code;

  /// 可直接呈現給長者的白話訊息（不含工程術語）。
  final String message;

  @override
  String toString() => 'CompanionChatException($code): $message';
}
