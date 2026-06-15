import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pet_companion_app/controllers/agent_tool_controller.dart';
import 'package:pet_companion_app/controllers/app_navigation_controller.dart';
import 'package:pet_companion_app/controllers/check_in_controller.dart';
import 'package:pet_companion_app/controllers/conversation_controller.dart';
import 'package:pet_companion_app/controllers/inventory_controller.dart';
import 'package:pet_companion_app/controllers/memory_controller.dart';
import 'package:pet_companion_app/controllers/pet_controller.dart';
import 'package:pet_companion_app/controllers/pet_stats_controller.dart';
import 'package:pet_companion_app/controllers/profile_controller.dart';
import 'package:pet_companion_app/controllers/reminder_controller.dart';
import 'package:pet_companion_app/controllers/task_controller.dart';
import 'package:pet_companion_app/controllers/voice_agent_controller.dart';
import 'package:pet_companion_app/controllers/wallet_controller.dart';
import 'package:pet_companion_app/models/agent_route_result.dart';
import 'package:pet_companion_app/models/agent_tool_execution_result.dart';
import 'package:pet_companion_app/models/agent_tool_intent.dart';
import 'package:pet_companion_app/models/voice_agent_state.dart';
import 'package:pet_companion_app/services/ai_navigation_service.dart';
import 'package:pet_companion_app/services/ai_tool_router.dart';
import 'package:pet_companion_app/services/agent_router_service.dart';
import 'package:pet_companion_app/services/asr_strategy_service.dart';
import 'package:pet_companion_app/services/check_in_storage_service.dart';
import 'package:pet_companion_app/services/companion_chat_service.dart';
import 'package:pet_companion_app/services/companion_content_service.dart';
import 'package:pet_companion_app/services/companion_engine_service.dart';
import 'package:pet_companion_app/services/companion_reply_strategy_service.dart';
import 'package:pet_companion_app/services/emotion_services.dart';
import 'package:pet_companion_app/services/inventory_storage_service.dart';
import 'package:pet_companion_app/services/language_routing_service.dart';
import 'package:pet_companion_app/services/local_storage_service.dart';
import 'package:pet_companion_app/services/memory_service.dart';
import 'package:pet_companion_app/services/mock_ai_service.dart';
import 'package:pet_companion_app/services/mock_speech_to_text_service.dart';
import 'package:pet_companion_app/services/native_tool_executor_service.dart';
import 'package:pet_companion_app/services/notification_service.dart';
import 'package:pet_companion_app/services/pet_stats_storage_service.dart';
import 'package:pet_companion_app/services/realtime_voice_service.dart';
import 'package:pet_companion_app/services/reminder_service.dart';
import 'package:pet_companion_app/services/search_service.dart';
import 'package:pet_companion_app/services/shop_service.dart';
import 'package:pet_companion_app/services/taigi_asr_strategy.dart';
import 'package:pet_companion_app/services/taigi_asr_service.dart';
import 'package:pet_companion_app/services/text_to_speech_service.dart';
import 'package:pet_companion_app/services/web_search_service.dart';

