import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

/// 對話標題服務（CR-0027）。
///
/// 呼叫後端 `POST /api/conversation/title`，把一段對話內容換成簡短自然的繁中標題。
/// 後端無金鑰 / 失敗會自行退回本地短標題；本服務再把網路錯誤吞掉回 null，
/// 讓 Controller 退回 fallback，畫面永遠不卡。
///
/// 設計成可被測試覆寫（[generateTitle] 為 instance method），測試可注入 fake。
class ConversationTitleService {
  const ConversationTitleService();

  String get _baseApi =>
      AppConfig.apiBaseUrlForSttProxy(AppConfig.defaultSttProxyUrl);

  /// 依對話內容產生標題；失敗或空白回 null（交給呼叫端 fallback）。
  Future<String?> generateTitle({
    required String firstUserText,
    required String conversationText,
  }) async {
    try {
      final resp = await http.post(
        Uri.parse('$_baseApi/conversation/title'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'firstUserText': firstUserText,
          'conversationText': conversationText,
        }),
      );
      if (resp.statusCode >= 400) return null;
      final data = jsonDecode(resp.body) as Map<String, dynamic>?;
      final title = (data?['title'] as String?)?.trim() ?? '';
      return title.isEmpty ? null : title;
    } catch (_) {
      return null;
    }
  }
}
