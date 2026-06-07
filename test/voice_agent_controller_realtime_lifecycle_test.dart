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
    expect(harness.petController.message, '連線不太穩，正在幫你重新連接。');

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
    expect(harness.petController.message, '現在連不上線，我們正在幫你重新連接，請稍等一下。');

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
    // Turn-based：寵物回覆結束 → 回 idle（不是 listening），等使用者再按一次。
    expect(harness.controller.state, VoiceAgentState.idle);

    harness.dispose();
  });

  test('response timeout 後回到 idle（turn-based，不自動 listening）', () async {
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

    expect(harness.controller.state, VoiceAgentState.idle);

    harness.dispose();
  });

  group('語音輪次控制（turn-based 一人一句 + mic 閘門）', () {
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

    test('寵物回覆中抵達的使用者 final transcript 仍被接住記錄（不被守衛丟掉）',
        () async {
      // 迴歸：server VAD 的 create_response 讓寵物常在使用者這句轉錄完成前就先開口，
      // 本輪 final transcript 比 response 晚到。修正前會被 turn-based 守衛整個丟掉，
      // 導致對話紀錄使用者文字空白、情緒/長期記憶/Care Alert 全失效。
      final service = RealtimeVoiceService(
        healthCheckImplementationForTesting: (_) async => _healthyBackend(),
        connectImplementationForTesting: (_) async {},
      );
      final harness = await _VoiceControllerHarness.create(service);
      await _reachSpeaking(harness, service);
      expect(harness.controller.state, VoiceAgentState.speaking);

      // 寵物正在說話時，使用者這句的 final transcript 才回來。
      service.handleDataChannelEventForTest(
        '{"type":"conversation.item.input_audio_transcription.completed",'
        '"transcript":"我的心情不好覺得很累"}',
      );
      await pumpEventQueue();

      // 修正後：被旁路接住 → 設定 latestUserText（讓寵物回覆能配對成完整一筆、
      // 並觸發 companion 分析 / Care Alert）。
      expect(
        harness.conversationController.latestUserText,
        '我的心情不好覺得很累',
      );
      // 不可打斷寵物：仍停在 speaking。
      expect(harness.controller.state, VoiceAgentState.speaking);

      harness.dispose();
    });

    test('speaking 播放完成後回到 idle（turn-based，麥克風關閉、需再按一次）', () async {
      final service = RealtimeVoiceService(
        healthCheckImplementationForTesting: (_) async => _healthyBackend(),
        connectImplementationForTesting: (_) async {},
      );
      final harness = await _VoiceControllerHarness.create(service);
      await _reachSpeaking(harness, service);
      expect(harness.controller.state, VoiceAgentState.speaking);
      // 寵物說話時麥克風關閉，咳嗽 / 雜音不會被當成新一輪。
      expect(service.isMicEnabled, isFalse);

      service.handleDataChannelEventForTest('{"type":"response.done"}');
      await pumpEventQueue();

      // 回 idle（不是 listening），麥克風維持關閉，可再次開始下一句。
      expect(harness.controller.state, VoiceAgentState.idle);
      expect(service.isMicEnabled, isFalse);
      expect(harness.controller.canStartVoiceInput, isTrue);

      harness.dispose();
    });

    test('response.done 同時帶 done + audioEnd 兩個結束事件，冪等收斂在 idle（不回 listening）',
        () async {
      final service = RealtimeVoiceService(
        healthCheckImplementationForTesting: (_) async => _healthyBackend(),
        connectImplementationForTesting: (_) async {},
      );
      final harness = await _VoiceControllerHarness.create(service);
      await _reachSpeaking(harness, service);

      // response.done 會先後送出 assistantResponseDone 與 assistantAudioEnd，
      // 兩者都收尾到 idle；確認不會互相覆蓋、也不會被任何殘留事件拉回 listening。
      service.handleDataChannelEventForTest('{"type":"response.done"}');
      await pumpEventQueue();
      expect(harness.controller.state, VoiceAgentState.idle);

      // 再多 pump 幾次，確認沒有延遲的自動 listening。
      await pumpEventQueue();
      expect(harness.controller.state, VoiceAgentState.idle);

      harness.dispose();
    });

    test('idle 後再按一次 → 同一條連線開始下一句（不重連），回到 listening', () async {
      var attempts = 0;
      final service = RealtimeVoiceService(
        healthCheckImplementationForTesting: (_) async => _healthyBackend(),
        connectImplementationForTesting: (_) async {
          attempts += 1;
        },
      );
      final harness = await _VoiceControllerHarness.create(service);
      await _reachSpeaking(harness, service);
      service.handleDataChannelEventForTest('{"type":"response.done"}');
      await pumpEventQueue();
      expect(harness.controller.state, VoiceAgentState.idle);
      expect(attempts, 1);

      // 再按一次語音按鈕：不應重連（attempts 不變），恢復麥克風並回到 listening。
      await harness.controller.startRealtimeConversation();
      await pumpEventQueue();

      expect(attempts, 1, reason: '同一條連線開始下一句，不重建連線');
      expect(harness.controller.state, VoiceAgentState.listening);
      expect(service.isMicEnabled, isTrue);

      harness.dispose();
    });

    test('speaking 期間按語音鈕不打斷寵物：不送 response.cancel、狀態維持 speaking',
        () async {
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

      // UI 在 speaking 時不會呼叫打斷；即使直接呼叫也一律 no-op。
      final interrupted = await harness.controller.interruptPetForUserTurn();
      // 同時也不能透過 startRealtimeConversation 偷插一輪。
      await harness.controller.startRealtimeConversation();
      await pumpEventQueue();

      expect(interrupted, isFalse);
      expect(harness.controller.state, VoiceAgentState.speaking);
      expect(sentPayloads.where((p) => p.contains('response.cancel')), isEmpty);

      harness.dispose();
    });

    test('speaking 期間使用者語音事件被忽略：不觸發新一輪、不改狀態', () async {
      final service = RealtimeVoiceService(
        healthCheckImplementationForTesting: (_) async => _healthyBackend(),
        connectImplementationForTesting: (_) async {},
      );
      final harness = await _VoiceControllerHarness.create(service);
      await _reachSpeaking(harness, service);
      expect(harness.controller.state, VoiceAgentState.speaking);

      // 模擬寵物說話時，使用者咳嗽 / 雜音被 server 當成語音輸入送上來。
      service.handleDataChannelEventForTest(
        '{"type":"input_audio_buffer.speech_started"}',
      );
      service.handleDataChannelEventForTest('''
{"type":"conversation.item.input_audio_transcription.completed","transcript":"咳咳"}
''');
      await pumpEventQueue();

      // 全部被忽略：仍在 speaking、沒有新增使用者 turn。
      expect(harness.controller.state, VoiceAgentState.speaking);
      expect(harness.conversationController.history, isEmpty);

      harness.dispose();
    });

    test('thinking 時也不可打斷寵物：回傳 false、不送 cancel、維持 thinking', () async {
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

      expect(interrupted, isFalse);
      expect(harness.controller.state, VoiceAgentState.thinking);
      expect(sentPayloads.where((p) => p.contains('response.cancel')), isEmpty);

      harness.dispose();
    });

    test('listening 待命中按打斷無作用：回傳 false、不送 cancel', () async {
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
