import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'speech_to_text_service.dart';

class OpenAiSpeechToTextService implements SpeechToTextService {
  OpenAiSpeechToTextService({
    required this.proxyUrl,
    AudioRecorder? recorder,
  }) : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  final String proxyUrl;

  @override
  Future<void> startRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw Exception('No microphone permission');
    }
    final dir = await getTemporaryDirectory();
    final filePath = path.join(
      dir.path,
      'recording_${DateTime.now().millisecondsSinceEpoch}.m4a',
    );
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 44100,
        numChannels: 1,
      ),
      path: filePath,
    );
  }

  @override
  Future<File?> stopRecording() async {
    final resultPath = await _recorder.stop();
    if (resultPath == null || resultPath.isEmpty) {
      return null;
    }
    return File(resultPath);
  }

  @override
  Future<SttResult> transcribeAudio(File audioFile) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse(proxyUrl))
        ..files.add(
          await http.MultipartFile.fromPath('audio', audioFile.path),
        );
      final response = await request.send();
      final responseText = await response.stream.bytesToString();
      if (response.statusCode >= 400) {
        return const SttResult(
          success: false,
          transcript: '',
          errorType: SttErrorType.networkError,
          message: '連線好像不太穩，我這次沒辦法聽清楚你說的話。',
        );
      }
      final decoded = jsonDecode(responseText) as Map<String, dynamic>;
      final text = (decoded['text'] as String? ?? '').trim();
      if (text.isEmpty) {
        return handleEmptyTranscript();
      }
      return SttResult(success: true, transcript: text);
    } catch (_) {
      return const SttResult(
        success: false,
        transcript: '',
        errorType: SttErrorType.networkError,
        message: '語音辨識暫時不太順，我們等一下再試一次。',
      );
    }
  }

  @override
  Future<SttResult> retryTranscription(File audioFile) async {
    final first = await transcribeAudio(audioFile);
    if (first.success) {
      return first;
    }
    return transcribeAudio(audioFile);
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

  @override
  SttResult handleEmptyTranscript() {
    return const SttResult(
      success: false,
      transcript: '',
      errorType: SttErrorType.emptyTranscript,
      message: '我剛剛沒有聽清楚，可以再說一次嗎？',
    );
  }
}
