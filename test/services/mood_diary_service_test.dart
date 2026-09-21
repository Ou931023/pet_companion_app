import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pet_companion_app/services/mood_diary_service.dart';

void main() {
  test('create sends explicit sharing, no caller-controlled resident identity',
      () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/mood-diary');
      expect(request.method, 'POST');
      expect(request.headers['Authorization'], 'Bearer fixture');
      expect(jsonDecode(request.body), {
        'mood': 'okay',
        'content': '今天和家人散步',
        'sharedWithCaregiver': false,
      });
      return http.Response('{"success":true}', 201);
    });
    final service = MoodDiaryService(
        ownerId: 'user-a',
        currentUserId: () => 'user-a',
        authTokenProvider: () async => 'fixture',
        client: client);
    await service.create(
        mood: 'okay', content: ' 今天和家人散步 ', sharedWithCaregiver: false);
    service.dispose();
  });

  test('account change during token retrieval sends no request', () async {
    var user = 'user-a';
    var requests = 0;
    final service = MoodDiaryService(
        ownerId: user,
        currentUserId: () => user,
        authTokenProvider: () async {
          user = 'user-b';
          return 'fixture';
        },
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }));
    await expectLater(service.list(), throwsA(isA<MoodDiaryException>()));
    expect(requests, 0);
    service.dispose();
  });

  test('stale account response discarded and server error never exposed',
      () async {
    var user = 'user-a';
    final response = Completer<http.Response>();
    final started = Completer<void>();
    final service = MoodDiaryService(
        ownerId: user,
        currentUserId: () => user,
        authTokenProvider: () async => 'fixture',
        client: MockClient((_) {
          started.complete();
          return response.future;
        }));
    final future = service.list();
    final assertion = expectLater(future, throwsA(isA<MoodDiaryException>()));
    await started.future;
    user = 'user-b';
    response.complete(http.Response('{"success":true,"entries":[]}', 200));
    await assertion;
    service.dispose();
  });

  test('failed POST is never automatically retried', () async {
    var requests = 0;
    final service = MoodDiaryService(
        ownerId: 'user-a',
        currentUserId: () => 'user-a',
        authTokenProvider: () async => 'fixture',
        client: MockClient((_) async {
          requests++;
          throw http.ClientException('private transport detail');
        }));
    await expectLater(
        service.create(mood: 'low', content: '想念家人', sharedWithCaregiver: true),
        throwsA(isA<MoodDiaryException>().having((e) => e.message, 'safe error',
            allOf(contains('重新整理'), isNot(contains('private transport'))))));
    expect(requests, 1);
    service.dispose();
  });

  test('sharing revoke and delete use scoped entry paths', () async {
    final methods = <String>[];
    final service = MoodDiaryService(
        ownerId: 'user-a',
        currentUserId: () => 'user-a',
        authTokenProvider: () async => 'fixture',
        client: MockClient((request) async {
          methods.add(request.method);
          expect(request.url.path, '/api/mood-diary/entry-1');
          if (request.method == 'PATCH') {
            expect(jsonDecode(request.body), {'sharedWithCaregiver': false});
          }
          return http.Response('{"success":true}', 200);
        }));
    await service.setSharing('entry-1', false);
    await service.delete('entry-1');
    expect(methods, ['PATCH', 'DELETE']);
    service.dispose();
  });
}