/// 整合測試：CR-0013 語音輪次控制 + CR-0015a/b Agent intent/execution 一起運作。
/// 驗證使用者講完一句（final transcript）會交給 Agent Router，且工具執行不會破壞輪次控制。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({'ttsEnabled': false}));

  test('講完一句 → 交給 Agent Router；高影響工具保留 pending（需確認、不自動執行），語音進 thinking 且不能重複開始', () async {
    final harness = await _Harness.create(
      _intent('open_phone_dialer',
          riskLevel: AgentToolRiskLevel.high, requiresConfirmation: true),
    );
    await harness.connect();

    harness.realtime.handleDataChannelEventForTest(
      '{"type":"conversation.item.input_audio_transcription.completed","transcript":"幫我打給女兒"}',
    );
    await pumpEventQueue();
    await pumpEventQueue();

    // 交給 Agent Router 了。
    expect(harness.router.routedTexts, contains('幫我打給女兒'));
    // 高影響 → 保留 pending、需確認、未自動執行。
    expect(harness.controller.state, VoiceAgentState.thinking);
    expect(harness.agent.pendingIntent, isNotNull);
    expect(harness.agent.pendingIntent!.requiresConfirmation, isTrue);
    expect(harness.executor.executedCount, 0);
    // 語音輪次控制：thinking 時不能重複開始。
    expect(harness.controller.canStartVoiceInput, isFalse);
    final attemptsBefore = harness.connectAttempts;
    await harness.controller.startRealtimeConversation();
    await pumpEventQueue();
    expect(harness.connectAttempts, attemptsBefore, reason: '不可重複建立連線');

    harness.dispose();
  });

  test('低風險工具（play_music）在同一輪直接執行，且不改變語音狀態（仍 thinking）', () async {
    final harness = await _Harness.create(_intent('play_music'));
    await harness.connect();

    harness.realtime.handleDataChannelEventForTest(
      '{"type":"conversation.item.input_audio_transcription.completed","transcript":"我想聽音樂"}',
    );
    await pumpEventQueue();
    await pumpEventQueue();

    expect(harness.router.routedTexts, contains('我想聽音樂'));
    expect(harness.executor.executedCount, 1); // 低風險直接執行
    expect(harness.controller.state, VoiceAgentState.thinking); // 工具執行不搶語音狀態

    harness.dispose();
  });

  test('Turn-based：寵物說話完成後保留連線但回到 idle（非 listening）；speaking 時不能重複開始',
      () async {
    final harness = await _Harness.create(_intent('play_music'));
    await harness.connect();

    harness.realtime
        .handleDataChannelEventForTest('{"type":"response.created"}');
    await pumpEventQueue();
    harness.realtime
        .handleDataChannelEventForTest('{"type":"response.output_audio.delta"}');
    await pumpEventQueue();
    expect(harness.controller.state, VoiceAgentState.speaking);
    expect(harness.controller.canStartVoiceInput, isFalse);

    harness.realtime.handleDataChannelEventForTest('{"type":"response.done"}');
    await pumpEventQueue();
    // CR-0089：response.done ≠ 語音播完 → 仍 speaking，talk/字幕保留。
    expect(harness.controller.state, VoiceAgentState.speaking);

    // 語音真的播完 → 一人一句：回到 idle，等使用者再按一次才開始下一句。
    harness.realtime
        .handleDataChannelEventForTest('{"type":"output_audio_buffer.stopped"}');
    await pumpEventQueue();
    expect(harness.controller.state, VoiceAgentState.idle);
    expect(harness.controller.canStartVoiceInput, isTrue);

    harness.dispose();
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
    userFacingMessage: '好，我幫你看看。',
    createdAt: DateTime.now(),
  );
}

class _RecordingRouter extends AgentRouterService {
  _RecordingRouter(this.intent);
  final AgentToolIntent intent;
  final List<String> routedTexts = [];

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
    routedTexts.add(userText);
    return AgentRouteResult(hasToolIntent: true, intent: intent);
  }
}

class _RecordingExecutor extends NativeToolExecutorService {
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
      message: '好，已經幫你處理好了。',
    );
  }
}

class _Harness {
  _Harness({
    required this.controller,
    required this.agent,
    required this.router,
    required this.executor,
    required this.realtime,
    required this.attemptsRef,
    required this.disposeAll,
  });

  final VoiceAgentController controller;
  final AgentToolController agent;
  final _RecordingRouter router;
  final _RecordingExecutor executor;
  final RealtimeVoiceService realtime;
  final Map<String, int> attemptsRef;
  final void Function() disposeAll;

  int get connectAttempts => attemptsRef['attempts'] ?? 0;

