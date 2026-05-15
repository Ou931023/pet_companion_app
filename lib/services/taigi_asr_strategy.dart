import 'asr_strategy_service.dart';

class MockTaigiAsrStrategy implements AsrStrategy {
  const MockTaigiAsrStrategy({this.forceFailure = false});

  final bool forceFailure;

  @override
  String get strategyName => 'mockTaigiAsr';

  @override
  bool get supportsRealtime => false;

  @override
  bool get supportsTaigi => true;

  @override
  Future<String> transcribe({
    required String realtimeTranscript,
    List<int>? audioBytes,
  }) async {
    if (forceFailure || realtimeTranscript.contains('[taigi-fail]')) {
      throw StateError('mock_taigi_asr_failed');
    }
    return normalizeTranscript(realtimeTranscript);
  }

  @override
  Stream<String> streamTranscribe({
    required Stream<List<int>> audioStream,
    String realtimeTranscript = '',
  }) async* {
    final transcript = await transcribe(realtimeTranscript: realtimeTranscript);
    if (transcript.isNotEmpty) yield transcript;
  }

  @override
  String normalizeTranscript(String transcript) {
    return transcript
        .replaceAll('[taigi-fail]', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
