import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pet_companion_app/services/agent_router_service.dart';

void main() {
  test('routes phone intent from backend response', () async {
    final service = AgentRouterService(
      client: MockClient((request) async {
        expect(request.url.path, '/api/agent/route');
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'hasToolIntent': true,
            'assistantMessage': '需要確認',
            'intent': {
              'id': 'agent_tool_1',
              'toolName': 'open_phone_dialer',
              'displayName': '開啟撥號畫面',
              'arguments': {'contactName': '女兒'},
              'requiresConfirmation': true,
              'riskLevel': 'high',
              'status': 'pending',
              'userFacingMessage': '要幫你開啟撥號畫面嗎？',
              'createdAt': DateTime.now().toIso8601String(),
            },
          })),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final result = await service.route(
      sttProxyUrl: 'http://192.168.99.99:3001/api/stt/transcribe',
      userText: '幫我打給女兒',
      sessionId: 's',
      turnId: 't',
      petName: '小伴',
      emotion: 'neutral',
      languageHint: 'zh-TW',
    );

    expect(result.hasToolIntent, isTrue, reason: result.errorMessage);
    expect(result.intent?.toolName, 'open_phone_dialer');
  });

  test('timeout returns no intent without throwing', () async {
    final service = AgentRouterService(
      client: MockClient((request) async {
        await Future<void>.delayed(const Duration(seconds: 6));
        return http.Response('{}', 200);
      }),
    );

    final result = await service.route(
      sttProxyUrl: 'http://192.168.99.99:3001/api/stt/transcribe',
      userText: '幫我打給女兒',
      sessionId: 's',
      turnId: 't',
      petName: '小伴',
      emotion: 'neutral',
      languageHint: 'zh-TW',
    );

    expect(result.hasToolIntent, isFalse);
    expect(result.errorMessage, contains('timeout'));
  }, timeout: const Timeout(Duration(seconds: 7)));
}
