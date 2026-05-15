import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/companion_analysis_result.dart';

class CompanionEngineService {
  const CompanionEngineService();

  Future<CompanionAnalysisResult?> analyze({
    required String userId,
    required String sessionId,
    required String turnId,
    required String petName,
    required String transcript,
    required Map<String, dynamic> petState,
    List<Map<String, dynamic>> recentTurns = const [],
    String languageHint = 'zh',
    Map<String, dynamic> audioFeatures = const {
      'volumeMean': null,
      'pauseDensity': null,
      'speechRate': null,
    },
  }) async {
    final normalized = transcript.trim();
    if (normalized.isEmpty) return null;
    final uri = Uri.parse(
      '${AppConfig.apiBaseUrlForSttProxy(AppConfig.defaultSttProxyUrl)}/companion/analyze',
    );
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'userId': userId,
            'sessionId': sessionId,
            'turnId': turnId,
            'petName': petName,
            'transcript': normalized,
            'languageHint': languageHint,
            'recentTurns': recentTurns,
            'petState': petState,
            'audioFeatures': audioFeatures,
          }),
        )
        .timeout(const Duration(seconds: 3));
    if (response.statusCode >= 400) return null;
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return CompanionAnalysisResult.fromJson(data);
  }
}
