import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/daily_care_task.dart';
import '../services/app_usage_tracking_service.dart';
import '../services/daily_care_task_api_service.dart';
import '../utils/app_log.dart';

/// CR-0025 日常照護任務 Controller。
///
/// 負責長者端「今日任務」的載入、首次補上預設任務、以及上傳完成證明照片並依後端
/// AI Vision 結果更新任務狀態。錯誤一律轉白話，不讓長者看到工程訊息。
class DailyCareTaskController extends ChangeNotifier {
  DailyCareTaskController({
    DailyCareTaskApiService? apiService,
    AppUsageTrackingService? trackingService,
  })  : _api = apiService ?? DailyCareTaskApiService(),
        _trackingService = trackingService;

  final DailyCareTaskApiService _api;
  final AppUsageTrackingService? _trackingService;

  String _elderId = 'default_user';
  List<DailyCareTask> _tasks = const [];
  bool _isLoading = false;
  String? _errorMessage;
  String? _submittingTaskId;

  /// 已嘗試補過預設任務的 elderId，避免每次空清單都重複建立。
  final Set<String> _seededElders = {};

  List<DailyCareTask> get tasks => _tasks;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// 某任務是否正在上傳 / 等待 AI 確認中（給卡片顯示 loading）。
  bool isSubmitting(String taskId) => _submittingTaskId == taskId;

  /// 依帳號切換命名空間（由 app.dart applyAccount 呼叫）。不自動載入。
  void setElderId(String? elderId) {
    final next =
        (elderId == null || elderId.isEmpty) ? 'default_user' : elderId;
    if (next == _elderId) return;
    _elderId = next;
    _tasks = const [];
    _errorMessage = null;
    notifyListeners();
  }

  /// 載入今日任務；若該長者尚無任務，首次自動補上吃藥 / 喝水 / 運動三項。
  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      var tasks = await _api.listTasks(elderId: _elderId);
      if (tasks.isEmpty && !_seededElders.contains(_elderId)) {
        _seededElders.add(_elderId);
        await _seedDefaultTasks();
        tasks = await _api.listTasks(elderId: _elderId);
      }
      _tasks = tasks;
    } on DailyCareTaskApiException catch (error) {
      _errorMessage = error.friendlyMessage;
    } catch (error) {
      AppLog.error('[DAILY_CARE_TASK] load failed', error);
      _errorMessage = '現在拿不到今天的任務，待會再看看好嗎？';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 上傳完成證明照片 → 後端 AI Vision 確認 → 更新該任務狀態。
  /// 回傳該次 submission（含 AI 結果）供畫面顯示；失敗回 null 並設白話訊息。
  Future<DailyCareTaskSubmission?> submitProof(
    DailyCareTask task,
    File image,
  ) async {
    _submittingTaskId = task.id;
    _errorMessage = null;
    notifyListeners();
    try {
      final result = await _api.submitProof(taskId: task.id, image: image);
      _tasks = _tasks
          .map((t) => t.id == result.task.id ? result.task : t)
          .toList(growable: false);
      unawaited(
        _trackingService?.track(
              'photo_verification_submitted',
              metadata: {
                'taskType': task.type.name,
                'verificationStatus':
                    result.submission.verification?.status.name,
              },
            ) ??
            Future<bool>.value(false),
      );
      return result.submission;
    } on DailyCareTaskApiException catch (error) {
      _errorMessage = error.friendlyMessage;
      return null;
    } catch (error) {
      AppLog.error('[DAILY_CARE_TASK] submitProof failed', error);
      _errorMessage = '照片上傳沒成功，待會再試一次好嗎？';
      return null;
    } finally {
      _submittingTaskId = null;
      notifyListeners();
    }
  }

  Future<void> _seedDefaultTasks() async {
    const defaults = [
      (title: '吃藥', type: DailyCareTaskType.medication, time: '08:00'),
      (title: '喝水', type: DailyCareTaskType.hydration, time: '12:00'),
      (title: '運動', type: DailyCareTaskType.exercise, time: '16:00'),
    ];
    for (final d in defaults) {
      await _api.createTask(
        elderId: _elderId,
        title: d.title,
        type: d.type,
        scheduledTime: d.time,
      );
    }
  }
}
