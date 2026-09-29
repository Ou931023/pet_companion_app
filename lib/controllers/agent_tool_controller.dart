import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/agent_route_result.dart';
import '../models/agent_tool_execution_result.dart';
import '../models/agent_tool_intent.dart';
import '../services/agent_router_service.dart';
import '../services/native_tool_executor_service.dart';
import 'app_navigation_controller.dart';
import 'memory_controller.dart';
import 'profile_controller.dart';
import 'reminder_controller.dart';
import '../services/search_service.dart';
import '../utils/app_log.dart';

class AgentToolController extends ChangeNotifier {
  AgentToolController({
    required this.profileController,
    required this.routerService,
    required this.executorService,
    required this.reminderController,
    required this.searchService,
    required this.navigationController,
    required this.memoryController,
    this.routeTimeout = const Duration(seconds: 5),
  });

  final ProfileController profileController;
  final AgentRouterService routerService;
  final NativeToolExecutorService executorService;
  final ReminderController reminderController;
  final SearchService searchService;
  final AppNavigationController navigationController;
  final MemoryController memoryController;
  final Duration routeTimeout;

  static const routeFailureMessage = '這次還沒能幫你安排這個動作，請稍後再說一次。';
  static const executionUnknownMessage =
      '目前無法確認這個動作是否完成，請先確認結果、不要重複操作。我暫時不能代辦其他動作，但可以繼續陪你聊。';
  static const executionFailureMessage = '這個動作目前沒辦法完成。';
  static const busyMessage = '前一個動作還在處理，這次的新要求還沒有執行，請先等一下。';

  AgentToolIntent? _pendingIntent;
  AgentToolExecutionResult? _executionResult;
  bool _isRouting = false;
  bool _isExecuting = false;
  String? _errorMessage;
  int _generation = 0;
  String? _sessionId;
  String? _pendingShopContext;
  final Set<String> _routedTurns = {};
  bool _disposed = false;
  Object? _executionOperation;
  bool _hasUncertainExecution = false;

  AgentToolIntent? get pendingIntent {
    if (_pendingIntent?.toolName == 'purchase_shop_item' &&
        _pendingShopContext != executorService.shopContextKey?.call()) {
      _pendingIntent = null;
    }
    return _pendingIntent;
  }

  AgentToolExecutionResult? get executionResult => _executionResult;
  bool get isRouting => _isRouting;
  bool get isExecuting => _isExecuting;
  bool get hasUncertainExecution => _hasUncertainExecution;
  String? get errorMessage => _errorMessage;

  Future<void> routeFromUserText(
    String userText, {
    required String sessionId,
    required String turnId,
    required String petName,
    required String emotion,
    required String languageHint,
    Map<String, dynamic> petState = const {},
    List<Map<String, dynamic>> recentTurns = const [],
  }) async {
    final normalized = userText.trim();
    if (_disposed || normalized.isEmpty) return;
    if (_sessionId != null && _sessionId != sessionId) clear();
    if (_isRouting || _isExecuting || _hasUncertainExecution) return;
    _sessionId = sessionId;
    final turnKey = '$sessionId:$turnId';
    if (!_routedTurns.add(turnKey)) return;
    final generation = _generation;
    final accountContext = executorService.shopContextKey?.call();
    _isRouting = true;
    _errorMessage = null;
    _executionResult = null;
    notifyListeners();
    try {
      final AgentRouteResult result = await routerService
          .route(
            sttProxyUrl: profileController.sttProxyUrl,
            userText: normalized,
            sessionId: sessionId,
            turnId: turnId,
            petName: petName,
            emotion: emotion,
            languageHint: languageHint,
            petState: petState,
            recentTurns: recentTurns,
          )
          .timeout(routeTimeout);
      if (generation != _generation ||
          accountContext != executorService.shopContextKey?.call()) {
        return;
      }
      if (!result.hasToolIntent || result.intent == null) {
        _errorMessage =
            result.errorMessage.isEmpty ? null : routeFailureMessage;
        return;
      }
      var intent = result.intent!;
      if (intent.toolName == 'purchase_shop_item') {
        final quote = executorService.prepareShopPurchase(intent);
        if (quote == null) {
          _pendingIntent = null;
          _errorMessage = '請先在寵物商城確認商品、數量與登入狀態。';
          return;
        }
        intent = quote;
        _pendingShopContext = executorService.shopContextKey?.call();
      }
      _pendingIntent = intent;
      _executionResult = null;
      // 輪次控制 / 安全閘門：
      // - 低風險操作（create_reminder / play_music / navigate / tell_story /
      //   save_memory / retrieve_memory…）直接執行，不打斷使用者。
      // - 高影響操作（make_call / send_message / notify_caregiver /
      //   delete_memory / logout / purchase_pet_skin…）保留為 pending，等使用者
      //   明確確認（confirmAndExecute）後才執行，絕不自動執行。
      //   pendingIntent.userFacingMessage 即白話確認問句，供確認 UI / 寵物語音使用。
      if (intent.requiresConfirmation) {
        return;
      }
      await _executeCurrentIntent();
    } catch (_) {
      if (generation != _generation || _disposed) return;
      _errorMessage = routeFailureMessage;
      AppLog.debug('[AgentToolController] route_failed');
    } finally {
      if (generation == _generation) {
        _isRouting = false;
        notifyListeners();
      }
    }
  }

