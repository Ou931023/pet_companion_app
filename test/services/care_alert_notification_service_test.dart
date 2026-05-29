import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pet_companion_app/models/care_alert.dart';
import 'package:pet_companion_app/services/care_alert_notification_service.dart';

const _sttProxyUrl = 'http://192.168.99.99:3001/api/stt/transcribe';

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
  test('notify POST 到正確 URL，body 含所有欄位且不含 token / chat id', () async {
    http.Request? captured;
    final service = CareAlertNotificationService(
      client: MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode({'success': true}), 200);
      }),
    );

    await service.notify(sttProxyUrl: _sttProxyUrl, alert: _sampleAlert());

    expect(captured, isNotNull);
    expect(captured!.method, 'POST');
    expect(captured!.url.path, '/api/care-alerts/notify');
    expect(captured!.url.host, '192.168.99.99');
    expect(captured!.url.port, 3001);

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

  test('HTTP 200 + success:true 不 throw', () async {
    final service = CareAlertNotificationService(
      client: MockClient((request) async {
        return http.Response(jsonEncode({'success': true}), 200);
      }),
    );
    await expectLater(
      service.notify(sttProxyUrl: _sttProxyUrl, alert: _sampleAlert()),
      completes,
    );
  });

  test('HTTP 500 不 throw', () async {
    final service = CareAlertNotificationService(
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
      client: MockClient((request) async {
        throw const SocketExceptionLike('connection refused');
      }),
    );
    await expectLater(
      service.notify(sttProxyUrl: _sttProxyUrl, alert: _sampleAlert()),
      completes,
    );
  });
}

/// 模擬網路層丟出的例外（避免直接依賴 dart:io 的 SocketException）。
class SocketExceptionLike implements Exception {
  const SocketExceptionLike(this.message);
  final String message;
  @override
  String toString() => 'SocketExceptionLike: $message';
}
