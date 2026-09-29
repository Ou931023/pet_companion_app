import 'dart:async';

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
  test('CR0110 failed executor payload never exposes unsafe text or data',
      () async {
    final harness = await _Harness.create(
        router: _FakeRouter(AgentRouteResult(
            hasToolIntent: true, intent: _intent('play_music'))));
    addTearDown(harness.dispose);
    harness.executor.onExecute = () async => AgentToolExecutionResult.failed(
        toolName: 'play_music',
        message: 'UNSAFE_SENTINEL https://private.invalid',
        data: const {'unsafe': 'UNSAFE_SENTINEL'});
    await _route(harness.controller);
    expect(harness.controller.executionResult?.message,
        AgentToolController.executionFailureMessage);
    expect(harness.controller.executionResult?.data, isEmpty);
  });

  test('CR0110 late executor throw after clear still blocks a new session',
      () async {
    final harness = await _Harness.create(
        router: _FakeRouter(AgentRouteResult(
            hasToolIntent: true, intent: _intent('play_music'))));
    addTearDown(harness.dispose);
    final done = Completer<AgentToolExecutionResult>();
    harness.executor.onExecute = () => done.future;
    final routed = _route(harness.controller);
    await pumpEventQueue();
    harness.controller.clear();
    done.completeError(StateError('late unsafe error'));
    await routed;
    expect(harness.controller.executionResult, isNull);
    expect(harness.controller.hasUncertainExecution, isTrue);
    await _route(harness.controller, session: 'new', turn: 'new');
    expect(harness.executor.executedCount, 1);
  });

  test('CR0110 ordinary chat preserves a pending confirmation', () async {
    final router = _FakeRouter(AgentRouteResult(
        hasToolIntent: true,
        intent: _intent('open_phone_dialer',
            riskLevel: AgentToolRiskLevel.high, requiresConfirmation: true)));
    final harness = await _Harness.create(router: router);
    addTearDown(harness.dispose);
    await _route(harness.controller);
    final pending = harness.controller.pendingIntent;
    router.onRoute = () async => AgentRouteResult.noIntent();
    await _route(harness.controller, turn: 'chat-question');
    expect(harness.controller.pendingIntent, same(pending));
    await harness.controller.confirmAndExecute();
    expect(harness.executor.executedCount, 1);
  });

  test('CR0110 current router throw has safe feedback and releases routing',
      () async {
    final router = _FakeRouter(AgentRouteResult.noIntent())
      ..onRoute = () async => throw StateError('private command and URL');
    final harness = await _Harness.create(router: router);
    addTearDown(harness.dispose);
    await _route(harness.controller);
    expect(harness.controller.isRouting, isFalse);
    expect(harness.controller.errorMessage,
        AgentToolController.routeFailureMessage);
    expect(harness.executor.executedCount, 0);
  });

  test('CR0110 route timeout ignores late intent and allows a fresh route',
      () async {
    final late = Completer<AgentRouteResult>();
    final router = _FakeRouter(AgentRouteResult.noIntent())
      ..onRoute = () => late.future;
    final harness = await _Harness.create(
        router: router, routeTimeout: const Duration(milliseconds: 20));
    addTearDown(harness.dispose);
    await _route(harness.controller);
    expect(harness.controller.isRouting, isFalse);
    expect(harness.controller.errorMessage,
        AgentToolController.routeFailureMessage);
    router.onRoute = null;
    await _route(harness.controller, turn: 'fresh');
    late.complete(
        AgentRouteResult(hasToolIntent: true, intent: _intent('play_music')));
    await pumpEventQueue();
    expect(harness.executor.executedCount, 0);
    expect(harness.controller.pendingIntent, isNull);
    expect(harness.controller.errorMessage, isNull);
    await _route(harness.controller, turn: 'fresh');
    expect(router.routeCount, 2);
  });

  for (final invalidate in ['clear', 'new session', 'dispose']) {
    test('CR0110 late route throw after $invalidate cannot pollute state',
        () async {
      final old = Completer<AgentRouteResult>();
      final next = Completer<AgentRouteResult>();
      final router = _FakeRouter(AgentRouteResult.noIntent())
        ..onRoute = () => old.future;
      final harness = await _Harness.create(router: router);
      final first = _route(harness.controller);
      await pumpEventQueue();
      Future<void>? second;
      if (invalidate == 'dispose') {
        harness.dispose();
      } else {
        addTearDown(harness.dispose);
        if (invalidate == 'clear') harness.controller.clear();
        router.onRoute = () => next.future;
        second =
            _route(harness.controller, turn: 'new', session: 'new-session');
      }
      old.completeError(StateError('old route'));
      await first;
      expect(harness.controller.errorMessage, isNull);
      if (second != null) {
        expect(harness.controller.isRouting, isTrue);
        next.complete(AgentRouteResult.noIntent());
        await second;
        expect(harness.controller.isRouting, isFalse);
      }
    });
  }

  for (final throws in [true, false]) {
    test(
        'CR0110 confirmed ${throws ? 'throw' : 'failure'} settles once and cannot reconfirm',
        () async {
      final harness = await _Harness.create(
          router: _FakeRouter(AgentRouteResult(
              hasToolIntent: true,
              intent: _intent('open_phone_dialer',
                  riskLevel: AgentToolRiskLevel.high,
                  requiresConfirmation: true))));
      addTearDown(harness.dispose);
      final done = Completer<AgentToolExecutionResult>();
      harness.executor.onExecute = () => done.future;
      await _route(harness.controller);
      final first = harness.controller.confirmAndExecute();
      await harness.controller.confirmAndExecute();
      await _route(harness.controller, turn: 'busy');
      harness.controller.cancelIntent();
      expect(harness.controller.isExecuting, isTrue);
      expect(harness.executor.executedCount, 1);
      if (throws) {
        done.completeError(StateError('custom throw'));
      } else {
        done.complete(AgentToolExecutionResult.failed(
            toolName: 'open_phone_dialer', message: '目前無法開啟撥號畫面。'));
      }
      await first;
      expect(harness.controller.isExecuting, isFalse);
      expect(harness.controller.executionResult?.success, isFalse);
      expect(harness.controller.pendingIntent?.status, AgentToolStatus.failed);
      await harness.controller.confirmAndExecute();
      await harness.controller.executeLowRiskIfAllowed();
      expect(harness.executor.executedCount, 1);
    });
  }

  for (final throws in [true, false]) {
    test(
        'CR0110 late executor ${throws ? 'throw' : 'result'} after dispose is ignored',
        () async {
      final harness = await _Harness.create(
          router: _FakeRouter(AgentRouteResult(
              hasToolIntent: true, intent: _intent('play_music'))));
      final done = Completer<AgentToolExecutionResult>();
      harness.executor.onExecute = () => done.future;
      final routed = _route(harness.controller);
      await pumpEventQueue();
      harness.dispose();
      if (throws) {
        done.completeError(StateError('late throw'));
      } else {
        done.complete(AgentToolExecutionResult.succeeded(
            toolName: 'play_music', message: 'late'));
      }
      await routed;
      expect(harness.controller.executionResult, isNull);
      expect(harness.controller.errorMessage, isNull);
    });
  }

  test('CR0110 executor throw releases state without exposing raw errors',
      () async {
    final harness = await _Harness.create(
      router: _FakeRouter(
          AgentRouteResult(hasToolIntent: true, intent: _intent('play_music'))),
    );
    addTearDown(harness.dispose);
    harness.executor.onExecute =
        () async => throw StateError('native exception');
    await _route(harness.controller);
    expect(harness.controller.isExecuting, isFalse);
    expect(harness.controller.isRouting, isFalse);
    expect(harness.controller.executionResult?.success, isFalse);
    expect(harness.controller.errorMessage ?? '',
        isNot(contains('native exception')));
    expect(harness.controller.hasUncertainExecution, isTrue);
    harness.controller.clear();
    await _route(harness.controller, turn: 'repeat', session: 'new-session');
    await harness.controller.confirmAndExecute();
    await harness.controller.executeLowRiskIfAllowed();
    expect(harness.executor.executedCount, 1);
  });

  test('CR0110 clear cannot unlock a held external action', () async {
    final harness = await _Harness.create(
      router: _FakeRouter(
          AgentRouteResult(hasToolIntent: true, intent: _intent('play_music'))),
    );
    addTearDown(harness.dispose);
    final done = Completer<AgentToolExecutionResult>();
    harness.executor.onExecute = () => done.future;
    final first = _route(harness.controller);
    await pumpEventQueue();
    harness.controller.clear();
    final next = _route(harness.controller, turn: 'next');
    await pumpEventQueue();
    final count = harness.executor.executedCount;
    done.complete(AgentToolExecutionResult.succeeded(
        toolName: 'play_music', message: 'late'));
    await first;
    await next;
    expect(count, 1);
    expect(harness.controller.executionResult, isNull);
    expect(harness.controller.isExecuting, isFalse);
  });

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
    expect(harness.controller.errorMessage,
        AgentToolController.routeFailureMessage);
  });
}

Future<void> _route(AgentToolController controller,
        {String turn = 't', String session = 's'}) =>
    controller.routeFromUserText('幫我播放放鬆音樂',
        sessionId: session,
        turnId: turn,
        petName: '小伴',
        emotion: 'neutral',
        languageHint: 'zh-TW');

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
  Future<AgentRouteResult> Function()? onRoute;
  int routeCount = 0;

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
    routeCount++;
    if (onRoute != null) return onRoute!();
    return result;
  }
}

class _FakeExecutor extends NativeToolExecutorService {
  int executedCount = 0;
  Future<AgentToolExecutionResult> Function()? onExecute;

  @override
  Future<AgentToolExecutionResult> execute({
    required AgentToolIntent intent,
    required ReminderController reminderController,
    required SearchService searchService,
    required AppNavigationController navigationController,
    required MemoryController memoryController,
  }) async {
    executedCount++;
    if (onExecute != null) return onExecute!();
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

  static Future<_Harness> create(
      {required AgentRouterService router,
      Duration routeTimeout = const Duration(seconds: 5)}) async {
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
      routeTimeout: routeTimeout,
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
