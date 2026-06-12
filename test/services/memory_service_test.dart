import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pet_companion_app/services/memory_service.dart';

// CR-0075：memory_service 呼叫記憶端點時須帶 Firebase idToken（Authorization: Bearer）。
// 取不到 token 時不掛 header、且不 throw（記憶為非關鍵輔助）。

void main() {
  test('有 authTokenProvider 且取得 token → 各方法帶 Authorization: Bearer', () async {
    final captured = <String, String?>{};
    http.BaseRequest? lastReq;
    final service = MemoryService(
      authTokenProvider: () async => 'idtoken-abc',
      client: MockClient((request) async {
        lastReq = request;
        captured[request.url.path] = request.headers['Authorization'];
        // 回各端點預期的最小成功 body。
        if (request.url.path.endsWith('/memories/context')) {
          return http.Response(jsonEncode({'memoryUsed': false}), 200);
        }
        if (request.url.path.endsWith('/memories')) {
          return http.Response(jsonEncode({'memories': []}), 200);
        }
        return http.Response(jsonEncode({'ok': true}), 200);
      }),
    );

    await service.buildMemoryContext(userId: 'elder-1', userText: '我想聊聊天');
    await service.listMemories(userId: 'elder-1');

    expect(captured['/api/memories/context'], 'Bearer idtoken-abc');
    expect(captured['/api/memories'], 'Bearer idtoken-abc');
    expect(lastReq, isNotNull);
  });

  test('未注入 authTokenProvider → 不掛 Authorization、不 throw', () async {
    String? authHeader = 'sentinel';
    final service = MemoryService(
      client: MockClient((request) async {
        authHeader = request.headers['Authorization'];
        return http.Response(jsonEncode({'memoryUsed': false}), 200);
      }),
    );

    final result =
        await service.buildMemoryContext(userId: 'elder-1', userText: '我想聊聊天');
    expect(result, isNotNull);
    expect(authHeader, isNull); // 沒有 Authorization header
  });

  test('provider 回 null（如未登入）→ 不掛 Authorization、不 throw', () async {
    String? authHeader = 'sentinel';
    final service = MemoryService(
      authTokenProvider: () async => null,
      client: MockClient((request) async {
        authHeader = request.headers['Authorization'];
        return http.Response(jsonEncode({'memories': []}), 200);
      }),
    );

    final list = await service.listMemories(userId: 'elder-1');
    expect(list, isEmpty);
    expect(authHeader, isNull);
  });

  test('provider 拋例外 → 視為無 token、不掛 header、不 throw', () async {
    String? authHeader = 'sentinel';
    final service = MemoryService(
      authTokenProvider: () async => throw Exception('firebase down'),
      client: MockClient((request) async {
        authHeader = request.headers['Authorization'];
        return http.Response(jsonEncode({'memoryUsed': false}), 200);
      }),
    );

    final result =
        await service.buildMemoryContext(userId: 'elder-1', userText: '我想聊聊天');
    expect(result, isNotNull);
    expect(authHeader, isNull);
  });
}
