import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

class WebSearchResult {
  const WebSearchResult({
    required this.success,
    required this.needsSearch,
    required this.answer,
    required this.message,
    required this.highRisk,
  });

  final bool success;
  final bool needsSearch;
  final String answer;
  final String message;
  final bool highRisk;
}

class WebSearchService {
  WebSearchService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static bool shouldSearch(String text) {
    final normalized = text.trim();
    if (normalized.isEmpty) return false;
    return [
      '今天有什麼新聞',
      '新聞',
      '查天氣',
      '天氣',
      '附近有什麼活動',
      '附近活動',
      '最近活動',
      '幫我查',
      '查一下',
      '幫我搜尋',
      '最近詐騙',
      '詐騙新聞',
      '即時資訊',
      '健康資訊',
    ].any(normalized.contains);
  }

  Future<WebSearchResult> search(String query) async {
    if (!shouldSearch(query)) {
      return const WebSearchResult(
        success: true,
        needsSearch: false,
        answer: '',
        message: '',
        highRisk: false,
      );
    }

    try {
      final response = await _client.post(
        Uri.parse('$_baseApi/web/search'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'query': query}),
      );
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode >= 400) {
        return WebSearchResult(
          success: false,
          needsSearch: true,
          answer: '',
          message: (data['message'] as String?) ?? _failedMessage,
          highRisk: false,
        );
      }
      return WebSearchResult(
        success: data['success'] == true,
        needsSearch: data['needsSearch'] == true,
        answer: (data['answer'] as String?) ?? '',
        message: (data['message'] as String?) ?? '',
        highRisk: data['highRisk'] == true,
      );
    } on SocketException {
      return const WebSearchResult(
        success: false,
        needsSearch: true,
        answer: '',
        message: '現在好像連不上網路，我晚點再幫你查。',
        highRisk: false,
      );
    } catch (_) {
      return const WebSearchResult(
        success: false,
        needsSearch: true,
        answer: '',
        message: _failedMessage,
        highRisk: false,
      );
    }
  }

  String get _baseApi {
    return AppConfig.apiBaseUrlForSttProxy(AppConfig.defaultSttProxyUrl);
  }

  static const String _failedMessage = '搜尋暫時失敗了，我晚點再幫你查。';
}
