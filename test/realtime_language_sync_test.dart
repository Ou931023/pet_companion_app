import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_companion_app/services/realtime_voice_service.dart';
import 'package:pet_companion_app/services/voice_language_diagnostics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void supplyBaseline(RealtimeVoiceService service,
      [String instructions = 'SYNTHETIC_PERSONA PET_NAME MEMORY TOOL_SAFETY FIXED_COMPLIANCE']) {
    service.handleDataChannelEventForTest(jsonEncode({
      'type': 'session.created',
      'session': {'instructions': instructions},
    }));
  }

  void ack(RealtimeVoiceService service, Map event) {
    service.handleDataChannelEventForTest(jsonEncode({
      'type': 'session.updated',
      'session': event['session'],
    }));
  }

  test('P1 waits for initial baseline, sends only latest overlay, then waits for ACK', () async {
    final diagnostics = VoiceLanguageDiagnostics.forTesting();
    final sent = <Map>[];
    final service = RealtimeVoiceService(languageDiagnostics: diagnostics,
        eventSenderForTesting: (p) async => sent.add(jsonDecode(p) as Map));
    addTearDown(service.dispose);
    service.forceConnectionUsableForTest();
    service.pauseMicInput();
    final first = service.updateCompanionContext('replyLanguage=taigi\nOLD_DYNAMIC');
    final latest = service.updateCompanionContext('replyLanguage=zh-TW\nLATEST_DYNAMIC');
    expect(await first, isFalse);
    await service.speakToolOutcome('SYNTHETIC_TOOL_RESULT', outcomeId: 'synthetic-tool');
    await pumpEventQueue();
    expect(sent, isEmpty);
    expect(service.baselineReady, isFalse);
    expect(service.isLanguageSynchronized, isFalse);
    service.handleDataChannelEventForTest(
        '{"type":"session.updated","session":{"instructions":""}}');
    expect(service.isLanguageSynchronized, isFalse);
    const baseline = '  PERSONA\nPET_NAME\nMEMORY\nTOOL_CONFIRMATION\nSAFETY\nFIXED_COMPLIANCE\n';
    supplyBaseline(service, baseline);
    await pumpEventQueue();
    expect(sent, hasLength(1));
    final instructions = sent.single['session']['instructions'] as String;
    expect(instructions, startsWith(baseline));
    expect(instructions, contains('LATEST_DYNAMIC'));
    expect(instructions, isNot(contains('OLD_DYNAMIC')));
    expect(service.isLanguageSynchronized, isFalse);
    expect(service.isMicEnabled, isFalse);
    ack(service, sent.single);
    expect(await latest, isTrue);
    await pumpEventQueue();
    expect(sent.where((e) => e['type'] == 'response.create'), hasLength(1));
    expect(service.isMicEnabled, isFalse, reason: 'Capturing a baseline never opens input');
    final data = jsonDecode(diagnostics.snapshot()) as Map;
    expect(data['schemaVersion'], 2);
    final events = data['events'] as List;
    expect(events.firstWhere((e) => e['event'] == 'baseline_waiting')['baselineReady'], isFalse);
    expect(events.firstWhere((e) => e['event'] == 'baseline_ready')['baselineReady'], isTrue);
    diagnostics.clear();
    expect(service.baselineReady, isTrue, reason: 'Diagnostic clear is not business reset');
  });

  test('P1 immutable baseline survives first, analysis and rapid updates without accumulating overlays', () async {
    final sent = <Map>[];
    final service = RealtimeVoiceService(
        eventSenderForTesting: (p) async => sent.add(jsonDecode(p) as Map));
    addTearDown(service.dispose);
    service.forceConnectionUsableForTest();
    const baseline = 'PERSONA_SENTINEL petName=NAME_SENTINEL\nMEMORY_SENTINEL\n'
        'TOOL_SAFETY_SENTINEL FIXED_COMPLIANCE_SENTINEL\nreplyLanguage=zh-TW\nOLD_INITIAL_ANALYSIS';
    supplyBaseline(service, baseline);
    var updating = service.updateCompanionContext('replyLanguage=taigi\nDYNAMIC_FIRST');
    await pumpEventQueue();
    ack(service, sent.last);
    expect(await updating, isTrue);
    // A duplicate created event or update echo must not become the next baseline.
    supplyBaseline(service, 'DUPLICATE_BASELINE_SENTINEL');
    updating = service.updateCompanionContext('DYNAMIC_ANALYSIS\nnextStrategy=請改成國語\nlanguageHint=zh');
    await pumpEventQueue();
    final analysis = sent.last['session']['instructions'] as String;
    expect(analysis, contains('replyLanguage=taigi'));
    expect(analysis, contains('以台語為主'));
    expect(analysis, contains('nextStrategy 僅在不牴觸上述語言、安全與固定合規規則時採用'));
    expect(analysis.indexOf('回覆語言以本區塊'), greaterThan(analysis.indexOf('nextStrategy=請改成國語')));
    expect(analysis, isNot(contains('DYNAMIC_FIRST')));
    ack(service, sent.last);
    expect(await updating, isTrue);
    final old = service.updateCompanionContext('replyLanguage=zh-TW\nDYNAMIC_OLD');
    await pumpEventQueue();
    final oldEvent = sent.last;
    final latest = service.updateCompanionContext('replyLanguage=taigi\nDYNAMIC_LATEST');
    await pumpEventQueue();
    expect(await old, isFalse);
    ack(service, oldEvent);
    expect(service.isLanguageSynchronized, isFalse);
    ack(service, sent.last);
    expect(await latest, isTrue);
    for (final event in sent) {
      final text = event['session']['instructions'] as String;
      expect(text, startsWith(baseline));
      expect('[CURRENT_COMPANION_CONTEXT]'.allMatches(text), hasLength(1));
      expect(text, isNot(contains('DUPLICATE_BASELINE_SENTINEL')));
    }
    final last = sent.last['session']['instructions'] as String;
    expect(last, isNot(contains('DYNAMIC_OLD')));
    expect(last, isNot(contains('DYNAMIC_ANALYSIS')));
  });

  for (final initial in [null, <String, Object>{}, {'instructions': ''},
    {'instructions': '  \n'}, {'instructions': 42}]) {
    test('P1 missing or invalid initial instructions fail closed: $initial', () async {
      final diagnostics = VoiceLanguageDiagnostics.forTesting();
      final sent = <Map>[];
      final service = RealtimeVoiceService(languageDiagnostics: diagnostics,
          contextUpdateTimeout: const Duration(milliseconds: 20),
          eventSenderForTesting: (p) async => sent.add(jsonDecode(p) as Map));
      addTearDown(service.dispose);
      service.forceConnectionUsableForTest();
      if (initial != null) {
        service.handleDataChannelEventForTest(jsonEncode({'type': 'session.created', 'session': initial}));
        supplyBaseline(service, 'DUPLICATE_MUST_NOT_REPAIR_INITIAL');
      }
      service.handleDataChannelEventForTest(jsonEncode({
        'type': 'session.updated', 'session': {'instructions': 'ECHO_NOT_BASELINE'},
      }));
      expect(await service.updateCompanionContext('replyLanguage=taigi'), isFalse);
      expect(sent, isEmpty);
      expect(service.baselineReady, isFalse);
      expect(service.isLanguageSynchronized, isFalse);
      final events = jsonDecode(diagnostics.snapshot())['events'] as List;
      expect(events.last['event'], 'baseline_timeout');
      expect(events.last['baselineReady'], isFalse);
      expect(events.last['failure'], 'timeout');
    });
  }

  test('P1 late initial baseline after timeout waits for explicit retry', () async {
    final sent = <Map>[];
    final service = RealtimeVoiceService(
        contextUpdateTimeout: const Duration(milliseconds: 30),
        eventSenderForTesting: (p) async => sent.add(jsonDecode(p) as Map));
    addTearDown(service.dispose);
    service.forceConnectionUsableForTest();
    service.pauseMicInput();
    expect(await service.updateCompanionContext('replyLanguage=taigi'), isFalse);
    supplyBaseline(service);
    await pumpEventQueue();
    expect(sent, isEmpty);
    expect(service.isMicEnabled, isFalse);
    final retry = service.updateCompanionContext('replyLanguage=taigi');
    await pumpEventQueue(times: 2);
    ack(service, sent.single);
    expect(await retry, isTrue);
    expect(sent.where((e) => e['type'] == 'response.create'), isEmpty);
  });

  test('P1 stale connection callbacks cannot supply baseline after stop or reconnect', () async {
    final sent = <Map>[];
    final service = RealtimeVoiceService(connectImplementationForTesting: (_) async {},
        eventSenderForTesting: (p) async => sent.add(jsonDecode(p) as Map));
    addTearDown(service.dispose);
    await service.connect(realtimeCallUrl: 'https://synthetic.invalid', petName: 'synthetic', userId: 'synthetic');
    final stale = service.bindDataChannelEventHandlerForTest();
    supplyBaseline(service, 'OLD_GENERATION_BASELINE');
    expect(service.baselineReady, isTrue);
    await service.stop();
    expect(service.baselineReady, isFalse);
    stale('{"type":"session.created","session":{"instructions":"STALE_BASELINE"}}');
    expect(service.baselineReady, isFalse);
    await service.connect(realtimeCallUrl: 'https://synthetic.invalid', petName: 'synthetic', userId: 'synthetic');
    stale('{"type":"session.created","session":{"instructions":"STALE_BASELINE"}}');
    expect(service.baselineReady, isFalse);
    service.forceConnectionUsableForTest();
    supplyBaseline(service, 'NEW_GENERATION_BASELINE');
    final update = service.updateCompanionContext('replyLanguage=taigi');
    await pumpEventQueue();
    expect(sent.single['session']['instructions'], startsWith('NEW_GENERATION_BASELINE'));
    expect(sent.single['session']['instructions'], isNot(contains('OLD_GENERATION_BASELINE')));
    ack(service, sent.single);
    expect(await update, isTrue);
    final current = service.bindDataChannelEventHandlerForTest();
    service.dispose();
    current('{"type":"session.created","session":{"instructions":"AFTER_DISPOSE"}}');
    expect(service.baselineReady, isFalse);
  });

  test('P1 retry within same connect generation invalidates old channel callback', () async {
    late RealtimeVoiceService service;
    late void Function(String) oldChannel;
    service = RealtimeVoiceService(connectImplementationForTesting: (request) async {
      if (request.attempt == 1) {
        oldChannel = service.bindDataChannelEventHandlerForTest();
        supplyBaseline(service, 'OLD_ATTEMPT_BASELINE');
        throw StateError('synthetic retry');
      }
      oldChannel('{"type":"session.created","session":{"instructions":"STALE_CHANNEL"}}');
      expect(service.baselineReady, isFalse);
      supplyBaseline(service, 'CURRENT_CHANNEL_BASELINE');
    });
    addTearDown(service.dispose);
    await service.connect(realtimeCallUrl: 'https://synthetic.invalid', petName: 'synthetic', userId: 'synthetic');
    expect(service.baselineReady, isTrue);
  });

  test('D1 constructor probe and typed service traces contain no payloads', () async {
    final diagnostics = VoiceLanguageDiagnostics.forTesting();
    final sent = <Map>[];
    final service = RealtimeVoiceService(
      languageDiagnostics: diagnostics,
      eventSenderForTesting: (p) async => sent.add(jsonDecode(p) as Map),
      connectImplementationForTesting: (_) async {},
    );
    addTearDown(service.dispose);
    expect((jsonDecode(diagnostics.snapshot())['events'] as List).single['event'],
        'capture_ready');
    service.forceConnectionUsableForTest();
    supplyBaseline(service, 'PRIVATE_BASELINE_SENTINEL PRIVATE_NAME_SENTINEL PRIVATE_MEMORY_SENTINEL PRIVATE_SAFETY_SENTINEL');
    final first = service.updateCompanionContext(
        'replyLanguage=PRIVATE_LANGUAGE_SENTINEL\nPRIVATE_PROMPT_SENTINEL');
    await pumpEventQueue();
    service.handleDataChannelEventForTest(jsonEncode({
      'type': 'error',
      'error': {'event_id': sent.last['event_id'], 'message': 'PRIVATE_ERROR_SENTINEL'},
    }));
    expect(await first, isFalse);
    final second = service.updateCompanionContext('replyLanguage=taigi\nPRIVATE_MEMORY_SENTINEL');
    await pumpEventQueue();
    ack(service, sent.first);
    ack(service, sent.last);
    expect(await second, isTrue);
    for (final payload in [
      {'type': 'conversation.item.input_audio_transcription.delta', 'delta': 'PRIVATE_TRANSCRIPT_SENTINEL'},
      {'type': 'conversation.item.input_audio_transcription.completed', 'item_id': 'PRIVATE_ITEM_SENTINEL', 'transcript': 'PRIVATE_TRANSCRIPT_SENTINEL'},
      {'type': 'response.audio_transcript.done', 'transcript': 'PRIVATE_ASSISTANT_SENTINEL'},
      {'type': 'session.created', 'session': {'id': 'PRIVATE_SESSION_SENTINEL', 'instructions': 'PRIVATE_BASELINE_SENTINEL'}},
    ]) {
      service.handleDataChannelEventForTest(jsonEncode(payload));
    }
    final snapshot = diagnostics.snapshot();
    expect(snapshot, isNot(contains('PRIVATE_')));
    expect(snapshot, isNot(contains(sent.last['event_id'] as String)));
    final events = jsonDecode(snapshot)['events'] as List;
    expect(events.map((e) => e['event']), containsAll(['send', 'rejected', 'ignored', 'matched']));
    expect(events.firstWhere((e) => e['event'] == 'send')['desired'], 'unknown');
    await service.stop();
    ack(service, sent.last);
    expect(diagnostics.snapshot(), VoiceLanguageDiagnostics.emptySnapshot);
    await service.connect(realtimeCallUrl: 'https://PRIVATE_URL_SENTINEL',
        petName: 'PRIVATE_NAME_SENTINEL', userId: 'PRIVATE_ACCOUNT_SENTINEL');
    final next = jsonDecode(diagnostics.snapshot())['events'] as List;
    expect(next.single['event'], 'capture_ready');
    expect(next.single['sequence'], greaterThan(events.last['sequence'] as int));
    service.dispose();
    expect(diagnostics.snapshot(), VoiceLanguageDiagnostics.emptySnapshot);
  });

  test('D1 extension failure does not change language ACK outcome', () async {
    final diagnostics = VoiceLanguageDiagnostics.forTesting(
      extensions: VoiceLanguageDiagnosticsExtensions.forTesting(
          (_, __) => throw StateError('PRIVATE_REGISTRATION_SENTINEL')),
    );
    final sent = <Map>[];
    final service = RealtimeVoiceService(languageDiagnostics: diagnostics,
        eventSenderForTesting: (p) async => sent.add(jsonDecode(p) as Map));
    addTearDown(service.dispose);
    service.forceConnectionUsableForTest();
    supplyBaseline(service);
    final result = service.updateCompanionContext('replyLanguage=taigi');
    await pumpEventQueue();
    ack(service, sent.single);
    expect(await result, isTrue);
    expect(service.appliedReplyLanguage, 'taigi');
    expect(diagnostics.snapshot(), isNot(contains('PRIVATE_')));
  });

  test('language diagnostics distinguish rejection and ACK without context text',
      () async {
    final messages = <String>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) messages.add(message);
    };
    addTearDown(() => debugPrint = originalDebugPrint);
    final sent = <Map>[];
    final service = RealtimeVoiceService(
        eventSenderForTesting: (p) async => sent.add(jsonDecode(p) as Map));
    addTearDown(service.dispose);
    service.forceConnectionUsableForTest();
    supplyBaseline(service);
    const context = 'replyLanguage=taigi\nPRIVATE_CONTEXT_SENTINEL';
    final rejected = service.updateCompanionContext(context);
    await pumpEventQueue();
    service.handleDataChannelEventForTest(jsonEncode({
      'type': 'error',
      'error': {'event_id': sent.last['event_id'], 'message': 'PRIVATE_ERROR_SENTINEL'}
    }));
    expect(await rejected, isFalse);
    final retry = service.updateCompanionContext(context);
    await pumpEventQueue();
    ack(service, sent.first);
    ack(service, sent.last);
    expect(await retry, isTrue);
    final diagnostic = messages.where((m) => m.contains('[VOICE_LANGUAGE_ACK]')).join('\n');
    for (final code in ['send', 'rejected', 'ignored', 'matched']) {
      expect(diagnostic, contains('code=$code'));
    }
    expect(diagnostic, contains('desired=taigi'));
    expect(diagnostic, contains('revision=2'));
    expect(messages.join('\n'), isNot(contains('PRIVATE_')));
  });

  test('initial ACK must echo exact revision; sending is not application',
      () async {
    final sent = <Map>[];
    final service = RealtimeVoiceService(
        eventSenderForTesting: (p) async => sent.add(jsonDecode(p) as Map));
    addTearDown(service.dispose);
    service.forceConnectionUsableForTest();
    supplyBaseline(service);
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
    supplyBaseline(service);
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
    supplyBaseline(service);
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
    supplyBaseline(service);
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
    supplyBaseline(service);
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
    supplyBaseline(service);
    final old = service.updateCompanionContext('replyLanguage=taigi');
    await pumpEventQueue();
    final oldEvent = sent.single;
    await service.stop();
    expect(await old, isFalse);
    service.forceConnectionUsableForTest();
    supplyBaseline(service);
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
    supplyBaseline(service);
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
