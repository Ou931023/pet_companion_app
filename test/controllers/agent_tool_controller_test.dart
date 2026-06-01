import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/controllers/agent_tool_controller.dart';
import 'package:pet_companion_app/controllers/app_navigation_controller.dart';
import 'package:pet_companion_app/controllers/memory_controller.dart';
import 'package:pet_companion_app/controllers/profile_controller.dart';
import 'package:pet_companion_app/controllers/reminder_controller.dart';
import 'package:pet_companion_app/models/agent_route_result.dart';
import 'package:pet_companion_app/models/agent_tool_execution_result.dart';
import 'package:pet_companion_app/models/agent_tool_intent.dart';
import 'package:pet_companion_app/services/agent_router_service.dart';
import 'package:pet_companion_app/services/local_storage_service.dart';
import 'package:pet_companion_app/services/memory_service.dart';
import 'package:pet_companion_app/services/native_tool_executor_service.dart';
import 'package:pet_companion_app/services/notification_service.dart';
import 'package:pet_companion_app/services/reminder_service.dart';
import 'package:pet_companion_app/services/search_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('high impact intent waits for confirmation (does NOT auto-execute)',
      () async {
    final harness = await _Harness.create(
      router: _FakeRouter(
        AgentRouteResult(
          hasToolIntent: true,
          intent: _intent(
            'open_phone_dialer',
            riskLevel: AgentToolRiskLevel.high,
            requiresConfirmation: true,
          ),
        ),
      ),
    );
    addTearDown(harness.dispose);

    await harness.controller.routeFromUserText(
      '幫我打給女兒',
      sessionId: 's',
      turnId: 't',
      petName: '小伴',
      emotion: 'neutral',
      languageHint: 'zh-TW',
    );

    // 高影響操作：不自動執行，保留 pending 等使用者確認。
    expect(harness.executor.executedCount, 0);
    expect(harness.controller.pendingIntent, isNotNull);
    expect(harness.controller.pendingIntent!.requiresConfirmation, isTrue);
    expect(harness.controller.executionResult, isNull);
  });

  test('high impact intent executes after explicit confirmation', () async {
    final harness = await _Harness.create(
      router: _FakeRouter(
        AgentRouteResult(
          hasToolIntent: true,
          intent: _intent(
            'open_phone_dialer',
            riskLevel: AgentToolRiskLevel.high,
            requiresConfirmation: true,
          ),
        ),
      ),
    );
    addTearDown(harness.dispose);

    await harness.controller.routeFromUserText(
      '幫我打給女兒',
      sessionId: 's',
      turnId: 't',
      petName: '小伴',
      emotion: 'neutral',
      languageHint: 'zh-TW',
    );
    expect(harness.executor.executedCount, 0);

    await harness.controller.confirmAndExecute();

    expect(harness.executor.executedCount, 1);
    expect(harness.controller.executionResult?.success, isTrue);
  });

  test('low risk intent can execute automatically', () async {
    final harness = await _Harness.create(
      router: _FakeRouter(
        AgentRouteResult(
          hasToolIntent: true,
          intent: _intent('play_music'),
        ),
      ),
    );
    addTearDown(harness.dispose);

    await harness.controller.routeFromUserText(
      '幫我播放放鬆音樂',
      sessionId: 's',
      turnId: 't',
      petName: '小伴',
      emotion: 'neutral',
      languageHint: 'zh-TW',
    );

    expect(harness.executor.executedCount, 1);
    expect(harness.controller.pendingIntent, isNull);
  });

  test('router failure does not crash controller', () async {
    final harness = await _Harness.create(
      router: _FakeRouter(
        AgentRouteResult.noIntent(errorMessage: 'agent route timeout'),
      ),
    );
    addTearDown(harness.dispose);

    await harness.controller.routeFromUserText(
      '幫我打給女兒',
      sessionId: 's',
      turnId: 't',
      petName: '小伴',
      emotion: 'neutral',
      languageHint: 'zh-TW',
    );

    expect(harness.controller.pendingIntent, isNull);
    expect(harness.controller.errorMessage, contains('timeout'));
  });
}

AgentToolIntent _intent(
  String toolName, {
  AgentToolRiskLevel riskLevel = AgentToolRiskLevel.low,
  bool requiresConfirmation = false,
}) {
  return AgentToolIntent(
    id: 'agent_tool_test',
    toolName: toolName,
    displayName: toolName,
    arguments: const {},
    requiresConfirmation: requiresConfirmation,
    riskLevel: riskLevel,
    status: AgentToolStatus.pending,
    userFacingMessage: toolName,
    createdAt: DateTime.now(),
  );
}

class _FakeRouter extends AgentRouterService {
  _FakeRouter(this.result);

  final AgentRouteResult result;

  @override
  Future<AgentRouteResult> route({
    required String sttProxyUrl,
    required String userText,
    required String sessionId,
    required String turnId,
    required String petName,
    required String emotion,
    required String languageHint,
    Map<String, dynamic> petState = const {},
    List<Map<String, dynamic>> recentTurns = const [],
  }) async {
    return result;
  }
}

class _FakeExecutor extends NativeToolExecutorService {
  int executedCount = 0;

  @override
  Future<AgentToolExecutionResult> execute({
    required AgentToolIntent intent,
    required ReminderController reminderController,
    required SearchService searchService,
    required AppNavigationController navigationController,
    required MemoryController memoryController,
  }) async {
    executedCount++;
    return AgentToolExecutionResult.succeeded(
      toolName: intent.toolName,
      message: 'ok',
    );
  }
}

class _Harness {
  _Harness({
    required this.controller,
    required this.executor,
    required this.profileController,
    required this.memoryController,
    required this.reminderController,
  });

  final AgentToolController controller;
  final _FakeExecutor executor;
  final ProfileController profileController;
  final MemoryController memoryController;
  final ReminderController reminderController;

  void dispose() {
    controller.dispose();
    reminderController.dispose();
    memoryController.dispose();
    profileController.dispose();
  }

  static Future<_Harness> create({required AgentRouterService router}) async {
    SharedPreferences.setMockInitialValues({});
    final profile = ProfileController(LocalStorageService());
    await profile.completeOnboarding('小伴');
    final memory = MemoryController(MemoryService());
    final reminder = ReminderController(
      reminderService: ReminderService(),
      notificationService: NotificationService(),
    );
    final executor = _FakeExecutor();
    final controller = AgentToolController(
      profileController: profile,
      routerService: router,
      executorService: executor,
      reminderController: reminder,
      searchService: SearchService(),
      navigationController: AppNavigationController(),
      memoryController: memory,
    );
    return _Harness(
      controller: controller,
      executor: executor,
      profileController: profile,
      memoryController: memory,
      reminderController: reminder,
    );
  }
}
