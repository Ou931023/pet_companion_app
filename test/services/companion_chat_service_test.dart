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
