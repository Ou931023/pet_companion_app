import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pet_companion_app/services/daily_care_task_api_service.dart';

void main() {
  test('real Flutter photo serialization preserves octet-stream and auth', () async {
    final directory = await Directory.systemTemp.createTemp('proof_multipart_');
    final photo = File('${directory.path}/proof.jpg');
    await photo.writeAsBytes([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10]);
    addTearDown(() => directory.delete(recursive: true));
    final service = DailyCareTaskApiService(
      client: MockClient((request) async {
        // MockClient consumes MultipartRequest.finalize(): these are the real
        // serialized headers/bytes, rather than a hand-authored multipart body.
        expect(request.headers['Authorization'], 'Bearer synthetic-resident');
        expect(request.headers['content-type'], startsWith('multipart/form-data; boundary='));
        final body = latin1.decode(request.bodyBytes);
        expect(body, contains('name="photo"; filename="proof.jpg"'));
        expect(body, contains('content-type: application/octet-stream'));
        expect(request.bodyBytes, containsAllInOrder([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10]));
        return http.Response(jsonEncode({
          'success': true,
          'task': {'id': 'synthetic-task', 'title': '散步', 'scheduledTime': '16:30'},
          'submission': {'id': 'synthetic-proof', 'taskId': 'synthetic-task', 'status': 'needs_review'},
        }), 200, headers: {'content-type': 'application/json'});
      }),
      authTokenProvider: () async => 'synthetic-resident',
    );
    await service.submitProof(taskId: 'synthetic-task', image: photo);
  });

  test('task edit works without revision fields or If-Match', () async {
    late http.Request captured;
    final service = DailyCareTaskApiService(
      client: MockClient((request) async {
        captured = request;
        return http.Response.bytes(
            utf8.encode(jsonEncode({
              'success': true,
              'task': {
                'id': 'task-1',
                'title': '散步',
                'scheduledTime': '16:30',
              },
            })),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }),
      authTokenProvider: () async => 'test-only-token',
    );
    final task = await service.updateTask(
      taskId: 'task-1',
      title: ' 散步 ',
      description: ' 慢慢走 ',
      scheduledTime: '16:30',
    );
    expect(captured.method, 'PATCH');
    expect(captured.url.path, '/api/daily-care-tasks/task-1');
    expect(captured.headers.keys.map((key) => key.toLowerCase()),
        isNot(contains('if-match')));
    expect(captured.headers['Authorization'], 'Bearer test-only-token');
    expect(jsonDecode(captured.body),
        {'title': '散步', 'description': '慢慢走', 'scheduledTime': '16:30'});
    expect(task.title, '散步');
  });

  test('task edit conflict requests refresh and never returns success',
      () async {
    final service = DailyCareTaskApiService(
        client: MockClient((_) async => http.Response(
            '{"success":false,"error":"task_not_editable"}', 409)));
    await expectLater(
        service.updateTask(
          taskId: 'task-1',
          title: '散步',
          description: '',
          scheduledTime: '16:30',
        ),
        throwsA(isA<DailyCareTaskApiException>()
            .having((e) => e.requiresRefresh, 'requiresRefresh', true)));
  });

  test('dated task schedule conflict explains restriction without retry',
      () async {
    final service = DailyCareTaskApiService(
        client: MockClient((_) async => http.Response(
            '{"success":false,"error":"task_schedule_conflict"}', 409)));
    await expectLater(
        service.updateTask(
            taskId: 'task-1',
            title: '散步',
            description: '',
            scheduledTime: '16:30'),
        throwsA(isA<DailyCareTaskApiException>()
            .having((e) => e.requiresRefresh, 'requiresRefresh', false)
            .having((e) => e.friendlyMessage, 'message', contains('已有指定日期'))));
  });

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
