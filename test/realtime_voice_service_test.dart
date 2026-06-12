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
  });
}
