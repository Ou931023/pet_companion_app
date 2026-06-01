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
import 'package:pet_companion_app/models/language_route.dart';
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
import 'package:pet_companion_app/services/taigi_asr_service.dart';
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

  test('taigi realtime mode passes taigi language hint without Taigi ASR',
      () async {
    RealtimeConnectRequest? captured;
    final realtimeService = RealtimeVoiceService(
      healthCheckImplementationForTesting: (_) async => _healthyBackend(),
      connectImplementationForTesting: (request) async {
        captured = request;
      },
    );
    final harness = await _VoiceControllerHarness.create(realtimeService);
    await harness.controller.profileController
        .setVoiceLanguageMode(VoiceLanguageMode.taigiRealtime);

    await harness.controller.startRealtimeConversation();

    expect(captured, isNotNull);
    expect(captured!.languageHint, 'taigi');
    expect(captured!.replyLanguage, 'mixed-zh-taigi');
    expect(captured!.mode, 'taigi_realtime');
    expect(harness.conversationController.isTaigiAsrRecording, isFalse);
    expect(harness.conversationController.taigiAsrStatusMessage, isEmpty);

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

  test('taigi realtime final transcript stores taigi realtime metadata',
      () async {
    final realtimeService = RealtimeVoiceService(
      healthCheckImplementationForTesting: (_) async => _healthyBackend(),
      connectImplementationForTesting: (_) async {},
    );
    final harness = await _VoiceControllerHarness.create(realtimeService);
    await harness.controller.profileController
        .setVoiceLanguageMode(VoiceLanguageMode.taigiRealtime);

    await harness.controller.startRealtimeConversation();
    realtimeService.handleDataChannelEventForTest('''
{"type":"conversation.item.input_audio_transcription.completed","transcript":"心情無好"}
''');
    await pumpEventQueue();

    final turn = harness.conversationController.history.first;
    expect(turn.userText, '心情無好');
    expect(turn.languageHint, 'taigi');
    expect(turn.asrSource, 'openai-realtime');
    expect(turn.routeReason, 'taigi_realtime_mode');
    expect(turn.replyLanguage, 'mixed-zh-taigi');

    harness.dispose();
  });

  test('sendTextDuringRealtime returns false when realtime is not connected',
      () async {
    final realtimeService = RealtimeVoiceService(
      healthCheckImplementationForTesting: (_) async => _healthyBackend(),
      connectImplementationForTesting: (_) async {},
    );
    final harness = await _VoiceControllerHarness.create(realtimeService);

    // Never started realtime -> idle, connection not usable.
    final handled = await harness.controller.sendTextDuringRealtime('今天好嗎');

    expect(handled, isFalse);
    expect(harness.conversationController.history, isEmpty);

    harness.dispose();
  });

  test(
      'sendTextDuringRealtime injects user turn, sends text and triggers reply',
      () async {
    final sentPayloads = <String>[];
    final realtimeService = RealtimeVoiceService(
      healthCheckImplementationForTesting: (_) async => _healthyBackend(),
      connectImplementationForTesting: (_) async {},
      eventSenderForTesting: (payload) async {
        sentPayloads.add(payload);
      },
    );
    final harness = await _VoiceControllerHarness.create(realtimeService);

    await harness.controller.startRealtimeConversation();
    realtimeService.handleDataChannelStateForTest('RTCDataChannelStateOpen');
    await pumpEventQueue();
    realtimeService.forceConnectionUsableForTest();

    final handled =
        await harness.controller.sendTextDuringRealtime('  我今天很開心  ');
    await pumpEventQueue();

    expect(handled, isTrue);
    // User typed text becomes the displayed user bubble + a recorded user turn.
    expect(harness.conversationController.history, hasLength(1));
    final userTurn = harness.conversationController.history.single;
    expect(userTurn.userText, '我今天很開心');
    expect(userTurn.petReply, isEmpty);
    expect(userTurn.toolName, 'realtime-user-text');
    expect(harness.controller.state, VoiceAgentState.thinking);

    // The two realtime events (item.create + response.create) were sent.
    expect(sentPayloads, hasLength(2));
    expect(sentPayloads[0], contains('conversation.item.create'));
    expect(sentPayloads[0], contains('我今天很開心'));
    expect(sentPayloads[1], contains('response.create'));

    // The pet reply lands via the normal realtime assistantText flow and pairs
    // with the same turn (no orphan empty bubble, no stuck thinking).
    realtimeService.handleDataChannelEventForTest('{"type":"response.created"}');
    realtimeService.handleDataChannelEventForTest(
      '{"type":"response.output_audio_transcript.delta","delta":"聽你這樣說我也很開心。"}',
    );
    realtimeService.handleDataChannelEventForTest('{"type":"response.done"}');
    await pumpEventQueue();

    expect(harness.conversationController.latestReply, '聽你這樣說我也很開心。');
    expect(harness.controller.state, VoiceAgentState.listening);

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

  group('語音輪次控制（連續 session + UI 閘門）', () {
    test('idle 可以開始語音；連線後進入 listening 並標記為不可再次開始', () async {
      var attempts = 0;
      final service = RealtimeVoiceService(
        healthCheckImplementationForTesting: (_) async => _healthyBackend(),
        connectImplementationForTesting: (_) async {
          attempts += 1;
        },
      );
      final harness = await _VoiceControllerHarness.create(service);

      expect(harness.controller.state, VoiceAgentState.idle);
      expect(harness.controller.canStartVoiceInput, isTrue);

      await _reachListening(harness, service);

      expect(attempts, 1);
      // 連續 session 連上後落在 ready/listening 待命，兩者都代表「可開口、不可重啟」。
      expect(harness.controller.isAwaitingUserSpeech, isTrue);
      expect(harness.controller.canStartVoiceInput, isFalse);

      harness.dispose();
    });

    test('listening 待命中再次按開始 → 不建立新連線', () async {
      var attempts = 0;
      final service = RealtimeVoiceService(
        healthCheckImplementationForTesting: (_) async => _healthyBackend(),
        connectImplementationForTesting: (_) async {
          attempts += 1;
        },
      );
      final harness = await _VoiceControllerHarness.create(service);
      await _reachListening(harness, service);
      expect(harness.controller.isAwaitingUserSpeech, isTrue);

      await harness.controller.startRealtimeConversation();
      await pumpEventQueue();

      expect(attempts, 1);
      expect(harness.controller.isAwaitingUserSpeech, isTrue);

      harness.dispose();
    });

    test('thinking 思考中不能再次開始新的語音對話', () async {
      var attempts = 0;
      final service = RealtimeVoiceService(
        healthCheckImplementationForTesting: (_) async => _healthyBackend(),
        connectImplementationForTesting: (_) async {
          attempts += 1;
        },
      );
      final harness = await _VoiceControllerHarness.create(service);
      await _reachListening(harness, service);
      service.handleDataChannelEventForTest('{"type":"response.created"}');
      await pumpEventQueue();

      expect(harness.controller.state, VoiceAgentState.thinking);
      expect(harness.controller.canStartVoiceInput, isFalse);
      expect(harness.controller.isPetResponding, isTrue);

      await harness.controller.startRealtimeConversation();
      await pumpEventQueue();

      expect(attempts, 1);

      harness.dispose();
    });

    test('speaking 說話中不能再次開始新的語音對話', () async {
      var attempts = 0;
      final service = RealtimeVoiceService(
        healthCheckImplementationForTesting: (_) async => _healthyBackend(),
        connectImplementationForTesting: (_) async {
          attempts += 1;
        },
      );
      final harness = await _VoiceControllerHarness.create(service);
      await _reachSpeaking(harness, service);

      expect(harness.controller.state, VoiceAgentState.speaking);
      expect(harness.controller.canStartVoiceInput, isFalse);
      expect(harness.controller.isPetResponding, isTrue);

      await harness.controller.startRealtimeConversation();
      await pumpEventQueue();

      expect(attempts, 1);

      harness.dispose();
    });

    test('speaking 播放完成後回到 listening（連續 session 保持，可繼續說）', () async {
      final service = RealtimeVoiceService(
        healthCheckImplementationForTesting: (_) async => _healthyBackend(),
        connectImplementationForTesting: (_) async {},
      );
      final harness = await _VoiceControllerHarness.create(service);
      await _reachSpeaking(harness, service);
      expect(harness.controller.state, VoiceAgentState.speaking);

      service.handleDataChannelEventForTest('{"type":"response.done"}');
      await pumpEventQueue();

      expect(harness.controller.state, VoiceAgentState.listening);

      harness.dispose();
    });

    test('speaking 時按語音鈕打斷寵物 → 送出 response.cancel 並回到 listening', () async {
      final sentPayloads = <String>[];
      final service = RealtimeVoiceService(
        healthCheckImplementationForTesting: (_) async => _healthyBackend(),
        connectImplementationForTesting: (_) async {},
        eventSenderForTesting: (payload) async {
          sentPayloads.add(payload);
        },
      );
      final harness = await _VoiceControllerHarness.create(service);
      await _reachSpeaking(harness, service);
      expect(harness.controller.state, VoiceAgentState.speaking);

      final interrupted = await harness.controller.interruptPetForUserTurn();
      await pumpEventQueue();

      expect(interrupted, isTrue);
      expect(harness.controller.state, VoiceAgentState.listening);
      expect(
        sentPayloads.where((p) => p.contains('response.cancel')),
        hasLength(1),
      );

      harness.dispose();
    });

    test('thinking 時也能打斷寵物 → 回到 listening', () async {
      final sentPayloads = <String>[];
      final service = RealtimeVoiceService(
        healthCheckImplementationForTesting: (_) async => _healthyBackend(),
        connectImplementationForTesting: (_) async {},
        eventSenderForTesting: (payload) async {
          sentPayloads.add(payload);
        },
      );
      final harness = await _VoiceControllerHarness.create(service);
      await _reachListening(harness, service);
      service.handleDataChannelEventForTest('{"type":"response.created"}');
      await pumpEventQueue();
      expect(harness.controller.state, VoiceAgentState.thinking);

      final interrupted = await harness.controller.interruptPetForUserTurn();
      await pumpEventQueue();

      expect(interrupted, isTrue);
      expect(harness.controller.state, VoiceAgentState.listening);
      expect(
        sentPayloads.where((p) => p.contains('response.cancel')),
        hasLength(1),
      );

      harness.dispose();
    });

    test('待命聆聽中（listening）打斷無作用：回傳 false、不送 cancel', () async {
      final sentPayloads = <String>[];
      final service = RealtimeVoiceService(
        healthCheckImplementationForTesting: (_) async => _healthyBackend(),
        connectImplementationForTesting: (_) async {},
        eventSenderForTesting: (payload) async {
          sentPayloads.add(payload);
        },
      );
      final harness = await _VoiceControllerHarness.create(service);
      await _reachListening(harness, service);
      expect(harness.controller.isAwaitingUserSpeech, isTrue);

      final interrupted = await harness.controller.interruptPetForUserTurn();

      expect(interrupted, isFalse);
      expect(harness.controller.isAwaitingUserSpeech, isTrue);
      expect(sentPayloads.where((p) => p.contains('response.cancel')), isEmpty);

      harness.dispose();
    });

    test('error 狀態可以重試：canStartVoiceInput 為 true 且能再次連線', () async {
      var shouldFail = true;
      var attempts = 0;
      final service = RealtimeVoiceService(
        healthCheckImplementationForTesting: (_) async => _healthyBackend(),
        connectImplementationForTesting: (_) async {
          attempts += 1;
          if (shouldFail) {
            throw Exception('call failed');
          }
        },
      );
      final harness = await _VoiceControllerHarness.create(service);

      await harness.controller.startRealtimeConversation();
      expect(harness.controller.state, VoiceAgentState.error);
      expect(harness.controller.canStartVoiceInput, isTrue);

      shouldFail = false;
      final attemptsBeforeRetry = attempts;
      await harness.controller.startRealtimeConversation();
      service.handleDataChannelStateForTest('RTCDataChannelStateOpen');
      await pumpEventQueue();

      expect(attempts, greaterThan(attemptsBeforeRetry));
      expect(harness.controller.isAwaitingUserSpeech, isTrue);

      harness.dispose();
    });
  });
}

/// 連線並把 data channel 打開，讓 controller 進入 listening 待命狀態，
/// 並標記連線可用（讓「已連線時再次開始」走乾淨的 no-op，而非觸發重連）。
Future<void> _reachListening(
  _VoiceControllerHarness harness,
  RealtimeVoiceService service,
) async {
  await harness.controller.startRealtimeConversation();
  service.handleDataChannelStateForTest('RTCDataChannelStateOpen');
  await pumpEventQueue();
  service.forceConnectionUsableForTest();
}

/// 在 listening 之後，灌入 response.created + 一段語音輸出事件，
/// 讓 controller 進入 speaking（寵物正在說話）。
Future<void> _reachSpeaking(
  _VoiceControllerHarness harness,
  RealtimeVoiceService service,
) async {
  await _reachListening(harness, service);
  service.handleDataChannelEventForTest('{"type":"response.created"}');
  await pumpEventQueue();
  service
      .handleDataChannelEventForTest('{"type":"response.output_audio.delta"}');
  await pumpEventQueue();
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
      languageRoutingService: LanguageRoutingService(
        AsrStrategyService(
          strategies: const [
            OpenAiRealtimeAsrStrategy(),
            MockTaigiAsrStrategy(),
          ],
        ),
      ),
      taigiAsrService: TaigiAsrService(),
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
