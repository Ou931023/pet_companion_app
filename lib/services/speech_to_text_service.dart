import 'dart:io';

enum SttMode { mock, openAiProxy }

enum SttErrorType {
  none,
  noVoice,
  emptyTranscript,
  noiseDetected,
  networkError,
  unknown,
}

class SttResult {
  const SttResult({
    required this.success,
    required this.transcript,
    this.errorType = SttErrorType.none,
    this.message,
  });

  final bool success;
  final String transcript;
  final SttErrorType errorType;
  final String? message;
}

abstract class SpeechToTextService {
  Future<void> startRecording();
  Future<File?> stopRecording();
  Future<SttResult> transcribeAudio(File audioFile);
  Future<SttResult> retryTranscription(File audioFile);
  SttResult handleNoiseDetected();
  SttResult handleEmptyTranscript();
}
