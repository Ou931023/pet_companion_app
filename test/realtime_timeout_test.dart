import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/models/realtime_timeout.dart';
import 'package:pet_companion_app/models/voice_agent_state.dart';
import 'package:pet_companion_app/services/realtime_timeout_registry.dart';

void main() {
  group('RealtimeTimeoutPolicy', () {
    const policy = RealtimeTimeoutPolicy();

    test('connection timeout recovers instead of staying connecting', () {
      final plan = policy.planFor(RealtimeTimeoutType.connectionTimeout);

      expect(plan.targetState, VoiceAgentState.recovering);
      expect(plan.stopConnection, isTrue);
      expect(plan.fallbackReply, '連線有點不穩，我們再試一次。');
    });

    test('transcript timeout returns to listening with retry prompt', () {
      final plan = policy.planFor(RealtimeTimeoutType.transcriptTimeout);

      expect(plan.targetState, VoiceAgentState.listening);
      expect(plan.fallbackReply, '我剛剛有點沒聽清楚，可以再跟我說一次嗎？');
    });

    test('response timeout returns fallback reply', () {
      final plan = policy.planFor(RealtimeTimeoutType.responseTimeout);

      expect(plan.targetState, VoiceAgentState.listening);
      expect(plan.fallbackReply, '我還在這裡陪你，我們慢慢說就好。');
    });

    test('tts timeout returns to listening', () {
      final plan = policy.planFor(RealtimeTimeoutType.ttsTimeout);

      expect(plan.targetState, VoiceAgentState.listening);
      expect(plan.reason, 'tts_timeout');
    });

    test('reconnect timeout exits to idle', () {
      final plan = policy.planFor(RealtimeTimeoutType.reconnectTimeout);

      expect(plan.targetState, VoiceAgentState.idle);
      expect(plan.stopConnection, isTrue);
    });
  });

  group('RealtimeTimeoutRegistry', () {
    test('fires a registered timeout', () async {
      final registry = RealtimeTimeoutRegistry();
      final fired = Completer<void>();

      registry.start(
        RealtimeTimeoutType.connectionTimeout,
        const Duration(milliseconds: 10),
        fired.complete,
      );

      await fired.future.timeout(const Duration(milliseconds: 80));
      expect(registry.isActive(RealtimeTimeoutType.connectionTimeout), isFalse);
    });

    test('dispose clears timers and prevents callbacks', () async {
      final registry = RealtimeTimeoutRegistry();
      var fired = false;

      registry.start(
        RealtimeTimeoutType.responseTimeout,
        const Duration(milliseconds: 20),
        () => fired = true,
      );
      expect(registry.isActive(RealtimeTimeoutType.responseTimeout), isTrue);

      registry.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(fired, isFalse);
      expect(registry.isActive(RealtimeTimeoutType.responseTimeout), isFalse);
    });
  });
}
