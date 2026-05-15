import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/services/realtime_turn_coordinator.dart';

void main() {
  group('RealtimeTurnCoordinator', () {
    test('rejects empty final transcript', () {
      final coordinator = RealtimeTurnCoordinator();

      final decision = coordinator.acceptFinalTranscript('   ');

      expect(decision.accepted, isFalse);
      expect(decision.reason, 'empty_transcript');
      expect(coordinator.activeTurnId, isEmpty);
    });

    test('rejects duplicate final transcript within two seconds', () {
      final coordinator = RealtimeTurnCoordinator();
      final now = DateTime(2026, 5, 15, 10);

      final first = coordinator.acceptFinalTranscript('今天家裡好安靜', now: now);
      final second = coordinator.acceptFinalTranscript(
        ' 今天家裡好安靜 ',
        now: now.add(const Duration(milliseconds: 900)),
      );

      expect(first.accepted, isTrue);
      expect(second.accepted, isFalse);
      expect(second.reason, 'duplicate_transcript');
      expect(coordinator.activeTurnId, first.turnId);
    });

    test('accepts same transcript after duplicate window', () {
      final coordinator = RealtimeTurnCoordinator();
      final now = DateTime(2026, 5, 15, 10);

      final first = coordinator.acceptFinalTranscript('今天家裡好安靜', now: now);
      final second = coordinator.acceptFinalTranscript(
        '今天家裡好安靜',
        now: now.add(const Duration(seconds: 3)),
      );

      expect(first.accepted, isTrue);
      expect(second.accepted, isTrue);
      expect(second.turnId, isNot(first.turnId));
      expect(coordinator.isActiveTurn(first.turnId), isFalse);
      expect(coordinator.isActiveTurn(second.turnId), isTrue);
    });

    test('clears only the active turn', () {
      final coordinator = RealtimeTurnCoordinator();
      final now = DateTime(2026, 5, 15, 10);

      final first = coordinator.acceptFinalTranscript('第一句', now: now);
      final second = coordinator.acceptFinalTranscript(
        '第二句',
        now: now.add(const Duration(seconds: 1)),
      );

      coordinator.clearActiveTurn(first.turnId);
      expect(coordinator.activeTurnId, second.turnId);

      coordinator.clearActiveTurn(second.turnId);
      expect(coordinator.activeTurnId, isEmpty);
    });
  });
}
