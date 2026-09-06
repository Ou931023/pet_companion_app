import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pet_companion_app/controllers/app_navigation_controller.dart';
import 'package:pet_companion_app/controllers/care_alert_controller.dart';
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
import 'package:pet_companion_app/models/care_alert.dart';
import 'package:pet_companion_app/models/companion_analysis_result.dart';
import 'package:pet_companion_app/models/voice_agent_state.dart';
import 'package:pet_companion_app/models/realtime_timeout.dart';
import 'package:pet_companion_app/services/ai_navigation_service.dart';
import 'package:pet_companion_app/services/ai_tool_router.dart';
import 'package:pet_companion_app/services/asr_strategy_service.dart';
import 'package:pet_companion_app/services/care_alert_storage_service.dart';
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

  test(
      'voice start button is unavailable while initial health/connect is in flight',
      () async {
    final healthCompleter = Completer<RealtimeHealthStatus>();
    final realtimeService = RealtimeVoiceService(
      healthCheckImplementationForTesting: (_) => healthCompleter.future,
      connectImplementationForTesting: (_) async {},
    );
    final harness = await _VoiceControllerHarness.create(realtimeService);

    final start = harness.controller.startRealtimeConversation();
    await pumpEventQueue();

    expect(harness.controller.state, VoiceAgentState.idle);
    expect(
      harness.controller.canStartVoiceInput,
      isFalse,
      reason: '連線流程已開始時按鈕不可看起來仍能重複啟動',
    );

    healthCompleter.complete(_healthyBackend());
    await start;
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
    realtimeService
        .handleDataChannelEventForTest('{"type":"response.created"}');
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

    test('寵物回覆中抵達的使用者 final transcript 仍被接住記錄（不被守衛丟掉）', () async {
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

      // CR-0089：response.done ≠ 語音播完 → 仍 speaking、talk/字幕保留；
      // 但麥克風已在 response.done 暫停（語音尾段不被使用者插話蓋字幕）。
      expect(harness.controller.state, VoiceAgentState.speaking);
      expect(service.isMicEnabled, isFalse);

      // 語音真的播完（output_audio_buffer.stopped）→ 才回 idle。
      service.handleDataChannelEventForTest(
          '{"type":"output_audio_buffer.stopped"}');
      await pumpEventQueue();
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

      // CR-0089：response.done 會先後送出 assistantResponseDone 與 assistantAudioEnd，
      // 本輪有語音 → 兩條結束路徑都先「等播完」（保留 speaking），不互相覆蓋、
      // 也不被殘留事件拉回 listening。output_audio_buffer.stopped 才冪等收斂到 idle。
      service.handleDataChannelEventForTest('{"type":"response.done"}');
      await pumpEventQueue();
      expect(harness.controller.state, VoiceAgentState.speaking);

      service.handleDataChannelEventForTest(
          '{"type":"output_audio_buffer.stopped"}');
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
      // CR-0089：有語音 → 先保留 speaking，播完才收 idle。
      service.handleDataChannelEventForTest(
          '{"type":"output_audio_buffer.stopped"}');
      await pumpEventQueue();
      expect(harness.controller.state, VoiceAgentState.idle);
      expect(attempts, 1);
      expect(harness.controller.isWarmNextTurnReady, isTrue);
      expect(harness.controller.isRealtimeReady, isTrue);
      expect(harness.controller.canStartVoiceInput, isTrue);

      // 再按一次語音按鈕：不應重連（attempts 不變），恢復麥克風並回到 listening。
      await harness.controller.startRealtimeConversation();
      await pumpEventQueue();

      expect(attempts, 1, reason: '同一條連線開始下一句，不重建連線');
      expect(harness.controller.state, VoiceAgentState.listening);
      expect(service.isMicEnabled, isTrue);

      harness.dispose();
    });

    test(
        'CR-0105: 30 warm turns reuse one session and never strand lifecycle state',
        () async {
      var attempts = 0;
      final service = RealtimeVoiceService(
        healthCheckImplementationForTesting: (_) async => _healthyBackend(),
        connectImplementationForTesting: (_) async {
          attempts += 1;
        },
      );
      final harness = await _VoiceControllerHarness.create(service);
      await _reachListening(harness, service);

      for (var index = 0; index < 30; index += 1) {
        final historyBefore = harness.conversationController.history.length;
        service.handleDataChannelEventForTest(jsonEncode({
          'type': 'conversation.item.input_audio_transcription.delta',
          'item_id': 'user-$index',
          'delta': '食飽',
        }));
        await pumpEventQueue();
        expect(
          harness.conversationController.history.length,
          historyBefore,
          reason: 'turn ${index + 1}: partial 不可永久化到 history',
        );

        service.handleDataChannelEventForTest(jsonEncode({
          'type': 'conversation.item.input_audio_transcription.completed',
          'item_id': 'user-$index',
          'transcript': '食飽未',
        }));
        await pumpEventQueue();
        service.handleDataChannelEventForTest(
          jsonEncode({
            'type': 'response.created',
            'response': {'id': 'r-$index'}
          }),
        );
        service.handleDataChannelEventForTest(jsonEncode({
          'type': 'response.output_audio_transcript.delta',
          'response_id': 'r-$index',
          'delta': '第${index + 1}輪，我陪你。',
        }));
        service.handleDataChannelEventForTest(jsonEncode({
          'type': 'response.output_audio.delta',
          'response_id': 'r-$index',
        }));
        await pumpEventQueue();
        expect(harness.controller.state, VoiceAgentState.speaking);

        service.handleDataChannelEventForTest(jsonEncode({
          'type': 'response.done',
          'response': {'id': 'r-$index', 'output': []},
        }));
        await pumpEventQueue();
        expect(
          harness.controller.state,
          VoiceAgentState.speaking,
          reason: 'turn ${index + 1}: response.done 不可早於播放結束收 turn',
        );

        service.handleDataChannelEventForTest(
          jsonEncode({'type': 'output_audio_buffer.stopped'}),
        );
        await pumpEventQueue();
        expect(harness.controller.state, VoiceAgentState.idle);
        expect(harness.controller.isWarmNextTurnReady, isTrue);
        expect(harness.controller.canStartVoiceInput, isTrue);
        expect(attempts, 1, reason: 'turn ${index + 1}: warm session 不可重連');

        if (index < 29) {
          await harness.controller.startRealtimeConversation();
          await pumpEventQueue();
          expect(harness.controller.state, VoiceAgentState.listening);
        }
      }

      expect(attempts, 1);
      expect(
        harness.conversationController.history
            .where((turn) => turn.toolName == 'realtime-user'),
        hasLength(30),
        reason: '30 個 final 各落地一次 user turn',
      );
      expect(
        harness.conversationController.history
            .where((turn) => turn.userText == '食飽'),
        isEmpty,
        reason: 'partial transcript 永遠不可落入 history',
      );
      expect(
        harness.controller.state,
        isNot(anyOf(
          VoiceAgentState.connecting,
          VoiceAgentState.thinking,
          VoiceAgentState.speaking,
        )),
      );

      harness.dispose();
    });

    test(
        'late user final after playback stop pairs completed reply without a new turn or timeout',
        () async {
      final careAlertController =
          CareAlertController(CareAlertStorageService());
      await careAlertController.loadAlerts();
      final service = RealtimeVoiceService(
        healthCheckImplementationForTesting: (_) async => _healthyBackend(),
        connectImplementationForTesting: (_) async {},
      );
      final harness = await _VoiceControllerHarness.create(
        service,
        timeoutConfig: const RealtimeTimeoutConfig(
          responseTimeout: Duration(milliseconds: 10),
        ),
        companionEngineService: _UrgentCompanionEngineService(),
        careAlertController: careAlertController,
      );
      await _reachListening(harness, service);

      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'response.created',
        'response': {'id': 'response-late-final'},
      }));
      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'response.output_audio.delta',
        'response_id': 'response-late-final',
      }));
      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'response.done',
        'response': {
          'id': 'response-late-final',
          'output': [
            {
              'role': 'assistant',
              'content': [
                {'type': 'audio', 'transcript': '我有聽到，我陪你。'},
              ],
            },
          ],
        },
      }));
      service.handleDataChannelEventForTest(
        jsonEncode({'type': 'output_audio_buffer.stopped'}),
      );
      await pumpEventQueue();

      expect(harness.controller.state, VoiceAgentState.idle);
      expect(harness.controller.activeTurnId, isEmpty);
      expect(harness.controller.isWarmNextTurnReady, isTrue);
      expect(
        harness.conversationController.history
            .where((turn) => turn.petReply == '我有聽到，我陪你。'),
        isEmpty,
        reason: '等待 late final 時不可先落一筆 assistant-only 歷史',
      );

      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'conversation.item.input_audio_transcription.completed',
        'item_id': 'user-late-final',
        'transcript': '我今天有一點累',
      }));
      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'conversation.item.done',
        'item': {
          'id': 'user-late-final',
          'role': 'user',
          'content': [
            {'type': 'input_audio', 'transcript': '我今天有一點累'},
          ],
        },
      }));
      await pumpEventQueue();

      expect(harness.controller.state, VoiceAgentState.idle);
      expect(harness.controller.activeTurnId, isEmpty);
      expect(harness.controller.isPetResponding, isFalse);
      expect(harness.controller.isWarmNextTurnReady, isTrue);
      expect(harness.conversationController.latestUserText, '我今天有一點累');
      expect(harness.conversationController.latestReply, '我有聽到，我陪你。');
      expect(
        harness.conversationController.history.where(
          (turn) => turn.userText == '我今天有一點累' && turn.petReply == '我有聽到，我陪你。',
        ),
        hasLength(1),
        reason: '同一個 item 的 completed/item.done 只能落一筆配對紀錄',
      );
      expect(
        harness.conversationController.history
            .where((turn) => turn.petReply == '我有聽到，我陪你。'),
        hasLength(1),
        reason: 'assistant-only 與完整配對不可重複落地',
      );
      expect(careAlertController.alerts, hasLength(1));
      expect(
        careAlertController.alerts.single.riskLevel,
        CareAlertRiskLevel.urgent,
      );

      await Future<void>.delayed(const Duration(milliseconds: 30));
      await pumpEventQueue();
      expect(harness.controller.state, VoiceAgentState.idle);
      expect(harness.controller.activeTurnId, isEmpty);
      expect(harness.controller.lastError, isEmpty);
      expect(harness.controller.isWarmNextTurnReady, isTrue);

      harness.dispose();
      careAlertController.dispose();
    });

    test(
        'async language routing cannot create a turn after response playback completed',
        () async {
      final routing = _DeferredLanguageRoutingService();
      final service = RealtimeVoiceService(
        healthCheckImplementationForTesting: (_) async => _healthyBackend(),
        connectImplementationForTesting: (_) async {},
      );
      final harness = await _VoiceControllerHarness.create(
        service,
        languageRoutingService: routing,
        timeoutConfig: const RealtimeTimeoutConfig(
          responseTimeout: Duration(milliseconds: 10),
        ),
      );
      await _reachListening(harness, service);

      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'conversation.item.input_audio_transcription.completed',
        'item_id': 'user-routing-race',
        'transcript': '我今天有點累',
      }));
      await pumpEventQueue();
      expect(routing.hasPendingRoute, isTrue);

      _completeAudioResponse(
        service,
        responseId: 'response-routing-race',
        reply: '我有聽到，我陪你。',
      );
      await pumpEventQueue();
      expect(harness.controller.state, VoiceAgentState.idle);

      routing.complete('我今天有點累');
      await pumpEventQueue();

      expect(harness.controller.state, VoiceAgentState.idle);
      expect(harness.controller.activeTurnId, isEmpty);
      expect(harness.controller.isWarmNextTurnReady, isTrue);
      expect(
        harness.conversationController.history.where(
          (turn) => turn.userText == '我今天有點累' && turn.petReply == '我有聽到，我陪你。',
        ),
        hasLength(1),
      );

      await Future<void>.delayed(const Duration(milliseconds: 30));
      await pumpEventQueue();
      expect(harness.controller.state, VoiceAgentState.idle);
      expect(harness.controller.activeTurnId, isEmpty);
      expect(harness.controller.lastError, isEmpty);

      harness.dispose();
    });

    test(
        'routing completed after assistant text but before audio stop records one complete turn',
        () async {
      final routing = _DeferredLanguageRoutingService();
      final service = RealtimeVoiceService(
        healthCheckImplementationForTesting: (_) async => _healthyBackend(),
        connectImplementationForTesting: (_) async {},
      );
      final harness = await _VoiceControllerHarness.create(
        service,
        languageRoutingService: routing,
        timeoutConfig: const RealtimeTimeoutConfig(
          responseTimeout: Duration(milliseconds: 50),
        ),
      );
      await _reachListening(harness, service);

      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'input_audio_buffer.committed',
        'item_id': 'user-routing-before-audio-stop',
      }));
      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'conversation.item.input_audio_transcription.completed',
        'item_id': 'user-routing-before-audio-stop',
        'transcript': '我今天有點累',
      }));
      await pumpEventQueue();
      expect(routing.hasPendingRoute, isTrue);

      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'response.created',
        'response': {'id': 'response-routing-before-audio-stop'},
      }));
      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'response.output_audio.delta',
        'response_id': 'response-routing-before-audio-stop',
      }));
      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'response.done',
        'response': {
          'id': 'response-routing-before-audio-stop',
          'output': [
            {
              'role': 'assistant',
              'content': [
                {'type': 'audio', 'transcript': '我有聽到，我陪你。'},
              ],
            },
          ],
        },
      }));
      await pumpEventQueue();
      expect(harness.controller.state, VoiceAgentState.speaking);

      routing.complete('我今天有點累');
      await pumpEventQueue();

      expect(harness.controller.state, VoiceAgentState.speaking);
      expect(harness.controller.activeTurnId, isEmpty);
      expect(
        harness.conversationController.history.where(
          (turn) => turn.userText == '我今天有點累' && turn.petReply == '我有聽到，我陪你。',
        ),
        hasLength(1),
      );
      expect(
        harness.conversationController.history.where(
          (turn) => turn.userText == '我今天有點累' && turn.petReply.isEmpty,
        ),
        isEmpty,
        reason: 'routing continuation 不可先落 user-only turn',
      );

      service.handleDataChannelEventForTest(
        jsonEncode({'type': 'output_audio_buffer.stopped'}),
      );
      await pumpEventQueue();
      expect(harness.controller.state, VoiceAgentState.idle);
      expect(harness.controller.isWarmNextTurnReady, isTrue);

      harness.dispose();
    });

    test(
        'old item final after warm next speech pairs previous reply and still raises Care Alert',
        () async {
      final careAlertController =
          CareAlertController(CareAlertStorageService());
      await careAlertController.loadAlerts();
      final service = RealtimeVoiceService(
        healthCheckImplementationForTesting: (_) async => _healthyBackend(),
        connectImplementationForTesting: (_) async {},
      );
      final harness = await _VoiceControllerHarness.create(
        service,
        companionEngineService: _UrgentCompanionEngineService(),
        careAlertController: careAlertController,
      );
      await _reachListening(harness, service);

      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'input_audio_buffer.committed',
        'item_id': 'old-user-item',
      }));
      _completeAudioResponse(
        service,
        responseId: 'response-before-warm-turn',
        reply: '上一句回覆。',
      );
      await pumpEventQueue();
      expect(harness.controller.state, VoiceAgentState.idle);

      await harness.controller.startRealtimeConversation();
      await pumpEventQueue();
      expect(harness.controller.state, VoiceAgentState.listening);

      service.handleDataChannelEventForTest(
        jsonEncode({'type': 'input_audio_buffer.speech_started'}),
      );
      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'input_audio_buffer.committed',
        'item_id': 'new-user-item',
      }));
      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'conversation.item.input_audio_transcription.completed',
        'item_id': 'old-user-item',
        'transcript': '上一輪晚到的文字',
      }));
      await pumpEventQueue();

      expect(harness.controller.state, VoiceAgentState.listening,
          reason: '舊 final 不可啟動或破壞新的 warm turn');
      expect(harness.controller.activeTurnId, isEmpty);
      expect(
        harness.conversationController.history.where(
          (turn) => turn.userText == '上一輪晚到的文字' && turn.petReply == '上一句回覆。',
        ),
        hasLength(1),
      );
      expect(careAlertController.alerts, hasLength(1));
      expect(careAlertController.alerts.single.riskLevel,
          CareAlertRiskLevel.urgent);

      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'conversation.item.input_audio_transcription.completed',
        'item_id': 'new-user-item',
        'transcript': '這是新的一輪',
      }));
      await pumpEventQueue();

      expect(harness.controller.state, VoiceAgentState.thinking);
      expect(harness.controller.activeTurnId, isNotEmpty);
      expect(
        harness.conversationController.history
            .where((turn) => turn.userText == '這是新的一輪'),
        hasLength(1),
      );

      harness.dispose();
      careAlertController.dispose();
    });

    test('CR-0089：有語音時 response.done 不收 turn，保留 speaking + 字幕；播完才 idle',
        () async {
      final service = RealtimeVoiceService(
        healthCheckImplementationForTesting: (_) async => _healthyBackend(),
        connectImplementationForTesting: (_) async {},
      );
      final harness = await _VoiceControllerHarness.create(service);
      await _reachListening(harness, service);
      service.handleDataChannelEventForTest('{"type":"response.created"}');
      await pumpEventQueue();
      service.handleDataChannelEventForTest(
        '{"type":"response.output_audio_transcript.delta","delta":"我在這裡陪你。"}',
      );
      // 真實語音開始 → assistantAudioPlaybackStarted。
      service.handleDataChannelEventForTest(
          '{"type":"response.output_audio.delta"}');
      await pumpEventQueue();
      expect(harness.controller.state, VoiceAgentState.speaking);

      service.handleDataChannelEventForTest('{"type":"response.done"}');
      await pumpEventQueue();
      // response.done 後仍 speaking、字幕（latestReply）保留 → 不被提前清除/切換。
      expect(harness.controller.state, VoiceAgentState.speaking);
      expect(harness.conversationController.latestReply, '我在這裡陪你。');

      service.handleDataChannelEventForTest(
          '{"type":"output_audio_buffer.stopped"}');
      await pumpEventQueue();
      expect(harness.controller.state, VoiceAgentState.idle);
      // 字幕在語音播完後仍保留（不立即清空）。
      expect(harness.conversationController.latestReply, '我在這裡陪你。');

      harness.dispose();
    });

    test('CR-0089：純文字回覆（無語音 buffer）→ response.done 立即收 idle，不等播完', () async {
      final service = RealtimeVoiceService(
        healthCheckImplementationForTesting: (_) async => _healthyBackend(),
        connectImplementationForTesting: (_) async {},
      );
      final harness = await _VoiceControllerHarness.create(service);
      await _reachListening(harness, service);
      service.handleDataChannelEventForTest('{"type":"response.created"}');
      await pumpEventQueue();
      // 只有純文字 delta，沒有任何 output_audio_buffer / audio delta。
      service.handleDataChannelEventForTest(
        '{"type":"response.output_text.delta","delta":"好的"}',
      );
      await pumpEventQueue();

      service.handleDataChannelEventForTest('{"type":"response.done"}');
      await pumpEventQueue();
      // 無真實語音 → 不延後，response.done 立即回 idle（不會卡在 speaking 等保底）。
      expect(harness.controller.state, VoiceAgentState.idle);

      harness.dispose();
    });

    test('speaking 期間按語音鈕不打斷寵物：不送 response.cancel、狀態維持 speaking', () async {
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

    test('CR-0096：聆聽中有語音時按停止＝送出本輪（commit+response.create、進 thinking、不斷線不清字幕）',
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
      await _reachListening(harness, service);

      // 使用者開口（server VAD 偵測到 speech started）+ 串流 partial transcript。
      service.handleDataChannelEventForTest(
          '{"type":"input_audio_buffer.speech_started"}');
      service.handleDataChannelEventForTest(
        '{"type":"conversation.item.input_audio_transcription.delta","transcript":"我今天有點累"}',
      );
      await pumpEventQueue();
      expect(harness.controller.isCapturingUserSpeech, isTrue);
      expect(harness.controller.partialTranscript, '我今天有點累');

      await harness.controller.stopListeningAndSubmit();
      await pumpEventQueue();

      // 送出本輪：commit + response.create（不是取消、不是斷線）。
      expect(sentPayloads, hasLength(2));
      expect(sentPayloads[0], contains('input_audio_buffer.commit'));
      expect(sentPayloads[1], contains('response.create'));
      // 進入處理中（不是 idle），而且剛說的話沒被清掉（stopRealtimeConversation 才會清 partial）。
      expect(harness.controller.state, VoiceAgentState.thinking);
      expect(harness.controller.partialTranscript, '我今天有點累');

      harness.dispose();
    });

    test('CR-0096：聆聽中還沒開口就按停止＝不送空 commit、維持待命（不誤觸 commit_empty）', () async {
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

      // 沒有任何 speech_started / partial transcript 就按停止。
      await harness.controller.stopListeningAndSubmit();
      await pumpEventQueue();

      expect(sentPayloads.where((p) => p.contains('input_audio_buffer.commit')),
          isEmpty);
      expect(harness.controller.isAwaitingUserSpeech, isTrue);
      expect(harness.controller.state, isNot(VoiceAgentState.thinking));

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

void _completeAudioResponse(
  RealtimeVoiceService service, {
  required String responseId,
  required String reply,
}) {
  service.handleDataChannelEventForTest(jsonEncode({
    'type': 'response.created',
    'response': {'id': responseId},
  }));
  service.handleDataChannelEventForTest(jsonEncode({
    'type': 'response.output_audio.delta',
    'response_id': responseId,
  }));
  service.handleDataChannelEventForTest(jsonEncode({
    'type': 'response.done',
    'response': {
      'id': responseId,
      'output': [
        {
          'role': 'assistant',
          'content': [
            {'type': 'audio', 'transcript': reply},
          ],
        },
      ],
    },
  }));
  service.handleDataChannelEventForTest(
    jsonEncode({'type': 'output_audio_buffer.stopped'}),
  );
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
    CompanionEngineService companionEngineService =
        const CompanionEngineService(),
    LanguageRoutingService? languageRoutingService,
    CareAlertController? careAlertController,
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
      companionChatService: CompanionChatService(),
      reminderController: ReminderController(
        reminderService: ReminderService(),
        notificationService: NotificationService(),
      ),
      useMockChat: true,
    );
    final routingService = languageRoutingService ??
        LanguageRoutingService(
          AsrStrategyService(
            strategies: const [
              OpenAiRealtimeAsrStrategy(),
              MockTaigiAsrStrategy(),
            ],
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
      languageRoutingService: routingService,
      taigiAsrService: TaigiAsrService(),
    );
    final controller = VoiceAgentController(
      profileController: profile,
      petController: petController,
      petStatsController: petStats,
      conversationController: conversationController,
      realtimeVoiceService: realtimeService,
      companionEngineService: companionEngineService,
      languageRoutingService: routingService,
      memoryController: memoryController,
      navigationService: navigationService,
      navigationController: navigationController,
      timeoutConfig: timeoutConfig,
      careAlertController: careAlertController,
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

class _DeferredLanguageRoutingService extends LanguageRoutingService {
  _DeferredLanguageRoutingService()
      : super(
          AsrStrategyService(
            strategies: const [OpenAiRealtimeAsrStrategy()],
          ),
        );

  final Completer<LanguageRouteResult> _route =
      Completer<LanguageRouteResult>();
  bool _wasCalled = false;

  bool get hasPendingRoute => _wasCalled && !_route.isCompleted;

  void complete(String transcript) {
    _route.complete(LanguageRouteResult(
      strategyName: 'deferred-test-route',
      languageHint: TranscriptLanguageHint.zh,
      routeReason: 'deferred_test',
      isFallback: false,
      transcript: transcript,
      replyLanguage: ReplyLanguage.zhTw,
    ));
  }

  @override
  Future<LanguageRouteResult> routeTranscript({
    required VoiceLanguageMode mode,
    required String realtimeTranscript,
    String manualStrategyName = 'defaultOpenAiRealtime',
  }) {
    _wasCalled = true;
    return _route.future;
  }
}

class _UrgentCompanionEngineService extends CompanionEngineService {
  @override
  Future<CompanionAnalysisResult?> analyze({
    required String sttProxyUrl,
    required String userId,
    required String sessionId,
    required String turnId,
    required String petName,
    required String transcript,
    required Map<String, dynamic> petState,
    List<Map<String, dynamic>> recentTurns = const [],
    String languageHint = 'zh',
    Map<String, dynamic> audioFeatures = const {
      'volumeMean': null,
      'pauseDensity': null,
      'speechRate': null,
    },
  }) async {
    return CompanionAnalysisResult.fromJson({
      'turnId': turnId,
      'implicitMeaning': '使用者可能需要立即協助。',
      'careAlertSummary': '使用者提到急迫風險，請立即確認安全。',
      'safety': {
        'riskLevel': 'urgent',
        'needsHumanSupport': true,
      },
    });
  }
}
