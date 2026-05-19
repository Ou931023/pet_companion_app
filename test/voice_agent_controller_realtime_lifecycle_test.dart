import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
import 'package:pet_companion_app/models/voice_agent_state.dart';
import 'package:pet_companion_app/models/realtime_timeout.dart';
import 'package:pet_companion_app/services/ai_navigation_service.dart';
import 'package:pet_companion_app/services/ai_tool_router.dart';
import 'package:pet_companion_app/services/asr_strategy_service.dart';
import 'package:pet_companion_app/services/check_in_storage_service.dart';
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
import 'package:pet_companion_app/services/notification_service.dart';
import 'package:pet_companion_app/services/pet_stats_storage_service.dart';
import 'package:pet_companion_app/services/realtime_voice_service.dart';
import 'package:pet_companion_app/services/reminder_service.dart';
import 'package:pet_companion_app/services/search_service.dart';
import 'package:pet_companion_app/services/shop_service.dart';
import 'package:pet_companion_app/services/taigi_asr_strategy.dart';
import 'package:pet_companion_app/services/text_to_speech_service.dart';
import 'package:pet_companion_app/services/web_search_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'ttsEnabled': false,
    });
  });

  test('realtime call retries before controller enters error', () async {
    var attempts = 0;
    final realtimeService = RealtimeVoiceService(
      healthCheckImplementationForTesting: (_) async => _healthyBackend(),
      connectImplementationForTesting: (_) async {
        attempts += 1;
        throw Exception('call failed');
      },
    );
    final harness = await _VoiceControllerHarness.create(realtimeService);

    await harness.controller.startRealtimeConversation();

    expect(attempts, 3);
    expect(harness.controller.state, VoiceAgentState.error);
    expect(harness.petController.message, 'WebRTC SDP 交換失敗。');

    harness.dispose();
  });

  test('startRealtimeConversation double tap only starts one connection',
      () async {
    final completer = Completer<void>();
    var attempts = 0;
    final realtimeService = RealtimeVoiceService(
      healthCheckImplementationForTesting: (_) async => _healthyBackend(),
      connectImplementationForTesting: (_) async {
        attempts += 1;
        await completer.future;
      },
    );
    final harness = await _VoiceControllerHarness.create(realtimeService);

    final first = harness.controller.startRealtimeConversation();
    final second = harness.controller.startRealtimeConversation();
    await pumpEventQueue();

    expect(attempts, 1);
    completer.complete();
    await Future.wait([first, second]);

    harness.dispose();
  });

  test('health check failed does not stay connecting', () async {
    var attempts = 0;
    final realtimeService = RealtimeVoiceService(
      healthCheckImplementationForTesting: (_) async =>
          RealtimeHealthStatus.unavailable('後端未啟動'),
      connectImplementationForTesting: (_) async {
        attempts += 1;
      },
    );
    final harness = await _VoiceControllerHarness.create(realtimeService);

    await harness.controller.startRealtimeConversation();

    expect(attempts, 0);
    expect(harness.controller.state, VoiceAgentState.error);
    expect(harness.petController.message, contains('後端'));

    harness.dispose();
  });

  test('peer connection failed reconnects only once', () async {
    var attempts = 0;
    final realtimeService = RealtimeVoiceService(
      healthCheckImplementationForTesting: (_) async => _healthyBackend(),
      connectImplementationForTesting: (_) async {
        attempts += 1;
      },
    );
    final harness = await _VoiceControllerHarness.create(realtimeService);

    await harness.controller.startRealtimeConversation();
    realtimeService.handleDataChannelStateForTest('RTCDataChannelStateOpen');
    await pumpEventQueue();
    realtimeService.handlePeerStateForTest('RTCPeerConnectionStateFailed');
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await pumpEventQueue();
    realtimeService.handleDataChannelStateForTest('RTCDataChannelStateOpen');
    await pumpEventQueue();
    realtimeService.handlePeerStateForTest('RTCPeerConnectionStateFailed');
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await pumpEventQueue();

    expect(attempts, 2);
    expect(harness.controller.state, VoiceAgentState.error);

    harness.dispose();
  });

  test('stopRealtimeConversation clears timers and temporary transcript',
      () async {
    final realtimeService = RealtimeVoiceService(
      healthCheckImplementationForTesting: (_) async => _healthyBackend(),
      connectImplementationForTesting: (_) async {},
    );
    final harness = await _VoiceControllerHarness.create(realtimeService);

    await harness.controller.startRealtimeConversation();
    realtimeService.handleDataChannelEventForTest('''
{"type":"conversation.item.input_audio_transcription.delta","delta":"今天"}
''');
    await pumpEventQueue();
    await harness.controller.stopRealtimeConversation();

    expect(harness.controller.state, VoiceAgentState.idle);
    expect(harness.controller.partialTranscript, isEmpty);
    expect(harness.conversationController.temporaryUserBubbleText, isEmpty);

    harness.dispose();
  });

  test('response timeout returns to listening', () async {
    final realtimeService = RealtimeVoiceService(
      healthCheckImplementationForTesting: (_) async => _healthyBackend(),
      connectImplementationForTesting: (_) async {},
    );
    final harness = await _VoiceControllerHarness.create(
      realtimeService,
      timeoutConfig: const RealtimeTimeoutConfig(
        responseTimeout: Duration(milliseconds: 10),
      ),
    );

    await harness.controller.startRealtimeConversation();
    realtimeService
        .handleDataChannelEventForTest('{"type":"response.created"}');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await pumpEventQueue();

    expect(harness.controller.state, VoiceAgentState.listening);

    harness.dispose();
  });
}

RealtimeHealthStatus _healthyBackend() {
  return RealtimeHealthStatus(
    ok: true,
    hasOpenAiKey: true,
    realtimeModel: 'gpt-realtime',
    checkedAt: DateTime.now(),
  );
}

class _VoiceControllerHarness {
  _VoiceControllerHarness({
    required this.controller,
    required this.petController,
    required this.conversationController,
    required this.realtimeService,
  });

  final VoiceAgentController controller;
  final PetController petController;
  final ConversationController conversationController;
  final RealtimeVoiceService realtimeService;

  static Future<_VoiceControllerHarness> create(
    RealtimeVoiceService realtimeService, {
    RealtimeTimeoutConfig timeoutConfig = const RealtimeTimeoutConfig(),
  }) async {
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
    );
    final conversationController = ConversationController(
      profileController: profile,
      petController: petController,
      toolRouter: toolRouter,
      ttsService: TextToSpeechService(),
      mockSttService: MockSpeechToTextService(),
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
    );
    final controller = VoiceAgentController(
      profileController: profile,
      petController: petController,
      petStatsController: petStats,
      conversationController: conversationController,
      realtimeVoiceService: realtimeService,
      companionEngineService: const CompanionEngineService(),
      languageRoutingService: LanguageRoutingService(
        AsrStrategyService(
          strategies: const [
            OpenAiRealtimeAsrStrategy(),
            MockTaigiAsrStrategy(),
          ],
        ),
      ),
      memoryController: memoryController,
      navigationService: navigationService,
      navigationController: navigationController,
      timeoutConfig: timeoutConfig,
    );
    return _VoiceControllerHarness(
      controller: controller,
      petController: petController,
      conversationController: conversationController,
      realtimeService: realtimeService,
    );
  }

  void dispose() {
    controller.dispose();
    conversationController.dispose();
    petController.dispose();
  }
}
