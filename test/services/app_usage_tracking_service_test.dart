import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pet_companion_app/services/app_usage_tracking_service.dart';

void main() {
  test('track POST 到 app usage endpoint，帶 Bearer，body 不含 elderId / token',
      () async {
    http.Request? captured;
    final service = AppUsageTrackingService(
      authTokenProvider: () async => 'mock-id-token-default_user',
      client: MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode({'success': true}), 201);
      }),
    );

    final ok = await service.track(
      'voice_interaction_end',
      sessionId: 'session-1',
      durationMs: 42000,
      metadata: {
        'mode': 'realtime',
        'nested': {'not': 'sent'},
        'long': List.filled(140, 'x').join(),
      },
    );

    expect(ok, isTrue);
    expect(captured, isNotNull);
    expect(captured!.method, 'POST');
    expect(captured!.url.path, '/api/app-usage/events');
    expect(
      captured!.headers['Authorization'],
      'Bearer mock-id-token-default_user',
    );

    final body = jsonDecode(captured!.body) as Map<String, dynamic>;
    expect(body['eventType'], 'voice_interaction_end');
    expect(body['sessionId'], 'session-1');
    expect(body['durationMs'], 42000);
    expect(body.containsKey('elderId'), isFalse);
    expect(captured!.body.toLowerCase().contains('token'), isFalse);
    final metadata = body['metadata'] as Map<String, dynamic>;
    expect(metadata['mode'], 'realtime');
    expect(metadata.containsKey('nested'), isFalse);
    expect((metadata['long'] as String).length, 120);
  });

  test('沒有 token 時不送出、不 throw', () async {
    var posted = false;
    final service = AppUsageTrackingService(
      authTokenProvider: () async => null,
      client: MockClient((request) async {
        posted = true;
        return http.Response('{}', 201);
      }),
    );

    await expectLater(service.track('app_open'), completion(isFalse));
    expect(posted, isFalse);
  });

  test('HTTP 非 2xx 或網路例外都回 false，不影響主流程', () async {
    final non2xx = AppUsageTrackingService(
      authTokenProvider: () async => 'token',
      client: MockClient((request) async => http.Response('no', 500)),
    );
    await expectLater(non2xx.track('typed_chat_sent'), completion(isFalse));

    final throwing = AppUsageTrackingService(
      authTokenProvider: () async => 'token',
      client: MockClient((request) async => throw Exception('network')),
    );
    await expectLater(throwing.track('typed_chat_sent'), completion(isFalse));
  });
}
