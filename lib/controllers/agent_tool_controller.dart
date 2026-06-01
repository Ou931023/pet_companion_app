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

class AgentToolController extends ChangeNotifier {
  AgentToolController({
    required this.profileController,
    required this.routerService,
    required this.executorService,
    required this.reminderController,
    required this.searchService,
    required this.navigationController,
    required this.memoryController,
  });

  final ProfileController profileController;
  final AgentRouterService routerService;
  final NativeToolExecutorService executorService;
  final ReminderController reminderController;
  final SearchService searchService;
  final AppNavigationController navigationController;
  final MemoryController memoryController;

  AgentToolIntent? _pendingIntent;
  AgentToolExecutionResult? _executionResult;
  bool _isRouting = false;
  bool _isExecuting = false;
  String? _errorMessage;

  AgentToolIntent? get pendingIntent => _pendingIntent;
  AgentToolExecutionResult? get executionResult => _executionResult;
  bool get isRouting => _isRouting;
  bool get isExecuting => _isExecuting;
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
    if (normalized.isEmpty || _isRouting) return;
    _isRouting = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final AgentRouteResult result = await routerService.route(
        sttProxyUrl: profileController.sttProxyUrl,
        userText: normalized,
        sessionId: sessionId,
        turnId: turnId,
        petName: petName,
        emotion: emotion,
        languageHint: languageHint,
        petState: petState,
        recentTurns: recentTurns,
      );
      if (!result.hasToolIntent || result.intent == null) {
        _errorMessage =
            result.errorMessage.isEmpty ? null : result.errorMessage;
        return;
      }
      final intent = result.intent!;
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
    } catch (error) {
      _errorMessage = error.toString();
      debugPrint('[AgentToolController] route failed: $error');
    } finally {
      _isRouting = false;
      notifyListeners();
    }
  }

  Future<void> confirmAndExecute() async {
    final intent = _pendingIntent;
    if (intent == null || !intent.isExecutable || _isExecuting) return;
    _pendingIntent = intent.copyWith(status: AgentToolStatus.confirmed);
    notifyListeners();
    await _executeCurrentIntent();
  }

  Future<void> executeLowRiskIfAllowed() async {
    final intent = _pendingIntent;
    if (intent == null || intent.requiresConfirmation || _isExecuting) return;
    await _executeCurrentIntent();
  }

  void cancelIntent() {
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
    _pendingIntent = null;
    _executionResult = null;
    _errorMessage = null;
    _isRouting = false;
    _isExecuting = false;
    notifyListeners();
  }

  Future<void> _executeCurrentIntent() async {
    final intent = _pendingIntent;
    if (intent == null) return;
    _isExecuting = true;
    _errorMessage = null;
    _pendingIntent = intent.copyWith(status: AgentToolStatus.executing);
    notifyListeners();
    final result = await executorService.execute(
      intent: intent,
      reminderController: reminderController,
      searchService: searchService,
      navigationController: navigationController,
      memoryController: memoryController,
    );
    _executionResult = result;
    _pendingIntent =
        result.success ? null : intent.copyWith(status: AgentToolStatus.failed);
    _isExecuting = false;
    notifyListeners();
  }
}
