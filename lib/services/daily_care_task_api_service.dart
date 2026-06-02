import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/daily_care_task.dart';

/// 日常照護任務 API 呼叫失敗時丟出的應用層例外（訊息已是白話，可直接顯示）。
class DailyCareTaskApiException implements Exception {
  const DailyCareTaskApiException(this.friendlyMessage);
  final String friendlyMessage;
  @override
  String toString() => 'DailyCareTaskApiException($friendlyMessage)';
}

/// submit 完成證明後的結果（任務最新狀態 + 該次 submission 的 AI 結果）。
class DailyCareTaskSubmitResult {
  const DailyCareTaskSubmitResult({required this.task, required this.submission});
  final DailyCareTask task;
  final DailyCareTaskSubmission submission;
}

/// 呼叫後端 `/api/daily-care-tasks` 系列端點的 HTTP 服務。
///
/// 失敗一律轉成白話 [DailyCareTaskApiException]，不外洩工程訊息（長者友善）。
/// HTTP client 可注入，方便測試；方法皆為 instance method，可在測試以子類覆寫。
class DailyCareTaskApiService {
  DailyCareTaskApiService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 20);

  String get _base => AppConfig.backendBaseUrl;

  /// 取得某長者的今日任務。
  Future<List<DailyCareTask>> listTasks({required String elderId}) async {
    final uri = Uri.parse('$_base/api/daily-care-tasks')
        .replace(queryParameters: {'elderId': elderId});
    try {
      final response = await _client.get(uri).timeout(_timeout);
      final decoded = _decodeOk(response);
      final tasks = (decoded['tasks'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(DailyCareTask.fromJson)
          .toList();
      return tasks;
    } catch (error) {
      throw _friendly(error, '現在拿不到今天的任務，待會再看看好嗎？');
    }
  }

  /// 建立任務（長者端首次進入時用來補上預設的吃藥 / 喝水 / 運動任務）。
  Future<DailyCareTask> createTask({
    required String elderId,
    required String title,
    required DailyCareTaskType type,
    String scheduledTime = '',
    String description = '',
  }) async {
    final uri = Uri.parse('$_base/api/daily-care-tasks');
    try {
      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'elderId': elderId,
              'title': title,
              'type': dailyCareTaskTypeToString(type),
              'scheduledTime': scheduledTime,
              'description': description,
            }),
          )
          .timeout(_timeout);
      final decoded = _decodeOk(response);
      return DailyCareTask.fromJson(decoded['task'] as Map<String, dynamic>);
    } catch (error) {
      throw _friendly(error, '現在沒辦法建立任務，待會再試一次好嗎？');
    }
  }

  /// 上傳完成證明照片並觸發後端 AI Vision 確認。
  Future<DailyCareTaskSubmitResult> submitProof({
    required String taskId,
    required File image,
  }) async {
    final uri = Uri.parse('$_base/api/daily-care-tasks/$taskId/submit');
    try {
      final request = http.MultipartRequest('POST', uri)
        ..files.add(await http.MultipartFile.fromPath('photo', image.path));
      final streamed = await _client.send(request).timeout(_timeout);
      final response = await http.Response.fromStream(streamed);
      final decoded = _decodeOk(response);
      return DailyCareTaskSubmitResult(
        task: DailyCareTask.fromJson(decoded['task'] as Map<String, dynamic>),
        submission: DailyCareTaskSubmission.fromJson(
          decoded['submission'] as Map<String, dynamic>,
        ),
      );
    } catch (error) {
      throw _friendly(error, '照片上傳沒成功，待會再試一次好嗎？');
    }
  }

  /// 更新任務狀態（管理者 / 系統用）。
  Future<DailyCareTask> updateStatus({
    required String taskId,
    required DailyCareTaskStatus status,
  }) async {
    final uri = Uri.parse('$_base/api/daily-care-tasks/$taskId/status');
    try {
      final response = await _client
          .patch(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'status': _statusToWire(status)}),
          )
          .timeout(_timeout);
      final decoded = _decodeOk(response);
      return DailyCareTask.fromJson(decoded['task'] as Map<String, dynamic>);
    } catch (error) {
      throw _friendly(error, '現在沒辦法更新任務，待會再試一次好嗎？');
    }
  }

  Map<String, dynamic> _decodeOk(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const DailyCareTaskApiException('伺服器忙線中，待會再試一次好嗎？');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['success'] != true) {
      throw const DailyCareTaskApiException('伺服器回應怪怪的，待會再試一次好嗎？');
    }
    return decoded;
  }

  DailyCareTaskApiException _friendly(Object error, String fallback) {
    if (error is DailyCareTaskApiException) return error;
    debugPrint('[DAILY_CARE_TASK] API 失敗：$error');
    return DailyCareTaskApiException(fallback);
  }

  static String _statusToWire(DailyCareTaskStatus status) {
    switch (status) {
      case DailyCareTaskStatus.pending:
        return 'pending';
      case DailyCareTaskStatus.submitted:
        return 'submitted';
      case DailyCareTaskStatus.completed:
        return 'completed';
      case DailyCareTaskStatus.needsReview:
        return 'needs_review';
      case DailyCareTaskStatus.rejected:
        return 'rejected';
      case DailyCareTaskStatus.missed:
        return 'missed';
    }
  }
}
