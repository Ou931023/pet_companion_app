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

  /// CR-0080：即時資訊 intent 關鍵字。必須與後端
  /// `tavilySearchService.js` 的 `REALTIME_INFO_KEYWORDS` 保持一致——
  /// 前端放行的查詢，後端才會真的去搜尋並整理結果回來；兩端對齊可避免
  /// 「前端判定要查、後端又說不用查」而回出生硬的「查不到」。
  /// 只放「明確需要外部即時資訊」的詞，刻意不放單獨的「今天 / 現在 / 最近」，
  /// 以免把「我今天有點累」這類心情話誤判成搜尋。
  static const List<String> realtimeInfoKeywords = [
    // 新聞 / 防詐
    '今天有什麼新聞',
    '新聞',
    '看新聞',
    '啥物新聞',
    '啥新聞',
    '什麼新聞',
    '有啥新聞',
    '有什麼新聞',
    '今仔日新聞',
    '新聞予我聽',
    '最新消息',
    '防詐',
    '詐騙新聞',
    '最近詐騙',
    // 天氣
    '查天氣',
    '天氣',
    '氣溫',
    '會不會下雨',
    '下雨機率',
    // 活動
    '附近有什麼活動',
    '附近活動',
    '最近活動',
    // 主動查詢動詞
    '幫我查',
    '查一下',
    '幫我搜尋',
    '幫我搜',
    '上網查',
    '搜尋',
    '即時資訊',
    '健康資訊',
    // 補助 / 政策
    '補助',
    '津貼',
    '長照',
    '政策',
    '法規',
    '規定',
    // 價格 / 時刻
    '油價',
    '匯率',
    '股市',
    '股價',
    '票價',
    '高鐵時刻',
    '台鐵時刻',
    '營業時間',
    '開放時間',
    // 災防 / 公共
    '颱風',
    '地震',
    '路況',
    '停水',
    '停電',
    '確診',
    '疫情',
    // 申請流程
    '怎麼申請',
    '如何申請',
  ];

  static bool shouldSearch(String text) {
    final normalized = text.trim();
    if (normalized.isEmpty) return false;
    if (isBroadNewsRequest(normalized)) return false;
    return realtimeInfoKeywords.any(normalized.contains);
  }

  static bool isBroadNewsRequest(String text) {
    final normalized = text.replaceAll(RegExp(r'[\s，。！？!?、,.]'), '');
    if (normalized.isEmpty || !normalized.contains(RegExp(r'新聞|消息'))) {
      return false;
    }
    if (_newsTopicPattern.hasMatch(normalized)) return false;
    return _broadNewsPattern.hasMatch(normalized);
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

  static final RegExp _newsTopicPattern = RegExp(
    r'防詐|詐騙|健康|長照|醫療|天氣|政治|運動|股票|股市|財經|社會|地方|嘉義|台灣|國際|娛樂|棒球|政策|補助|高齡|照護|食安|交通|颱風|地震',
  );

  static final RegExp _broadNewsPattern = RegExp(
    r'^(幫我|請|想|我要|我想|欲|我欲)?(查|搜尋|搜|看|聽|聽看)?(一下|一下子)?(今天|今仔日|今日|現在|最近)?(有)?(什麼|啥物|啥|啥米)?(重要)?(新聞|消息)(予我聽|給我聽|給我看|一下|嗎|呢|啦|喔)?$',
  );
}