  Future<void> confirmAndExecute() async {
    if (_disposed) return;
    final intent = pendingIntent;
    if (intent == null ||
        !intent.isExecutable ||
        _isExecuting ||
        _hasUncertainExecution) {
      return;
    }
    _pendingIntent = intent.copyWith(status: AgentToolStatus.confirmed);
    notifyListeners();
    await _executeCurrentIntent();
  }

  Future<void> executeLowRiskIfAllowed() async {
    final intent = _pendingIntent;
    if (_disposed ||
        intent == null ||
        !intent.isExecutable ||
        intent.requiresConfirmation ||
        _isExecuting ||
        _hasUncertainExecution) {
      return;
    }
    await _executeCurrentIntent();
  }

  void cancelIntent() {
    if (_disposed) return;
    if (_isExecuting || _hasUncertainExecution) {
      _errorMessage = executionUnknownMessage;
      notifyListeners();
      return;
    }
    executorService.cancelShopPurchase();
    final intent = _pendingIntent;
    _pendingIntent = null;
    _executionResult = intent == null
        ? null
        : AgentToolExecutionResult.failed(
            toolName: intent.toolName,
            message: '已取消工具執行。',
          );
    _errorMessage = null;
    notifyListeners();
  }

  void clear() {
    if (_disposed) return;
    _generation++;
    executorService.cancelShopPurchase();
    _pendingShopContext = null;
    _pendingIntent = null;
    _executionResult = null;
    _errorMessage = null;
    _isRouting = false;
    // Clearing presentation cannot cancel an external side effect in flight.
    _isExecuting = _executionOperation != null;
    notifyListeners();
  }

  Future<void> _executeCurrentIntent() async {
    final intent = _pendingIntent;
    if (_disposed ||
        intent == null ||
        !intent.isExecutable ||
        _isExecuting ||
        _hasUncertainExecution) {
      return;
    }
    if (intent.toolName == 'purchase_shop_item' &&
        intent.status != AgentToolStatus.confirmed) {
      return;
    }
    final generation = _generation;
    final operation = Object();
    _executionOperation = operation;
    _isExecuting = true;
    _errorMessage = null;
    _pendingIntent = intent.copyWith(status: AgentToolStatus.executing);
    notifyListeners();
    try {
      final result = await executorService.execute(
        intent: intent,
        reminderController: reminderController,
        searchService: searchService,
        navigationController: navigationController,
        memoryController: memoryController,
      );
      if (generation != _generation || _disposed) return;
      _executionResult = result.success
          ? result
          : AgentToolExecutionResult.failed(
              toolName: intent.toolName, message: executionFailureMessage);
      _pendingIntent = result.success
          ? null
          : intent.copyWith(status: AgentToolStatus.failed);
    } catch (_) {
      // A thrown executor may already have caused a side effect. Keep this
      // controller fail-closed even across clear/session changes, not retryable.
      _hasUncertainExecution = true;
      if (generation != _generation || _disposed) return;
      AppLog.debug('[AgentToolController] execution_outcome_unknown');
      _executionResult = AgentToolExecutionResult.failed(
        toolName: intent.toolName,
        message: executionUnknownMessage,
      );
      _pendingIntent = intent.copyWith(status: AgentToolStatus.failed);
    } finally {
      if (identical(_executionOperation, operation)) {
        _executionOperation = null;
        _isExecuting = false;
        if (!_disposed) notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
