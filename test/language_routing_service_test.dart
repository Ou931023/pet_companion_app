import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/models/language_route.dart';
import 'package:pet_companion_app/services/asr_strategy_service.dart';
import 'package:pet_companion_app/services/language_routing_service.dart';
import 'package:pet_companion_app/services/taigi_asr_strategy.dart';

void main() {
  group('LanguageRoutingService', () {
    test('default mode uses OpenAI Realtime transcript', () async {
      final service = LanguageRoutingService(
        AsrStrategyService(
          strategies: const [
            OpenAiRealtimeAsrStrategy(),
            MockTaigiAsrStrategy(),
          ],
        ),
      );

      final route = await service.routeTranscript(
        mode: VoiceLanguageMode.defaultOpenAiRealtime,
        realtimeTranscript: ' 今天家裡好安靜 ',
      );

      expect(route.strategyName, 'defaultOpenAiRealtime');
      expect(route.languageHint, TranscriptLanguageHint.zh);
      expect(route.routeReason, 'default_openai_realtime');
      expect(route.isFallback, isFalse);
      expect(route.transcript, '今天家裡好安靜');
    });

    test('taigiPreferred selects Taigi strategy first', () async {
      final service = LanguageRoutingService(
        AsrStrategyService(
          strategies: const [
            OpenAiRealtimeAsrStrategy(),
            MockTaigiAsrStrategy(),
          ],
        ),
      );

      final route = await service.routeTranscript(
        mode: VoiceLanguageMode.taigiPreferred,
        realtimeTranscript: '阿嬤 今天 睡不太著',
      );

      expect(route.strategyName, 'mockTaigiAsr');
      expect(route.languageHint, TranscriptLanguageHint.taigi);
      expect(route.routeReason, 'taigi_preferred_strategy_selected');
      expect(route.isFallback, isFalse);
    });

    test('taigi strategy failure falls back to OpenAI Realtime', () async {
      final service = LanguageRoutingService(
        AsrStrategyService(
          strategies: const [
            OpenAiRealtimeAsrStrategy(),
            MockTaigiAsrStrategy(forceFailure: true),
          ],
        ),
      );

      final route = await service.routeTranscript(
        mode: VoiceLanguageMode.taigiPreferred,
        realtimeTranscript: '阿公想聊天',
      );

      expect(route.strategyName, 'defaultOpenAiRealtime');
      expect(route.languageHint, TranscriptLanguageHint.zh);
      expect(route.routeReason, contains('fallback_openai_realtime'));
      expect(route.isFallback, isTrue);
      expect(route.transcript, '阿公想聊天');
    });

    test('manualOverride can specify strategy', () async {
      final service = LanguageRoutingService(
        AsrStrategyService(
          strategies: const [
            OpenAiRealtimeAsrStrategy(),
            MockTaigiAsrStrategy(),
          ],
        ),
      );

      final route = await service.routeTranscript(
        mode: VoiceLanguageMode.manualOverride,
        manualStrategyName: 'mockTaigiAsr',
        realtimeTranscript: '來講台語',
      );

      expect(route.strategyName, 'mockTaigiAsr');
      expect(route.languageHint, TranscriptLanguageHint.taigi);
      expect(route.routeReason, 'manual_override_strategy_selected');
      expect(route.isFallback, isFalse);
    });

    test('fallback keeps transcript so voice flow can continue', () async {
      final service = LanguageRoutingService(
        AsrStrategyService(
          strategies: const [
            OpenAiRealtimeAsrStrategy(),
            MockTaigiAsrStrategy(forceFailure: true),
          ],
        ),
      );

      final route = await service.routeTranscript(
        mode: VoiceLanguageMode.taigiPreferred,
        realtimeTranscript: '我想聽一則新聞',
      );

      expect(route.isFallback, isTrue);
      expect(route.transcript, isNotEmpty);
      expect(route.transcript, '我想聽一則新聞');
    });

    test('slow taigi strategy times out and falls back', () async {
      final service = LanguageRoutingService(
        AsrStrategyService(
          strategies: const [
            OpenAiRealtimeAsrStrategy(),
            _SlowTaigiStrategy(),
          ],
        ),
        strategyTimeout: const Duration(milliseconds: 10),
      );

      final route = await service.routeTranscript(
        mode: VoiceLanguageMode.taigiPreferred,
        realtimeTranscript: '主線不能被台語模型卡住',
      );

      expect(route.strategyName, 'defaultOpenAiRealtime');
      expect(
          route.routeReason, 'taigi_strategy_timeout_fallback_openai_realtime');
      expect(route.isFallback, isTrue);
      expect(route.transcript, '主線不能被台語模型卡住');
    });
  });
}

class _SlowTaigiStrategy implements AsrStrategy {
  const _SlowTaigiStrategy();

  @override
  String get strategyName => 'slowTaigiAsr';

  @override
  bool get supportsRealtime => false;

  @override
  bool get supportsTaigi => true;

  @override
  Future<String> transcribe({
    required String realtimeTranscript,
    List<int>? audioBytes,
  }) async {
    await Future<void>.delayed(const Duration(seconds: 1));
    return realtimeTranscript;
  }

  @override
  Stream<String> streamTranscribe({
    required Stream<List<int>> audioStream,
    String realtimeTranscript = '',
  }) async* {
    yield realtimeTranscript;
  }

  @override
  String normalizeTranscript(String transcript) => transcript.trim();
}
