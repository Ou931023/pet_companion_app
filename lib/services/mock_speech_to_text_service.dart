import 'dart:io';

import 'speech_to_text_service.dart';

class MockSpeechToTextService implements SpeechToTextService {
  String _nextTranscript = '幫我簽到';

  void setNextTranscript(String text) {
    _nextTranscript = text;
  }

  @override
  Future<void> startRecording() async {}

  @override
  Future<File?> stopRecording() async => null;

  @override
  Future<SttResult> transcribeAudio(File audioFile) async {
    final text = _nextTranscript.trim();
    if (text.contains('[noise]')) {
      return handleNoiseDetected();
    }
    if (text.isEmpty) {
      return handleEmptyTranscript();
    }
    if (text == '[novoice]') {
      return const SttResult(
        success: false,
        transcript: '',
        errorType: SttErrorType.noVoice,
        message: '我剛剛沒有聽到聲音，可以再說一次嗎？',
      );
    }
    return SttResult(success: true, transcript: text);
  }

  @override
  Future<SttResult> retryTranscription(File audioFile) async {
    return transcribeAudio(audioFile);
  }

  @override
  SttResult handleEmptyTranscript() {
    return const SttResult(
      success: false,
      transcript: '',
      errorType: SttErrorType.emptyTranscript,
      message: '我剛剛沒有聽清楚，可以再說一次嗎？',
    );
  }

  @override
  SttResult handleNoiseDetected() {
    return const SttResult(
      success: false,
      transcript: '',
      errorType: SttErrorType.noiseDetected,
      message: '附近好像有點吵，我會再試著聽一次。',
    );
  }
}
