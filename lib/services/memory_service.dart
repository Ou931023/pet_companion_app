import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../utils/zh_convert.dart';

class MemoryService {
  MemoryService();

  String get _baseApi {
    return AppConfig.apiBaseUrlForSttProxy(AppConfig.defaultSttProxyUrl);
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
    final resp = await http.post(url,
        headers: {'Content-Type': 'application/json'}, body: body);
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
    final resp = await http.post(url,
        headers: {'Content-Type': 'application/json'}, body: body);
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
    final resp = await http.post(url,
        headers: {'Content-Type': 'application/json'}, body: body);
    if (resp.statusCode >= 400) return null;
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> listMemories({
    required String userId,
  }) async {
    final uri = Uri.parse('$_baseApi/memories').replace(queryParameters: {
      'userId': userId,
    });
    final resp = await http.get(uri);
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
    final resp = await http.patch(
      url,
      headers: {'Content-Type': 'application/json'},
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
    final resp = await http.get(uri);
    if (resp.statusCode >= 400) return null;
    final data = jsonDecode(resp.body) as Map<String, dynamic>?;
    final greeting = data?['greeting'] as String?;
    return greeting == null ? null : toTraditional(greeting);
  }

  Future<bool> forgetRecent({required String userId}) async {
    final url = Uri.parse('$_baseApi/memory/forget-recent');
    final resp = await http.post(url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': userId}));
    if (resp.statusCode >= 400) return false;
    final data = jsonDecode(resp.body) as Map<String, dynamic>?;
    return data?['deleted'] == true;
  }
}
