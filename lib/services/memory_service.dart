import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../utils/zh_convert.dart';
import 'care_alert_notification_service.dart' show AuthTokenProvider;

class MemoryService {
  /// CR-0075：記憶端點後端已掛 `requireResidentCaller`，呼叫需帶住民 Firebase
  /// idToken。token 由建構期注入的 [authTokenProvider] 取得（與 CompanionChatService /
  /// CareAlertNotificationService 同源：`AuthController.resolveNotifyAuthToken`）。
  /// 取不到 token 時**不 throw**（記憶為非關鍵輔助；呼叫端 MemoryController 已 catch
  /// 並靜默降級），維持「沒登入就沒記憶」而非讓對話崩潰。
  MemoryService({http.Client? client, AuthTokenProvider? authTokenProvider})
      : _client = client ?? http.Client(),
        _authTokenProvider = authTokenProvider;

  final http.Client _client;
  final AuthTokenProvider? _authTokenProvider;

  String get _baseApi {
    return AppConfig.apiBaseUrlForSttProxy(AppConfig.defaultSttProxyUrl);
  }

  // 組 request headers：JSON body 時帶 Content-Type；有可用 idToken 時帶
  // Authorization: Bearer。取 token 失敗 / 為空 → 不掛 Authorization（請求會 401，
  // 由呼叫端靜默處理），不 throw。
  Future<Map<String, String>> _headers({bool json = false}) async {
    final headers = <String, String>{};
    if (json) headers['Content-Type'] = 'application/json';
    final provider = _authTokenProvider;
    if (provider != null) {
      String? token;
      try {
        token = await provider();
      } catch (_) {
        token = null;
      }
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    return headers;
  }

  // 舊記憶多以簡體存入，顯示前統一轉台灣繁體（只轉文字欄位，id / 時間 / emotion
  // 等英數欄位不受影響）。
  static const List<String> _memoryTextKeys = [
    'content',
    'summary',
    'memorySummary',
    'memory_summary',
    'memoryText',
    'memory_text',
  ];

  Map<String, dynamic> _memoryToTraditional(Map<String, dynamic> item) {
    for (final key in _memoryTextKeys) {
      final value = item[key];
      if (value is String && value.isNotEmpty) {
        item[key] = toTraditional(value);
      }
    }
    return item;
  }

  Future<Map<String, dynamic>?> extractMemory({
    required String userId,
    String? sessionId,
    String? turnId,
    required String userText,
    required String aiReply,
    required String emotion,
  }) async {
    final url = Uri.parse('$_baseApi/memories/extract');
    final body = jsonEncode({
      'userId': userId,
      'sessionId': sessionId,
      'turnId': turnId,
      'userText': userText,
      'agentReply': aiReply,
      'emotion': emotion,
    });
    final resp =
        await _client.post(url, headers: await _headers(json: true), body: body);
    if (resp.statusCode >= 400) return null;
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> searchMemories({
    required String userId,
    required String query,
    int topK = 5,
  }) async {
    final url = Uri.parse('$_baseApi/memory/search');
    final body = jsonEncode({'userId': userId, 'query': query, 'topK': topK});
    final resp =
        await _client.post(url, headers: await _headers(json: true), body: body);
    if (resp.statusCode >= 400) return [];
    final data = jsonDecode(resp.body) as Map<String, dynamic>?;
    final items = data?['memories'] as List<dynamic>? ?? [];
    return items
        .map((e) => _memoryToTraditional(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<Map<String, dynamic>?> buildMemoryContext({
    required String userId,
    required String userText,
    int limit = 5,
  }) async {
    final url = Uri.parse('$_baseApi/memories/context');
    final body =
        jsonEncode({'userId': userId, 'userText': userText, 'limit': limit});
    final resp =
        await _client.post(url, headers: await _headers(json: true), body: body);
    if (resp.statusCode >= 400) return null;
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> listMemories({
    required String userId,
  }) async {
    final uri = Uri.parse('$_baseApi/memories').replace(queryParameters: {
      'userId': userId,
    });
    final resp = await _client.get(uri, headers: await _headers());
    if (resp.statusCode >= 400) {
      throw Exception('memory list failed');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final items = data['memories'] as List<dynamic>? ?? const [];
    return items
        .map((item) =>
            _memoryToTraditional(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<bool> archiveMemory({
    required String userId,
    required Object memoryId,
  }) async {
    final url = Uri.parse('$_baseApi/memories/$memoryId/archive');
    final resp = await _client.patch(
      url,
      headers: await _headers(json: true),
      body: jsonEncode({'userId': userId}),
    );
    if (resp.statusCode >= 400) return false;
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return data['success'] == true;
  }

  Future<String?> getGreeting({
    required String userId,
    required String petName,
    required int localHour,
  }) async {
    final uri =
        Uri.parse('$_baseApi/memories/greeting').replace(queryParameters: {
      'userId': userId,
      'petName': petName,
      'localHour': localHour.toString(),
    });
    final resp = await _client.get(uri, headers: await _headers());
    if (resp.statusCode >= 400) return null;
    final data = jsonDecode(resp.body) as Map<String, dynamic>?;
    final greeting = data?['greeting'] as String?;
    return greeting == null ? null : toTraditional(greeting);
  }

  Future<bool> forgetRecent({required String userId}) async {
    final url = Uri.parse('$_baseApi/memory/forget-recent');
    final resp = await _client.post(url,
        headers: await _headers(json: true),
        body: jsonEncode({'userId': userId}));
    if (resp.statusCode >= 400) return false;
    final data = jsonDecode(resp.body) as Map<String, dynamic>?;
    return data?['deleted'] == true;
  }
}