  Future<void> connect() async {
    await controller.startRealtimeConversation();
    realtime.handleDataChannelStateForTest('RTCDataChannelStateOpen');
    await pumpEventQueue();
    realtime.forceConnectionUsableForTest();
  }

  void dispose() => disposeAll();

  static Future<_Harness> create(AgentToolIntent intent) async {
    final harnessRef = <String, int>{'attempts': 0};
    final realtime = RealtimeVoiceService(
      healthCheckImplementationForTesting: (_) async => RealtimeHealthStatus(
        ok: true,
        hasOpenAiKey: true,
        realtimeModel: 'gpt-realtime',
        checkedAt: DateTime.now(),
      ),
      connectImplementationForTesting: (_) async {
        harnessRef['attempts'] = (harnessRef['attempts'] ?? 0) + 1;
      },
    );

    final localStorage = LocalStorageService();
    final profile = ProfileController(localStorage);
    await profile.load();
    final petController = PetController();
    final petStats = PetStatsController(PetStatsStorageService());
    final memoryController = MemoryController(MemoryService());
    final navigationController = AppNavigationController();
    const navigationService = AiNavigationService();
    final webSearchService = WebSearchService();
    final reminderController = ReminderController(
      reminderService: ReminderService(),
      notificationService: NotificationService(),
    );
    final taskController = TaskController(profile);
    final walletController = WalletController(profile);
    final checkInController = CheckInController(CheckInStorageService());
    final inventoryController = InventoryController(InventoryStorageService());
    final companionContentService = CompanionContentService(webSearchService);
    final toolRouter = AiToolRouter(
      profileController: profile,
      taskController: taskController,
      walletController: walletController,
      checkInController: checkInController,
      petStatsController: petStats,
      inventoryController: inventoryController,
      shopService: const ShopService(),
      webSearchService: webSearchService,
      mockAiService: MockAiService(),
      companionContentService: companionContentService,
      companionChatService: CompanionChatService(),
      reminderController: ReminderController(
        reminderService: ReminderService(),
        notificationService: NotificationService(),
      ),
      useMockChat: true,
    );
    final languageRoutingService = LanguageRoutingService(
      AsrStrategyService(
        strategies: const [OpenAiRealtimeAsrStrategy(), MockTaigiAsrStrategy()],
      ),
    );
    final conversationController = ConversationController(
      profileController: profile,
      petController: petController,
      toolRouter: toolRouter,
      ttsService: TextToSpeechService(),
      sttService: MockSpeechToTextService(),
      storageService: localStorage,
      searchService: SearchService(),
      petStatsController: petStats,
      navigationService: navigationService,
      navigationController: navigationController,
      reminderController: reminderController,
      emotionFusionService: const EmotionFusionService(),
      petEmotionMapper: const PetEmotionMapper(),
      memoryController: memoryController,
      companionReplyStrategy: const CompanionReplyStrategyService(),
      languageRoutingService: languageRoutingService,
      taigiAsrService: TaigiAsrService(),
    );
    final router = _RecordingRouter(intent);
    final executor = _RecordingExecutor();
    final agent = AgentToolController(
      profileController: profile,
      routerService: router,
      executorService: executor,
      reminderController: reminderController,
      searchService: SearchService(),
      navigationController: navigationController,
      memoryController: memoryController,
    );
    final controller = VoiceAgentController(
      profileController: profile,
      petController: petController,
      petStatsController: petStats,
      conversationController: conversationController,
      realtimeVoiceService: realtime,
      companionEngineService: const CompanionEngineService(),
      languageRoutingService: languageRoutingService,
      memoryController: memoryController,
      navigationService: navigationService,
      navigationController: navigationController,
      agentToolController: agent,
    );

    return _Harness(
      controller: controller,
      agent: agent,
      router: router,
      executor: executor,
      realtime: realtime,
      attemptsRef: harnessRef,
      disposeAll: () {
        controller.dispose();
        conversationController.dispose();
        agent.dispose();
        petController.dispose();
      },
    );
  }
}
