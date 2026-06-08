import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../utils/app_log.dart';

/// 呼叫後端 `POST /api/companion/chat` 取得 AI 寵物的文字回覆。
///
/// 設計原則（CR-0049 B2）：
/// - 金鑰留在後端：Flutter 不持有、也不傳 OpenAI key。本服務只呼叫自家後端。
/// - 失敗一律 throw [CompanionChatException]，**絕不吞錯、絕不回 fake / 罐頭、
///   絕不回空字串**。呼叫端（B3a 接線）負責把例外轉成長者友善的白話提示。
/// - log 只走 [AppLog]（release 為 no-op），且不輸出完整 reply 內容。
class CompanionChatService {
  CompanionChatService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

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

    http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
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
