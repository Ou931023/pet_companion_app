import 'package:flutter_tts/flutter_tts.dart';

class TextToSpeechService {
  TextToSpeechService() : _tts = FlutterTts();

  final FlutterTts _tts;

  Future<void> _configure({
    required double volume,
    required String speechStyle,
  }) async {
    await _tts.setLanguage('zh-TW');
    await _tts.setSpeechRate(_rateForStyle(speechStyle));
    await _tts.setVolume(volume.clamp(0.0, 1.0));
    await _tts.setPitch(_pitchForStyle(speechStyle));
  }

  Future<void> speak(
    String text, {
    required bool enabled,
    required double volume,
    required String speechStyle,
    required Future<void> Function() onStart,
    required Future<void> Function() onComplete,
    required Future<void> Function() onError,
  }) async {
    if (!enabled) {
      await onComplete();
      return;
    }
    try {
      await _configure(volume: volume, speechStyle: speechStyle);
      _tts.setStartHandler(() async => onStart());
      _tts.setCompletionHandler(() async => onComplete());
      _tts.setErrorHandler((_) async => onError());
      await _tts.awaitSpeakCompletion(true);
      await _tts.speak(text);
    } catch (_) {
      await onError();
    }
  }

  Future<void> stop() async {
    await _tts.stop();
  }

  double _rateForStyle(String speechStyle) {
    return switch (speechStyle) {
      'bright' => 0.46,
      'calm' => 0.36,
      _ => 0.42,
    };
  }

  double _pitchForStyle(String speechStyle) {
    return switch (speechStyle) {
      'bright' => 1.08,
      'calm' => 0.92,
      _ => 1.0,
    };
  }
}
