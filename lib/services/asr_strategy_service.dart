abstract class AsrStrategy {
  String get strategyName;
  bool get supportsRealtime;
  bool get supportsTaigi;

  Future<String> transcribe({
    required String realtimeTranscript,
    List<int>? audioBytes,
  });

  Stream<String> streamTranscribe({
    required Stream<List<int>> audioStream,
    String realtimeTranscript = '',
  });

  String normalizeTranscript(String transcript);
}

class OpenAiRealtimeAsrStrategy implements AsrStrategy {
  const OpenAiRealtimeAsrStrategy();

  @override
  String get strategyName => 'defaultOpenAiRealtime';

  @override
  bool get supportsRealtime => true;

  @override
  bool get supportsTaigi => false;

  @override
  Future<String> transcribe({
    required String realtimeTranscript,
    List<int>? audioBytes,
  }) async {
    return normalizeTranscript(realtimeTranscript);
  }

  @override
  Stream<String> streamTranscribe({
    required Stream<List<int>> audioStream,
    String realtimeTranscript = '',
  }) async* {
    final normalized = normalizeTranscript(realtimeTranscript);
    if (normalized.isNotEmpty) yield normalized;
  }

  @override
  String normalizeTranscript(String transcript) {
    return transcript.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

class AsrStrategyService {
  AsrStrategyService({List<AsrStrategy>? strategies})
      : _strategies = {
          for (final strategy in strategies ??
              const [
                OpenAiRealtimeAsrStrategy(),
              ])
            strategy.strategyName: strategy,
        };

  final Map<String, AsrStrategy> _strategies;

  AsrStrategy strategyFor(String strategyName) {
    return _strategies[strategyName] ??
        _strategies['defaultOpenAiRealtime'] ??
        const OpenAiRealtimeAsrStrategy();
  }

  AsrStrategy get defaultRealtime => strategyFor('defaultOpenAiRealtime');

  AsrStrategy? get taigiStrategy {
    for (final strategy in _strategies.values) {
      if (strategy.supportsTaigi) return strategy;
    }
    return null;
  }

  List<AsrStrategy> get strategies => List.unmodifiable(_strategies.values);
}
