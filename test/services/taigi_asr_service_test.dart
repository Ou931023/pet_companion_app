import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as path;
import 'package:pet_companion_app/services/taigi_asr_service.dart';

void main() {
  test('TaigiAsrService parses successful response', () async {
    final client = MockClient.streaming((request, bodyStream) async {
      expect(request.url.path, '/api/asr/taigi');
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({
          'language': 'taigi',
          'transcript': '今仔日心情無好',
          'confidence': 0.82,
          'source': 'taigi-asr',
          'durationMs': 3200,
        }))),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final file = await _tempAudioFile();
    try {
      final result = await TaigiAsrService(client: client).transcribeAudio(
        audioFile: file,
        sttProxyUrl: 'http://127.0.0.1:3001/api/stt/transcribe',
      );

      expect(result.success, isTrue);
      expect(result.transcript, '今仔日心情無好');
      expect(result.language, 'taigi');
      expect(result.confidence, 0.82);
      expect(result.source, 'taigi-asr');
      expect(result.durationMs, 3200);
    } finally {
      await file.delete();
    }
  });

  test('TaigiAsrService handles unavailable response safely', () async {
    final client = MockClient.streaming((request, bodyStream) async {
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode({
          'error': 'TAIGI_ASR_UNAVAILABLE',
          'message': 'Taigi ASR service is not configured',
        }))),
        503,
        headers: {'content-type': 'application/json'},
      );
    });
    final file = await _tempAudioFile();
    try {
      final result = await TaigiAsrService(client: client).transcribeAudio(
        audioFile: file,
        sttProxyUrl: 'http://127.0.0.1:3001/api/stt/transcribe',
      );

      expect(result.success, isFalse);
      expect(result.transcript, isEmpty);
      expect(result.message, '目前台語語音辨識暫時無法使用，請稍後再試。');
    } finally {
      await file.delete();
    }
  });
}

Future<File> _tempAudioFile() async {
  final dir = await Directory.systemTemp.createTemp('taigi_asr_test_');
  final file = File(path.join(dir.path, 'sample.m4a'));
  await file.writeAsBytes([0, 1, 2, 3]);
  return file;
}
