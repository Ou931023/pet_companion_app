class RealtimeTranscriptDecision {
  const RealtimeTranscriptDecision({
    required this.accepted,
    required this.reason,
    this.turnId = '',
    this.transcript = '',
  });

  final bool accepted;
  final String reason;
  final String turnId;
  final String transcript;
}

class RealtimeTurnCoordinator {
  RealtimeTurnCoordinator({this.duplicateWindow = const Duration(seconds: 2)});

  final Duration duplicateWindow;
  String _activeTurnId = '';
  String _lastFinalTranscript = '';
  DateTime? _lastFinalAt;
  final Set<String> _acceptedSourceIds = <String>{};
  int _sequence = 0;
  final Set<String> _committedTurnIds = <String>{};

  String get activeTurnId => _activeTurnId;

  RealtimeTranscriptDecision acceptFinalTranscript(
    String transcript, {
    DateTime? now,
    String sourceId = '',
  }) {
    final normalized = transcript.trim();
    if (normalized.isEmpty) {
      return const RealtimeTranscriptDecision(
        accepted: false,
        reason: 'empty_transcript',
      );
    }

    final currentTime = now ?? DateTime.now();
    final normalizedSourceId = sourceId.trim();
    if (normalizedSourceId.isNotEmpty &&
        !_acceptedSourceIds.add(normalizedSourceId)) {
      return const RealtimeTranscriptDecision(
        accepted: false,
        reason: 'duplicate_source_item',
      );
    }
    final previousAt = _lastFinalAt;
    if (normalizedSourceId.isEmpty &&
        _lastFinalTranscript == normalized &&
        previousAt != null &&
        currentTime.difference(previousAt).abs() <= duplicateWindow) {
      return const RealtimeTranscriptDecision(
        accepted: false,
        reason: 'duplicate_transcript',
      );
    }

    _lastFinalTranscript = normalized;
    _lastFinalAt = currentTime;
    _sequence += 1;
    final turnId = 'rt_${currentTime.microsecondsSinceEpoch}_$_sequence';
    _activeTurnId = turnId;
    _committedTurnIds.add(turnId);
    return RealtimeTranscriptDecision(
      accepted: true,
      reason: 'accepted',
      turnId: turnId,
      transcript: normalized,
    );
  }

  bool isActiveTurn(String turnId) {
    return turnId.isNotEmpty && turnId == _activeTurnId;
  }

  bool hasCommittedTurn(String turnId) {
    return _committedTurnIds.contains(turnId);
  }

  void clearActiveTurn(String turnId) {
    if (turnId == _activeTurnId) {
      _activeTurnId = '';
    }
  }

  void reset() {
    _activeTurnId = '';
    _lastFinalTranscript = '';
    _lastFinalAt = null;
    _acceptedSourceIds.clear();
    _committedTurnIds.clear();
  }
}
