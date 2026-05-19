import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/agent_route_result.dart';

class AgentRouterService {
  AgentRouterService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<AgentRouteResult> route({
    required String sttProxyUrl,
    required String userText,
    required String sessionId,
    required String turnId,
    required String petName,
    required String emotion,
    required String languageHint,
    Map<String, dynamic> petState = const {},
    List<Map<String, dynamic>> recentTurns = const [],
  }) async {
    final normalized = userText.trim();
    if (normalized.isEmpty) return AgentRouteResult.noIntent();
    final apiBase = Uri.parse(AppConfig.apiBaseUrlForSttProxy(sttProxyUrl));
    final basePath = apiBase.path.endsWith('/')
        ? apiBase.path.substring(0, apiBase.path.length - 1)
        : apiBase.path;
    final uri = apiBase.replace(
      path: '$basePath/agent/route',
      query: null,
      fragment: null,
    );
    try {
      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'userText': normalized,
              'sessionId': sessionId,
              'turnId': turnId,
              'petName': petName,
              'context': {
                'emotion': emotion,
                'languageHint': languageHint,
                'petState': petState,
                'recentTurns': recentTurns,
              },
            }),
          )
          .timeout(const Duration(seconds: 5));
      if (response.statusCode >= 400) {
        return AgentRouteResult.noIntent(
          errorMessage: 'agent route failed: ${response.statusCode}',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return AgentRouteResult.noIntent();
      return AgentRouteResult.fromJson(Map<String, dynamic>.from(decoded));
    } on TimeoutException {
      return AgentRouteResult.noIntent(errorMessage: 'agent route timeout');
    } catch (error) {
      return AgentRouteResult.noIntent(errorMessage: error.toString());
    }
  }
}
