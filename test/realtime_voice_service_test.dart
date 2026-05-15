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

    test('response done emits assistant text and returns to listening',
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
        events
            .lastWhere((event) => event.type == RealtimeEventType.state)
            .payload,
        'listening',
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
  });
}
