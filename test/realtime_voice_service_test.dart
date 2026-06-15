import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/services/realtime_voice_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RealtimeVoiceService event handling', () {
    test('does not emit final transcript for empty transcript', () async {
      final service = RealtimeVoiceService();
      final events = <RealtimeVoiceEvent>[];
      final sub = service.events.listen(events.add);

      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'conversation.item.input_audio_transcription.completed',
        'transcript': '   ',
      }));
      await pumpEventQueue();

      expect(
        events
            .where((event) => event.type == RealtimeEventType.finalTranscript),
        isEmpty,
      );

      await sub.cancel();
      service.dispose();
    });

    test('error event surfaces plain-language message instead of API text',
        () async {
      final service = RealtimeVoiceService();
      final events = <RealtimeVoiceEvent>[];
      final sub = service.events.listen(events.add);

      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'error',
        'error': {
          'type': 'invalid_request_error',
          'code': 'session_expired',
          'message': 'The server had an error while processing your request.',
        },
      }));
      await pumpEventQueue();

      final errorEvents =
          events.where((event) => event.type == RealtimeEventType.error).toList();
      expect(errorEvents, hasLength(1));
      expect(errorEvents.single.payload, equals(realtimeApiErrorUserMessage));
      expect(errorEvents.single.payload, isNot(contains('server had an error')));
      expect(errorEvents.single.payload, isNot(contains('Realtime API')));

      await sub.cancel();
      service.dispose();
    });

    test('separates partial and final transcript events', () async {
      final service = RealtimeVoiceService();
      final events = <RealtimeVoiceEvent>[];
      final sub = service.events.listen(events.add);

      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'conversation.item.input_audio_transcription.delta',
        'transcript': '今天家裡',
      }));
      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'conversation.item.input_audio_transcription.completed',
        'transcript': '今天家裡好安靜',
      }));
      await pumpEventQueue();

      expect(events[0].type, RealtimeEventType.partialTranscript);
      expect(events[0].payload, '今天家裡');
      expect(events[1].type, RealtimeEventType.finalTranscript);
      expect(events[1].payload, '今天家裡好安靜');

      await sub.cancel();
      service.dispose();
    });

    test('appends incremental transcript deltas before final transcript',
        () async {
      final service = RealtimeVoiceService();
      final events = <RealtimeVoiceEvent>[];
      final sub = service.events.listen(events.add);

      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'conversation.item.input_audio_transcription.delta',
        'delta': '今天',
      }));
      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'conversation.item.input_audio_transcription.delta',
        'delta': '家裡',
      }));
      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'conversation.item.input_audio_transcription.completed',
        'transcript': '今天家裡好安靜',
      }));
      await pumpEventQueue();

      final partials = events
          .where((event) => event.type == RealtimeEventType.partialTranscript)
          .map((event) => event.payload)
          .toList();
      expect(partials, ['今天', '今天家裡']);
      expect(
        events
            .lastWhere(
              (event) => event.type == RealtimeEventType.finalTranscript,
            )
            .payload,
        '今天家裡好安靜',
      );

      await sub.cancel();
      service.dispose();
    });

    test(
        'response audio transcript delta can update user partial before response',
        () async {
      final service = RealtimeVoiceService();
      final events = <RealtimeVoiceEvent>[];
      final sub = service.events.listen(events.add);

      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'response.audio_transcript.delta',
        'delta': '我今天',
      }));
      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'response.audio_transcript.delta',
        'delta': '有點累',
      }));
      await pumpEventQueue();

      final partials = events
          .where((event) => event.type == RealtimeEventType.partialTranscript)
          .map((event) => event.payload)
          .toList();
      expect(partials, ['我今天', '我今天有點累']);
      expect(
        events.where((event) => event.type == RealtimeEventType.assistantText),
        isEmpty,
      );

      await sub.cancel();
      service.dispose();
    });

    test(
        'response audio transcript delta remains assistant text after response',
        () async {
      final service = RealtimeVoiceService();
      final events = <RealtimeVoiceEvent>[];
      final sub = service.events.listen(events.add);

      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'response.created',
      }));
      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'response.audio_transcript.delta',
        'delta': '我在這裡陪你。',
      }));
      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'response.done',
      }));
      await pumpEventQueue();

      expect(
        events.where(
            (event) => event.type == RealtimeEventType.partialTranscript),
        isEmpty,
      );
      expect(
        events.any((event) =>
            event.type == RealtimeEventType.assistantText &&
            event.payload == '我在這裡陪你。'),
        isTrue,
      );

      await sub.cancel();
      service.dispose();
    });

    test(
        'response done emits assistant text + done/audioEnd，turn-based 不再強制回 listening',
        () async {
      final service = RealtimeVoiceService();
      final events = <RealtimeVoiceEvent>[];
      final sub = service.events.listen(events.add);

      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'response.created',
      }));
      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'response.output_audio_transcript.delta',
        'delta': '我在這裡陪你。',
      }));
      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'response.done',
      }));
      await pumpEventQueue();

      expect(
        events.any((event) =>
            event.type == RealtimeEventType.assistantText &&
            event.payload == '我在這裡陪你。'),
        isTrue,
      );
      expect(
        events.any(
          (event) => event.type == RealtimeEventType.assistantResponseDone,
        ),
        isTrue,
      );
      expect(
        events.any(
          (event) => event.type == RealtimeEventType.assistantAudioEnd,
        ),
        isTrue,
      );
      // Turn-based：response.done 之後不應再自動送出 state=listening，
      // 由 controller 收回 idle，等使用者再次按鈕。
      expect(
        events.where((event) =>
            event.type == RealtimeEventType.state &&
            event.payload == 'listening'),
        isEmpty,
      );

      await sub.cancel();
      service.dispose();
    });

    test(
        'assistant transcript deltas are throttled but the last partial '
        'carries the full text, and assistantText fires once at response.done',
        () async {
      // 用較短的節流視窗讓測試可決定地等到 trailing emit。
      final service = RealtimeVoiceService(
        assistantPartialThrottle: const Duration(milliseconds: 20),
      );
      final events = <RealtimeVoiceEvent>[];
      final sub = service.events.listen(events.add);

      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'response.created',
      }));
      // 第一筆 delta 走 leading edge，立即送出；緊接的第二筆落在節流視窗內，
      // 合併成一筆 trailing emit，帶當下最新累積文字。
      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'response.output_audio_transcript.delta',
        'delta': '我在',
      }));
      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'response.output_audio_transcript.delta',
        'delta': '這裡陪你。',
      }));

      // 等過節流視窗，trailing emit 帶最新累積文字「我在這裡陪你。」送出。
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await pumpEventQueue();

      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'response.done',
      }));
      await pumpEventQueue();

      // 即時字幕不會跨進使用者 partial 路徑。
      final assistantPartials = events
          .where(
              (event) => event.type == RealtimeEventType.assistantPartialText)
          .map((event) => event.payload)
          .toList();
      expect(
        events
            .where((event) => event.type == RealtimeEventType.partialTranscript),
        isEmpty,
      );
      // Leading edge 先送出第一段，最後一筆 partial 一定帶完整累積文字（最後幾個字不丟）。
      expect(assistantPartials.first, '我在');
      expect(assistantPartials.last, '我在這裡陪你。');
      // 節流確實壓低了 emit 次數（兩筆 delta 不會各送一筆 + 額外重複）。
      expect(assistantPartials.length, lessThanOrEqualTo(2));

      // Final full text still lands exactly once at response.done.
      final finals = events
          .where((event) => event.type == RealtimeEventType.assistantText)
          .map((event) => event.payload)
          .toList();
      expect(finals, ['我在這裡陪你。']);

      await sub.cancel();
      service.dispose();
    });

    test('data channel closed emits recoverable close event', () async {
      final service = RealtimeVoiceService();
      final events = <RealtimeVoiceEvent>[];
      final sub = service.events.listen(events.add);

      service.handleDataChannelStateForTest('RTCDataChannelStateClosed');
      await pumpEventQueue();

      expect(
        events.where(
          (event) => event.type == RealtimeEventType.dataChannelClosed,
        ),
        isNotEmpty,
      );

      await sub.cancel();
      service.dispose();
    });

    test('peer disconnected emits failure instead of connected state',
        () async {
      final service = RealtimeVoiceService();
      final events = <RealtimeVoiceEvent>[];
      final sub = service.events.listen(events.add);

      service.handlePeerStateForTest('RTCPeerConnectionStateDisconnected');
      await pumpEventQueue();

      expect(
        events.where(
          (event) => event.type == RealtimeEventType.peerConnectionFailed,
        ),
        isNotEmpty,
      );
      expect(
        events.where(
          (event) =>
              event.type == RealtimeEventType.state &&
              event.payload == 'connected',
        ),
        isEmpty,
      );

      await sub.cancel();
      service.dispose();
    });

    test('ice completed is treated as a connected peer state', () async {
      final service = RealtimeVoiceService();
      final events = <RealtimeVoiceEvent>[];
      final sub = service.events.listen(events.add);

      service.handleIceStateForTest('RTCIceConnectionStateCompleted');
      await pumpEventQueue();

      expect(
        events.where(
          (event) =>
              event.type == RealtimeEventType.state &&
              event.payload == 'connected',
        ),
        isNotEmpty,
      );

      await sub.cancel();
      service.dispose();
    });

    test('connect called concurrently only starts one attempt', () async {
      final connectCompleter = Completer<void>();
      var attempts = 0;
      final service = RealtimeVoiceService(
        connectImplementationForTesting: (_) async {
          attempts += 1;
          await connectCompleter.future;
        },
      );

      final first = service.connect(
        realtimeCallUrl: 'http://localhost:3001/api/realtime/call',
        petName: 'Momo',
        userId: 'user-1',
      );
      final second = service.connect(
        realtimeCallUrl: 'http://localhost:3001/api/realtime/call',
        petName: 'Momo',
        userId: 'user-1',
      );
      await pumpEventQueue();

      expect(attempts, 1);
      connectCompleter.complete();
      await Future.wait([first, second]);

      service.dispose();
    });

    test('queues event until data channel opens', () async {
      final sentPayloads = <String>[];
      final service = RealtimeVoiceService(
        eventSenderForTesting: (payload) async {
          sentPayloads.add(payload);
        },
      );

      await service.updateCompanionContext('陪伴脈絡');

      expect(sentPayloads, isEmpty);
      expect(service.pendingEventCountForTest, 1);

      service.handleDataChannelStateForTest('RTCDataChannelStateOpen');
      await pumpEventQueue();

      expect(sentPayloads, hasLength(1));
      expect(sentPayloads.single, contains('session.update'));
      expect(service.pendingEventCountForTest, 0);

      service.dispose();
    });

    test(
        'CR-0093A: mid-session session.update persona 同步 CR-0090 自然度 + 台語自然 + 安全',
        () async {
      final sentPayloads = <String>[];
      final service = RealtimeVoiceService(
        eventSenderForTesting: (payload) async {
          sentPayloads.add(payload);
        },
      );

      // 帶 taigi 的 nextStrategy context → 觸發台語輸出指引。
      await service.updateCompanionContext('replyLanguage=taigi\n先陪他聊聊天');
      service.handleDataChannelStateForTest('RTCDataChannelStateOpen');
      await pumpEventQueue();

      final updates =
          sentPayloads.where((p) => p.contains('session.update')).toList();
      expect(updates, isNotEmpty);
      final instructions =
          ((jsonDecode(updates.last) as Map)['session'] as Map)['instructions']
              as String;

      // 陪伴優先 / 不硬轉任務。
      expect(instructions,
          contains('不要硬把話題帶去提醒、喝水、吃藥或任務'));
      // 避免重複。
      expect(instructions, contains('這類同一句罐頭'));
      expect(instructions, contains('不要每句都用問句收尾'));
      // 低落先陪伴、不過度醫療化。
      expect(instructions, contains('先陪伴，不急著解決、不過度醫療化'));
      // 安全邊界（新增，未弱化）。
      expect(instructions,
          contains('胸痛、呼吸困難、跌倒、嚴重不適或自傷意念'));
      // 台語自然、長者聽得懂優先。
      expect(instructions, contains('以台語為主、長者聽得懂優先'));
      // 仍保留 nextStrategy 框架語，不外漏分析欄位名稱。
      expect(instructions,
          contains('請優先遵守 nextStrategy，但不要提到 Companion Engine'));

      service.dispose();
    });

    test('closed peer state prevents sending on an old open data channel',
        () async {
      final sentPayloads = <String>[];
      final service = RealtimeVoiceService(
        eventSenderForTesting: (payload) async {
          sentPayloads.add(payload);
        },
      );

      service.handleDataChannelStateForTest('RTCDataChannelStateOpen');
      service.handlePeerStateForTest('RTCPeerConnectionStateClosed');
      await service.sendEventPayloadForTest('{"type":"session.update"}');
      await pumpEventQueue();

      expect(sentPayloads, isEmpty);
      expect(service.pendingEventCountForTest, 1);

      service.dispose();
    });

    test('data channel open timeout emits dataChannelFailed', () async {
      final service = RealtimeVoiceService(
        dataChannelOpenTimeout: const Duration(milliseconds: 10),
      );
      final events = <RealtimeVoiceEvent>[];
      final sub = service.events.listen(events.add);

      service.startDataChannelOpenTimerForTest();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await pumpEventQueue();

      expect(service.lastFailureType, RealtimeFailureType.dataChannelFailed);
      expect(
        events.where((event) => event.type == RealtimeEventType.error),
        isNotEmpty,
      );

      await sub.cancel();
      service.dispose();
    });

    test('failed connect can be retried with a new connect call', () async {
      var attempts = 0;
      final service = RealtimeVoiceService(
        connectImplementationForTesting: (_) async {
          attempts += 1;
          if (attempts <= 3) {
            throw Exception('temporary call failure');
          }
        },
      );

      await expectLater(
        service.connect(
          realtimeCallUrl: 'http://localhost:3001/api/realtime/call',
          petName: 'Momo',
          userId: 'user-1',
        ),
        throwsException,
      );
      expect(attempts, 3);

      await service.connect(
        realtimeCallUrl: 'http://localhost:3001/api/realtime/call',
        petName: 'Momo',
        userId: 'user-1',
      );
      expect(attempts, 4);

      service.dispose();
    });

    test('sendUserText injects conversation item then triggers response',
        () async {
      final sentPayloads = <String>[];
      final service = RealtimeVoiceService(
        eventSenderForTesting: (payload) async {
          sentPayloads.add(payload);
        },
      );
      service.handleDataChannelStateForTest('RTCDataChannelStateOpen');
      await pumpEventQueue();

      await service.sendUserText('  今天有點累  ');
      await pumpEventQueue();

      expect(sentPayloads, hasLength(2));

      final itemEvent = jsonDecode(sentPayloads[0]) as Map<String, dynamic>;
      expect(itemEvent['type'], 'conversation.item.create');
      final item = itemEvent['item'] as Map<String, dynamic>;
      expect(item['type'], 'message');
      expect(item['role'], 'user');
      final content = item['content'] as List;
      final part = content.single as Map<String, dynamic>;
      expect(part['type'], 'input_text');
      expect(part['text'], '今天有點累');

      final responseEvent = jsonDecode(sentPayloads[1]) as Map<String, dynamic>;
      expect(responseEvent['type'], 'response.create');

      service.dispose();
    });

    test('sendUserText ignores empty or whitespace text', () async {
      final sentPayloads = <String>[];
      final service = RealtimeVoiceService(
        eventSenderForTesting: (payload) async {
          sentPayloads.add(payload);
        },
      );
      service.handleDataChannelStateForTest('RTCDataChannelStateOpen');
      await pumpEventQueue();

      await service.sendUserText('   ');
      await pumpEventQueue();

      expect(sentPayloads, isEmpty);

      service.dispose();
    });

    test('disconnect can be called repeatedly without crashing', () async {
      final service = RealtimeVoiceService();

      await service.disconnect();
      await service.disconnect();
      await service.stop();

      service.dispose();
      service.dispose();
    });

    bool isToolOutcomeResponse(String payload) {
      final map = jsonDecode(payload) as Map<String, dynamic>;
      if (map['type'] != 'response.create') return false;
      final response = map['response'] as Map<String, dynamic>?;
      final instructions = response?['instructions'] as String?;
      return instructions != null && instructions.contains('天氣晴');
    }

    test(
        'tool outcome queued during an audio response is flushed on '
        'output_audio_buffer.stopped, not at response.done', () async {
      final sentPayloads = <String>[];
      final service = RealtimeVoiceService(
        eventSenderForTesting: (payload) async {
          sentPayloads.add(payload);
        },
      );
      service.handleDataChannelStateForTest('RTCDataChannelStateOpen');
      await pumpEventQueue();

      // 寵物先回了 filler（response 1），且開始播放語音。
      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'response.created',
      }));
      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'output_audio_buffer.started',
      }));

      // 工具結果在 response 1 還在進行時送來 → 應被排隊，先不送出。
      await service.speakToolOutcome('今天天氣晴');
      await pumpEventQueue();
      expect(sentPayloads.where(isToolOutcomeResponse), isEmpty,
          reason: 'queued tool outcome must not be sent while response active');

      // response.done 只代表生成結束，語音可能還在播 → 此時不可送工具念稿。
      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'response.done',
      }));
      await pumpEventQueue();
      expect(sentPayloads.where(isToolOutcomeResponse), isEmpty,
          reason: 'tool outcome must NOT be flushed at response.done '
              'when audio is still playing');

      // 語音真的播完 → 現在才送出工具念稿（response 2）。
      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'output_audio_buffer.stopped',
      }));
      await pumpEventQueue();
      expect(sentPayloads.where(isToolOutcomeResponse), hasLength(1),
          reason: 'tool outcome should be flushed on '
              'output_audio_buffer.stopped');

      service.dispose();
    });

    test(
        'text-only response (no audio buffer events) still flushes the queued '
        'tool outcome at response.done', () async {
      final sentPayloads = <String>[];
      final service = RealtimeVoiceService(
        eventSenderForTesting: (payload) async {
          sentPayloads.add(payload);
        },
      );
      service.handleDataChannelStateForTest('RTCDataChannelStateOpen');
      await pumpEventQueue();

      // 純文字回覆：只有 text delta，沒有任何 output_audio_buffer 事件。
      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'response.created',
      }));
      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'response.output_text.delta',
        'delta': '好的',
      }));

      await service.speakToolOutcome('今天天氣晴');
      await pumpEventQueue();
      expect(sentPayloads.where(isToolOutcomeResponse), isEmpty);

      // 沒有語音 buffer → response.done 沿用舊行為，立刻送出工具念稿。
      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'response.done',
      }));
      await pumpEventQueue();
      expect(sentPayloads.where(isToolOutcomeResponse), hasLength(1),
          reason: 'text-only fallback must still flush at response.done');

      service.dispose();
    });

    test(
        'queued tool outcome is flushed by the bounded fallback timer when '
        'output_audio_buffer.stopped never arrives', () async {
      final sentPayloads = <String>[];
      final service = RealtimeVoiceService(
        toolOutcomeFlushFallback: const Duration(milliseconds: 20),
        eventSenderForTesting: (payload) async {
          sentPayloads.add(payload);
        },
      );
      service.handleDataChannelStateForTest('RTCDataChannelStateOpen');
      await pumpEventQueue();

      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'response.created',
      }));
      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'output_audio_buffer.started',
      }));

      await service.speakToolOutcome('今天天氣晴');
      await pumpEventQueue();

      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'response.done',
      }));
      await pumpEventQueue();
      expect(sentPayloads.where(isToolOutcomeResponse), isEmpty);

      // output_audio_buffer.stopped 一直沒到，保底計時器仍會送出念稿。
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await pumpEventQueue();
      expect(sentPayloads.where(isToolOutcomeResponse), hasLength(1),
          reason: 'fallback timer must flush the queued tool outcome');

      service.dispose();
    });

    // CR-0089：暴露「語音真的播完」訊號（output_audio_buffer.stopped）。
    test(
        'CR-0089: output_audio_buffer.stopped emits assistantAudioPlaybackStopped '
        'exactly once; response.done still emits assistantAudioEnd', () async {
      final service = RealtimeVoiceService();
      final events = <RealtimeVoiceEvent>[];
      final sub = service.events.listen(events.add);

      service.handleDataChannelEventForTest(
          jsonEncode({'type': 'response.created'}));
      service.handleDataChannelEventForTest(
          jsonEncode({'type': 'output_audio_buffer.started'}));
      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'response.output_audio_transcript.delta',
        'delta': '好的',
      }));
      service.handleDataChannelEventForTest(
          jsonEncode({'type': 'response.done'}));
      await pumpEventQueue();

      // response.done 仍照常發 assistantAudioEnd（不可移除）。
      expect(
        events.where((e) => e.type == RealtimeEventType.assistantAudioEnd),
        hasLength(1),
      );
      // 此時語音尚未播完 → 還不該有 playback-stopped。
      expect(
        events.where(
            (e) => e.type == RealtimeEventType.assistantAudioPlaybackStopped),
        isEmpty,
      );

      service.handleDataChannelEventForTest(
          jsonEncode({'type': 'output_audio_buffer.stopped'}));
      await pumpEventQueue();
      // 播完 → 恰好一次 playback-stopped。
      expect(
        events.where(
            (e) => e.type == RealtimeEventType.assistantAudioPlaybackStopped),
        hasLength(1),
      );

      await sub.cancel();
      service.dispose();
    });

    // CR-0089：順序回歸 —— 有 pending tool outcome 時，flush（送工具念稿）必須
    // 先於 assistantAudioPlaybackStopped（保留 CR-0083 既有 flush 時機與順序）。
    test(
        'CR-0089: pending tool outcome flush precedes assistantAudioPlaybackStopped',
        () async {
      final order = <String>[];
      final service = RealtimeVoiceService(
        eventSenderForTesting: (payload) async {
          if (isToolOutcomeResponse(payload)) order.add('flush');
        },
      );
      final sub = service.events.listen((e) {
        if (e.type == RealtimeEventType.assistantAudioPlaybackStopped) {
          order.add('stopped');
        }
      });
      service.handleDataChannelStateForTest('RTCDataChannelStateOpen');
      await pumpEventQueue();

      service.handleDataChannelEventForTest(
          jsonEncode({'type': 'response.created'}));
      service.handleDataChannelEventForTest(
          jsonEncode({'type': 'output_audio_buffer.started'}));
      await service.speakToolOutcome('今天天氣晴');
      service.handleDataChannelEventForTest(
          jsonEncode({'type': 'response.done'}));
      await pumpEventQueue();
      service.handleDataChannelEventForTest(
          jsonEncode({'type': 'output_audio_buffer.stopped'}));
      await pumpEventQueue();

      expect(order, ['flush', 'stopped']);

      await sub.cancel();
      service.dispose();
    });

    // CR-0089：assistantAudioPlaybackStarted 只在「真實語音」出現時發一次。
    int startedCount(List<RealtimeVoiceEvent> events) => events
        .where((e) => e.type == RealtimeEventType.assistantAudioPlaybackStarted)
        .length;

    test('CR-0089: audio response emits assistantAudioPlaybackStarted exactly once',
        () async {
      final service = RealtimeVoiceService();
      final events = <RealtimeVoiceEvent>[];
      final sub = service.events.listen(events.add);
      service.handleDataChannelEventForTest(
          jsonEncode({'type': 'response.created'}));
      service.handleDataChannelEventForTest(
          jsonEncode({'type': 'output_audio_buffer.started'}));
      service.handleDataChannelEventForTest(
          jsonEncode({'type': 'response.output_audio.delta'}));
      await pumpEventQueue();
      expect(startedCount(events), 1);
      await sub.cancel();
      service.dispose();
    });

    test('CR-0089: text-only response emits NO assistantAudioPlaybackStarted',
        () async {
      final service = RealtimeVoiceService();
      final events = <RealtimeVoiceEvent>[];
      final sub = service.events.listen(events.add);
      service.handleDataChannelEventForTest(
          jsonEncode({'type': 'response.created'}));
      service.handleDataChannelEventForTest(jsonEncode(
          {'type': 'response.output_text.delta', 'delta': '好的'}));
      service.handleDataChannelEventForTest(
          jsonEncode({'type': 'response.done'}));
      await pumpEventQueue();
      expect(startedCount(events), 0);
      await sub.cancel();
      service.dispose();
    });

    test(
        'CR-0089: text-then-audio response still emits assistantAudioPlaybackStarted once',
        () async {
      final service = RealtimeVoiceService();
      final events = <RealtimeVoiceEvent>[];
      final sub = service.events.listen(events.add);
      service.handleDataChannelEventForTest(
          jsonEncode({'type': 'response.created'}));
      // 文字 delta 先到（_isSpeaking 已被設 true），語音才開始。
      service.handleDataChannelEventForTest(jsonEncode(
          {'type': 'response.output_audio_transcript.delta', 'delta': '我在'}));
      service.handleDataChannelEventForTest(
          jsonEncode({'type': 'output_audio_buffer.started'}));
      service.handleDataChannelEventForTest(
          jsonEncode({'type': 'response.output_audio.delta'}));
      await pumpEventQueue();
      expect(startedCount(events), 1,
          reason: '文字先於語音時仍要正確發出一次（守 _sawOutputAudioBufferThisResponse）');
      await sub.cancel();
      service.dispose();
    });
  });
}
