import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../config/app_config.dart';
import '../models/taigi_asr_result.dart';

class TaigiAsrService {
  TaigiAsrService({
    AudioRecorder? recorder,
    http.Client? client,
  })  : _recorder = recorder,
        _client = client ?? http.Client();

  AudioRecorder? _recorder;
  final http.Client _client;

  Future<void> startRecording() async {
    final recorder = _recorder ??= AudioRecorder();
    final hasPermission = await recorder.hasPermission();
    if (!hasPermission) {
      throw const TaigiAsrException('microphone_denied');
    }
    final dir = await getTemporaryDirectory();
    final filePath = path.join(
      dir.path,
      'taigi_recording_${DateTime.now().millisecondsSinceEpoch}.m4a',
    );
    await recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 44100,
        numChannels: 1,
      ),
      path: filePath,
    );
  }

  Future<File?> stopRecording() async {
    final recorder = _recorder ??= AudioRecorder();
    final resultPath = await recorder.stop();
    if (resultPath == null || resultPath.isEmpty) return null;
    return File(resultPath);
  }

  Future<TaigiAsrResult> transcribeAudio({
    required File audioFile,
    required String sttProxyUrl,
  }) async {
    try {
      final apiBase = Uri.parse(AppConfig.apiBaseUrlForSttProxy(sttProxyUrl));
      final uri = apiBase.replace(path: '${apiBase.path}/asr/taigi');
      final request = http.MultipartRequest('POST', uri)
        ..files.add(await http.MultipartFile.fromPath('audio', audioFile.path));
      final response = await _client.send(request).timeout(
            const Duration(seconds: 75),
          );
      final responseText = await response.stream.bytesToString();
      final decoded = jsonDecode(responseText) as Map<String, dynamic>;
      if (response.statusCode >= 400) {
        return TaigiAsrResult.unavailable();
      }
      final result = TaigiAsrResult.fromJson(decoded);
      if (result.transcript.trim().isEmpty) {
        return TaigiAsrResult.empty();
      }
      return result;
    } catch (_) {
      return TaigiAsrResult.unavailable();
    }
  }
}

class TaigiAsrException implements Exception {
  const TaigiAsrException(this.code);

  final String code;
}
