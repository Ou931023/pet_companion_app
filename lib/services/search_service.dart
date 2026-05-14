import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/search_response.dart';

class SearchService {
  SearchService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static bool shouldHandle(String text) {
    final normalized = text.trim();
    if (normalized.isEmpty) return false;
    return [
      '今天',
      '最近',
      '新聞',
      '最新',
      '查一下',
      '幫我查',
      '搜尋',
      '健康',
      '睡眠',
      '運動',
      '喝水',
      '吃藥',
      '長輩',
      '老人',
      '天氣',
      '孤單',
      '難過',
      '心情不好',
      '故事',
    ].any(normalized.contains);
  }

  Future<SearchResponse> search(String query) async {
    try {
      final response = await _client.post(
        Uri.parse(
            '${AppConfig.apiBaseUrlForSttProxy(AppConfig.defaultSttProxyUrl)}/search'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'query': query,
          'mode': 'auto',
          'userProfile': {
            'ageGroup': 'elderly',
            'language': 'zh-TW',
          },
        }),
      );
      if (response.statusCode >= 400) return _fallback();
      return SearchResponse.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } on SocketException {
      return _fallback(message: '現在好像連不上搜尋服務，我先陪你聊聊，晚點再幫你查。');
    } catch (_) {
      return _fallback();
    }
  }

  SearchResponse _fallback({String? message}) {
    return SearchResponse(
      answer: message ?? '目前沒有取得可靠來源，我先不亂說，我可以先陪你聊聊或稍後再幫你查。',
      summary: '搜尋失敗 fallback',
      sources: const [],
      mode: 'general_web_search',
      provider: 'mock_fallback',
      toolUsed: 'fallback',
      confidence: 'low',
      shouldShowSources: false,
    );
  }
}
