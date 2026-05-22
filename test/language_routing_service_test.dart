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
      expect(route.replyLanguage, ReplyLanguage.zhTw);
    });

    test('taigi cue in default mode selects mixed reply language', () async {
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
        realtimeTranscript: '今仔日厝內足安靜',
      );

      expect(route.languageHint, TranscriptLanguageHint.mixed);
      expect(route.replyLanguage, ReplyLanguage.mixedZhTaigi);
    });

    test('taigi realtime mode keeps OpenAI Realtime and marks taigi metadata',
        () async {
      final service = LanguageRoutingService(
        AsrStrategyService(
          strategies: const [
            OpenAiRealtimeAsrStrategy(),
            MockTaigiAsrStrategy(),
          ],
        ),
      );

      final route = await service.routeTranscript(
        mode: VoiceLanguageMode.taigiRealtime,
        realtimeTranscript: ' 心情無好 ',
      );

      expect(route.strategyName, 'openai-realtime');
      expect(route.languageHint, TranscriptLanguageHint.taigi);
      expect(route.routeReason, 'taigi_realtime_mode');
      expect(route.replyLanguage, ReplyLanguage.mixedZhTaigi);
      expect(route.transcript, '心情無好');
    });

    test('taigi realtime text preview marks taigi context', () {
      final service = LanguageRoutingService(
        AsrStrategyService(
          strategies: const [
            OpenAiRealtimeAsrStrategy(),
            MockTaigiAsrStrategy(),
          ],
        ),
      );

      final route = service.previewRouteFromText(
        mode: VoiceLanguageMode.taigiRealtime,
        text: '今天心情不太好',
      );

      expect(route.languageHint, TranscriptLanguageHint.taigi);
      expect(route.routeReason, 'taigi_realtime_mode');
      expect(route.replyLanguage, ReplyLanguage.mixedZhTaigi);
    });

    test('text preview keeps plain Mandarin in zh context', () {
      final service = LanguageRoutingService(
        AsrStrategyService(
          strategies: const [
            OpenAiRealtimeAsrStrategy(),
            MockTaigiAsrStrategy(),
          ],
        ),
      );

      final route = service.previewRouteFromText(
        mode: VoiceLanguageMode.defaultOpenAiRealtime,
        text: '今天心情不太好',
      );

      expect(route.strategyName, 'textInput');
      expect(route.languageHint, TranscriptLanguageHint.zh);
      expect(route.routeReason, 'zh_text_default');
      expect(route.replyLanguage, ReplyLanguage.zhTw);
    });

    test('text preview marks mixed Taigi Mandarin as taigi context', () {
      final service = LanguageRoutingService(
        AsrStrategyService(
          strategies: const [
            OpenAiRealtimeAsrStrategy(),
            MockTaigiAsrStrategy(),
          ],
        ),
      );

      final route = service.previewRouteFromText(
        mode: VoiceLanguageMode.defaultOpenAiRealtime,
        text: '今仔日心情無好',
      );

      expect(route.languageHint, TranscriptLanguageHint.taigi);
      expect(route.routeReason, 'taigi_mixed_zh_detected');
      expect(route.replyLanguage, ReplyLanguage.mixedZhTaigi);
    });

    test('text preview honors taigi preferred mode without changing ASR route',
        () {
      final service = LanguageRoutingService(
        AsrStrategyService(
          strategies: const [
            OpenAiRealtimeAsrStrategy(),
            MockTaigiAsrStrategy(),
          ],
        ),
      );

      final route = service.previewRouteFromText(
        mode: VoiceLanguageMode.taigiPreferred,
        text: '今天心情不太好',
      );

      expect(route.strategyName, 'textInput');
      expect(route.languageHint, TranscriptLanguageHint.taigi);
      expect(route.routeReason, 'taigi_manual_mode');
      expect(route.replyLanguage, ReplyLanguage.mixedZhTaigi);
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
      expect(route.replyLanguage, ReplyLanguage.mixedZhTaigi);
    });

    test('taigiPreferred prefers mixed reply language for Mandarin input',
        () async {
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
        realtimeTranscript: '今天家裡好安靜',
      );

      expect(route.replyLanguage, ReplyLanguage.mixedZhTaigi);
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
      expect(route.replyLanguage, ReplyLanguage.mixedZhTaigi);
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
