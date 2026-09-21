import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/mood_diary_entry.dart';
import 'care_alert_notification_service.dart' show AuthTokenProvider;

class MoodDiaryException implements Exception {
  const MoodDiaryException(this.message);
  final String message;
}

/// An account-bound service; stale requests cannot cross a sign-in change.
class MoodDiaryService {
  MoodDiaryService({
    required this.ownerId,
    required String Function() currentUserId,
    required AuthTokenProvider authTokenProvider,
    http.Client? client,
  })  : _currentUserId = currentUserId,
        _authTokenProvider = authTokenProvider,
        _client = client ?? http.Client();

  final String ownerId;
  final String Function() _currentUserId;
  final AuthTokenProvider _authTokenProvider;
  final http.Client _client;

  void dispose() => _client.close();

  Future<List<MoodDiaryEntry>> list() async {
    final data = await _request('GET');
    try {
      return (data['entries'] as List)
          .map(
              (entry) => MoodDiaryEntry.fromJson(entry as Map<String, dynamic>))
          .toList();
    } catch (_) {
      throw const MoodDiaryException('日記暫時讀不到，請再試一次。');
    }
  }

  Future<void> create({
    required String mood,
    required String content,
    required bool sharedWithCaregiver,
  }) async {
    if (!MoodDiaryEntry.moods.containsKey(mood) ||
        content.trim().isEmpty ||
        content.trim().runes.length > 1000) {
      throw const MoodDiaryException('請寫下今天的心情，最多 1000 字。');
    }
    await _request('POST', body: {
      'mood': mood,
      'content': content.trim(),
      'sharedWithCaregiver': sharedWithCaregiver,
    });
  }

  Future<void> setSharing(String id, bool share) async {
    await _request('PATCH', id: id, body: {'sharedWithCaregiver': share});
  }

  Future<void> delete(String id) async {
    await _request('DELETE', id: id);
  }

  void _checkOwner() {
    if (ownerId.isEmpty ||
        ownerId == 'default_user' ||
        _currentUserId() != ownerId) {
      throw const MoodDiaryException('請先登入，再查看自己的日記。');
    }
  }

  Future<Map<String, dynamic>> _request(
    String method, {
    String? id,
    Map<String, dynamic>? body,
  }) async {
    try {
      _checkOwner();
      final token = await _authTokenProvider();
      _checkOwner();
      if (token == null || token.trim().isEmpty) {
        throw const MoodDiaryException('請重新登入，再查看日記。');
      }
      final suffix = id == null ? '' : '/${Uri.encodeComponent(id)}';
      final request = http.Request(
          method, Uri.parse('${AppConfig.apiBaseUrl}/api/mood-diary$suffix'));
      request.headers.addAll({
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      });
      if (body != null) request.body = jsonEncode(body);
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 25));
      _checkOwner();
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const MoodDiaryException('請重新登入，再查看自己的日記。');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const MoodDiaryException('日記暫時連不上，請稍後再試。');
      }
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic> || data['success'] != true) {
        throw const MoodDiaryException('日記暫時連不上，請稍後再試。');
      }
      return data;
    } on MoodDiaryException {
      rethrow;
    } catch (_) {
      // Never log diary text, response bodies, or authentication headers.
      throw MoodDiaryException(
          method == 'POST' ? '還無法確認是否儲存，請先重新整理日記，避免重複儲存。' : '日記暫時連不上，請稍後再試。');
    }
  }
}
