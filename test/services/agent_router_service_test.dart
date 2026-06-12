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
    // CR-0079：逾時要回白話訊息，不可出現工程字眼。
    expect(result.errorMessage, '等待時間比較久，請稍後再試一次。');
  }, timeout: const Timeout(Duration(seconds: 7)));

  test('http error returns friendly message without status code', () async {
    final service = AgentRouterService(
      client: MockClient((request) async {
        return http.Response('internal server error', 500);
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
    expect(result.errorMessage, '寵物現在回應比較慢，請稍等一下再試一次。');
    expect(result.errorMessage, isNot(contains('500')));
    expect(result.errorMessage, isNot(contains('agent route')));
  });

  test('network exception returns friendly message without raw error',
      () async {
    final service = AgentRouterService(
      client: MockClient((request) async {
        throw http.ClientException('Connection refused');
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
    expect(result.errorMessage, '目前連線不太穩，請確認網路後再試一次。');
    expect(result.errorMessage, isNot(contains('Connection refused')));
    expect(result.errorMessage, isNot(contains('Exception')));
  });
}
