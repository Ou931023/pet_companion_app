import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pet_companion_app/config/app_config.dart';
import 'package:pet_companion_app/models/care_alert.dart';
import 'package:pet_companion_app/services/care_alert_notification_service.dart';

const _sttProxyUrl = AppConfig.defaultSttProxyUrl;

CareAlert _sampleAlert() {
  return CareAlert(
    id: 'care_alert_t1',
    createdAt: DateTime.parse('2026-05-28T16:30:00.000Z'),
    riskLevel: CareAlertRiskLevel.urgent,
    category: CareAlertCategory.other,
    triggerSummary: '對話中偵測到需要關心的狀況',
    transcriptSnippet: '我昨天晚上都睡不好，今天有點頭暈。',
    source: 'companion_analysis',
    isRead: false,
  );
}

void main() {
  test('notify POST 到正確 URL，帶 Authorization: Bearer，body 不含 token / chat id / elderId',
      () async {
    http.Request? captured;
    final service = CareAlertNotificationService(
      authTokenProvider: () async => 'mock-id-token-default_user',
      client: MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode({'success': true}), 200);
      }),
    );

    await service.notify(sttProxyUrl: _sttProxyUrl, alert: _sampleAlert());

    expect(captured, isNotNull);
    expect(captured!.method, 'POST');
    expect(captured!.url.path, '/api/care-alerts/notify');
    expect(captured!.url.scheme, 'https');
    expect(captured!.url.host, 'ai-companion-api-1gm7.onrender.com');

    // Authorization header 帶 token；server 由 token 推導 elderId。
    expect(captured!.headers['Authorization'], 'Bearer mock-id-token-default_user');

    final body = jsonDecode(captured!.body) as Map<String, dynamic>;
    expect(body.keys.toSet(), {
      'riskLevel',
      'riskLevelLabel',
      'category',
      'categoryLabel',
      'triggerSummary',
      'transcriptSnippet',
      'createdAt',
      'source',
    });
    // 前端不送 elderId（server 權威推導）。
    expect(body.containsKey('elderId'), isFalse);
    expect(body['riskLevel'], 'urgent');
    expect(body['riskLevelLabel'], '緊急');
    expect(body['category'], 'other');
    expect(body['categoryLabel'], '其他');
    expect(body['triggerSummary'], '對話中偵測到需要關心的狀況');
    expect(body['transcriptSnippet'], '我昨天晚上都睡不好，今天有點頭暈。');
    expect(body['createdAt'], '2026-05-28T16:30:00.000Z');
    expect(body['source'], 'companion_analysis');

    // 確認沒有夾帶任何 Telegram 機密。
    final rawBody = captured!.body.toLowerCase();
    expect(rawBody.contains('token'), isFalse);
    expect(rawBody.contains('chat'), isFalse);
    expect(rawBody.contains('telegram'), isFalse);
  });

  test('firebase 模式：Authorization 帶 Firebase idToken', () async {
    http.Request? captured;
    const fakeIdToken = 'eyJfirebaseidtoken.payload.sig';
    final service = CareAlertNotificationService(
      authTokenProvider: () async => fakeIdToken,
      client: MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode({'success': true}), 200);
      }),
    );

    await service.notify(sttProxyUrl: _sttProxyUrl, alert: _sampleAlert());

    expect(captured!.headers['Authorization'], 'Bearer $fakeIdToken');
  });

  test('mock 模式：Authorization 帶 mock-id-token-<uid>', () async {
    http.Request? captured;
    final service = CareAlertNotificationService(
      authTokenProvider: () async => 'mock-id-token-elder_42',
      client: MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode({'success': true}), 200);
      }),
    );

    await service.notify(sttProxyUrl: _sttProxyUrl, alert: _sampleAlert());

    expect(captured!.headers['Authorization'], 'Bearer mock-id-token-elder_42');
  });

  test('token 為 null：不送出 notify、不 throw', () async {
    var posted = false;
    final service = CareAlertNotificationService(
      authTokenProvider: () async => null,
      client: MockClient((request) async {
        posted = true;
        return http.Response(jsonEncode({'success': true}), 200);
      }),
    );

    await expectLater(
      service.notify(sttProxyUrl: _sttProxyUrl, alert: _sampleAlert()),
      completes,
    );
    expect(posted, isFalse);
  });

  test('token provider 丟例外：安全略過、不送出、不 throw', () async {
    var posted = false;
    final service = CareAlertNotificationService(
      authTokenProvider: () async => throw Exception('token failure'),
      client: MockClient((request) async {
        posted = true;
        return http.Response(jsonEncode({'success': true}), 200);
      }),
    );

    await expectLater(
      service.notify(sttProxyUrl: _sttProxyUrl, alert: _sampleAlert()),
      completes,
    );
    expect(posted, isFalse);
  });

  test('未注入 authTokenProvider：不送出、不 throw', () async {
    var posted = false;
    final service = CareAlertNotificationService(
      client: MockClient((request) async {
        posted = true;
        return http.Response(jsonEncode({'success': true}), 200);
      }),
    );

    await expectLater(
      service.notify(sttProxyUrl: _sttProxyUrl, alert: _sampleAlert()),
      completes,
    );
    expect(posted, isFalse);
  });

  test('HTTP 200 + success:true 不 throw', () async {
    final service = CareAlertNotificationService(
      authTokenProvider: () async => 'mock-id-token-default_user',
      client: MockClient((request) async {
        return http.Response(jsonEncode({'success': true}), 200);
      }),
    );
    await expectLater(
      service.notify(sttProxyUrl: _sttProxyUrl, alert: _sampleAlert()),
      completes,
    );
  });

  test('HTTP 401（missing/invalid token）不 throw、不阻斷', () async {
    final service = CareAlertNotificationService(
      authTokenProvider: () async => 'mock-id-token-default_user',
      client: MockClient((request) async {
        return http.Response(
          jsonEncode({'success': false, 'error': 'invalid_session'}),
          401,
        );
      }),
    );
    await expectLater(
      service.notify(sttProxyUrl: _sttProxyUrl, alert: _sampleAlert()),
      completes,
    );
  });

  test('HTTP 403（無權）不 throw、不阻斷', () async {
    final service = CareAlertNotificationService(
      authTokenProvider: () async => 'mock-id-token-default_user',
      client: MockClient((request) async {
        return http.Response(
          jsonEncode({'success': false, 'error': 'forbidden'}),
          403,
        );
      }),
    );
    await expectLater(
      service.notify(sttProxyUrl: _sttProxyUrl, alert: _sampleAlert()),
      completes,
    );
  });

  test('HTTP 500 不 throw', () async {
    final service = CareAlertNotificationService(
      authTokenProvider: () async => 'mock-id-token-default_user',
      client: MockClient((request) async {
        return http.Response('internal error', 500);
      }),
    );
    await expectLater(
      service.notify(sttProxyUrl: _sttProxyUrl, alert: _sampleAlert()),
      completes,
    );
  });

  test('HTTP 200 + success:false 不 throw', () async {
    final service = CareAlertNotificationService(
      authTokenProvider: () async => 'mock-id-token-default_user',
      client: MockClient((request) async {
        return http.Response(
          jsonEncode({'success': false, 'error': 'telegram_not_configured'}),
          200,
        );
      }),
    );
    await expectLater(
      service.notify(sttProxyUrl: _sttProxyUrl, alert: _sampleAlert()),
      completes,
    );
  });

  test('網路錯誤不 throw', () async {
    final service = CareAlertNotificationService(
      authTokenProvider: () async => 'mock-id-token-default_user',
      client: MockClient((request) async {
        throw const SocketExceptionLike('connection refused');
      }),
    );
    await expectLater(
      service.notify(sttProxyUrl: _sttProxyUrl, alert: _sampleAlert()),
      completes,
    );
  });

  test('debug log 不顯示完整 token', () async {
    const secretToken = 'eyJsupersecretfirebaseidtoken.payload.signature';
    final logs = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
    try {
      // 401 會走 non-200 log 分支；確認該分支不含 token。
      final service = CareAlertNotificationService(
        authTokenProvider: () async => secretToken,
        client: MockClient((request) async {
          return http.Response(
            jsonEncode({'success': false, 'error': 'invalid_session'}),
            401,
          );
        }),
      );
      await service.notify(sttProxyUrl: _sttProxyUrl, alert: _sampleAlert());
    } finally {
      debugPrint = original;
    }

    for (final line in logs) {
      expect(line.contains(secretToken), isFalse,
          reason: 'log 不可包含完整 token');
    }
  });
}

/// 模擬網路層丟出的例外（避免直接依賴 dart:io 的 SocketException）。
class SocketExceptionLike implements Exception {
  const SocketExceptionLike(this.message);
  final String message;
  @override
  String toString() => 'SocketExceptionLike: $message';
}
