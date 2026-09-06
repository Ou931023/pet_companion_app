import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pet_companion_app/services/daily_care_task_api_service.dart';

void main() {
  test('照護任務請求帶 Firebase Bearer token', () async {
    late http.Request captured;
    final service = DailyCareTaskApiService(
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({'success': true, 'tasks': <Object>[]}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      authTokenProvider: () async => 'fresh-firebase-token',
    );

    final tasks = await service.listTasks(elderId: 'client-supplied-id');

    expect(tasks, isEmpty);
    expect(captured.headers['Authorization'], 'Bearer fresh-firebase-token');
  });

  test('取 token 失敗時不外洩例外，交由後端拒絕', () async {
    late http.Request captured;
    final service = DailyCareTaskApiService(
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({'success': true, 'tasks': <Object>[]}),
          200,
        );
      }),
      authTokenProvider: () async => throw StateError('firebase unavailable'),
    );

    await service.listTasks(elderId: 'elder-1');

    expect(captured.headers.containsKey('Authorization'), isFalse);
  });
}
