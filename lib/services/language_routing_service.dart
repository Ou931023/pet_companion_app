import 'dart:async';

import '../models/language_route.dart';
import 'asr_strategy_service.dart';

class LanguageRoutingService {
  const LanguageRoutingService(
    this._asrStrategies, {
    this.strategyTimeout = const Duration(milliseconds: 1200),
  });

  final AsrStrategyService _asrStrategies;
  final Duration strategyTimeout;

  Future<LanguageRouteResult> routeTranscript({
    required VoiceLanguageMode mode,
    required String realtimeTranscript,
    String manualStrategyName = 'defaultOpenAiRealtime',
  }) async {
    final normalizedRealtime =
        _asrStrategies.defaultRealtime.normalizeTranscript(realtimeTranscript);
    if (normalizedRealtime.isEmpty) {
      return const LanguageRouteResult(
        strategyName: 'defaultOpenAiRealtime',
        languageHint: TranscriptLanguageHint.unknown,
        routeReason: 'empty_transcript',
        isFallback: false,
        transcript: '',
      );
    }

    return switch (mode) {
      VoiceLanguageMode.taigiPreferred => _routeTaigiPreferred(
          normalizedRealtime,
        ),
      VoiceLanguageMode.manualOverride => _routeManualOverride(
          normalizedRealtime,
          manualStrategyName,
        ),
      VoiceLanguageMode.defaultOpenAiRealtime => Future.value(
          LanguageRouteResult(
            strategyName: _asrStrategies.defaultRealtime.strategyName,
            languageHint: TranscriptLanguageHint.zh,
            routeReason: 'default_openai_realtime',
            isFallback: false,
            transcript: normalizedRealtime,
          ),
        ),
    };
  }

  Future<LanguageRouteResult> _routeTaigiPreferred(
    String realtimeTranscript,
  ) async {
    final taigi = _asrStrategies.taigiStrategy;
    if (taigi == null) {
      return LanguageRouteResult(
        strategyName: _asrStrategies.defaultRealtime.strategyName,
        languageHint: TranscriptLanguageHint.zh,
        routeReason: 'taigi_strategy_unavailable_fallback_openai_realtime',
        isFallback: true,
        transcript: realtimeTranscript,
      );
    }

    try {
      final transcript = await taigi
          .transcribe(
            realtimeTranscript: realtimeTranscript,
          )
          .timeout(strategyTimeout);
      if (transcript.trim().isEmpty) {
        throw StateError('empty_taigi_transcript');
      }
      return LanguageRouteResult(
        strategyName: taigi.strategyName,
        languageHint: TranscriptLanguageHint.taigi,
        routeReason: 'taigi_preferred_strategy_selected',
        isFallback: false,
        transcript: transcript,
      );
    } catch (error) {
      final reason = error is TimeoutException
          ? 'taigi_strategy_timeout_fallback_openai_realtime'
          : 'taigi_strategy_failed_fallback_openai_realtime: $error';
      return LanguageRouteResult(
        strategyName: _asrStrategies.defaultRealtime.strategyName,
        languageHint: TranscriptLanguageHint.zh,
        routeReason: reason,
        isFallback: true,
        transcript: realtimeTranscript,
      );
    }
  }

  Future<LanguageRouteResult> _routeManualOverride(
    String realtimeTranscript,
    String manualStrategyName,
  ) async {
    final strategy = _asrStrategies.strategyFor(manualStrategyName);
    try {
      final transcript = await strategy
          .transcribe(
            realtimeTranscript: realtimeTranscript,
          )
          .timeout(strategyTimeout);
      if (transcript.trim().isEmpty) {
        throw StateError('empty_manual_transcript');
      }
      return LanguageRouteResult(
        strategyName: strategy.strategyName,
        languageHint: strategy.supportsTaigi
            ? TranscriptLanguageHint.taigi
            : TranscriptLanguageHint.zh,
        routeReason: 'manual_override_strategy_selected',
        isFallback: false,
        transcript: transcript,
      );
    } catch (error) {
      final reason = error is TimeoutException
          ? 'manual_override_timeout_fallback_openai_realtime'
          : 'manual_override_failed_fallback_openai_realtime: $error';
      return LanguageRouteResult(
        strategyName: _asrStrategies.defaultRealtime.strategyName,
        languageHint: TranscriptLanguageHint.zh,
        routeReason: reason,
        isFallback: true,
        transcript: realtimeTranscript,
      );
    }
  }
}
