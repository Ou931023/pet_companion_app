import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/services/realtime_voice_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void ack(RealtimeVoiceService service, Map event) {
    service.handleDataChannelEventForTest(jsonEncode({
      'type': 'session.updated',
      'session': event['session'],
    }));
  }

  test('initial ACK must echo exact revision; sending is not application',
      () async {
    final sent = <Map>[];
    final service = RealtimeVoiceService(
        eventSenderForTesting: (p) async => sent.add(jsonDecode(p) as Map));
    addTearDown(service.dispose);
    service.forceConnectionUsableForTest();
    final updating = service.updateCompanionContext('replyLanguage=taigi');
    await pumpEventQueue();
    expect(service.isLanguageSynchronized, isFalse);
    expect(service.appliedReplyLanguage, 'zh-TW');
    service.handleDataChannelEventForTest(
        '{"type":"session.updated","session":{"instructions":"unrelated"}}');
    expect(service.isLanguageSynchronized, isFalse);
    ack(service, sent.single);
    expect(await updating, isTrue);
    expect(service.appliedReplyLanguage, 'taigi');
    expect(sent.where((e) => e['type'] == 'response.create'), isEmpty);
  });

  test('timeout retains pending language; retry requires its own ACK',
      () async {
    final sent = <Map>[];
    final service = RealtimeVoiceService(
      contextUpdateTimeout: const Duration(milliseconds: 15),
      eventSenderForTesting: (p) async => sent.add(jsonDecode(p) as Map),
    );
    addTearDown(service.dispose);
    service.forceConnectionUsableForTest();
    expect(
        await service.updateCompanionContext('replyLanguage=taigi'), isFalse);
    final retry = service.updateCompanionContext('replyLanguage=taigi');
    await pumpEventQueue(times: 2);
    ack(service, sent.first);
    expect(service.isLanguageSynchronized, isFalse);
    ack(service, sent.last);
    expect(await retry, isTrue);
  });

  test('rapid switches ignore old ACKs and tool response waits for latest',
      () async {
    final sent = <Map>[];
    final service = RealtimeVoiceService(
        eventSenderForTesting: (p) async => sent.add(jsonDecode(p) as Map));
    addTearDown(service.dispose);
    service.forceConnectionUsableForTest();
    final taigi = service.updateCompanionContext('replyLanguage=taigi');
    await pumpEventQueue();
    final mandarin = service.updateCompanionContext('replyLanguage=zh-TW');
    await pumpEventQueue();
    expect(await taigi, isFalse);
    await service.speakToolOutcome('找到音樂了', outcomeId: 'music');
    ack(service, sent.first);
    expect(sent.where((e) => e['type'] == 'response.create'), isEmpty);
    ack(service, sent.last);
    expect(await mandarin, isTrue);
    await pumpEventQueue();
    final responses =
        sent.where((e) => e['type'] == 'response.create').toList();
    expect(responses, hasLength(1));
    expect(responses.single['response']['instructions'], contains('自然國語'));
    expect(service.appliedReplyLanguage, 'zh-TW');
  });

  test(
      'analysis-only failure preserves applied language and does not block tools',
      () async {
    final sent = <Map>[];
    final service = RealtimeVoiceService(
        eventSenderForTesting: (p) async => sent.add(jsonDecode(p) as Map));
    addTearDown(service.dispose);
    service.forceConnectionUsableForTest();
    final initial = service.updateCompanionContext('replyLanguage=taigi');
    await pumpEventQueue();
    ack(service, sent.single);
    expect(await initial, isTrue);
    final analysis = service.updateCompanionContext('emotion=neutral');
    await pumpEventQueue();
    service.handleDataChannelEventForTest(jsonEncode({
      'type': 'error',
      'error': {
        'event_id': sent.last['event_id'],
        'code': 'invalid_request_error'
      },
    }));
    expect(await analysis, isFalse);
    expect(service.isLanguageSynchronized, isTrue);
    await service.speakToolOutcome('找到音樂了', outcomeId: 'music');
    expect(sent.last['type'], 'response.create');
    expect(sent.last['response']['instructions'], contains('以台語為主'));
  });

  test('send errors are observable and never report applied', () async {
    final service = RealtimeVoiceService(
        eventSenderForTesting: (_) async => throw StateError('offline'));
    addTearDown(service.dispose);
    service.forceConnectionUsableForTest();
    expect(
        await service.updateCompanionContext('replyLanguage=taigi'), isFalse);
    expect(service.appliedReplyLanguage, 'zh-TW');
  });

  test(
      'stop invalidates pending update and old ACK cannot affect a new session',
      () async {
    final sent = <Map>[];
    final service = RealtimeVoiceService(
        eventSenderForTesting: (p) async => sent.add(jsonDecode(p) as Map));
    addTearDown(service.dispose);
    service.forceConnectionUsableForTest();
    final old = service.updateCompanionContext('replyLanguage=taigi');
    await pumpEventQueue();
    final oldEvent = sent.single;
    await service.stop();
    expect(await old, isFalse);
    service.forceConnectionUsableForTest();
    final next = service.updateCompanionContext('replyLanguage=zh-TW');
    await pumpEventQueue();
    ack(service, oldEvent);
    expect(service.isLanguageSynchronized, isFalse);
    ack(service, sent.last);
    expect(await next, isTrue);
  });

  test(
      'slow send cannot overtake a newer update; callers still have bounded waits',
      () async {
    final sent = <Map>[];
    final blocked = Completer<void>();
    final service = RealtimeVoiceService(
      contextUpdateTimeout: const Duration(milliseconds: 20),
      eventSenderForTesting: (p) async {
        if (sent.isEmpty) await blocked.future;
        sent.add(jsonDecode(p) as Map);
      },
    );
    addTearDown(service.dispose);
    service.forceConnectionUsableForTest();
    final old = service.updateCompanionContext('replyLanguage=taigi');
    await pumpEventQueue(times: 2);
    final next = service.updateCompanionContext('replyLanguage=zh-TW');
    expect(await old, isFalse);
    expect(await next, isFalse);
    blocked.complete();
    await pumpEventQueue();
    expect(sent, hasLength(1));
    ack(service, sent.single);
    expect(service.isLanguageSynchronized, isFalse);
  });
}
