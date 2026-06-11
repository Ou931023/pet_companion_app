import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pet_companion_app/services/companion_chat_service.dart';

void main() {
  test('成功 200 + success:true + reply → 回傳該 reply', () async {
    final service = CompanionChatService(
      client: MockClient((request) async {
        return http.Response(
          jsonEncode({'success': true, 'reply': '我在這裡陪你，今天有沒有好好吃飯？'}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final reply = await service.reply(userText: '我今天有點無聊');
    expect(reply, '我在這裡陪你，今天有沒有好好吃飯？');
  });

  test('request：POST 到 /api/companion/chat，帶 Content-Type，body 含 userText',
      () async {
    http.Request? captured;
    final service = CompanionChatService(
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({'success': true, 'reply': '好呀'}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    await service.reply(
      userText: '你好',
      petName: '小白',
      memoryContextSummary: '使用者喜歡散步',
      languageHint: 'zh-TW',
      replyLanguage: 'zh-TW',
    );

    expect(captured, isNotNull);
    expect(captured!.method, 'POST');
    expect(captured!.url.path, '/api/companion/chat');
    expect(captured!.headers['Content-Type'],
        contains('application/json'));

    final body = jsonDecode(captured!.body) as Map<String, dynamic>;
    expect(body['userText'], '你好');
    expect(body['petName'], '小白');
    expect(body['memoryContextSummary'], '使用者喜歡散步');
    expect(body['languageHint'], 'zh-TW');
    expect(body['replyLanguage'], 'zh-TW');
  });

  test('CR-0072 request：帶 history → body 含 history 陣列（role/content）', () async {
    http.Request? captured;
    final service = CompanionChatService(
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({'success': true, 'reply': '你剛說想睡覺'}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    await service.reply(
      userText: '我剛剛說想做什麼？',
      history: const [
        {'role': 'user', 'content': '我想睡覺'},
        {'role': 'assistant', 'content': '那早點休息喔'},
      ],
    );

    final body = jsonDecode(captured!.body) as Map<String, dynamic>;
    final history = body['history'] as List<dynamic>;
    expect(history.length, 2);
    expect(history.first['role'], 'user');
    expect(history.first['content'], '我想睡覺');
    expect(history.last['role'], 'assistant');
  });

  test('CR-0072 request：history 為空 → 不送出 history key', () async {
    http.Request? captured;
    final service = CompanionChatService(
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({'success': true, 'reply': '嗨'}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    await service.reply(userText: '你好', history: const []);

    final body = jsonDecode(captured!.body) as Map<String, dynamic>;
    expect(body.containsKey('history'), isFalse);
  });

  test('request：可選欄位為空時不送出對應 key（只送必填 userText）', () async {
    http.Request? captured;
    final service = CompanionChatService(
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({'success': true, 'reply': '嗨'}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    await service.reply(userText: '只有必填');

    final body = jsonDecode(captured!.body) as Map<String, dynamic>;
    expect(body.keys.toSet(), {'userText'});
    expect(body['userText'], '只有必填');
  });

  test('400 invalid_input → throw CompanionChatException（不回空）', () async {
    final service = CompanionChatService(
      client: MockClient((request) async {
        return http.Response(
          jsonEncode({'success': false, 'error': 'invalid_input'}),
          400,
        );
      }),
    );

    await expectLater(
      service.reply(userText: ''),
      throwsA(isA<CompanionChatException>()),
    );
  });

  test('503 openai_unavailable → throw CompanionChatException', () async {
    final service = CompanionChatService(
      client: MockClient((request) async {
        return http.Response(
          jsonEncode({'success': false, 'error': 'openai_unavailable'}),
          503,
        );
      }),
    );

    await expectLater(
      service.reply(userText: '你好'),
      throwsA(isA<CompanionChatException>()),
    );
  });

  test('200 + success:false → throw CompanionChatException', () async {
    final service = CompanionChatService(
      client: MockClient((request) async {
        return http.Response(
          jsonEncode({'success': false, 'error': 'openai_unavailable'}),
          200,
        );
      }),
    );

    await expectLater(
      service.reply(userText: '你好'),
      throwsA(isA<CompanionChatException>()),
    );
  });

  test('200 + success:true 但 reply 為空字串 → throw（不回空）', () async {
    final service = CompanionChatService(
      client: MockClient((request) async {
        return http.Response(
          jsonEncode({'success': true, 'reply': '   '}),
          200,
        );
      }),
    );

    await expectLater(
      service.reply(userText: '你好'),
      throwsA(isA<CompanionChatException>()),
    );
  });

  test('200 + success:true 但缺 reply 欄位 → throw', () async {
    final service = CompanionChatService(
      client: MockClient((request) async {
        return http.Response(jsonEncode({'success': true}), 200);
      }),
    );

    await expectLater(
      service.reply(userText: '你好'),
      throwsA(isA<CompanionChatException>()),
    );
  });

  test('非 200（500）→ throw CompanionChatException', () async {
    final service = CompanionChatService(
      client: MockClient((request) async {
        return http.Response('internal error', 500);
      }),
    );

    await expectLater(
      service.reply(userText: '你好'),
      throwsA(isA<CompanionChatException>()),
    );
  });

  test('回傳非 JSON body → throw CompanionChatException', () async {
    final service = CompanionChatService(
      client: MockClient((request) async {
        return http.Response('<html>not json</html>', 200);
      }),
    );

    await expectLater(
      service.reply(userText: '你好'),
      throwsA(isA<CompanionChatException>()),
    );
  });

  test('網路錯誤 → throw（不吞、不回空）', () async {
    final service = CompanionChatService(
      client: MockClient((request) async {
        throw const _SocketExceptionLike('connection refused');
      }),
    );

    await expectLater(
      service.reply(userText: '你好'),
      throwsA(isA<CompanionChatException>()),
    );
  });

  test('timeout → throw CompanionChatException', () async {
    final service = CompanionChatService(
      client: MockClient((request) async {
        // 永遠不完成，觸發 10s timeout。用 fakeAsync-free 方式：
        // 直接丟 TimeoutException 模擬逾時路徑。
        throw TimeoutException('slow backend');
      }),
    );

    await expectLater(
      service.reply(userText: '你好'),
      throwsA(isA<CompanionChatException>()),
    );
  });

  test('成功 body 含 careAlert 欄位 → reply 解析不受影響（不崩潰）', () async {
    final service = CompanionChatService(
      client: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'reply': '我都在這裡，慢慢說沒關係。',
            'careAlert': {
              'created': true,
              'riskLevel': 'medium',
              'id': 'alert-123',
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final reply = await service.reply(userText: '我最近都睡不好');
    expect(reply, '我都在這裡，慢慢說沒關係。');
  });

  test('成功 body 含未知/多餘欄位 → 仍正確取出 reply', () async {
    final service = CompanionChatService(
      client: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'reply': '好呀，我陪你。',
            'careAlert': null,
            'someFutureField': {'a': 1},
            'anotherUnknown': [1, 2, 3],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final reply = await service.reply(userText: '你好');
    expect(reply, '好呀，我陪你。');
  });

  test('有注入 provider 且取得 token → 送出 Authorization: Bearer header', () async {
    http.Request? captured;
    var providerCalls = 0;
    final service = CompanionChatService(
      authTokenProvider: () async {
        providerCalls++;
        return 'mock-id-token-elder-1';
      },
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({'success': true, 'reply': '嗨，我在。'}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final reply = await service.reply(userText: '你好');

    expect(reply, '嗨，我在。');
    expect(providerCalls, 1);
    expect(captured, isNotNull);
    expect(captured!.headers['Authorization'], 'Bearer mock-id-token-elder-1');
  });

  test('provider 回傳 null（如 production demo）→ throw 白話例外，且不發出請求', () async {
    var requestSent = false;
    final service = CompanionChatService(
      authTokenProvider: () async => null,
      client: MockClient((request) async {
        requestSent = true;
        return http.Response(
          jsonEncode({'success': true, 'reply': '不該出現'}),
          200,
        );
      }),
    );

    await expectLater(
      service.reply(userText: '你好'),
      throwsA(isA<CompanionChatException>()),
    );
    expect(requestSent, isFalse, reason: '取不到 token 不應送出註定 401 的請求');
  });

  test('provider 回傳空字串 → throw 白話例外，且不發出請求', () async {
    var requestSent = false;
    final service = CompanionChatService(
      authTokenProvider: () async => '',
      client: MockClient((request) async {
        requestSent = true;
        return http.Response('', 200);
      }),
    );

    await expectLater(
      service.reply(userText: '你好'),
      throwsA(isA<CompanionChatException>()),
    );
    expect(requestSent, isFalse);
  });

  test('provider 拋例外 → 視為取不到 token，throw 白話例外、不送請求', () async {
    var requestSent = false;
    final service = CompanionChatService(
      authTokenProvider: () async => throw Exception('firebase down'),
      client: MockClient((request) async {
        requestSent = true;
        return http.Response('', 200);
      }),
    );

    await expectLater(
      service.reply(userText: '你好'),
      throwsA(isA<CompanionChatException>()),
    );
    expect(requestSent, isFalse);
  });

  test('401（後端拒絕）→ 映射為 CompanionChatException（白話、非原始 HTTP 文字）',
      () async {
    final service = CompanionChatService(
      authTokenProvider: () async => 'expired-token',
      client: MockClient((request) async {
        return http.Response('Unauthorized', 401);
      }),
    );

    await expectLater(
      service.reply(userText: '你好'),
      throwsA(isA<CompanionChatException>().having(
        (e) => e.message,
        'message',
        isNot(contains('Unauthorized')),
      )),
    );
  });

  test('403 → 映射為 CompanionChatException', () async {
    final service = CompanionChatService(
      authTokenProvider: () async => 'wrong-token',
      client: MockClient((request) async {
        return http.Response(
          jsonEncode({'success': false, 'error': 'forbidden'}),
          403,
        );
      }),
    );

    await expectLater(
      service.reply(userText: '你好'),
      throwsA(isA<CompanionChatException>()),
    );
  });

  test('CompanionChatException.toString 含 code/message、不含敏感字樣', () {
    const ex = CompanionChatException(
      code: 'network_error',
      message: '連線不太穩，請稍後再試一次。',
    );
    final text = ex.toString().toLowerCase();
    expect(text, contains('network_error'));
    expect(text.contains('token'), isFalse);
    expect(text.contains('apikey'), isFalse);
    expect(text.contains('sk-'), isFalse);
  });
}

/// 模擬網路層丟出的例外（避免直接依賴 dart:io 的 SocketException）。
class _SocketExceptionLike implements Exception {
  const _SocketExceptionLike(this.message);
  final String message;
  @override
  String toString() => '_SocketExceptionLike: $message';
}
