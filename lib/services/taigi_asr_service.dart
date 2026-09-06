import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../config/app_config.dart';
import '../models/taigi_asr_result.dart';
import '../models/taigi_asr_status.dart';
import '../utils/app_log.dart';

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
    Uri? uri;
    try {
      final apiBase = Uri.parse(AppConfig.apiBaseUrlForSttProxy(sttProxyUrl));
      uri = apiBase.replace(path: '${apiBase.path}/asr/taigi');
      AppLog.debug('[TAIGI_ASR] transcribe started');
      final request = http.MultipartRequest('POST', uri)
        ..files.add(await http.MultipartFile.fromPath('audio', audioFile.path));
      final response = await _client.send(request).timeout(
            const Duration(seconds: 75),
          );
      final responseText = await response.stream.bytesToString();
      AppLog.debug('[TAIGI_ASR] transcribe status=${response.statusCode}');
      final decoded = jsonDecode(responseText) as Map<String, dynamic>;
      if (response.statusCode >= 400) {
        return TaigiAsrResult.unavailable();
      }
      final result = TaigiAsrResult.fromJson(decoded);
      if (result.transcript.trim().isEmpty) {
        return TaigiAsrResult.empty();
      }
      return result;
    } catch (error) {
      AppLog.error('[TAIGI_ASR] transcribe failed', error);
      return TaigiAsrResult.unavailable();
    }
  }

  Future<TaigiAsrStatus> fetchStatus({
    required String sttProxyUrl,
  }) async {
    Uri? uri;
    try {
      uri = _apiUri(sttProxyUrl, '/asr/taigi/status');
      AppLog.debug('[TAIGI_ASR] status requested');
      final response = await _client.get(uri).timeout(
            const Duration(seconds: 8),
          );
      AppLog.debug('[TAIGI_ASR] status code=${response.statusCode}');
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return TaigiAsrStatus.fromJson(decoded);
    } catch (error) {
      AppLog.error('[TAIGI_ASR] status failed', error);
      return TaigiAsrStatus.unavailable();
    }
  }

  Future<TaigiAsrStatus> warmup({
    required String sttProxyUrl,
  }) async {
    try {
      final uri = _apiUri(sttProxyUrl, '/asr/taigi/warmup');
      final response = await _client.post(uri).timeout(
            const Duration(seconds: 40),
          );
      if (response.statusCode >= 400) {
        return TaigiAsrStatus.unavailable();
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return TaigiAsrStatus.fromJson({
        'enabled': true,
        ...decoded,
      });
    } catch (_) {
      return TaigiAsrStatus.unavailable();
    }
  }

  Uri _apiUri(String sttProxyUrl, String endpointPath) {
    final apiBase = Uri.parse(AppConfig.apiBaseUrlForSttProxy(sttProxyUrl));
    return apiBase.replace(path: '${apiBase.path}$endpointPath');
  }
}

class TaigiAsrException implements Exception {
  const TaigiAsrException(this.code);

  final String code;
}
