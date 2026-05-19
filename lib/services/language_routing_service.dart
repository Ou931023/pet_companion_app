import 'dart:async';

import '../models/language_route.dart';
import 'asr_strategy_service.dart';
import 'taigi_text_detection_service.dart';

class LanguageRoutingService {
  const LanguageRoutingService(
    this._asrStrategies, {
    this.strategyTimeout = const Duration(milliseconds: 1200),
    this.taigiTextDetectionService = const TaigiTextDetectionService(),
  });

  final AsrStrategyService _asrStrategies;
  final Duration strategyTimeout;
  final TaigiTextDetectionService taigiTextDetectionService;

  LanguageRouteResult previewRouteFromText({
    required VoiceLanguageMode mode,
    required String text,
    String manualStrategyName = 'defaultOpenAiRealtime',
  }) {
    final normalizedText = text.trim();
    if (normalizedText.isEmpty) {
      return const LanguageRouteResult(
        strategyName: 'textInput',
        languageHint: TranscriptLanguageHint.unknown,
        routeReason: 'empty_text',
        isFallback: false,
        transcript: '',
      );
    }

    if (mode == VoiceLanguageMode.taigiPreferred) {
      return LanguageRouteResult(
        strategyName: 'textInput',
        languageHint: TranscriptLanguageHint.taigi,
        routeReason: 'taigi_manual_mode',
        isFallback: false,
        transcript: normalizedText,
        replyLanguage: ReplyLanguage.mixedZhTaigi,
      );
    }
    if (mode == VoiceLanguageMode.manualOverride &&
        manualStrategyName.toLowerCase().contains('taigi')) {
      return LanguageRouteResult(
        strategyName: 'textInput',
        languageHint: TranscriptLanguageHint.taigi,
        routeReason: 'taigi_manual_mode',
        isFallback: false,
        transcript: normalizedText,
        replyLanguage: ReplyLanguage.mixedZhTaigi,
      );
    }

    final detected = taigiTextDetectionService.detect(normalizedText);
    if (detected.isLikelyTaigi) {
      final reason = detected.reason == 'matched_taigi_mixed_zh_keywords'
          ? 'taigi_mixed_zh_detected'
          : 'taigi_text_keywords_detected';
      return LanguageRouteResult(
        strategyName: 'textInput',
        languageHint: TranscriptLanguageHint.taigi,
        routeReason: reason,
        isFallback: false,
        transcript: normalizedText,
        replyLanguage: ReplyLanguage.mixedZhTaigi,
      );
    }

    return LanguageRouteResult(
      strategyName: 'textInput',
      languageHint: TranscriptLanguageHint.zh,
      routeReason: 'zh_text_default',
      isFallback: false,
      transcript: normalizedText,
      replyLanguage: ReplyLanguage.zhTw,
    );
  }

  Future<LanguageRouteResult> routeTranscript({
    required VoiceLanguageMode mode,
    required String realtimeTranscript,
    String manualStrategyName = 'defaultOpenAiRealtime',
  }) async {
    final normalizedRealtime =
        _asrStrategies.defaultRealtime.normalizeTranscript(realtimeTranscript);
    final detectedReplyLanguage = replyLanguageForTranscript(
        normalizedRealtime, mode, manualStrategyName);
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
            languageHint: detectedReplyLanguage == ReplyLanguage.mixedZhTaigi
                ? TranscriptLanguageHint.mixed
                : TranscriptLanguageHint.zh,
            routeReason: 'default_openai_realtime',
            isFallback: false,
            transcript: normalizedRealtime,
            replyLanguage: detectedReplyLanguage,
          ),
        ),
    };
  }

  static ReplyLanguage replyLanguageForTranscript(
    String transcript,
    VoiceLanguageMode mode, [
    String manualStrategyName = 'defaultOpenAiRealtime',
  ]) {
    if (mode == VoiceLanguageMode.taigiPreferred) {
      return ReplyLanguage.mixedZhTaigi;
    }
    if (mode == VoiceLanguageMode.manualOverride &&
        manualStrategyName.toLowerCase().contains('taigi')) {
      return ReplyLanguage.mixedZhTaigi;
    }
    if (const TaigiTextDetectionService().detect(transcript).isLikelyTaigi) {
      return ReplyLanguage.mixedZhTaigi;
    }
    return ReplyLanguage.zhTw;
  }

  static bool containsTaigiCue(String transcript) {
    return const TaigiTextDetectionService().detect(transcript).isLikelyTaigi;
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
        replyLanguage: ReplyLanguage.mixedZhTaigi,
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
        replyLanguage: ReplyLanguage.mixedZhTaigi,
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
        replyLanguage: ReplyLanguage.mixedZhTaigi,
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
        replyLanguage: strategy.supportsTaigi
            ? ReplyLanguage.mixedZhTaigi
            : replyLanguageForTranscript(
                transcript, VoiceLanguageMode.defaultOpenAiRealtime),
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
        replyLanguage: replyLanguageForTranscript(
          realtimeTranscript,
          VoiceLanguageMode.manualOverride,
          manualStrategyName,
        ),
      );
    }
  }
}
